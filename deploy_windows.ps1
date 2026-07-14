###############################################################################
# Flutter Windows Release 빌드 후 Lightsail(EC2) 서버에 ZIP 업로드 및
# Windows 버전 JSON 자동 업데이트 스크립트 (PowerShell)
#
# 사용법: .\deploy_windows.ps1
###############################################################################

# 콘솔/파이프라인 인코딩 UTF-8 고정 (한글 출력 깨짐 방지)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

# Single unified build for both regions. The server (live/japanLive) is chosen
# at runtime on the login screen, so there is no variant argument or
# APPFIT_VARIANT dart-define injection.

# 0) 사용자 정의 변수
# Windows OpenSSH scp는 -i 경로에 슬래시(/) 사용 필요
$PEM_KEY_PATH      = ($env:USERPROFILE + "/.ssh/LightsailDefaultKey-ap-northeast-3.pem") -replace '\\', '/'
$REMOTE_USER       = "ec2-user"
$REMOTE_HOST       = "52.78.172.188"
$REMOTE_DIR        = "/var/www/docs/waldpay_html"
# 채널은 레거시 무접미 하나만 사용한다. Windows 는 패키지 개념이 없고 exe명이
# 기존 설치본과 동일하므로, 기존 설치본이 이 채널로 자연스럽게 자동 업데이트된다.
# (Android 는 구 패키지 일본 매장 때문에 무접미 채널을 동결하고 _release 채널을
#  사용한다. 정책이 반대이니 혼동 주의.)
$ZIP_NAME          = "appfit_order_agent_windows.zip"
$VERSION_JSON_NAME = "appfit_order_agent_windows_version.json"
$BUILD_DIR         = "build\windows\x64"
$CACHE_FILE        = "$BUILD_DIR\CMakeCache.txt"
$BUILD_OUTPUT      = "$BUILD_DIR\runner\Release"
$INSTALL_PREFIX    = (Resolve-Path ".").Path + "\$BUILD_DIR\runner\Release"
$WINDOWS_SRC       = (Resolve-Path ".").Path + "\windows"

# Flutter 확인
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Error "Flutter를 찾을 수 없습니다. Flutter SDK를 설치하세요."
    exit 1
}

# cmake.exe 탐색 (Visual Studio 설치 경로)
$cmake = Get-ChildItem "C:\Program Files\Microsoft Visual Studio" -Recurse -Filter "cmake.exe" `
    -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "CMake\\bin" } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $cmake) { Write-Error "cmake.exe를 찾을 수 없습니다. Visual Studio가 설치되어 있는지 확인하세요."; exit 1 }

# CMake install prefix 확인 및 자동 수정
$needReconfigure = $false

if (-not (Test-Path $CACHE_FILE)) {
    Write-Host "[INFO] CMakeCache.txt 없음 - cmake reconfigure 필요"
    $needReconfigure = $true
} else {
    $currentPrefix = (Select-String -Path $CACHE_FILE -Pattern "^CMAKE_INSTALL_PREFIX:PATH=").Line `
        -replace "^CMAKE_INSTALL_PREFIX:PATH=", ""
    $expectedSuffix = "$BUILD_DIR\runner\Release" -replace "\\", "/"
    $currentNorm    = $currentPrefix -replace "\\", "/"

    if ($currentNorm -notmatch [regex]::Escape($expectedSuffix.TrimStart("./"))) {
        Write-Host "[INFO] CMAKE_INSTALL_PREFIX 불일치 ($currentPrefix) - reconfigure"
        $needReconfigure = $true
    }

    # generator platform 불일치 감지: -A x64 로 재구성하려는데
    # 기존 캐시가 다른 플랫폼(none/Win32 등)으로 잡혀 있으면 빌드가 실패한다.
    if (-not $needReconfigure) {
        $platformLine = (Select-String -Path $CACHE_FILE -Pattern "^CMAKE_GENERATOR_PLATFORM:" -ErrorAction SilentlyContinue).Line
        $currentPlatform = if ($platformLine) {
            ($platformLine -replace "^CMAKE_GENERATOR_PLATFORM:[^=]*=", "").Trim()
        } else { "" }
        if ($currentPlatform -ne "x64") {
            Write-Host "[INFO] CMAKE_GENERATOR_PLATFORM 불일치 ('$currentPlatform' != 'x64') - reconfigure"
            $needReconfigure = $true
        }
    }
}

