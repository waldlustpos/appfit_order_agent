# 윈도우 릴리스 빌드 스크립트 (PowerShell)
# 사용법: .\build_windows.ps1 [-Variant update|standalone]

param(
    [ValidateSet('update','standalone')]
    [string]$Variant = 'update'
)

# 콘솔/파이프라인 인코딩 UTF-8 고정 (한글 출력 깨짐 방지)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

$ErrorActionPreference = "Stop"

# === Build variant selection ===
# standalone makes CMake branch the exe name (BINARY_NAME) and compile macros.
# CMake freezes BINARY_NAME at configure time, so if the previous build used a
# different variant, wipe build/windows to force a clean reconfigure.
$VariantSentinel = "build\.appfit_windows_variant"
$prevVariant = if (Test-Path $VariantSentinel) { (Get-Content $VariantSentinel -Raw).Trim() } else { "" }
if ($prevVariant -ne $Variant -and (Test-Path "build\windows")) {
    Write-Host "[INFO] Build variant changed ($prevVariant -> $Variant): cleaning build/windows" -ForegroundColor Yellow
    Remove-Item "build\windows" -Recurse -Force
}
New-Item -ItemType Directory -Force -Path "build" | Out-Null
Set-Content -Path $VariantSentinel -Value $Variant -NoNewline
if ($Variant -eq 'standalone') {
    $env:APPFIT_WINDOWS_VARIANT = 'standalone'
    $ExeName = 'appfit_order_agent_standalone.exe'
} else {
    Remove-Item Env:\APPFIT_WINDOWS_VARIANT -ErrorAction SilentlyContinue
    $ExeName = 'appfit_order_agent.exe'
}
Write-Host "[INFO] Build variant: $Variant (exe: $ExeName)" -ForegroundColor Cyan

Write-Host "🚀 Windows Release 빌드 시작..." -ForegroundColor Green
Write-Host ""

# Flutter 확인
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host "❌ Flutter를 찾을 수 없습니다. Flutter SDK를 설치하세요." -ForegroundColor Red
    exit 1
}

# 빌드 실행
Write-Host "📦 Windows Release 빌드 중..." -ForegroundColor Cyan
if (-not (Test-Path ".env")) {
    Write-Host "❌ .env 파일이 없습니다. APPFIT_AES_KEY가 빌드에 주입되지 않으면 로그인 API가 실패합니다." -ForegroundColor Red
    exit 1
}
# Windows 전용 버전 로드 (pubspec.yaml과 분리 관리 — version_windows.txt가 정본)
if (-not (Test-Path "version_windows.txt")) {
    Write-Host "❌ version_windows.txt 파일이 없습니다. 예: 1.0.0+1" -ForegroundColor Red
    exit 1
}
$WinVersionLine = (Get-Content "version_windows.txt" | Where-Object { $_ -match '^[0-9]' } | Select-Object -First 1).Trim()
if ($WinVersionLine -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$') {
    Write-Host "❌ version_windows.txt 형식이 잘못됨: '$WinVersionLine' (기대: x.y.z+n)" -ForegroundColor Red
    exit 1
}
$WinBuildName   = $WinVersionLine.Split('+')[0]
$WinBuildNumber = $WinVersionLine.Split('+')[1]
Write-Host "🏷  Windows 버전: $WinBuildName ($WinBuildNumber)" -ForegroundColor Cyan

flutter build windows --release `
    --dart-define-from-file=.env `
    --dart-define=WINDOWS_APP_VERSION="$WinBuildName" `
    --dart-define=WINDOWS_APP_BUILD="$WinBuildNumber" `
    --dart-define=APPFIT_VARIANT="$Variant" `
    --build-name="$WinBuildName" `
    --build-number="$WinBuildNumber"

# Flutter 3.29+ 는 x64 하위 폴더에 산출물을 둔다
$buildOutput = "build\windows\x64\runner\Release"

if (-not (Test-Path $buildOutput)) {
    Write-Host ""
    Write-Host "❌ 빌드 실패: 출력 폴더를 찾을 수 없습니다. ($buildOutput)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ 빌드 완료!" -ForegroundColor Green
Write-Host "📂 출력 폴더: $buildOutput"
Write-Host ""

# --- VC++ 런타임 DLL 자동 번들 ---
Write-Host "🔧 VC++ 런타임 DLL 번들 중..." -ForegroundColor Cyan

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
$copiedFrom = $null

if ($srcDir) {
    foreach ($dll in $dllNames) {
        $srcPath = Join-Path $srcDir $dll
        if (Test-Path $srcPath) {
            Copy-Item -Path $srcPath -Destination $buildOutput -Force
        }
    }
    $copiedFrom = $srcDir
}

# 폴백: 아직 빠진 DLL 이 있으면 System32 에서 보강
$missing = @()
foreach ($dll in $dllNames) {
    if (-not (Test-Path (Join-Path $buildOutput $dll))) {
        $sys32 = Join-Path $env:WINDIR "System32\$dll"
        if (Test-Path $sys32) {
            Copy-Item -Path $sys32 -Destination $buildOutput -Force
            if (-not $copiedFrom) { $copiedFrom = "$env:WINDIR\System32" }
        } else {
            $missing += $dll
        }
    }
}

if ($copiedFrom) {
    Write-Host "   ↳ 복사 출처: $copiedFrom" -ForegroundColor DarkGray
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠️  다음 DLL 을 찾지 못했습니다: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host "   → Microsoft Visual C++ Redistributable (x64) 를 설치하거나, 수동으로 복사하세요." -ForegroundColor Yellow
} else {
    Write-Host "✅ VC++ 런타임 DLL 번들 완료 (3/3)" -ForegroundColor Green
}

Write-Host ""

# --- 빌드 폴더 자동 열기 ---
$fullPath = (Get-Item $buildOutput).FullName
Start-Process -FilePath explorer.exe -ArgumentList "`"$fullPath`"" -ErrorAction SilentlyContinue

Write-Host "💡 배포 시 포함되어야 할 파일:" -ForegroundColor Yellow
Write-Host "   - $ExeName (메인 실행파일)"
Write-Host "   - vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll (VC++ 런타임)"
Write-Host "   - flutter_windows.dll, *_plugin.dll (Flutter/플러그인)"
Write-Host "   - data\ 폴더 (flutter_assets, icudtl.dat, app.so)"
Write-Host ""
Write-Host "ℹ️  Release 폴더 전체를 ZIP 으로 압축해 배포하면 됩니다." -ForegroundColor Cyan

# --- 로컬 아카이브 보관 (Release 폴더를 ZIP 으로 압축해 버전별 보관 + 노트 기록 + 폴더 열기) ---
Write-Host ""
& "$PSScriptRoot\archive_windows.ps1" -SrcArtifact $buildOutput -Variant $Variant
