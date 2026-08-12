---
name: reference-sentry-delayed-ingest
description: 네트워크 장애로 생긴 Sentry 이벤트는 앱 재시작 후에야 도착 — 슬랙 알림 시각 ≠ 발생 시각. 알림 규칙 lastTriggered 로 판별
metadata: 
  node_type: memory
  type: reference
  originSessionId: edc1203b-2e3b-4f14-a2b6-1624bccc6e84
  modified: 2026-08-12T02:49:16.847Z
---

**Sentry 알림 규칙은 이벤트가 *발생*한 시각이 아니라 서버에 *도착*한 시각에 평가된다.**
그래서 네트워크 장애로 생긴 이벤트는 구조적으로 늦게 알림이 온다 — 그 장애 때문에 전송 자체가
막히기 때문이다. sentry_flutter 는 실패한 envelope 을 디스크에 캐시한다(앱은 cache 옵션을
건드리지 않아 기본값 사용).

**관측 사실(2026-08-11 PAIK00002)**: 21:09/21:19 발생분이 다음 날 **07:00** 에 슬랙 도착
(9시간 41분 지연). 결정적으로, **21:19:20 네트워크가 회복된 뒤 앱이 11분을 더 돌았는데도
캐시분은 안 올라갔다.** 즉 네트워크 회복만으로는 부족하고 **앱 재시작이 있어야 플러시된다**
(이 기기는 매일 07시경 부팅 — `boot_time` 태그로 확인 가능). 추정이 아니라 관측이다.

**판별법**: `find_alert_rules(kind='issue')` 의 `lastTriggered` 를 이벤트 timestamp 와 비교한다.
정상이면 19~40초 차이. 몇 시간씩 벌어졌으면 지연 인제스트다. 같은 프로젝트의 다른 매장 규칙과
나란히 보면 "규칙 설정 문제 아님"까지 한 번에 배제된다.

**설계 함의**: 장애 *진입* 계측은 실시간 경보가 될 수 없다. **회복 시점은 네트워크가 살아 있어
즉시 전송되므로, 실시간 도달이 보장되는 유일한 채널이다.** 그래서 회복 쪽에 이벤트를 싣는다
([[project-network-degradation-2026-08]] 의 `NetworkOutageSummary`). 진짜 실시간 경보가 필요하면
서버측 heartbeat 부재 감지로 가야 한다 — [[project-sentry-crons-liveness]].

**How to apply**: 원격 관제 문구(예외 `toString()`)에 **날짜 포함 시각을 반드시 넣는다**.
`08-11 21:07` 형태. 넣지 않으면 도착 시각을 발생 시각으로 오독한다 — 실제로 그렇게 읽혔다.
`lib/core/net/net_report_format.dart` 의 `formatStamp`.
