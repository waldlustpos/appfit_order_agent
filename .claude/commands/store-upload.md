---
description: Sunmi App Store 수동 업로드 절차 강제 + 로컬 이력 기록 (common/mammoth 브랜드 선택)
---

Sunmi App Store 업로드는 콘솔 UI 작업이라 **자동화할 수 없다**. 이 명령어는
업로드 자체를 대신하지 않고, 그 앞뒤의 검증·확인·이력 기록을 강제해 사고를
줄인다 — 잘못된 아티팩트를 잘못된 리스팅에 올리는 실수는 되돌릴 수 없다.

## 1단계 — 브랜드 선택

`AskUserQuestion` 으로 묻는다: **common**(기본, 공통 리스팅)/**mammoth**(매머드
전용 리스팅). 매머드는 별도 App Store 리스팅이 필요하며, **아직 등록되지
않았다면 여기서 멈추고 사용자에게 알린다** — 등록 없이 업로드할 방법이 없다.

## 2단계 — 아티팩트 확인

빌드된 APK 가 있는지 확인한다. 없으면 `/release-apk <브랜드>` 로 먼저 빌드하라고
안내한다. 있으면 Bash 툴로 `aapt dump badging` 을 실행해 재확인:

```
aapt dump badging <APK 경로> | grep -E "^package:|^application-label"
```

- `package:` 가 선택한 브랜드와 일치하는지(`co.kr.waldlust.order.receive.appfit` /
  `….appfit.mammoth`) 확인 — **불일치면 중단**하고 재빌드를 안내한다.
- `versionCode` 를 `pubspec.yaml` 의 빌드번호와 대조한다.
- `application-label` 이 브랜드에 맞는지(`Appfit 주문 접수` / `매머드오더 에이전트`) 확인한다.
- 서명 확인: `apksigner verify <APK 경로>` (Android SDK build-tools 에 포함). 실패하면 릴리즈 키로 서명되지 않았을 가능성 — 중단하고 안내.

## 3단계 — Gray 타깃 범위 확인

사용자에게 이번 업로드의 gray canary 범위를 묻는다(예: "매장 5곳", "전체").
Sunmi 콘솔에서 매장/기기 단위로 단계 배포가 가능하다는 점을 상기시킨다.
`docs/RELEASE.md` 의 릴리즈 절차(canary → 검증 → 확대)를 따르도록 안내한다.

## 4단계 — 사용자가 콘솔에서 업로드 수행

이 단계는 사람이 Sunmi App Store 콘솔에서 직접 한다. 에이전트는 다음을 안내만
한다:
- 업로드할 정확한 APK 파일 경로(위 2단계에서 검증한 그 파일)
- 대상 리스팅(공통/매머드 — 다른 리스팅에 올리면 되돌릴 수 없다)
- gray 범위(3단계에서 확인한 값)

업로드가 끝났으면 사용자에게 "완료되었습니까?"를 묻는다. "예"가 아니면 5단계로
넘어가지 않는다.

## 5단계 — 로컬 이력 기록

업로드 완료 확인 후, Bash 툴로 이력 파일에 한 줄을 append 한다(없으면 생성):

```
<ISO8601 일시> | brand=<브랜드> | version=<pubspec 버전> | versionCode=<versionCode> | gray=<gray 범위> | committer=<git log 최근 커밋 해시>
```

경로: `~/Documents/!Project Files/appfit_order_agent/store_uploads.log`
(플랫폼 무관하게 `$HOME/Documents/!Project Files/...` — Windows Git Bash 는
`/c/Users/<user>/Documents/...`).

> 이 파일이 스토어 업로드의 **유일한 정본**이다 — 서버 JSON 처럼 자동 생성되는
> 이력이 없다(OTA 채널과 달리 스토어 업로드는 앱이 조회할 방법이 없다).

## 5-1단계 — Fleet 대시보드에 배포 버전 게시 (**mammoth 만**)

`common` 이면 이 단계를 건너뛴다 — Fleet 이 표기하는 Sunmi 칸은 매머드 하나뿐이다
(`docs/RELEASE.md`: Sunmi App Store 관리 함대 = `sunmiAppStoreUpdate` 브랜드 = 매머드).

Sunmi 스토어에는 OTA 의 version JSON 같은 조회 지점이 없다. 이 단계가 같은 정보를
정적 호스트에 한 벌 올려, Fleet 대시보드가 나머지 4개 OTA 채널과 **같은 방식으로**
읽게 한다(`appfit-fleet` 의 `RELEASE_ARTIFACTS`).

> **이 파일은 채널이 아니다.** 앱은 폴링하지 않고 아티팩트도 딸려 있지 않다 —
> `fleet_stores.json` 과 같은 성격의 수동 자산이라 `fleet_` 접두사를 쓴다.
> `docs/RELEASE.md` 의 채널 불변식("아티팩트 없이 채널만 늘리지 않는다")과 무관하다.

Bash 툴로 아래를 그대로 실행한다. `<...>` 는 앞 단계에서 **이미 확정된 값**으로
채운다(5단계에 append 한 이력 라인과 같은 값이어야 한다).

```bash
cat > /tmp/fleet_sunmi_mammoth_version.json <<EOF
{"version": <versionCode>, "versionName": "<pubspec x.y.z>", "gray": "<gray 범위>", "uploadedAt": "<ISO8601 일시>", "committer": "<커밋 해시>"}
EOF
scp -o StrictHostKeyChecking=no -i ~/.ssh/LightsailDefaultKey-ap-northeast-3.pem \
  /tmp/fleet_sunmi_mammoth_version.json \
  ec2-user@52.78.172.188:/var/www/docs/waldpay_html/fleet_sunmi_mammoth_version.json \
  && curl -s https://waldpay.kokonutstamp2.com/fleet_sunmi_mammoth_version.json
```

- `version` 키 이름은 OTA version JSON 과 **일부러 같게** 둔다 — Fleet 이 5개를 한
  파서로 읽는다. 나머지 키는 Fleet 이 선택적으로 표기하는 부가 정보다.
- 배포 시각은 넣지 않아도 된다 — Fleet 은 파일의 `Last-Modified` 를 쓴다.
- **실패해도 중단하지 않는다.** 5단계의 로컬 로그가 여전히 유일한 정본이고 이
  파일은 대시보드 표기용 사본일 뿐이다. 사용자에게 "Fleet 표기만 갱신 안 됨"으로
  알리고 다음으로 넘어간다.

## 실행 후

- 기록된 이력 라인을 보여준다
- 다음 단계(canary 검증 기간, 확대 시점)를 `docs/RELEASE.md` 릴리즈 절차 기준으로 안내한다
- **마지막 단계는 항상 OTA 갱신이다** — 스토어 canary 검증이 끝나면 `/deploy-android <브랜드>` 로 OTA 채널도 채워야 완결된다(빈 채널은 안전망이 아니다)
