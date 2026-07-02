###############################################################################
# Build the Flutter Windows Release output and wrap it with Inno Setup 6
# to produce a Setup.exe installer.
#
# Usage : .\build_installer.ps1
# Output: dist\AppfitOrderAgent-Setup-<semver>.exe
#
# Requires:
#   - Inno Setup 6 (ISCC.exe)
#     winget install JRSoftware.InnoSetup  or  https://jrsoftware.org/isdl.php
#   - Visual Studio 2022 (for cmake.exe)
#   - Flutter SDK on PATH
#
# This script is for the "initial install" installer only.
# OTA (zip) publishing continues to use deploy_windows.ps1.
#
# Usage: .\build_installer.ps1 [-Variant update|standalone]
###############################################################################

param(
    [ValidateSet('update','standalone')]
    [string]$Variant = 'update'
)

# Force UTF-8 console so that ISCC output is readable even if it contains
# localized strings.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

# === Variant selection ===
# standalone makes CMake branch the exe name (BINARY_NAME) and compile macros.
# The CMake cache freezes BINARY_NAME at configure time, so if the previous
# build used a different variant, wipe build/windows to force a clean reconfigure.
$VariantSentinel = "build\.appfit_windows_variant"
$prevVariant = if (Test-Path $VariantSentinel) { (Get-Content $VariantSentinel -Raw).Trim() } else { "" }
if ($prevVariant -ne $Variant -and (Test-Path "build\windows")) {
    Write-Host "[INFO] Build variant changed ($prevVariant -> $Variant): cleaning build/windows"
    Remove-Item "build\windows" -Recurse -Force
}
New-Item -ItemType Directory -Force -Path "build" | Out-Null
Set-Content -Path $VariantSentinel -Value $Variant -NoNewline
if ($Variant -eq 'standalone') {
    $env:APPFIT_WINDOWS_VARIANT = 'standalone'
} else {
    Remove-Item Env:\APPFIT_WINDOWS_VARIANT -ErrorAction SilentlyContinue
}
Write-Host "[INFO] Installer variant: $Variant"

# Path constants
$BUILD_DIR      = "build\windows\x64"
$BUILD_OUTPUT   = "$BUILD_DIR\runner\Release"
$INSTALL_PREFIX = (Resolve-Path ".").Path + "\$BUILD_DIR\runner\Release"
$WINDOWS_SRC    = (Resolve-Path ".").Path + "\windows"
$CACHE_FILE     = "$BUILD_DIR\CMakeCache.txt"
$ISS_FILE       = "installer\appfit_order_agent.iss"
$DIST_DIR       = "dist"

# 0) Prerequisite tools
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Error "Flutter SDK not found on PATH."
    exit 1
}

$cmake = Get-ChildItem "C:\Program Files\Microsoft Visual Studio" -Recurse -Filter "cmake.exe" `
    -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "CMake\\bin" } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $cmake) {
    Write-Error "cmake.exe not found. Install Visual Studio 2022."
    exit 1
}

$iscc = @(
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { $iscc = $onPath.Source }
}

if (-not $iscc) {
    Write-Error "ISCC.exe not found. Install Inno Setup 6 first. (winget install JRSoftware.InnoSetup)"
    exit 1
}

Write-Host "[INFO] Using ISCC: $iscc"

# 1) CMake configure check (mirrors deploy_windows.ps1: install prefix +
#    generator platform). flutter build windows configures with -A x64, so a
#    cache left without a platform (or a different one) makes the build fail.
$needReconfigure = $false

if (-not (Test-Path $CACHE_FILE)) {
    Write-Host "[INFO] No CMakeCache.txt - cmake reconfigure required"
    $needReconfigure = $true
} else {
    $currentPrefix = (Select-String -Path $CACHE_FILE -Pattern "^CMAKE_INSTALL_PREFIX:PATH=").Line `
        -replace "^CMAKE_INSTALL_PREFIX:PATH=", ""
    $expectedSuffix = "$BUILD_DIR\runner\Release" -replace "\\", "/"
    $currentNorm    = $currentPrefix -replace "\\", "/"

    if ($currentNorm -notmatch [regex]::Escape($expectedSuffix.TrimStart("./"))) {
        Write-Host "[INFO] CMAKE_INSTALL_PREFIX mismatch ($currentPrefix) - reconfigure"
        $needReconfigure = $true
    }

    # Generator platform mismatch: flutter builds with -A x64; a cache pinned to
    # a different/empty platform makes 'flutter build windows' fail.
    if (-not $needReconfigure) {
        $platformLine = (Select-String -Path $CACHE_FILE -Pattern "^CMAKE_GENERATOR_PLATFORM:" -ErrorAction SilentlyContinue).Line
        $currentPlatform = if ($platformLine) {
            ($platformLine -replace "^CMAKE_GENERATOR_PLATFORM:[^=]*=", "").Trim()
        } else { "" }
        if ($currentPlatform -ne "x64") {
            Write-Host "[INFO] CMAKE_GENERATOR_PLATFORM mismatch ('$currentPlatform' != 'x64') - reconfigure"
            $needReconfigure = $true
        }
    }
}

