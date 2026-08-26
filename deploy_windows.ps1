###############################################################################
# Flutter Windows Release 빌드 후 Lightsail(EC2) 서버에 ZIP 업로드 및
# Windows 버전 JSON 자동 업데이트 스크립트 (PowerShell)
#
# 사용법:
#   .\deploy_windows.ps1 [-Brand common|mammoth]   빌드부터 업로드까지 전부 수행
#   .\deploy_windows.ps1 -SkipBuild                빌드를 건너뛰고 기존 Release
#                                                  폴더를 그대로 포장
#
# -SkipBuild 를 쓰는 이유:
#   이 스크립트와 build_installer.ps1 이 각각 flutter build 를 돌리면 러너 exe
#   가 두 번 링크된다. MSVC 링커는 링크할 때마다 PE 헤더의 TimeDateStamp 와
#   PDB 서명 GUID 를 새로 새기므로, 소스가 같아도 두 산출물의 해시가 달라진다
#   (크기는 같다). Defender 평판은 해시 단위로 쌓이므로 릴리즈마다 평판 0 인
#   바이너리가 둘 생기고, 오탐 신고도 두 건을 내야 한다.
#
#   아래 순서로 돌리면 설치본과 OTA ZIP 이 문자 그대로 같은 exe 를 담는다.
#       .\build_installer.ps1 -Brand <brand>
#       .\deploy_windows.ps1  -Brand <brand> -SkipBuild
###############################################################################

param(
    [ValidateSet('common', 'mammoth')]
    [string]$Brand = 'common',
    [switch]$SkipBuild
)

# 콘솔/파이프라인 인코딩 UTF-8 고정 (한글 출력 깨짐 방지)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

# 지역(한국/일본)은 이 빌드와 무관 — 서버(live/japanLive)는 로그인 화면에서
# 런타임 선택된다. 채널은 브랜드가 아니라 **아티팩트**에 종속(ota_config.dart
# 와 동일 원칙) — Tier 1 아티팩트는 자기 exe명이 다르므로 공통 채널을 물리적으로
# 쓸 수 없다(자연 업데이트가 안 걸린다).

# 0) 사용자 정의 변수
# Windows OpenSSH scp는 -i 경로에 슬래시(/) 사용 필요
$PEM_KEY_PATH      = ($env:USERPROFILE + "/.ssh/LightsailDefaultKey-ap-northeast-3.pem") -replace '\\', '/'
$REMOTE_USER       = "ec2-user"
$REMOTE_HOST       = "52.78.172.188"
$REMOTE_DIR        = "/var/www/docs/waldpay_html"
# 공통은 레거시 무접미 채널(그대로 유지 — Windows 는 패키지 개념이 없고 exe명이
# 기존 설치본과 동일하므로, 기존 설치본이 이 채널로 자연스럽게 자동 업데이트된다.
# Android 는 구 패키지 일본 매장 때문에 무접미 채널을 동결하고 _release 채널을
# 쓴다. 정책이 반대이니 혼동 주의). 매머드는 전용 채널 신설 — 매머드 exe 는
# 공통 채널 ZIP 을 받아도 파일명이 달라 자연 업데이트가 걸리지 않는다.
$ZIP_NAME          = if ($Brand -eq 'mammoth') { "appfit_order_agent_mammoth_windows.zip" } else { "appfit_order_agent_windows.zip" }
$VERSION_JSON_NAME = if ($Brand -eq 'mammoth') { "appfit_order_agent_mammoth_windows_version.json" } else { "appfit_order_agent_windows_version.json" }
Write-Host "[INFO] Brand: $Brand / Channel: $ZIP_NAME"

# 브랜드 전환 시 CMake 캐시가 이전 BINARY_NAME 을 참조해 두 exe 가 같은
# Release 폴더에 공존하는 사고를 막는다(같은 ZIP 에 잘못된 exe 까지 함께
# 담길 수 있음). CMakeCache.txt/CMakeFiles 만 정밀 삭제한다 — build\windows
# 전체를 지우면(특히 _deps, 즉 sentry-native 재fetch 를 동반한 완전 콜드
# configure) 이 머신의 CMake+VS2022 조합에서 generator platform 기록이
# 비어버리는 간헐적 버그를 실측했다. 이 클린이 아래 CACHE_FILE 체크보다
# 먼저 와야, 그 체크가 "캐시 없음 -> reconfigure" 로 올바르게 판정한다.
$BrandSentinel = "build\windows\.appfit_brand"
$previousBrand = if (Test-Path $BrandSentinel) { (Get-Content $BrandSentinel -Raw).Trim() } else { $null }
if ($previousBrand -and $previousBrand -ne $Brand) {
    Write-Host "[INFO] Brand changed ($previousBrand -> $Brand) - cleaning CMake cache + stale exe"
    Remove-Item "build\windows\x64\CMakeCache.txt" -Force -ErrorAction SilentlyContinue
    Remove-Item "build\windows\x64\CMakeFiles" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "build\windows\x64\runner\Release\*.exe" -Force -ErrorAction SilentlyContinue
}
$env:APPFIT_BRAND = $Brand

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

