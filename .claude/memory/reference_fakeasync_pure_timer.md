---
name: reference_fakeasync_pure_timer
description: OrderQueueManager 등 타이머 버퍼 로직은 순수 Timer 로 구현해야 fakeAsync 테스트 성립 — DateTime.now() 금지
metadata: 
  node_type: memory
  type: reference
  originSessionId: 61867af9-5e13-4b4a-b641-cdae6cf0d363
---

`OrderQueueManager` 버퍼(디바운스/cap) 같은 시간 의존 로직은 **순수 `Timer` 로만** 구현해야 `test/providers/order_queue_manager_test.dart` 의 `fakeAsync` 검증이 성립한다. `fakeAsync` 는 `Timer`/`Future.delayed`/`clock.now()` 는 가상시계로 제어하지만 **`DateTime.now()` 는 실제 벽시계라 `async.elapse()` 로 전혀 안 움직인다.**

실사례: 버퍼 cap 을 `_bufferFirstArrival = DateTime.now()` + `now.difference()` 로 구현했더니, fakeAsync 에서 elapsed 가 항상 ~0 → cap 이 절대 발화 안 해 테스트 실패(프로덕션에선 동작하지만 테스트로 잠기지 않음). 해결: cap 을 **첫 주문에만 1회 무장하고 재무장하지 않는 별도 `_bufferCapTimer`** (디바운스는 도착마다 재무장하는 `_bufferTimer`), 둘 중 먼저 만료된 쪽이 flush 하고 `_flushBuffer` 에서 양쪽 취소. `DateTime.now()` 제거 → fakeAsync 로 cap/디바운스 모두 검증됨.

경과시간이 꼭 필요하면 `clock.now()`(clock 패키지) 를 쓰되 lint(`depend_on_referenced_packages`) 주의. 대개는 절대 Timer 조합으로 재설계하는 편이 낫다. 표시 정렬은 [[reference_slang_regen_command]] 무관, 큐 흐름은 [[feedback_queue_enqueue_timing]] 참고.
