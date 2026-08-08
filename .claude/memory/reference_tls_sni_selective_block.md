---
name: reference-tls-sni-selective-block
description: 같은 IP를 공유하는 두 서비스를 iptables SNI 문자열 매칭으로 분리 차단하는 기법 (소켓만 죽이고 HTTP는 살리기)
metadata: 
  node_type: memory
  type: reference
  originSessionId: 278d02e2-d30f-4005-8858-95a5214b5761
  modified: 2026-08-08T15:19:59.655Z
---

한 대상만 골라 끊어야 하는데 **호스트명이 달라도 같은 IP** 로 해석될 때(공용 LB/ELB
뒤에 있으면 흔함) IP·포트 기반 iptables 로는 분리가 불가능하다. TLS ClientHello 의
**SNI 는 평문**이라 문자열 매칭으로 잡을 수 있다.

```
adb shell "su 0 iptables -A OUTPUT -p tcp --dport 443 \
  -m string --string 'notifier-stgapi.waldplatform.com' --algo bm -j DROP"
```

**왜 필요했나**: AppFit 소켓(`notifier-stgapi`)과 REST API(`core-stgapi`)가 같은 ELB
IP 2개를 공유해서, `--dport 443` 전체 차단은 둘 다 죽인다. 그러면 HTTP 실패 →
ApiHealth 열화 → 회복 시 앱의 소켓 깨우기(R3)가 자동 발화해 **"코어가 스스로 복구한
것"과 "앱이 깨운 것"을 구분할 수 없다**. SNI 차단으로 HTTP 를 무결하게 유지하니
건강도 로그가 0줄이 되어 교란 변수가 구조적으로 제거됐다.

**성질**:
- ClientHello 만 막으므로 **이미 수립된 연결은 안 죽는다**. 대상 세션을 먼저
  끊어야 한다(앱 재시작이 가장 깔끔 — connectivity 이벤트 부작용도 없다).
- 연결은 TCP 수립 후 핸드셰이크에서 멈추므로 실패 모드가 `connectTimeout` 이다.
- 확인/해제: `iptables -L OUTPUT -n -v | grep -i <문자열>` / 같은 인자로 `-D`.
- 에뮬레이터는 `adb remount` 가 막혀도(`bootloader unlocked` 요구) `su 0` 은 되므로
  이 방식이 `/system/etc/hosts` 오염보다 손이 적다.

대비: 전체 포트 DROP 은 기존 세션도 죽여 "기존 세션은 살고 신규만 실패"하는
NAT 고갈형 장애의 비대칭을 재현하지 못한다 — [[project-network-degradation-2026-08]].