if ($SkipBuild) {
    Write-Host "==== Flutter build 생략 (-SkipBuild) ===="
    Write-Host "     기존 $BUILD_OUTPUT 을 그대로 포장합니다."
} else {
    flutter build windows --release `
        --dart-define-from-file=.env `
        --dart-define=APPFIT_BRAND="$Brand" `
        --dart-define=WINDOWS_APP_VERSION="$WinBuildName" `
        --dart-define=WINDOWS_APP_BUILD="$WinBuildNumber" `
        --build-name="$WinBuildName" `
        --build-number="$WinBuildNumber"
    if ($LASTEXITCODE -ne 0) { Write-Error "[오류] Flutter Windows 빌드 실패!"; exit 1 }
}

if (-not (Test-Path $BUILD_OUTPUT) -or -not (Get-ChildItem $BUILD_OUTPUT -ErrorAction SilentlyContinue)) {
    Write-Error "[오류] 빌드 산출물 디렉토리 없음: $BUILD_OUTPUT"
    if ($SkipBuild) {
        Write-Error "       -SkipBuild 를 뺀 채 다시 실행하거나 build_installer.ps1 을 먼저 돌리세요."
    }
    exit 1
}

# 1-0) 산출물과 pubspec 버전 일치 검증.
# -SkipBuild 의 가장 큰 위험은 낡은 Release 폴더를 새 버전 번호로 올리는 것이다.
# 그러면 version JSON 은 새 빌드번호를 가리키는데 매장이 받는 바이너리는 구버전
# 이라, 매장이 업데이트를 받아도 계속 같은 팝업을 보게 된다. 빌드 경로에서도
# 무해한 검증이므로 두 모드 모두에서 돌린다.
#
# 브랜드마다 exe 명이 다르므로(공통/매머드) 대상 파일을 브랜드로 분기한다 —
# 브랜드 전환 직후 남아 있던 이전 브랜드 exe 를 검사해 버리면 무의미하다.
Write-Host "==== 1-0) 산출물 버전 검증 ===="
$ExeName = if ($Brand -eq 'mammoth') { "appfit_order_agent_mammoth.exe" } else { "appfit_order_agent.exe" }
$exePath = Join-Path $BUILD_OUTPUT $ExeName
if (-not (Test-Path $exePath)) {
    Write-Error "[오류] exe 없음: $exePath"
    Write-Error "       Release 폴더가 다른 브랜드 빌드이거나 비어 있습니다."
    exit 1
}
$exeVersion = (Get-Item $exePath).VersionInfo.ProductVersion
if ($exeVersion -ne $WinVersionLine) {
    Write-Error "[오류] 산출물 버전 불일치: exe=$exeVersion, pubspec=$WinVersionLine"
    Write-Error "       Release 폴더가 오래된 빌드입니다. -SkipBuild 를 빼고 다시 빌드하세요."
    exit 1
}
Write-Host "[OK] 버전 일치: $exeVersion"
Write-Host ("     exe 링크 시각: {0}" -f (Get-Item $exePath).LastWriteTime)

# 브랜드 sentinel 갱신 (다음 실행의 브랜드 전환 감지용)
New-Item -ItemType Directory -Force -Path "build\windows" | Out-Null
Set-Content -Path $BrandSentinel -Value $Brand -NoNewline

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
& "$PSScriptRoot\archive_windows.ps1" -SrcArtifact $ZIP_NAME -Brand $Brand

Write-Host "###############################################################################"
Write-Host "[완료] Windows 배포 완료!"
Write-Host "서버 경로: ${REMOTE_HOST}:${REMOTE_DIR}/${ZIP_NAME}"
Write-Host "OTA 업데이트 URL: http://waldpay.kokonutstamp2.com/$ZIP_NAME"
Write-Host "버전 JSON URL: http://waldpay.kokonutstamp2.com/$VERSION_JSON_NAME (version=$buildNumber)"
Write-Host "###############################################################################"
