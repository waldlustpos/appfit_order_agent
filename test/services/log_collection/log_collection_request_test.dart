import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/services/log_collection/log_collection_request.dart';
import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';

/// 이 캡션은 리팩터 전 `settings_log_collection_section.dart` 의 위젯 private
/// 로직이 만들던 문자열과 **문자 단위로 같아야 한다.** 수동 버튼과 원격 명령이
/// 같은 함수를 쓰게 만들면서 포맷이 바뀌면, 운영 중 Slack 에서 매장/기기를
/// 식별하던 눈이 어긋난다.
DeviceIdentity _identity({
  String? projectName = '마타',
  String? shopName = '마타 강남점',
  String? shopCode = 'MATA00001',
  String deviceModel = 'SUNMI D3 MINI',
  String? serial = 'H092W24A1G00862',
}) =>
    DeviceIdentity(
      projectName: projectName,
      shopName: shopName,
      shopCode: shopCode,
      deviceModel: deviceModel,
      serial: serial,
      deviceId: serial ?? 'installid0123456789abcdef01234567',
      idSource: serial != null ? 'serial' : 'installId',
      deviceManufacturer: 'SUNMI',
      platform: 'android',
      osVersion: '13',
    );

void main() {
  final from = DateTime(2026, 7, 24);
  final to = DateTime(2026, 7, 30);

  group('캡션 포맷 (리팩터 전 문자열 고정)', () {
    test('모든 필드가 있을 때', () {
      final req = buildLogCollectionRequest(
        identity: _identity(),
        storeName: '마타 강남점',
        from: from,
        to: to,
        platformName: 'Android',
      );

      expect(req.caption, '''
[AppFit 로그]
브랜드: 마타
매장명: 마타 강남점
매장코드: MATA00001
기기: SUNMI D3 MINI (H092W24A1G00862) (Android)
기간: 2026-07-24 ~ 2026-07-30''');
    });

    test('브랜드가 없으면 브랜드 줄이 빠진다', () {
      final req = buildLogCollectionRequest(
        identity: _identity(projectName: null),
        storeName: '마타 강남점',
        from: from,
        to: to,
        platformName: 'Android',
      );
      expect(req.caption, isNot(contains('브랜드:')));
      expect(req.caption.split('\n').first, '[AppFit 로그]');
    });

    test('매장명이 비면 매장명 줄이 빠진다 (로그인 전 기기)', () {
      final req = buildLogCollectionRequest(
        identity: _identity(),
        storeName: '',
        from: from,
        to: to,
        platformName: 'Android',
      );
      expect(req.caption, isNot(contains('매장명:')));
      expect(req.caption, contains('매장코드: MATA00001'));
    });

    test('매장코드가 없으면 매장코드 줄이 빠진다', () {
      final req = buildLogCollectionRequest(
        identity: _identity(shopCode: null),
        storeName: '마타 강남점',
        from: from,
        to: to,
        platformName: 'Android',
      );
      expect(req.caption, isNot(contains('매장코드:')));
    });

    test('시리얼이 없으면 기기 줄에 설치 UUID 가 들어간다', () {
      final req = buildLogCollectionRequest(
        identity: _identity(serial: null),
        storeName: '마타 강남점',
        from: from,
        to: to,
        platformName: 'Android',
      );
      expect(
        req.caption,
        contains(
            '기기: SUNMI D3 MINI (installid0123456789abcdef01234567) (Android)'),
      );
    });

    test('Windows 기기는 플랫폼 표기가 Windows', () {
      final req = buildLogCollectionRequest(
        identity: _identity(deviceModel: 'POS-01', serial: null),
        storeName: '마타 강남점',
        from: from,
        to: to,
        platformName: 'Windows',
      );
      expect(req.caption, contains('(Windows)'));
    });
  });

  group('원격 요청 표시', () {
    test('source 를 주면 마지막 줄에 요청 출처가 붙는다', () {
      final req = buildLogCollectionRequest(
        identity: _identity(),
        storeName: '마타 강남점',
        from: from,
        to: to,
        source: '원격 (c-3f2a)',
        platformName: 'Android',
      );
      expect(req.caption.split('\n').last, '요청: 원격 (c-3f2a)');
    });

    test('source 가 없으면 요청 줄이 아예 없다 (수동 버튼 회귀 방지)', () {
      final req = buildLogCollectionRequest(
        identity: _identity(),
        storeName: '마타 강남점',
        from: from,
        to: to,
        platformName: 'Android',
      );
      expect(req.caption, isNot(contains('요청:')));
      expect(req.caption.split('\n').last, '기간: 2026-07-24 ~ 2026-07-30');
    });
  });

  group('파일명', () {
    test('하루짜리는 날짜 하나', () {
      final req = buildLogCollectionRequest(
        identity: _identity(),
        storeName: '',
        from: DateTime(2026, 7, 30),
        to: DateTime(2026, 7, 30),
      );
      expect(req.filename, 'appfit_logs_2026-07-30.zip');
    });

    test('기간이면 두 날짜', () {
      final req = buildLogCollectionRequest(
        identity: _identity(),
        storeName: '',
        from: from,
        to: to,
      );
      expect(req.filename, 'appfit_logs_2026-07-24_2026-07-30.zip');
    });
  });

  group('resolveLogRange', () {
    final now = DateTime(2026, 7, 30, 14, 37, 12);

    test('today 는 당일 0시 ~ 당일 0시', () {
      final r = resolveLogRange(LogRangePreset.today, now: now);
      expect(r.from, DateTime(2026, 7, 30));
      expect(r.to, DateTime(2026, 7, 30));
    });

    test('7일은 오늘 포함 7일 (today-6)', () {
      final r = resolveLogRange(LogRangePreset.days7, now: now);
      expect(r.from, DateTime(2026, 7, 24));
      expect(r.to, DateTime(2026, 7, 30));
      expect(r.to.difference(r.from).inDays, 6);
    });

    test('30일은 오늘 포함 30일 (today-29)', () {
      final r = resolveLogRange(LogRangePreset.days30, now: now);
      expect(r.from, DateTime(2026, 7, 1));
      expect(r.to.difference(r.from).inDays, 29);
    });

    test('월 경계를 넘어도 정확하다', () {
      final r =
          resolveLogRange(LogRangePreset.days7, now: DateTime(2026, 3, 3));
      expect(r.from, DateTime(2026, 2, 25));
    });

    test('시각 성분은 버리고 자정으로 맞춘다', () {
      final r = resolveLogRange(LogRangePreset.today, now: now);
      expect(r.from.hour, 0);
      expect(r.from.minute, 0);
    });
  });

  group('formatLogDate / humanSize', () {
    test('formatLogDate 는 로그 파일명 규칙과 같은 zero-pad 표기', () {
      expect(formatLogDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatLogDate(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('humanSize 경계', () {
      expect(humanSize(0), '0 B');
      expect(humanSize(1023), '1023 B');
      expect(humanSize(1024), '1.0 KB');
      expect(humanSize(1024 * 1024 - 1), '1024.0 KB');
      expect(humanSize(1024 * 1024), '1.0 MB');
      expect(humanSize(1258291), '1.2 MB');
    });
  });
}
