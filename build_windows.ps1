# 윈도우 릴리스 빌드 스크립트 (PowerShell)
# 사용법: .\build_windows.ps1

# 콘솔/파이프라인 인코딩 UTF-8 고정 (한글 출력 깨짐 방지)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

$ErrorActionPreference = "Stop"

# Single unified build for both regions. The server (live/japanLive) is chosen
# at runtime on the login screen, so there is no variant argument or
# APPFIT_VARIANT dart-define injection.
$ExeName = 'appfit_order_agent.exe'
Write-Host "[INFO] Build exe: $ExeName" -ForegroundColor Cyan

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

# Flutter 3.29+ 는 x64 하위 폴더에 산출물을 둔다
$buildOutput = "build\windows\x64\runner\Release"

# 주의: 함수가 값을 return 하면 flutter 의 콘솔 출력까지 반환값에 섞인다.
# 따라서 여기서는 아무것도 return 하지 않고(빌드 진행 출력은 콘솔로 그대로 흘림),
# 호출부에서 전역 $LASTEXITCODE 를 직접 읽어 종료 코드를 판정한다.
function Invoke-FlutterWindowsBuild {
    flutter build windows --release `
        --dart-define-from-file=.env `
        --dart-define=WINDOWS_APP_VERSION="$WinBuildName" `
        --dart-define=WINDOWS_APP_BUILD="$WinBuildNumber" `
        --build-name="$WinBuildName" `
        --build-number="$WinBuildNumber"
}

# 산출물 무결성 검사: exe 만으로는 부족하다.
# fresh CMake configure 직후 첫 INSTALL 패스가 비결정적으로 실패하면 exe 는 생기지만
# data\ (app.so/flutter_assets/icudtl.dat) 와 flutter_windows.dll 복사가 통째로 누락된다.
# 따라서 exe + flutter_windows.dll + data\app.so 세 가지가 모두 있어야 정상 빌드로 본다.
function Test-BuildArtifactComplete {
    return (Test-Path (Join-Path $buildOutput $ExeName)) `
        -and (Test-Path (Join-Path $buildOutput "flutter_windows.dll")) `
        -and (Test-Path (Join-Path $buildOutput "data\app.so"))
}

# $ErrorActionPreference="Stop" 는 네이티브 exe(flutter/cmake) 의 비정상 종료코드를 잡지 못하므로
# $LASTEXITCODE 를 직접 검사한다. 첫 패스가 실패/불완전하면 같은 build 디렉터리로 1회 재빌드한다.
# (두 번째 증분 패스에서는 INSTALL 단계가 안정적으로 성공한다.)
Invoke-FlutterWindowsBuild
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0 -or -not (Test-BuildArtifactComplete)) {
    Write-Host ""
    Write-Host "⚠️  첫 빌드 패스 실패/불완전 (exit=$exitCode). 같은 build 디렉터리로 1회 재빌드합니다..." -ForegroundColor Yellow
    Write-Host ""
    Invoke-FlutterWindowsBuild
    $exitCode = $LASTEXITCODE
}

if ($exitCode -ne 0 -or -not (Test-BuildArtifactComplete)) {
    Write-Host ""
    Write-Host "❌ 빌드 실패: 재시도 후에도 산출물이 불완전합니다 (exit=$exitCode)." -ForegroundColor Red
    Write-Host "   필수 파일: $ExeName, flutter_windows.dll, data\app.so" -ForegroundColor Red
    Write-Host "   깨진 산출물이 아카이브/배포되지 않도록 여기서 중단합니다." -ForegroundColor Red
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
& "$PSScriptRoot\archive_windows.ps1" -SrcArtifact $buildOutput
