# Windows 빌드 아카이브 가이드 (archive_windows.ps1)

Windows 빌드 산출물을 로컬 공용 보관소(`!Project Files`)에 버전별로 보관하고
빌드 노트를 남기는 스크립트입니다. **Mac 에서는 실행되지 않으므로**, Windows 빌드
PC 에서 이 저장소를 `git pull` 한 뒤 아래 절차대로 실행하세요.

> 보통은 **직접 실행할 필요가 없습니다.** `deploy_windows.ps1` / `build_windows.ps1` /
> `build_installer.ps1` 이 빌드·배포 성공 직후 이 스크립트를 **자동 호출**합니다.
> 아래는 수동으로 보관하거나 동작을 이해하기 위한 참고입니다.

## 전제
- 빌드/배포 스크립트가 산출물을 만든 상태.
- appfit 은 **단일 빌드**입니다: 단일 패키지(`co.kr.waldlust.order.receive.appfit`)·단일 exe(`appfit_order_agent.exe`)가 한국/일본을 모두 서빙하고, 서버(live/japanLive)는 앱 로그인 화면에서 런타임 선택됩니다. ZIP 채널도 하나입니다: `appfit_order_agent_windows.zip`.
- 버전 정본은 `version_windows.txt` 입니다 (pubspec.yaml 과 분리).

## 입력(`-SrcArtifact`) — 3가지 산출물 지원
| 산출물 | 생성 스크립트 | 보관 방식 |
| --- | --- | --- |
| ZIP 파일 | `deploy_windows.ps1` | 그대로 복사 |
| 설치본 `.exe` | `build_installer.ps1` (`dist\AppfitOrderAgent-Setup-<semver>.exe`) | 그대로 복사 |
| Release 폴더 | `build_windows.ps1` (`build\windows\x64\runner\Release`) | `appfit_order_agent_windows.zip` 으로 압축 |

## 실행 (수동)
프로젝트 루트(`pubspec.yaml` 이 있는 폴더)에서 PowerShell 로:

```powershell
# ZIP 보관
.\archive_windows.ps1 -SrcArtifact .\appfit_order_agent_windows.zip

# 설치본 보관
.\archive_windows.ps1 -SrcArtifact .\dist\AppfitOrderAgent-Setup-3.3.6.exe

# Release 폴더 보관 (폴더를 주면 자동으로 ZIP 압축)
.\archive_windows.ps1 -SrcArtifact .\build\windows\x64\runner\Release

# 보관소 위치를 바꾸고 싶을 때 (기본: ~\Documents\!Project Files)
.\archive_windows.ps1 -SrcArtifact .\appfit_order_agent_windows.zip -ArchiveBase "D:\Builds"
```

스크립트 실행 정책 때문에 막히면:

```powershell
powershell -ExecutionPolicy Bypass -File .\archive_windows.ps1 -SrcArtifact .\appfit_order_agent_windows.zip
```

## 결과 보관 구조
```
<ArchiveBase>\appfit_order_agent\windows\<버전>\
   ├─ appfit_order_agent_windows.zip      (또는 설치본 .exe)
   └─ release_notes.txt
```
예: `C:\Users\<user>\Documents\!Project Files\appfit_order_agent\windows\3.3.6+152\`

`release_notes.txt` 에는 버전 / 빌드번호 / 패키지명 / 빌드 일시 / 산출물 파일명 /
최근 git 커밋 5개가 기록됩니다. 완료 후 해당 버전 폴더가 탐색기로 열립니다.

## 동작 메모
- 아카이브 실패(소스 없음·복사 실패 등)는 경고만 출력하고 `exit 0` 으로 끝납니다.
  배포 흐름을 막지 않습니다.
- 동일 버전 재빌드 시 산출물 / 노트는 덮어쓰기됩니다.
