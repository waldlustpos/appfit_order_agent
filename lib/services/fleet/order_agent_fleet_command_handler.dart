import 'package:appfit_core/appfit_core.dart';

import 'package:appfit_order_agent/services/log_collection/log_collection_request.dart';
import 'package:appfit_order_agent/services/log_collection/log_collection_service.dart';
import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

/// 원격 명령 실행기. **core 승격 대상이 아니다** — 로그 수집은 order_agent 만
/// 가진 기능이라 앱에 남는다. DID/KIOSK 는 핸들러를 주입하지 않으므로
/// 리포터가 UNSUPPORTED 로 즉답한다.
///
/// 로그 수집은 설정화면 수동 버튼과 **완전히 같은 경로**를 쓴다
/// ([buildLogCollectionRequest] + [LogCollectionService.collectAndUpload]).
class OrderAgentFleetCommandHandler {
  /// 원격 요청 zip 원본 합계 상한. 초과하면 zip 을 시도조차 하지 않는다.
  ///
  /// 인메모리 zip 이라 피크 메모리가 "원본 + 결과"인데, 원격 명령은 아무도
  /// 보고 있지 않은 매장 기기(D3 MINI 급)에서 돈다. 파일럿 운영으로 실제 로그
  /// 크기를 실측한 뒤 조정한다.
  static const int maxSourceBytes = 30 * 1024 * 1024;

  final LogCollectionService _logCollection;
  final DeviceIdentityService _identityService;
  final String? Function() _readStoreName;
  final DateTime Function() _now;

  OrderAgentFleetCommandHandler({
    required LogCollectionService logCollection,
    required DeviceIdentityService identityService,
    required String? Function() readStoreName,
    DateTime Function()? now,
  })  : _logCollection = logCollection,
        _identityService = identityService,
        _readStoreName = readStoreName,
        _now = now ?? DateTime.now;

  Future<FleetCommandResult> handle(FleetCommand command) async {
    logToFile(
      tag: LogTag.SYSTEM,
      message: '원격 명령 수신: ${command.type} (${command.commandId})',
    );

    switch (command.type) {
      case FleetCommandTypes.logUpload:
        return _handleLogUpload(command);

      // 상태 보고는 명령 자체가 heartbeat 왕복이므로 도착한 시점에 이미 끝났다.
      case FleetCommandTypes.statusReport:
      case FleetCommandTypes.ping:
        return FleetCommandResult.ok(command.commandId, message: '상태 보고 완료');

      default:
        return FleetCommandResult.unsupported(
          command.commandId,
          message: '알 수 없는 명령: ${command.type}',
        );
    }
  }

  Future<FleetCommandResult> _handleLogUpload(FleetCommand command) async {
    final range = _resolveRange(command.payload);

    final identity = await _identityService.resolve();
    final storeName = _readStoreName() ?? identity.shopName ?? '';

    final request = buildLogCollectionRequest(
      identity: identity,
      storeName: storeName,
      from: range.from,
      to: range.to,
      source: '원격 (${command.commandId})',
    );

    final outcome = await _logCollection.collectAndUpload(
      from: request.from,
      to: request.to,
      caption: request.caption,
      filename: request.filename,
      maxSourceBytes: maxSourceBytes,
    );

    if (!outcome.success) {
      return FleetCommandResult.failed(
        command.commandId,
        outcome.error ?? '알 수 없는 실패',
      );
    }

    return FleetCommandResult.ok(
      command.commandId,
      message: '${outcome.fileCount}개 파일, ${humanSize(outcome.zipBytes)}',
      reference: outcome.reference,
    );
  }

  /// payload 의 fromDate/toDate 를 해석한다.
  ///
  /// 날짜가 없으면 **기기 로컬 기준 오늘**로 본다. 서버가 UTC 로 '오늘'을 정하면
  /// KST 매장에서 하루가 어긋나므로, 서버는 날짜를 비워 보내고 해석을 기기에
  /// 맡긴다. 서버도 31일로 클램프하지만 여기서 한 번 더 막는다 — 원격 명령의
  /// 실패는 아무도 보고 있지 않은 곳에서 일어난다.
  ({DateTime from, DateTime to}) _resolveRange(Map<String, dynamic> payload) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);

    final from = _parseDay(payload['fromDate']) ?? today;
    final to = _parseDay(payload['toDate']) ?? today;

    final start = from.isAfter(to) ? to : from;
    final end = from.isAfter(to) ? from : to;

    final maxSpan = Duration(days: maxRemoteLogRangeDays - 1);
    final clampedStart =
        end.difference(start) > maxSpan ? end.subtract(maxSpan) : start;

    return (from: clampedStart, to: end);
  }

  static DateTime? _parseDay(Object? value) {
    if (value is! String || value.length != 10) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }
}
