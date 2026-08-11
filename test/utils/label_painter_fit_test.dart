import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/utils/label_painter.dart';

/// `LabelPainter.fitFontSize` 계약 고정.
///
/// **주의: 절대 픽셀값을 단언하지 말 것.** flutter test 환경에는 Pretendard 가
/// 로드되지 않아(폴백 폰트로 대체) advance 폭이 실기기와 다르다. 여기서는
/// 폰트에 무관한 불변식 — 반환 범위, 경계 입력, 단조성 — 만 검증한다.
/// 실제 축소량 판정은 설정 화면의 라벨 테스트 출력으로 육안 확인한다.
void main() {
  // TextPainter.layout 에 바인딩이 필요하다.
  TestWidgetsFlutterBinding.ensureInitialized();

  const double base = LabelPainter.fsMenuName; // 28
  const double min = LabelPainter.fsMenuNameMin; // 20
  const double menuMaxWidth =
      LabelPainter.width - LabelPainter.defaultMargin * 2; // 340

  double fit(String text, {double maxWidth = menuMaxWidth}) =>
      LabelPainter.fitFontSize(
        text,
        maxWidth: maxWidth,
        baseFontSize: base,
        minFontSize: min,
        isBold: true,
      );

  group('fitFontSize — 경계 입력 (무한루프/0 나눗셈 가드)', () {
    test('빈 문자열은 base 유지', () {
      expect(fit(''), base);
    });

    test('maxWidth 가 0 이하면 base 유지', () {
      expect(fit('아메리카노', maxWidth: 0), base);
      expect(fit('아메리카노', maxWidth: -10), base);
    });
  });

  group('fitFontSize — 반환 범위', () {
    test('항상 [min, base] 안에 있다', () {
      const samples = [
        '아',
        '아메리카노',
        '아이스 바닐라 라떼',
        '아이스 바닐라 라떼 (레귤러 사이즈) 휘핑크림 추가',
        'Iced Vanilla Latte with Extra Whipped Cream and Two Shots',
        'バニララテ（レギュラーサイズ）ホイップクリーム追加',
      ];
      for (final s in samples) {
        final result = fit(s);
        expect(result, greaterThanOrEqualTo(min), reason: s);
        expect(result, lessThanOrEqualTo(base), reason: s);
      }
    });

    test('아주 긴 문자열은 하한까지 내려간다', () {
      expect(fit('가' * 200), min);
    });

    test('한 글자는 축소되지 않는다', () {
      expect(fit('가'), base);
    });
  });

  group('fitFontSize — 단조성', () {
    test('문자열이 길어질수록 폰트가 커지지 않는다', () {
      var previous = fit('');
      for (var length = 1; length <= 40; length++) {
        final current = fit('가' * length);
        expect(current, lessThanOrEqualTo(previous),
            reason: 'length=$length 에서 역전');
        previous = current;
      }
    });

    test('maxWidth 가 넓을수록 폰트가 작아지지 않는다', () {
      const text = '아이스 바닐라 라떼 (레귤러)';
      final narrow = fit(text, maxWidth: 120);
      final wide = fit(text, maxWidth: menuMaxWidth);
      expect(wide, greaterThanOrEqualTo(narrow));
    });
  });

  group('fitFontSize — 옵션 셀 파라미터', () {
    test('2열 셀(164)에서도 [fsOptionItemMin, fsOptionItem] 범위를 지킨다', () {
      const optionCellWidth =
          (LabelPainter.width - LabelPainter.defaultMargin * 2 - 12) / 2;
      final result = LabelPainter.fitFontSize(
        '휘핑크림 많이 추가해주세요',
        maxWidth: optionCellWidth,
        baseFontSize: LabelPainter.fsOptionItem,
        minFontSize: LabelPainter.fsOptionItemMin,
      );
      expect(result, greaterThanOrEqualTo(LabelPainter.fsOptionItemMin));
      expect(result, lessThanOrEqualTo(LabelPainter.fsOptionItem));
    });
  });

  group('fitFontSize — 줄 수 (기본 크기 우선, 축소는 최후)', () {
    // 사용자 결정: "폰트를 기본 유지한 채 두 줄까지, 그 이후에 폰트 사이즈 조정".
    test('2줄을 허용하면 같은 문자열이 1줄일 때보다 큰 폰트로 들어간다', () {
      const text = '아이스 바닐라 라떼 (레귤러 사이즈)';
      final oneLine = LabelPainter.fitFontSize(text,
          maxWidth: menuMaxWidth,
          baseFontSize: base,
          minFontSize: min,
          isBold: true,
          maxLines: 1);
      final twoLines = LabelPainter.fitFontSize(text,
          maxWidth: menuMaxWidth,
          baseFontSize: base,
          minFontSize: min,
          isBold: true,
          maxLines: 2,
          lineHeight: LabelPainter.menuNameLineHeight);
      expect(twoLines, greaterThanOrEqualTo(oneLine));
    });

    test('2줄 안에 들어가는 길이면 기본 크기(28)를 그대로 쓴다', () {
      // 1줄로는 확실히 넘치지만 2줄이면 여유가 있는 길이.
      final result = LabelPainter.fitFontSize('가' * 20,
          maxWidth: menuMaxWidth,
          baseFontSize: base,
          minFontSize: min,
          isBold: true,
          maxLines: 2,
          lineHeight: LabelPainter.menuNameLineHeight);
      expect(result, base, reason: '2줄로 담기는데 축소하면 안 된다');
    });

    test('2줄로도 안 되면 그때 축소한다', () {
      final result = LabelPainter.fitFontSize('가' * 200,
          maxWidth: menuMaxWidth,
          baseFontSize: base,
          minFontSize: min,
          isBold: true,
          maxLines: 2,
          lineHeight: LabelPainter.menuNameLineHeight);
      expect(result, min);
    });
  });

  group('V2 세로 예산 — 브랜드별 하단 여백', () {
    // offsetY(-60) 도입 당시 "메모 2줄에도 하단 잘림 없음" 으로 검증된 값이 49px.
    // 메뉴명 2줄 슬롯을 넣으면서 그 아래로 내려가지 않는지 브랜드별로 고정한다.
    const double provenSafeFloor = 45;

    test('등록된 모든 브랜드가 안전 하한을 지킨다', () {
      for (final key in BrandKey.values) {
        final meta = BrandRegistry.byKey(key);
        final margin = LabelPainter.v2BottomMargin(
          hasLogo: meta.hasLabelLogo,
          logoWidth: meta.labelLogoWidth,
        );

        expect(
          margin,
          greaterThanOrEqualTo(provenSafeFloor),
          reason: '${meta.storeIdPrefix}: 하단 여백 ${margin.toStringAsFixed(1)}px '
              '→ 메모 2줄이 잘린다. 헤더/본문 간격 상수를 다시 배분할 것.',
        );
      }
    });

    test('로고를 켜도(hasLabelLogo=true 가정) 안전 하한을 지킨다', () {
      // PAIK/TLJP 는 hasLabelLogo=false 지만 코드에 "로고 준비되면 true 로 복구"
      // TODO 가 달려 있다. labelLogoWidth 는 로고가 꺼진 동안 레이아웃에 잡히지
      // 않아 조용히 커질 수 있으므로 **켠 상태**를 미리 잠근다.
      for (final key in BrandKey.values) {
        final meta = BrandRegistry.byKey(key);
        final margin = LabelPainter.v2BottomMargin(
          hasLogo: true,
          logoWidth: meta.labelLogoWidth,
        );

        expect(
          margin,
          greaterThanOrEqualTo(provenSafeFloor),
          reason: '${meta.storeIdPrefix}: labelLogoWidth='
              '${meta.labelLogoWidth} 로 로고를 켜면 하단 여백이 '
              '${margin.toStringAsFixed(1)}px 로 떨어진다. 폭을 타 브랜드와 '
              '맞추거나(기본 50) 세로 간격을 다시 배분할 것.',
        );
      }
    });

    test('모든 브랜드의 라벨 로고 폭이 동일하다', () {
      // 폭이 브랜드마다 다르면 헤더 높이가 달라져 하단 여백이 브랜드별로 갈린다.
      // PAIK 이 70 이던 시절 로고를 켰다면 타 브랜드보다 20px 부족했다.
      final widths = {
        for (final key in BrandKey.values)
          BrandRegistry.byKey(key).storeIdPrefix:
              BrandRegistry.byKey(key).labelLogoWidth,
      };
      expect(widths.values.toSet(), hasLength(1), reason: '브랜드별 폭: $widths');
    });

    test('로고 없는 브랜드는 로고 폭을 예약하지 않는다', () {
      // 종전엔 hasLabelLogo 와 무관하게 labelLogoWidth 를 예약해서, 로고를 끈
      // 브랜드(PAIK/TLJP)가 그리지도 않는 자리를 잡아먹었다.
      const double logoWidth = 50;
      final withoutLogo = LabelPainter.headerContentHeight(
          hasLogo: false, logoWidth: logoWidth);
      final withLogo =
          LabelPainter.headerContentHeight(hasLogo: true, logoWidth: logoWidth);

      expect(withoutLogo, LabelPainter.headerTextBlockHeight);
      expect(withLogo, logoWidth);
      expect(withoutLogo, lessThan(withLogo));
    });

    test('로고가 텍스트 블록보다 작아도 텍스트 높이는 확보한다', () {
      expect(
        LabelPainter.headerContentHeight(hasLogo: true, logoWidth: 20),
        LabelPainter.headerTextBlockHeight,
      );
    });
  });

  group('상수 위계', () {
    test('메뉴명 하한은 subInfo 보다 작지 않다 (시각 위계 역전 방지)', () {
      expect(LabelPainter.fsMenuNameMin,
          greaterThanOrEqualTo(LabelPainter.fsSubInfo - 2));
    });

    test('옵션 하한 <= 옵션 기본 <= 메뉴명 기본', () {
      expect(LabelPainter.fsOptionItemMin,
          lessThanOrEqualTo(LabelPainter.fsOptionItem));
      expect(LabelPainter.fsOptionItem,
          lessThanOrEqualTo(LabelPainter.fsMenuName));
    });

    test('메뉴명 슬롯은 정확히 menuNameMaxLines 줄분이다', () {
      expect(
        LabelPainter.menuSlotHeight,
        LabelPainter.fsMenuName *
            LabelPainter.menuNameLineHeight *
            LabelPainter.menuNameMaxLines,
      );
    });
  });
}
