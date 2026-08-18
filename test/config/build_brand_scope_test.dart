import 'dart:io';

import 'package:appfit_order_agent/config/build_brand.dart';
import 'package:appfit_order_agent/config/ota_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// `BuildBrand` 를 참조해도 되는 파일의 화이트리스트.
///
/// 빌드 축의 사정거리는 **OS 셸 아이덴티티 + OTA 채널**까지다. 서버 환경,
/// `BrandFeature` 게이팅, 프린터·주문 로직, i18n 분기는 전부 `BrandRegistry`
/// 런타임 정본으로 남아야 한다.
///
/// 컴파일러는 이 규율을 강제할 수 없다 — `BuildBrand.isMammoth` 는 어디서든
/// 참조 가능한 그냥 const 다. 2026-07 변형 폐기의 교훈은 "브랜드로 빌드를
/// 나누지 마라"가 아니라 **"빌드 축이 로직까지 번지게 두지 마라"** 였고, 그때
/// 번짐을 막을 장치가 없었다는 게 문제였다. 그래서 목록으로 고정한다.
///
/// **새 참조를 추가하려면 이 목록을 사람이 의도적으로 늘려야 한다.** 늘리기
/// 전에 물을 것: 이게 OS 셸 아이덴티티나 배포 채널인가, 아니면 브랜드 동작인가?
/// 후자면 `BrandRegistry` 로 간다.
const Set<String> kAllowedBuildBrandReferences = {
  // 정의 자체.
  'lib/config/build_brand.dart',
  // OTA 채널 URL — 아티팩트마다 채널 1세트(패키지 불일치 설치 실패 방지).
  'lib/config/ota_config.dart',
  // 오설치 안내 판정 — 설치된 아티팩트 vs 매장 브랜드 비교. 게이팅이 아니라
  // 안내만 한다(차단하지 않음).
  'lib/providers/brand_provider.dart',
  // Phase C 예정: 'lib/config/update_config.dart' (Windows OTA 채널)
};

void main() {
  group('BuildBrand 참조 지점 화이트리스트', () {
    test('허용 목록 밖에서 BuildBrand 를 참조하지 않는다', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        if (kAllowedBuildBrandReferences.contains(rel)) continue;
        if (entity.readAsStringSync().contains('BuildBrand')) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '빌드 축이 새 파일로 번졌습니다: $offenders\n'
            '이게 OS 셸 아이덴티티나 배포 채널이 아니라면 BrandRegistry 로 옮기세요.\n'
            '맞다면 kAllowedBuildBrandReferences 에 의도적으로 추가하세요.',
      );
    });

    test('허용 목록의 파일은 전부 실재한다 (stale 목록 방지)', () {
      for (final path in kAllowedBuildBrandReferences) {
        expect(File(path).existsSync(), isTrue, reason: '없는 파일: $path');
      }
    });
  });

  group('OTA 채널 — 아티팩트당 정확히 1세트', () {
    // 기본(dart-define 없음) = common. 맘모스 쪽은
    //   flutter test --dart-define=APPFIT_BRAND=mammoth
    // 로 검증한다.
    //
    // 조건부 skip 을 쓰지 않는다 — define 이 전달되지 않으면 맘모스 케이스가
    // 조용히 통과해버려서, 정작 검증하려던 것을 검증하지 못한다. 대신 슬러그로
    // 분기해 **어느 쪽으로 돌든 반드시 한 세트를 단언**한다.
    test('채널 문자열이 슬러그와 정확히 대응한다', () {
      const base = 'http://waldpay.kokonutstamp2.com/';
      expect(
        BuildBrand.slug,
        anyOf('common', 'mammoth'),
        reason: '알 수 없는 브랜드 슬러그. 채널명은 슬러그에서 규칙 파생되므로 '
            '새 슬러그를 도입했다면 이 테스트도 함께 늘려야 한다.',
      );

      final expectedChannel = BuildBrand.isMammoth
          ? 'appfit_order_agent_mammoth_release'
          : 'appfit_order_agent_release';
      expect(OtaConfig.versionUrl, '$base${expectedChannel}_version.json');
      expect(OtaConfig.downloadUrl, '$base$expectedChannel.apk');
    });

    test('공통 슬러그면 채널이 종전 문자열 그대로다 (회귀 방지)', () {
      expect(BuildBrand.isCommon, BuildBrand.slug == 'common');
      if (!BuildBrand.isCommon) return;
      expect(
        OtaConfig.downloadUrl,
        'http://waldpay.kokonutstamp2.com/appfit_order_agent_release.apk',
      );
    });

    test('레거시 무접미 채널은 어느 브랜드에서도 나오지 않는다 (동결)', () {
      // 구 패키지로 설치된 일본 매장 1곳이 이 이름을 폴링 중이라, .appfit 계열
      // APK 를 그 이름으로 올리면 패키지 불일치로 설치가 실패한다.
      expect(OtaConfig.downloadUrl.endsWith('/appfit_order_agent.apk'), isFalse);
      expect(
        OtaConfig.versionUrl.endsWith('/appfit_order_agent_version.json'),
        isFalse,
      );
    });
  });
}
