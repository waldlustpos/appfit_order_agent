import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart' as appfit_core;

import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 웹소켓 원격 명령(DeviceCommand) 처리기 (스캐폴딩).
///
/// `order_socket_manager` 가 주문 디스패처 진입 전에 기기 명령을 가로채 이 핸들러로
/// 위임한다. 서버 푸시는 아직 없으며(백엔드 준비 후), 지금은 수동 버튼과 동일한
/// [logCollectionServiceProvider] 경로를 타므로 가짜 소켓 메시지로 전체 시나리오를
/// 재현/테스트할 수 있다.
class RemoteCommandHandler {
  final Ref _ref;

  RemoteCommandHandler(this._ref);

  Future<void> handle(appfit_core.DeviceCommandPayload cmd) async {
    switch (cmd.command) {
      case appfit_core.DeviceCommandType.logUploadRequested:
        await _handleLogUpload(cmd);
        break;
      case appfit_core.DeviceCommandType.statusReportRequested:
        await _handleStatusReport(cmd);
        break;
      case null:
        logger.d('[RemoteCommand] 미지원 명령 무시: ${cmd.commandRaw}');
        break;
    }
  }

  /// 이 기기가 명령 대상인지 판정.
  /// - shopCode 가 지정됐고 현재 매장과 다르면 대상 아님.
  /// - targetSerial 이 지정됐고 이 기기 식별자와 다르면 대상 아님.
  ///   (시리얼 미확보 단말은 deviceId 가 installId 이므로 매장 단위 지정만 매칭됨.)
  Future<bool> _matchesThisDevice(appfit_core.DeviceCommandPayload cmd) async {
    final myShop = _ref.read(preferenceServiceProvider).getId();
    if (cmd.shopCode != null && myShop != null && cmd.shopCode != myShop) {
      return false;
    }
    if (cmd.targetSerial != null) {
      final id = await _ref.read(deviceIdentityServiceProvider).resolve();
      if (id.deviceId != cmd.targetSerial) return false;
    }
    return true;
  }

  Future<void> _handleLogUpload(appfit_core.DeviceCommandPayload cmd) async {
    if (!await _matchesThisDevice(cmd)) {
      logger.d('[RemoteCommand] LOG_UPLOAD 대상 아님 — 무시 (cmd=${cmd.commandId})');
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = cmd.fromDate ?? today;
    final to = cmd.toDate ?? today;
    final fromStr = _fmt(from);
    final toStr = _fmt(to);
    final filename = fromStr == toStr
        ? 'appfit_logs_$fromStr.zip'
        : 'appfit_logs_${fromStr}_$toStr.zip';

    final id = await _ref.read(deviceIdentityServiceProvider).resolve();
    final caption = <String>[
      '[AppFit 로그] 원격 요청',
      if (cmd.commandId != null) 'cmd: ${cmd.commandId}',
      if (id.storeLabel.isNotEmpty) '매장: ${id.storeLabel}',
      '기기: ${id.deviceLabel}',
      '기간: $fromStr ~ $toStr',
    ].join('\n');

    logToFile(
      tag: LogTag.SYSTEM,
      message:
          '[RemoteCommand] 로그 업로드 요청 수신 ($fromStr~$toStr, cmd=${cmd.commandId})',
    );

    final outcome =
        await _ref.read(logCollectionServiceProvider).collectAndUpload(
              from: from,
              to: to,
              caption: caption,
              filename: filename,
            );

    logToFile(
      tag: LogTag.SYSTEM,
      message: outcome.success
          ? '[RemoteCommand] 로그 업로드 성공 (${outcome.fileCount}개 파일)'
          : '[RemoteCommand] 로그 업로드 실패: ${outcome.error}',
    );
  }

  Future<void> _handleStatusReport(appfit_core.DeviceCommandPayload cmd) async {
    if (!await _matchesThisDevice(cmd)) return;
    // 스캐폴딩: 전송 경로(소켓 emit/REST)는 서버 inbound 계약 확정 후 추가.
    final connected = _ref.read(appFitNotifierServiceProvider).isConnected;
    final snap = await _ref
        .read(deviceStatusReporterProvider)
        .snapshot(connected: connected);
    logToFile(
      tag: LogTag.SYSTEM,
      message: '[RemoteCommand] 상태 보고 요청 (전송 경로 미구현): $snap',
    );
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