if ($needReconfigure) {
    Write-Host "==== cmake reconfigure (install prefix 설정) ===="

    $sentryPatch = "C:\Users\Administrator\AppData\Local\Pub\Cache\hosted\pub.dev\sentry_flutter-8.14.2\sentry-native\sentry-native.cmake"
    if (Test-Path $sentryPatch) {
        $patchContent = Get-Content $sentryPatch -Raw
        if ($patchContent -notmatch 'GIT_SUBMODULES\s+""') {
            Write-Host "[경고] sentry-native.cmake에 GIT_SUBMODULES 패치가 없습니다."
            Write-Host "       chromium.googlesource.com 접근 실패 시 빌드가 중단될 수 있습니다."
        }
    }

    # ephemeral(generated_config.cmake, .plugin_symlinks) 생성 보장 - cmake보다 먼저 호출되어야 함
    $ephemeralDir = Join-Path $WINDOWS_SRC "flutter\ephemeral"
    $generatedConfig = Join-Path $ephemeralDir "generated_config.cmake"
    if (-not (Test-Path $generatedConfig)) {
        Write-Host "[INFO] flutter ephemeral 생성: flutter pub get + flutter build windows --config-only"
        flutter pub get
        if ($LASTEXITCODE -ne 0) { Write-Error "[오류] flutter pub get 실패!"; exit 1 }
        flutter build windows --config-only
        if ($LASTEXITCODE -ne 0) { Write-Error "[오류] flutter build windows --config-only 실패!"; exit 1 }
    }

    # 플랫폼/generator 불일치를 막기 위해 기존 cmake 산출물 제거 후 재구성
    if (Test-Path $CACHE_FILE) { Remove-Item $CACHE_FILE -Force }
    $cmakeFilesDir = Join-Path $BUILD_DIR "CMakeFiles"
    if (Test-Path $cmakeFilesDir) { Remove-Item $cmakeFilesDir -Recurse -Force }

    New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null
    & $cmake -S $WINDOWS_SRC -B $BUILD_DIR -A x64 -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DCMAKE_BUILD_TYPE=Release 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Error "cmake reconfigure 실패"; exit 1 }
    Write-Host "[OK] cmake reconfigure 완료"
    Write-Host ""
}

# 1) Flutter Windows Release 빌드
Write-Host "==== 1) Flutter build windows --release ===="
if (-not (Test-Path ".env")) {
    Write-Error "[오류] .env 파일이 없습니다. APPFIT_AES_KEY가 빌드에 주입되지 않으면 로그인 API가 실패합니다."
    exit 1
}
# 버전 로드 (Android 와 동일하게 pubspec.yaml 의 version 이 정본)
if (-not (Test-Path "pubspec.yaml")) {
    Write-Error "[오류] pubspec.yaml 파일이 없습니다. 레포 루트에서 실행하세요."
    exit 1
}
$WinVersionLine = ((Select-String -Path "pubspec.yaml" -Pattern '^version:' | Select-Object -First 1).Line `
    -replace '^version:\s*', '' -replace '#.*$', '').Trim().Trim('"').Trim("'")
if ($WinVersionLine -notmatch '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$') {
    Write-Error "[오류] pubspec.yaml 의 version 형식이 잘못됨: '$WinVersionLine' (기대: x.y.z+n)"
    exit 1
}
$WinBuildName   = $WinVersionLine.Split('+')[0]
$WinBuildNumber = $WinVersionLine.Split('+')[1]
Write-Host "[INFO] Windows 버전: $WinBuildName ($WinBuildNumber)"

flutter build windows --release `
    --dart-define-from-file=.env `
    --dart-define=WINDOWS_APP_VERSION="$WinBuildName" `
    --dart-define=WINDOWS_APP_BUILD="$WinBuildNumber" `
    --build-name="$WinBuildName" `
    --build-number="$WinBuildNumber"
if ($LASTEXITCODE -ne 0) { Write-Error "[오류] Flutter Windows 빌드 실패!"; exit 1 }

if (-not (Test-Path $BUILD_OUTPUT) -or -not (Get-ChildItem $BUILD_OUTPUT -ErrorAction SilentlyContinue)) {
    Write-Error "[오류] 빌드 산출물 디렉토리 없음: $BUILD_OUTPUT"
    exit 1
}

# 1-1) VC++ 런타임 DLL 번들링 (대상 PC에 Visual C++ Redistributable이 없어도 동작하도록)
Write-Host "==== 1-1) Bundle VC++ Runtime DLLs ===="

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
            Copy-Item -Path $srcPath -Destination $BUILD_OUTPUT -Force
            Write-Host "[INFO] Bundled: $dll"
        }
    }
    $copiedFrom = $srcDir
}

