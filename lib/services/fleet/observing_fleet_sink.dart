import 'package:appfit_core/appfit_core.dart';

import 'package:appfit_order_agent/services/fleet/fleet_connection_status.dart';

/// [FleetSink] 데코레이터. register/heartbeat 호출 결과를 가로채
/// [onStatus] 로 [FleetConnectionStatus] 를 통지한다 — 실제 전송 동작은
/// [inner] 에 그대로 위임.
///
/// FleetReporter._tick 은 sink 호출 전체를 try/catch 로 감싸 예외를 삼킨다
/// (관제가 주문 흐름을 막으면 안 되므로). 그 계약을 유지하기 위해 여기서도
/// 예외를 error 로 기록한 뒤 그대로 rethrow 한다.
class ObservingFleetSink implements FleetSink {
  final FleetSink _inner;
  final void Function(FleetConnectionStatus) _onStatus;

  ObservingFleetSink({
    required FleetSink inner,
    required void Function(FleetConnectionStatus) onStatus,
  })  : _inner = inner,
        _onStatus = onStatus;

  @override
  String get name => _inner.name;

  @override
  bool get isConfigured => _inner.isConfigured;

  @override
  Future<FleetAck> register(FleetDeviceInfo device) =>
      _observed(() => _inner.register(device));

  @override
  Future<FleetAck> heartbeat(
    FleetSnapshot snapshot,
    List<FleetCommandResult> results,
  ) =>
      _observed(() => _inner.heartbeat(snapshot, results));

  Future<FleetAck> _observed(Future<FleetAck> Function() call) async {
    try {
      final ack = await call();
      _onStatus(
        ack.success
            ? FleetConnectionStatus.connected
            : FleetConnectionStatus.error,
      );
      return ack;
    } catch (e) {
      _onStatus(FleetConnectionStatus.error);
      rethrow;
    }
  }
}
