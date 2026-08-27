---
name: reference-defender-exclusion-query
description: 비상승 Get-MpPreference 의 ExclusionPath 는 기기마다 다르게 응답 — 안내 문자열 1줄이 오기도 하고 실제 목록이 오기도 함
metadata: 
  node_type: memory
  type: reference
  originSessionId: c3baa59a-e7d6-4562-9fae-547e4cb390c0
  modified: 2026-08-27T02:44:57.239Z
---

`(Get-MpPreference).ExclusionPath` 를 **상승되지 않은** 프로세스에서 조회하면
기기마다 응답이 다르다. 2026-08-27 실측:

| 기기 | 응답 |
| --- | --- |
| 개발 PC (Defender + McAfee 공존) | `N/A: Must be an administrator to view exclusions` **1줄** |
| 사내 기기 (Defender 단독) | 실제 예외 경로 목록 |

**함정**: 전자의 경우 `exitCode` 는 **0** 이고 목록도 **비어 있지 않다**. 그래서
"조회 실패" / "목록 비어 있음" 두 가드로는 걸러지지 않고, 예외가 정상 등록된
PC 를 "미등록" 으로 오판한다. appfit 의 자가진단이 실제로 이 오보를 매일 ERROR
레벨로 남기고 있었다(고침 — `lib/utils/windows_startup_maintenance.dart`).

**판정 방법**: 안내 문구는 로캘에 따라 달라질 수 있으므로 문자열을 매칭하지 말 것.
항목이 **경로 모양**(`X:\` 또는 UNC `\\`)인지로 본다. 경로가 하나도 없으면
조회가 막힌 것 → "판정 불가" 이지 "미등록" 이 아니다.

**보조 근거**: 라이브 조회가 막힌 기기에서는 설치본이 남긴
`{app}\defender_exclusion.log`(설치 시점 기록)를 날짜와 함께 병기한다. 설치 후
예외가 지워졌을 수 있으므로 그것만으로 "정상" 이라 단정하지는 않는다.

`tamperProtected=True` 여도 `Add-MpPreference` 는 통과한다(상승된 프로세스라면).

관련: [[project-windows-peruser-install]]