if ($needReconfigure) {
    Write-Host "==== cmake reconfigure (install prefix + x64 platform) ===="

    # Ensure flutter ephemeral (generated_config.cmake) exists before cmake runs.
    $ephemeralDir = Join-Path $WINDOWS_SRC "flutter\ephemeral"
    $generatedConfig = Join-Path $ephemeralDir "generated_config.cmake"
    if (-not (Test-Path $generatedConfig)) {
        Write-Host "[INFO] Generating flutter ephemeral: flutter pub get + flutter build windows --config-only"
        flutter pub get
        if ($LASTEXITCODE -ne 0) { Write-Error "[ERROR] flutter pub get failed"; exit 1 }
        flutter build windows --config-only
        if ($LASTEXITCODE -ne 0) { Write-Error "[ERROR] flutter build windows --config-only failed"; exit 1 }
    }

    # Remove stale cmake artifacts so the platform/generator can change cleanly.
    if (Test-Path $CACHE_FILE) { Remove-Item $CACHE_FILE -Force }
    $cmakeFilesDir = Join-Path $BUILD_DIR "CMakeFiles"
    if (Test-Path $cmakeFilesDir) { Remove-Item $cmakeFilesDir -Recurse -Force }

    New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null
    & $cmake -S $WINDOWS_SRC -B $BUILD_DIR -A x64 -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DCMAKE_BUILD_TYPE=Release 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Error "cmake reconfigure failed"; exit 1 }
    Write-Host "[OK] cmake reconfigure done"
}

# 2) Flutter Windows Release build
Write-Host "==== 1) flutter build windows --release ===="
if (-not (Test-Path ".env")) {
    Write-Error "[ERROR] .env not found at repo root. APPFIT_AES_KEY must be injected at build time."
    exit 1
}

# Windows 전용 버전 로드 (pubspec.yaml과 분리 — version_windows.txt가 정본)
if (-not (Test-Path "version_windows.txt")) {
    Write-Error "[ERROR] version_windows.txt not found. e.g. 1.0.0+1"
    exit 1
}
$WinVersionLine = (Get-Content "version_windows.txt" | Where-Object { $_ -match '^[0-9]' } | Select-Object -First 1).Trim()
if ($WinVersionLine -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$') {
    Write-Error "[ERROR] version_windows.txt format invalid: '$WinVersionLine' (expected: x.y.z+n)"
    exit 1
}
$WinBuildName   = $WinVersionLine.Split('+')[0]
$WinBuildNumber = $WinVersionLine.Split('+')[1]
Write-Host "[INFO] Windows 버전: $WinBuildName ($WinBuildNumber)"

# 주의: 함수가 값을 return 하면 flutter 의 콘솔 출력까지 반환값에 섞인다.
# 아무것도 return 하지 않고(빌드 출력은 콘솔로 흘림) 호출부에서 전역 $LASTEXITCODE 를 읽는다.
function Invoke-FlutterWindowsBuild {
    flutter build windows --release `
        --dart-define-from-file=.env `
        --dart-define=APPFIT_VARIANT="$Variant" `
        --build-name="$WinBuildName" `
        --build-number="$WinBuildNumber"
}

