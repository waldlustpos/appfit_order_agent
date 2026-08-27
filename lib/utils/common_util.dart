import 'package:intl/intl.dart';

class CommonUtil {
  static String formatPrice(dynamic price, {String currencyUnit = '¥'}) {
    final NumberFormat currencyFormat = NumberFormat.currency(
      locale: 'ja_JP',
      symbol: '',
      decimalDigits: 0,
    );

    return '${currencyFormat.format(price)}$currencyUnit';
  }

  /// 뒤 [visible]자리만 노출하고 앞을 마스킹. 길이가 모자라면(빈 문자열 포함) 전체 마스킹.
  ///
  /// **전화번호 전용**이다. 로그 파일은 기기 밖으로 나가므로(Slack 업로드·로컬
  /// 로그서버·6개월 보관) 그 자체로 사람을 지목하는 값만 마스킹한다.
  /// 회원바코드·쿠폰번호는 **원문 유지** — 회원 DB 를 거쳐야만 사람으로 환원되는
  /// 가명 식별자라, 로그끼리 맞대조하는 추적 키 역할을 그대로 살린다.
  /// 실명일 수 있는 닉네임은 마스킹이 아니라 **로그에 남기지 않는 쪽**이 정책이다.
  static String maskTail(String value, {int visible = 4}) {
    if (value.length <= visible) return '*******';
    return '*******${value.substring(value.length - visible)}';
  }

  /// 카드번호 표시용 마스킹. 앞 4자리(BIN 일부)만 남긴다: `5327111122223333` → `5327-****`.
  ///
  /// 서버가 이미 마스킹해 보내면(`*` 포함) 원문을 그대로 둔다. 자릿수가 4 이하면
  /// 마스킹할 게 없으므로 원문 유지. 결제 응답을 모델에 담는 시점에 적용해서
  /// 원본 PAN 이 앱 메모리·프린터 페이로드·로그 어디에도 남지 않게 한다.
  static String maskCardNo(String value) {
    if (value.contains('*')) return value;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) return value;
    return '${digits.substring(0, 4)}-****';
  }

  /// `0` 으로 시작하는 9~11자리 숫자. 한국·일본 전화번호(휴대폰 11자리,
  /// 유선 9~10자리)를 덮는다.
  static final RegExp _phoneLike = RegExp(r'^0\d{8,10}$');

  /// 전화번호로 보이는 문자열인지. **쿠폰 코드 오입력 차단 전용.**
  ///
  /// 멤버십 화면은 입력란 하나를 [회원조회](전화번호·회원바코드)와
  /// [쿠폰사용](쿠폰코드)이 공유한다. 전화번호를 넣은 채 [쿠폰사용]을 누르는
  /// 오조작이 구조적으로 발생하는데, 그대로 서버에 보내면 400 INVALID_REQUEST 가
  /// 나고 서버가 입력값을 되돌려주는 `Invalid couponNo: 010…` 이 Sentry 이슈
  /// 제목 → Slack 알림까지 흘러가 **고객 전화번호가 그대로 노출된다.**
  /// 그래서 API 호출 전에 앱에서 끊는다.
  ///
  /// 판정은 일부러 좁게 잡았다 — 쿠폰번호 실물은 16자리에 `0` 으로 시작하지
  /// 않아서(`5001868426241491`) 겹치지 않는다. 국가별 번호 체계를 더 넓게
  /// 걸러내려 들지 않는다: 오탐으로 정상 쿠폰 사용을 막는 쪽이 더 나쁘다.
  static bool isLikelyPhoneNumber(String value) =>
      _phoneLike.hasMatch(value.trim());

  /// 리터럴 백슬래시+n (이스케이프가 안 풀린 채 문자 그대로 오는 케이스).
  /// `\r\n` 을 먼저 소비해야 공백 2칸이 되지 않는다.
  static final RegExp _literalNewline = RegExp(r'\\r\\n|\\n|\\r');

  /// 실제 제어문자 개행(LF/CR/CRLF). 연속 개행도 공백 1칸으로 접는다.
  static final RegExp _realNewline = RegExp(r'[\r\n]+');

  /// 공백/탭 런 축약. 전각공백(U+3000)은 일본어 메뉴명의 시각 간격이므로
  /// 의도적으로 대상에서 제외한다.
  static final RegExp _spaceRun = RegExp(r'[ \t]+');

  /// 한 줄 표시용 텍스트 정규화.
  ///
  /// 메뉴명/옵션명에 섞여 오는 개행(실제 LF/CR 및 리터럴 `\n` 문자열)을 공백
  /// 1칸으로 접고, 매체(KDS 카드 232px / 라벨 340dot)가 알아서 줄바꿈하게 한다.
  /// 매체마다 폭이 달라 원본 개행 위치를 따르면 한 줄에 두어 글자만 남는 식으로
  /// 오히려 깨진다.
  ///
  /// 실제 LF 를 남겨두면 `maxLines: 1` 위젯/TextPainter 가 하드 라인브레이크로
  /// 처리해 **개행 뒤 내용이 통째로 사라진다**. 표시·인쇄 경계에서 반드시 접을 것.
  ///
  /// 주의: `DateFormat('MM/dd\nHH:mm:ss')` 로 만드는 라벨 주문시각처럼 **의도적으로
  /// 삽입한 개행에는 절대 쓰지 말 것** (label_print_data.dart 참조).
  static String normalizeInlineText(String? value) {
    if (value == null || value.isEmpty) return '';
    return value
        .replaceAll(_literalNewline, ' ')
        .replaceAll(_realNewline, ' ')
        .replaceAll(_spaceRun, ' ')
        .trim();
  }
}
