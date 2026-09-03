---
name: reference_active_store_id_is_session_key
description: "매장 범위 prefs 키를 만들 때 매장 ID 정본은 getActiveStoreId()(세션 키 우선 + getId() 폴백)다. getId() 단독은 '아이디 저장' 체크박스에 종속돼 비어 있을 수 있다."
metadata:
  type: reference
---

`PreferenceService` 에 **매장별로 값이 다른 설정**(카테고리 코드·옵션그룹 코드처럼 매장마다 의미가 다른 값)을 저장할 때는 `<접두사><매장ID>` 형태의 매장 범위 키를 쓴다. 그 매장 ID 의 정본은 **`getActiveStoreId()`** 다.

```dart
String? getActiveStoreId() {
  final session = _prefs.getString(KEY_SESSION_STORE_ID);  // 로그인 성공 시 항상 기록
  if (session != null && session.trim().isNotEmpty) return session.trim().toUpperCase();
  return getId();                                          // 구버전 기기용 폴백
}
```

**함정:** `getId()`(`KEY_MID`) 단독으로 쓰면 안 된다. `KEY_MID` 는 로그인 화면의 **"아이디 저장" 체크박스에 종속**돼 `clearLoginInfo()` 에서 지워진다. 두 체크박스가 모두 꺼진 신규 매장 최초 로그인에서 `KEY_MID` 가 비어 인증 헤더가 누락된 사고가 세션 키 분리의 이유다. `getStoreId()`(`KEY_STORE_ID`)도 다른 키이니 혼동하지 말 것.

`feat/label-zone-routing` 브랜치의 zone 설정은 `getId()` 를 썼다(당시엔 세션 키가 없었다). 그 코드를 참고할 때 이 부분은 **그대로 베끼지 말 것** — [[project_label_category_subinfo_settings]] 는 `getActiveStoreId()` 로 고쳐 썼다.

**동반 규약 2개:**
- 매장 미확정이면 setter 는 저장을 건너뛰고 **`false` 를 반환**한다. 조용히 성공한 척하면 설정이 사라진 이유를 점주가 알 수 없다 — 호출한 화면이 SnackBar 로 알린다.
- getter 는 JSON 파싱 실패를 **빈 값으로 흡수**한다(+`logger.w`). 라벨 설정에서 빈 값 = 전량 출력 = 소실 0.
