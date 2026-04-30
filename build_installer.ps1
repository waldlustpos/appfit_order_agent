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
###############################################################################

# Force UTF-8 console so that ISCC output is readable even if it contains
# localized strings.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

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

# 1) CMake install prefix check (mirrors deploy_windows.ps1)
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
}

if ($needReconfigure) {
    Write-Host "==== cmake reconfigure (install prefix) ===="
    New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null
    & $cmake -S $WINDOWS_SRC -B $BUILD_DIR -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DCMAKE_BUILD_TYPE=Release 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Error "cmake reconfigure failed"; exit 1 }
    Write-Host "[OK] cmake reconfigure done"
}

# 2) Flutter Windows Release build
Write-Host "==== 1) flutter build windows --release ===="
if (-not (Test-Path ".env")) {
    Write-Error "[ERROR] .env not found at repo root. APPFIT_AES_KEY must be injected at build time."
    exit 1
}
flutter build windows --release --dart-define-from-file=.env
if ($LASTEXITCODE -ne 0) { Write-Error "[ERROR] Flutter Windows build failed"; exit 1 }

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

# 4) Extract semver from pubspec.yaml (for installer display)
Write-Host "==== 3) Extract semver from pubspec.yaml ===="
$versionLine = (Select-String -Path "pubspec.yaml" -Pattern "^version:").Line
if (-not $versionLine) {
    Write-Error "[ERROR] No version entry in pubspec.yaml"
    exit 1
}
$semver = ($versionLine -replace "^version:\s*", "" -replace "\+.*$", "").Trim()
if (-not $semver) {
    Write-Error "[ERROR] Failed to extract semver"
    exit 1
}
Write-Host "[INFO] semver: $semver"

# 5) Prepare dist directory
New-Item -ItemType Directory -Force -Path $DIST_DIR | Out-Null

# 6) Compile installer via ISCC.exe
Write-Host "==== 4) Compile installer with Inno Setup ===="
& $iscc "/DMyAppVersion=$semver" $ISS_FILE
if ($LASTEXITCODE -ne 0) { Write-Error "[ERROR] ISCC compile failed"; exit 1 }

# 7) Verify installer artifact
$installerPath = Join-Path $DIST_DIR "AppfitOrderAgent-Setup-$semver.exe"
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