# 산출물 무결성 검사: 종료 코드 0 만으로는 부족하다.
# fresh CMake configure 직후 첫 INSTALL 패스가 비결정적으로 실패하면 exe 는 생기지만
# data\ (app.so 등) 와 flutter_windows.dll 복사가 통째로 누락된다. 두 파일은 variant 무관이라
# 깨진 빌드의 확실한 지표가 된다.
function Test-BuildArtifactComplete {
    return (Test-Path (Join-Path $BUILD_OUTPUT "flutter_windows.dll")) `
        -and (Test-Path (Join-Path $BUILD_OUTPUT "data\app.so"))
}

# 첫 패스가 실패/불완전하면 같은 build 디렉터리로 1회 재빌드한다
# (두 번째 증분 패스에서는 INSTALL 단계가 안정적으로 성공한다).
Invoke-FlutterWindowsBuild
if ($LASTEXITCODE -ne 0 -or -not (Test-BuildArtifactComplete)) {
    Write-Host "[WARN] First build pass failed/incomplete (exit=$LASTEXITCODE). Rebuilding once in the same build dir..."
    Invoke-FlutterWindowsBuild
}
if ($LASTEXITCODE -ne 0 -or -not (Test-BuildArtifactComplete)) {
    Write-Error "[ERROR] Flutter Windows build failed/incomplete after retry. Required: flutter_windows.dll, data\app.so. Aborting before installer build to avoid shipping a broken installer."
    exit 1
}

if (-not (Test-Path $BUILD_OUTPUT) -or -not (Get-ChildItem $BUILD_OUTPUT -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] Build output directory missing: $BUILD_OUTPUT"
    exit 1
}

# 3) Bundle VC++ runtime DLLs (mirrors deploy_windows.ps1 L87-153)
Write-Host "==== 2) Bundle VC++ runtime DLLs ===="

$dllNames = @('vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll')

$redistRoots = @(
    "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC",
    "$env:ProgramFiles\Microsoft Visual Studio\2022\Professional\VC\Redist\MSVC",
    "$env:ProgramFiles\Microsoft Visual Studio\2022\Enterprise\VC\Redist\MSVC",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC"
)

function Find-RedistCrtDir {
    param([string[]] $Roots)
    foreach ($root in $Roots) {
        if (-not (Test-Path $root)) { continue }
        $versionDirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+' } |
            Sort-Object -Property { [version]($_.Name -replace '[^\d\.].*$','') } -Descending
        foreach ($v in $versionDirs) {
            $candidate = Join-Path $v.FullName 'x64\Microsoft.VC143.CRT'
            if (Test-Path $candidate) { return $candidate }
            $candidate = Join-Path $v.FullName 'x64\Microsoft.VC142.CRT'
            if (Test-Path $candidate) { return $candidate }
        }
    }
    return $null
}

$srcDir = Find-RedistCrtDir -Roots $redistRoots
if ($srcDir) {
    foreach ($dll in $dllNames) {
        $srcPath = Join-Path $srcDir $dll
        if (Test-Path $srcPath) {
            Copy-Item -Path $srcPath -Destination $BUILD_OUTPUT -Force
            Write-Host "[INFO] Bundled: $dll"
        }
    }
}

# Fallback: fill in any remaining DLL from System32
$missing = @()
foreach ($dll in $dllNames) {
    if (-not (Test-Path (Join-Path $BUILD_OUTPUT $dll))) {
        $sys32 = Join-Path $env:WINDIR "System32\$dll"
        if (Test-Path $sys32) {
            Copy-Item -Path $sys32 -Destination $BUILD_OUTPUT -Force
            Write-Host "[INFO] Bundled(System32): $dll"
        } else {
            $missing += $dll
        }
    }
}

if ($missing.Count -gt 0) {
    Write-Host "[WARN] Missing DLLs: $($missing -join ', ')"
}

# 4) Use semver from version_windows.txt (정본)
Write-Host "==== 3) Use semver from version_windows.txt ===="
$semver = $WinBuildName
Write-Host "[INFO] semver: $semver"

# 5) Prepare dist directory
New-Item -ItemType Directory -Force -Path $DIST_DIR | Out-Null

# 6) Compile installer via ISCC.exe
Write-Host "==== 4) Compile installer with Inno Setup ===="
$isccArgs = @("/DMyAppVersion=$semver")
if ($Variant -eq 'standalone') { $isccArgs += "/DStandalone=1" }
& $iscc @isccArgs $ISS_FILE
if ($LASTEXITCODE -ne 0) { Write-Error "[ERROR] ISCC compile failed"; exit 1 }

# 7) Verify installer artifact
if ($Variant -eq 'standalone') {
    $installerPath = Join-Path $DIST_DIR "AppfitOrderAgentStandalone-Setup-$semver.exe"
} else {
    $installerPath = Join-Path $DIST_DIR "AppfitOrderAgent-Setup-$semver.exe"
}
if (-not (Test-Path $installerPath)) {
    Write-Error "[ERROR] Installer not produced: $installerPath"
    exit 1
}

$sizeMB = (Get-Item $installerPath).Length / 1MB
Write-Host ""
Write-Host "==== Done ===="
Write-Host "Installer: $installerPath"
Write-Host ("Size     : {0:N2} MB" -f $sizeMB)
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1) Double-click the installer on a clean Windows PC to verify install/uninstall."
Write-Host "  2) Verify OTA self-update compatibility (expect UAC prompt, then robocopy success)."
Write-Host "  3) Upload to Lightsail manually, e.g.:"
Write-Host "       scp -i ~/.ssh/LightsailDefaultKey-ap-northeast-3.pem $installerPath ec2-user@52.78.172.188:/var/www/docs/waldpay_html/"

# Open Explorer with the new installer pre-selected.
$absInstallerPath = (Resolve-Path $installerPath).Path
Start-Process "explorer.exe" -ArgumentList "/select,`"$absInstallerPath`""

# 로컬 아카이브 보관 (설치본 .exe 를 버전별 보관 + 노트 기록)
Write-Host ""
& "$PSScriptRoot\archive_windows.ps1" -SrcArtifact $installerPath -Variant $Variant
