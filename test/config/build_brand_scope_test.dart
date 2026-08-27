import 'dart:io';

import 'package:appfit_order_agent/config/build_brand.dart';
import 'package:appfit_order_agent/config/ota_config.dart';
import 'package:appfit_order_agent/config/update_config.dart';
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
  // 로그인 전 기본 브랜드 프리시드 — 문서 주석(build_brand.dart)이 명시한
  // 허용 범위. 저장된 브랜드 테마가 없는 신규 설치에서만 개입하고, 로그인 후엔
  // 매장ID 기반 reconcileForStore 가 그대로 정본이다.
  'lib/main.dart',
  // 드로어 헤더 로고 — 매머드 flavor 전용 이미지 강제 적용. 다른 flavor는
  // 기존 고정 아이콘 그대로라 회귀 없음.
  'lib/widgets/home/drawer_menu.dart',
  // 로그인 화면 로고 — 매머드 flavor면 선택된 테마와 무관하게 항상 매머드
  // 이미지(런처 아이콘/이름과 동급의 아티팩트 정체성 요소로 취급). 다른
  // flavor는 기존 BrandLogo(activeBrand 기반) 그대로라 회귀 없음.
  'lib/screens/login_screen.dart',
  // Windows OTA 채널 — ota_config.dart 의 Windows 대응.
  'lib/config/update_config.dart',
  // 트레이 아이콘 — Runner.rc(창/작업표시줄) 아이콘과 동일 축의 OS 셸
  // 아이덴티티. rootBundle 로 읽는 Flutter asset이라 컴파일 리소스와 별도로
  // 브랜드 분기가 필요하다.
  'lib/services/windows_bubble_service.dart',
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
    // 기본(dart-define 없음) = common. 매머드 쪽은
    //   flutter test --dart-define=APPFIT_BRAND=mammoth
    // 로 검증한다.
    //
    // 조건부 skip 을 쓰지 않는다 — define 이 전달되지 않으면 매머드 케이스가
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

  group('Windows OTA 채널(UpdateConfig) — 아티팩트당 정확히 1세트', () {
    // Android 와 반대로 공통이 "레거시 무접미"고 매머드가 신설이다 — Windows
    // 는 패키지 개념이 없어 기존 설치본이 무접미 채널로 자연 업데이트되므로
    // 동결이 아니라 계속 사용이 정책이다(update_config.dart 클래스 doc 참조).
    // URL 스킴은 2026-08 per-user 전환에서 https 로 올렸다(중간자가 앱 자리에
    // 임의 코드를 앉히는 것을 막기 위함). **Android OtaConfig 는 이번 스코프
    // 밖이라 여전히 http 다** — 위 그룹의 http 단언을 함께 고치지 말 것.
    test('공통 슬러그면 채널·파일명이 이 파일 신설 이전과 동일하다 (스킴 제외)', () {
      if (!BuildBrand.isCommon) return;
      expect(UpdateConfig.downloadUrl,
          'https://waldpay.kokonutstamp2.com/appfit_order_agent_windows.zip');
      expect(
        UpdateConfig.versionUrl,
        'https://waldpay.kokonutstamp2.com/'
            'appfit_order_agent_windows_version.json',
      );
      expect(UpdateConfig.zipFileName, 'appfit_order_agent_windows.zip');
      expect(UpdateConfig.extractDirName, 'appfit_order_agent_update_extracted');
      expect(UpdateConfig.updaterBatName, 'appfit_order_agent_updater.bat');
      expect(UpdateConfig.updaterVbsName,
          'appfit_order_agent_updater_launcher.vbs');
      expect(UpdateConfig.updaterLogName, 'appfit_order_agent_updater.log');
    });

    test('매머드 슬러그면 전용 채널 + 전용 임시 파일명을 쓴다', () {
      if (!BuildBrand.isMammoth) return;
      expect(
        UpdateConfig.downloadUrl,
        'https://waldpay.kokonutstamp2.com/'
            'appfit_order_agent_mammoth_windows.zip',
      );
      expect(
        UpdateConfig.versionUrl,
        'https://waldpay.kokonutstamp2.com/'
            'appfit_order_agent_mammoth_windows_version.json',
      );
      expect(UpdateConfig.zipFileName, 'appfit_order_agent_mammoth_windows.zip');
      // 임시 파일명까지 분리해야 두 브랜드가 한 머신에서 동시에 업데이트를
      // 진행해도 서로의 updater 배치 파일을 밟지 않는다.
      expect(UpdateConfig.updaterBatName,
          'appfit_order_agent_mammoth_updater.bat');
    });

    test('OTA URL 은 https 다 (다운그레이드 방지)', () {
      // HTTP 폴백을 두지 않는 것이 전환의 핵심이다. 폴백이 있으면 중간자가
      // 평문 응답을 강제해 임의 exe 를 앱 자리에 앉힐 수 있다.
      expect(UpdateConfig.versionUrl, startsWith('https://'));
      expect(UpdateConfig.downloadUrl, startsWith('https://'));
    });
  });

  group('설치 폴더명 — Dart 와 Inno Setup 스크립트가 일치한다', () {
    // installer/appfit_order_agent.iss 는 Defender 예외를
    // `{localappdata}\{#MyAppDirName}` 에 건다. UpdateConfig.installDirName 이
    // 그 값과 어긋나면 예외가 실제 OTA 스테이징 폴더를 덮지 못하는데, **아무
    // 증상도 나타나지 않는다** — 업데이트는 그대로 되고 오탐이 났을 때에야
    // 드러난다. 사람이 두 파일을 나란히 놓고 볼 일이 없으므로 여기서 고정한다.
    const issPath = 'installer/appfit_order_agent.iss';

    /// 브랜드 `#if` 블록에서 현재 빌드 브랜드에 해당하는 `MyAppDirName` 을
    /// 뽑는다. `.iss` 는 브랜드당 별도 컴파일이라 두 정의가 한 파일에 있다.
    String issAppDirName() {
      final source = File(issPath).readAsStringSync();
      final ifAt = source.indexOf('#if AppfitBrand == "mammoth"');
      final elseAt = source.indexOf('#else', ifAt);
      final endAt = source.indexOf('#endif', elseAt);
      expect(
        ifAt >= 0 && elseAt > ifAt && endAt > elseAt,
        isTrue,
        reason: '$issPath 의 브랜드 #if/#else/#endif 블록을 찾지 못했습니다. '
            '구조가 바뀌었다면 이 테스트도 함께 고치세요.',
      );

      final block = BuildBrand.isMammoth
          ? source.substring(ifAt, elseAt)
          : source.substring(elseAt, endAt);
      final match =
          RegExp(r'#define\s+MyAppDirName\s+"([^"]+)"').firstMatch(block);
      expect(match, isNotNull,
          reason: '$issPath 의 ${BuildBrand.slug} 블록에 MyAppDirName 정의가 없습니다.');
      return match!.group(1)!;
    }

    test('installDirName 이 .iss 의 MyAppDirName 과 같다', () {
      expect(
        UpdateConfig.installDirName,
        issAppDirName(),
        reason: 'UpdateConfig.installDirName 과 $issPath 의 MyAppDirName 이 '
            '어긋났습니다. 이 상태로 배포하면 Defender 예외가 OTA 스테이징 '
            '폴더를 덮지 못한 채 조용히 무효화됩니다.',
      );
    });

    test('스테이징 폴더가 installDirName 아래에 있다', () {
      // .iss 가 거는 예외는 `{localappdata}\{#MyAppDirName}` 하나이고, 앱은 그
      // 아래 `\update` 를 쓴다. 이 부모-자식 관계가 깨지면 예외가 빗나간다.
      expect(
        UpdateConfig.stagingDir().parent.path,
        endsWith(UpdateConfig.installDirName),
      );
    });
  });
}
