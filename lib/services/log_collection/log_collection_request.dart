import 'dart:io';

import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';

/// 로그 수집 요청의 캡션·파일명·기간을 만드는 **단일 정본**.
///
/// 설정화면 수동 버튼과 원격 명령(FleetCommandHandler)이 둘 다 이 함수만 쓴다.
/// 원래 이 로직은 설정화면 위젯의 private 메서드였는데, 원격 경로가 그걸
/// 복붙하면 Slack 메시지 포맷이 두 벌로 갈라져 나중에 반드시 어긋난다.
///
/// UI·provider 에 의존하지 않는 순수 함수라서 단위 테스트로 포맷을 고정할 수 있다.
enum LogRangePreset { today, days7, days30 }

class LogCollectionRequest {
  final DateTime from;
  final DateTime to;

  /// Slack 첨부 메시지.
  final String caption;

  /// `appfit_logs_2026-07-30.zip` 또는 `appfit_logs_2026-07-24_2026-07-30.zip`
  final String filename;

  const LogCollectionRequest({
    required this.from,
    required this.to,
    required this.caption,
    required this.filename,
  });
}

/// 프리셋을 실제 날짜 범위(양끝 포함, 일 단위)로 바꾼다.
///
/// [now] 는 테스트 주입점. 기본은 기기 로컬 시각이며, **로컬 시각인 게 중요하다** —
/// 로그 파일명이 로컬 날짜 기준이라 UTC 로 '오늘'을 정하면 KST 매장에서 하루가
/// 어긋난다.
({DateTime from, DateTime to}) resolveLogRange(
  LogRangePreset preset, {
  DateTime? now,
}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  switch (preset) {
    case LogRangePreset.today:
      return (from: today, to: today);
    case LogRangePreset.days7:
      return (from: today.subtract(const Duration(days: 6)), to: today);
    case LogRangePreset.days30:
      return (from: today.subtract(const Duration(days: 29)), to: today);
  }
}

/// `yyyy-MM-dd`. 로그 파일명 규칙(`appfit_YYYY-MM-DD.txt`)과 같은 표기.
String formatLogDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 원격 명령이 허용하는 최대 기간(일). 기기의 zip 이 인메모리라 기간이 길면
/// 매장 기기에서 OOM 이 난다. 서버도 같은 값으로 클램프하지만, 원격 명령은
/// 아무도 보고 있지 않은 기기에서 터지므로 클라이언트에서도 막는다.
const int maxRemoteLogRangeDays = 31;

/// Slack 캡션과 파일명을 조립한다.
///
/// [source] 를 주면 캡션 끝에 `요청: ...` 줄이 붙는다(원격 명령 식별용).
/// null 이면 기존 수동 버튼과 **문자 단위로 동일한** 캡션이 나온다.
LogCollectionRequest buildLogCollectionRequest({
  required DeviceIdentity identity,
  required String storeName,
  required DateTime from,
  required DateTime to,
  String? source,
  String? platformName,
}) {
  final fromStr = formatLogDate(from);
  final toStr = formatLogDate(to);
  final filename = fromStr == toStr
      ? 'appfit_logs_$fromStr.zip'
      : 'appfit_logs_${fromStr}_$toStr.zip';

  final platform = platformName ?? (Platform.isWindows ? 'Windows' : 'Android');
  final projectName = identity.projectName;
  final shopCode = identity.shopCode;

  final caption = <String>[
    '[AppFit 로그]',
    if (projectName != null && projectName.isNotEmpty) '브랜드: $projectName',
    if (storeName.isNotEmpty) '매장명: $storeName',
    if (shopCode != null && shopCode.isNotEmpty) '매장코드: $shopCode',
    '기기: ${identity.deviceLabel} ($platform)',
    '기간: $fromStr ~ $toStr',
    if (source != null && source.isNotEmpty) '요청: $source',
  ].join('\n');

  return LogCollectionRequest(
    from: from,
    to: to,
    caption: caption,
    filename: filename,
  );
}