# 폴백: 아직 빠진 DLL이 있으면 System32에서 보강
$missing = @()
foreach ($dll in $dllNames) {
    if (-not (Test-Path (Join-Path $BUILD_OUTPUT $dll))) {
        $sys32 = Join-Path $env:WINDIR "System32\$dll"
        if (Test-Path $sys32) {
            Copy-Item -Path $sys32 -Destination $BUILD_OUTPUT -Force
            Write-Host "[INFO] Bundled(System32): $dll"
            if (-not $copiedFrom) { $copiedFrom = "$env:WINDIR\System32" }
        } else {
            $missing += $dll
        }
    }
}

if ($copiedFrom) {
    Write-Host "   복사 출처: $copiedFrom"
}

if ($missing.Count -gt 0) {
    Write-Host "[경고] 다음 DLL을 찾지 못했습니다: $($missing -join ', ')"
    Write-Host "       Microsoft Visual C++ Redistributable (x64)를 설치하거나, 수동으로 복사하세요."
}

# 2) Release 폴더를 ZIP으로 압축
Write-Host "==== 2) ZIP 압축: $BUILD_OUTPUT -> $ZIP_NAME ===="
if (Test-Path $ZIP_NAME) { Remove-Item $ZIP_NAME -Force }

$sourceItems = Get-ChildItem -Path $BUILD_OUTPUT | Select-Object -ExpandProperty FullName
Compress-Archive -Path $sourceItems -DestinationPath $ZIP_NAME -Force

if (-not (Test-Path $ZIP_NAME)) {
    Write-Error "[오류] ZIP 파일 생성 실패: $ZIP_NAME"
    exit 1
}
$zipSize = (Get-Item $ZIP_NAME).Length / 1MB
Write-Host ("[INFO] ZIP 생성 완료: $ZIP_NAME ({0:F1} MB)" -f $zipSize)

# 3) SCP로 서버에 ZIP 업로드
Write-Host "==== 3) Upload ZIP to Lightsail(EC2) server via SCP ===="
$scpDest = "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
& scp -o StrictHostKeyChecking=no -i $PEM_KEY_PATH $ZIP_NAME $scpDest
if ($LASTEXITCODE -ne 0) { Write-Error "[오류] scp ZIP 업로드 실패!"; exit 1 }
Write-Host "[INFO] ZIP 업로드 완료"

# 4) Windows 빌드 번호 (pubspec.yaml 정본 사용)
Write-Host "==== 4) Use build number from pubspec.yaml ===="
$buildNumber = $WinBuildNumber
Write-Host "빌드 번호: $buildNumber"

# 5) Windows 버전 JSON 생성 및 서버 업로드
Write-Host "==== 5) Upload Windows version JSON to server ===="
$versionJson = "{`"version`": $buildNumber}"
$versionJson | Out-File -FilePath "windows_version.json" -Encoding utf8 -NoNewline

$scpVersionDest = "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${VERSION_JSON_NAME}"
& scp -o StrictHostKeyChecking=no -i $PEM_KEY_PATH windows_version.json $scpVersionDest
if ($LASTEXITCODE -ne 0) {
    Remove-Item "windows_version.json" -Force
    Write-Error "[오류] version JSON 업로드 실패!"
    exit 1
}
Remove-Item "windows_version.json" -Force
Write-Host "[INFO] version JSON 업로드 완료: version = $buildNumber"

# 6) 로컬 아카이브 보관 + 노트 기록 + 폴더 열기 (배포 성공분만 보관)
Write-Host "==== 6) Archive Windows ZIP to local Project Files ===="
& "$PSScriptRoot\archive_windows.ps1" -SrcArtifact $ZIP_NAME

Write-Host "###############################################################################"
Write-Host "[완료] Windows 배포 완료!"
Write-Host "서버 경로: ${REMOTE_HOST}:${REMOTE_DIR}/${ZIP_NAME}"
Write-Host "OTA 업데이트 URL: http://waldpay.kokonutstamp2.com/$ZIP_NAME"
Write-Host "버전 JSON URL: http://waldpay.kokonutstamp2.com/$VERSION_JSON_NAME (version=$buildNumber)"
Write-Host "###############################################################################"
