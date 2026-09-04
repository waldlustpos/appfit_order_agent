/// 라벨 프린터 기종 식별 상수 — **native 의존 0 의 leaf 파일**.
///
/// 이 파일이 따로 있는 이유는 순환 import 회피다. `windows_label_router` 가
/// 기종 표시명을 반환해야 하는데 그 상수가 `print_service` 안에 있으면
/// `print_service → windows_label_router → print_service` 가 된다.
///
/// 여기에는 `dart:io` 조차 두지 않는다 — Android/Windows 양쪽 import 그래프에서
/// 무조건 안전해야 하는 자리다.
library;

/// 라벨 프린터 표시명 중 G30 — `OutputService` 가 이 값으로 연속용지 레이아웃
/// (`Continuous58LabelPainter` / `LabelMediaSpec.continuous58`) 분기를 탄다.
/// 40mm 는 서비스 대상이 아니라 용지 사이즈 분기는 없다(2026-09-03).
/// 문자열을 여기저기 새로 쓰지 말고 항상 이 상수를 참조할 것.
const String kBixolonG30ModelName = 'BIXOLON G30';

/// BIXOLON USB VID. G30 확정에는 부족하다 — [kBixolonG30ProductId] 로 가른다.
const int kBixolonVendorId = 0x1504;

/// G30 PID (실기기 확인). Android `BixolonPosDriver.KNOWN_PRODUCT_IDS` 와 동기 유지.
const int kBixolonG30ProductId = 0x0147;
