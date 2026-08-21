/// 라벨 프린터 용지 규격 — 캔버스 폭·높이 정책을 painter/드라이버에 전달하는 값 객체.
///
/// 갭 라벨(Caysn/REXOD/BIXOLON XD5-40d)은 고정 크기 낱장이라 [widthDots]/
/// [maxHeightDots] 가 곧 실제 인쇄 크기다. G30(연속 용지 + 커터)은 세로가
/// 가변이라 [maxHeightDots] 는 상한(cap)일 뿐이고 실제 높이는 콘텐츠 길이로
/// 정해진다 — [variableHeight] 가 그 분기를 표시한다.
class LabelMediaSpec {
  const LabelMediaSpec({
    required this.widthDots,
    required this.maxHeightDots,
    required this.minHeightDots,
    required this.sideMarginDots,
    required this.variableHeight,
    double? rightMarginDots,
  }) : rightMarginDots = rightMarginDots ?? sideMarginDots;

  /// 캔버스 폭(dots) — 갭 라벨·G30 모두 **실제 인쇄 가능폭 그대로**다(용지
  /// 물리 폭이 아니라). G30 은 인쇄 시작 위치 자체가 하드웨어에 고정돼 있어
  /// (2026-08-21 실기기 확인 — 여백을 아무리 좁혀도 인쇄가 용지 좌측 끝보다
  /// 안쪽에서 시작한다) 캔버스를 물리 용지폭으로 넓게 잡아 봐야 그 여분은
  /// 그냥 못 쓰는 공간일 뿐 시각적 중앙 보정에 쓸 수 없다 — 그래서 실측
  /// 경계에 맞춰 캔버스 자체를 좁힌다([continuous40] 참조).
  final double widthDots;

  /// 캔버스 최대 높이(dots). 갭 라벨은 고정 높이 그 자체(= 실제 인쇄 높이),
  /// G30 은 세로 가변의 상한(cap) — 실측 없이 넘길 수 없는 물리 한계.
  final double maxHeightDots;

  /// 가변 높이일 때의 하한(dots) — 콘텐츠가 거의 없어도 이 아래로는 자르지
  /// 않는다(상/하 여백 + 헤더 + 최소 콘텐츠가 자연스레 들어갈 여유).
  /// [variableHeight]=false 면 의미 없음(항상 [maxHeightDots] 로 고정).
  final double minHeightDots;

  /// 좌측 여백(dots). 기존 [LabelPainter.defaultMargin] 과 동일 개념이지만
  /// 이름을 spec 레벨로 올려 기종별 값을 명시적으로 분리한다.
  final double sideMarginDots;

  /// 우측 여백(dots). 생략하면 [sideMarginDots] 와 같은 값(좌우 대칭) —
  /// 모든 기종이 이 기본값을 쓴다(G30 포함, 2026-08-21 이후).
  final double rightMarginDots;

  /// true 면 세로가 콘텐츠 길이만큼 가변(연속 용지 + 커터). false 면 항상
  /// [maxHeightDots] 고정(갭 라벨 낱장).
  final bool variableHeight;

  /// 콘텐츠 폭(좌우 여백 제외).
  double get contentWidthDots => widthDots - sideMarginDots - rightMarginDots;

  /// 기존 4기종(Caysn/REXOD/XD5-40d) — [LabelPainter] 의 현행 상수를 그대로
  /// 담는다. **값을 바꾸지 말 것** — 3기종이 이 값으로 검증돼 있다.
  static const gap490x600 = LabelMediaSpec(
    widthDots: 490,
    maxHeightDots: 600,
    minHeightDots: 600,
    sideMarginDots: 75,
    variableHeight: false,
  );

  /// BIXOLON G30, 40mm 용지. 눈금자 테스트(0~40mm 전체 눈금, LEFT 정렬)로
  /// 실기기 판독 3회 재현 확인(2026-08-21) 끝에 도달한 결론:
  ///
  /// 1. 인쇄 가능 영역은 항상 정확히 35mm(280dot) — margin 을 12/12, 48/48,
  ///    4/48 로 바꿔봐도 잘리는 경계는 그대로 35mm 였다.
  /// 2. margin(좌측 padding)을 키운다고 콘텐츠가 시각적으로 중앙에 오지
  ///    않았다 — 오히려 더 오른쪽으로 밀렸다. **인쇄 시작 위치 자체가 하드웨어에
  ///    고정**돼 있어서다 — CL 마커(좌측 padding 0.5mm)조차 실물에서 "인쇄
  ///    자체가 왼쪽 공백이 있는 상태로 시작"하는 게 확인됐다(2026-08-21).
  ///
  /// 즉 40mm 를 캔버스로 잡고 margin 으로 시각 중앙을 맞추려는 접근 자체가
  /// 틀렸다 — 캔버스를 물리 용지폭(320)이 아니라 **실측 유효 인쇄폭(280) 부근**
  /// 으로 잡아야 한다. 시각 중앙 보정은 하드웨어 인쇄 시작 위치가 고정인 이상
  /// 소프트웨어로 불가능(가이드 재장착 등 하드웨어 쪽 확인 필요) — 여기서는
  /// 잘리지 않는 최대 콘텐츠 폭만 보장한다. [widthDots]=272(35mm 경계
  /// 대비 8dot=1mm 여유 — 좌측 여백이 살짝 넓어 보인다는 실물 피드백으로
  /// 280 에서 1mm 추가로 줄임, 2026-08-21). [sideMarginDots](좌)=0 —
  /// 어차피 하드웨어 인쇄 시작 위치 자체가 이미 여백을 두고 시작하므로
  /// (2026-08-21 확인) 소프트웨어 좌측 여백은 그 위에 얹는 중복일 뿐이라는
  /// 판단으로 0 처리. [rightMarginDots](우)=16 은 실물에서 우측 여백이 더
  /// 필요하다는 피드백으로 유지 — 콘텐츠가 캔버스 우측 끝에 바짝 붙어
  /// 보였던 것.
  /// 세로 cap 640(80mm) — [ContinuousLabelPainter] 문서의 세로 예산 참조.
  static const continuous40 = LabelMediaSpec(
    widthDots: 272,
    maxHeightDots: 640,
    minHeightDots: 340,
    sideMarginDots: 0,
    rightMarginDots: 16,
    variableHeight: true,
  );

  // 58mm 는 계획 미확정 — 값을 채우지 않는다(요청 시 continuous58 추가).
}
