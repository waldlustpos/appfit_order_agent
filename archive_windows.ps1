###############################################################################
# Windows 빌드 산출물을 로컬 공용 보관소에 아카이브하고 빌드 노트를 기록한 뒤
# 해당 버전 폴더를 탐색기로 연다. (PowerShell)
#
# 사용법:
#   .\archive_windows.ps1 -SrcArtifact <경로> [-ArchiveBase <dir>]
#     - -SrcArtifact : 보관할 산출물. 다음 셋 중 하나
#         * ZIP 파일 (deploy_windows.ps1 산출물)        → 그대로 복사
#         * 설치본 .exe (build_installer.ps1 산출물)    → 그대로 복사
#         * Release 폴더 (build_windows.ps1 산출물)     → <project>_windows.zip 으로 압축해 보관
#     - -ArchiveBase : 공용 보관소 베이스 (기본: ~\Documents\!Project Files)
#
# 보관 구조: <ArchiveBase>\<프로젝트명>\windows\<버전>\<산출물> + release_notes.txt
#   예) C:\Users\<user>\Documents\!Project Files\appfit_order_agent\windows\3.3.6+152\
#
# 버전 정본: appfit Windows 는 version_windows.txt 가 정본 (pubspec.yaml 과 분리).
#
# 주의: deploy/build 가 이미 끝난 뒤 호출되므로, 아카이브 실패가 전체 흐름을
#       중단시키지 않도록 항상 경고만 출력하고 exit 0 으로 끝낸다.
###############################################################################

param(
    [Parameter(Mandatory = $true)][string]$SrcArtifact,
    [string]$ArchiveBase = (Join-Path $env:USERPROFILE 'Documents\!Project Files')
)

# 콘솔/파이프라인 인코딩 UTF-8 고정 (한글 출력 깨짐 방지)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

# 아카이브 실패가 배포 흐름을 막지 않도록 비중단 정책
$ErrorActionPreference = 'Continue'

Write-Host "==== Archive Windows artifact to local Project Files ===="

# pubspec.yaml 에서 프로젝트명 추출
$projectName = ((Select-String -Path 'pubspec.yaml' -Pattern '^name:').Line -replace '^name:\s*', '').Trim().Trim('"').Trim("'")

# 버전 정본: version_windows.txt (없으면 pubspec.yaml 폴백)
if (Test-Path 'version_windows.txt') {
    $version = (Get-Content 'version_windows.txt' | Where-Object { $_ -match '^[0-9]' } | Select-Object -First 1).Trim()
} else {
    Write-Host "[경고] version_windows.txt 없음 - pubspec.yaml 버전으로 폴백"
    $version = ((Select-String -Path 'pubspec.yaml' -Pattern '^version:').Line -replace '^version:\s*', '').Trim().Trim('"').Trim("'")
}
$buildNumber = ($version -replace '.*\+', '')

# 단일 패키지 (국가 무관)
$appId = 'co.kr.waldlust.order.receive.appfit'

$archiveDir = Join-Path $ArchiveBase (Join-Path $projectName (Join-Path 'windows' $version))

# 소스 산출물 확인
if (-not (Test-Path $SrcArtifact)) {
    Write-Host "[경고] 아카이브할 산출물이 없습니다: $SrcArtifact (아카이브 건너뜀)"
    exit 0
}

# 보관 폴더 생성
try {
    New-Item -ItemType Directory -Force -Path $archiveDir -ErrorAction Stop | Out-Null
} catch {
    Write-Host "[경고] 아카이브 폴더 생성 실패: $archiveDir (아카이브 건너뜀)"
    exit 0
}

# 산출물 보관: 폴더면 ZIP 압축, 파일이면 그대로 복사
$srcItem = Get-Item $SrcArtifact
try {
    if ($srcItem.PSIsContainer) {
        # Release 폴더 -> <project>_windows.zip 압축
        $artifactName = "${projectName}_windows.zip"
        $destZip = Join-Path $archiveDir $artifactName
        if (Test-Path $destZip) { Remove-Item $destZip -Force }
        $items = Get-ChildItem -Path $SrcArtifact | Select-Object -ExpandProperty FullName
        Compress-Archive -Path $items -DestinationPath $destZip -Force -ErrorAction Stop
    } else {
        # ZIP / 설치본 .exe -> 그대로 복사 (덮어쓰기)
        $artifactName = $srcItem.Name
        Copy-Item -Path $SrcArtifact -Destination $archiveDir -Force -ErrorAction Stop
    }
} catch {
    Write-Host "[경고] 산출물 보관 실패: $SrcArtifact -> $archiveDir (아카이브 건너뜀)"
    exit 0
}

# 빌드 노트 기록 (덮어쓰기)
$notesFile = Join-Path $archiveDir "release_notes.txt"
$gitLog = (git log --oneline -5 2>$null)
if (-not $gitLog) { $gitLog = '(git 정보 없음)' }

$notes = @"
=== $projectName Windows 빌드 노트 ===
버전: $version
빌드번호: $buildNumber
패키지명: $appId
빌드 일시: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
산출물: $artifactName

--- 최근 git 커밋 (5) ---
$gitLog
"@
$notes | Out-File -FilePath $notesFile -Encoding utf8

Write-Host "✅ 아카이브 완료: $archiveDir"
Write-Host "   - 산출물: $artifactName"
Write-Host "   - 노트: $(Split-Path -Leaf $notesFile)"

# 보관한 버전 폴더 열기 (Windows 탐색기)
Start-Process -FilePath explorer.exe -ArgumentList "`"$archiveDir`"" -ErrorAction SilentlyContinue

exit 0
