---
name: reference-themeextension-type-field-collision
description: "ThemeExtension 에 `type` 필드를 두면 확장 조회가 조용히 null 이 된다"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 63d816ff-a848-4835-861f-76dd56b13cbb
  modified: 2026-08-28T06:52:30.736Z
---

`ThemeExtension<T>` 는 `Object get type => T` 를 갖고 있고, **`ThemeData` 가 그 값을 확장 맵의
키로 쓴다.** 그래서 서브클래스에 `type` 이라는 필드를 만들면 키가 그 필드값으로 바뀌어
`Theme.of(context).extension<MyExt>()` 가 **null** 을 돌려준다.

```dart
class PosThemeExt extends ThemeExtension<PosThemeExt> {
  final PosTypography type;   // ← 지뢰. 맵 키가 PosThemeExt 가 아니라 이 객체가 된다
}
```

증상이 고약하다 — **컴파일은 통과**하고 analyzer 는 `annotate_overrides` **info** 한 줄만 낸다
("The member 'type' overrides an inherited member but isn't annotated with '@override'").
info 라 무시하기 쉬운데, 그 한 줄이 앱 전체가 죽는다는 신호다.

**대응**: 필드명을 `typography` 등으로 바꾸고, 위젯 테스트로 고정한다 —
`context.<accessor>` 가 실제 값을 돌려주는지 `pumpWidget` 안에서 확인.

일반화: `ThemeExtension` 서브클래스에서 `type`·`copyWith`·`lerp` 이름을 우연히 재사용하지 말 것.
analyzer 가 error 가 아니라 info 로만 알려주는 충돌은 이것 말고도 있다.

[[project-simple-pos-jp-pilot]] P1 에서 발견.
