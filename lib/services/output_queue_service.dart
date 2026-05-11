import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/utils/serial_async_queue.dart';
import 'package:appfit_order_agent/core/orders/output_service.dart';

/// 출력 큐 작업 종류
sealed class OutputJob {
  const OutputJob(this.order);
  final OrderModel order;
}

/// 신규 주문 자동 출력 (영수증 + 라벨 + 사운드).
/// [printLabel] false 일 때는 KDS READY(픽업 알림) 처럼 영수증/사운드만 필요한 케이스.
final class NewOrderJob extends OutputJob {
  const NewOrderJob(super.order,
      {this.playSound = true, this.printLabel = true});
  final bool playSound;
  final bool printLabel;
}

/// 사용자 요청 기반 라벨 재출력 (영수증/사운드 없음)
final class ReprintJob extends OutputJob {
  const ReprintJob(super.order);
}

/// KDS PREPARING 자동접수 / 일반 모드 수동접수 등, 라벨만 출력하면 되는 자동 흐름.
/// `notifyNewOrder` 의 영수증/사운드 분기를 거치지 않고 라벨만 직렬 출력.
final class LabelOnlyJob extends OutputJob {
  const LabelOnlyJob(super.order);
}

/// 사용자 요청 기반 영수증 재출력 (라벨 동시 재출력 포함, 사운드 없음).
/// 라벨 프린터와 영수증 프린터의 USB 자원 경쟁을 같은 큐로 직렬화하기 위해 큐를 경유한다.
final class ReceiptReprintJob extends OutputJob {
  const ReceiptReprintJob(super.order, {required this.isCancelReceipt});
  final bool isCancelReceipt;
}

/// 출력 작업 관리를 위한 큐 서비스
/// 프린트/TTS 등 오래 걸리는 작업을 메인 로직과 분리하여 순차적으로 처리합니다.
/// 자체 구현 [SerialAsyncQueue] (lib/utils/serial_async_queue.dart) 를 사용합니다.
class OutputQueueService {
  final Ref ref;
  late final SerialAsyncQueue<OutputJob> _queue;

  OutputQueueService(this.ref) {
    _queue = SerialAsyncQueue(
      onProcess: _processItem,
      onError: (item, error, stack) {
        final num = item.order.displayNum;
        logger.e('[Label] $num 큐 처리 실패', error: error, stackTrace: stack);
        logToFile(tag: LogTag.ERROR, message: '[Label] $num 큐 처리 실패: $error');
      },
    );
  }

  /// 핵심 라이프사이클 한 줄 — `[PLATFORM] [Label]` 단일 채널로 기록.
  void _life(String message) {
    logToFile(tag: LogTag.PLATFORM, message: message);
  }

  /// 신규 주문 출력 작업 추가.
  /// 동일 orderId 의 NewOrderJob 이 이미 진행/대기 중이면 중복 추가를 무시한다
  /// (WebSocket+폴링 이중 트리거 안전망).
  void add(OrderModel order, {bool playSound = true, bool printLabel = true}) {
    final id = order.orderId;
    final num = order.displayNum;
    if (_inFlightNewOrders.contains(id)) {
      _life('[Label] $num 큐중복무시 (NEW, 진행/대기 중)');
      return;
    }
    _inFlightNewOrders.add(id);
    _queue
        .add(NewOrderJob(order, playSound: playSound, printLabel: printLabel));
    _life('[Label] $num 큐추가 (NEW'
        '${printLabel ? '' : ', 라벨X'}'
        '${playSound ? '' : ', 무음'}'
        ', 대기열: ${_queue.length})');
  }

  // 진행 중/대기 중 NewOrderJob 의 orderId 추적. _processItem 종료 시 제거.
  final Set<String> _inFlightNewOrders = <String>{};

  /// 라벨 단독 출력 작업 추가 (KDS PREPARING / 일반 수동접수 등).
  /// 동일 orderId 가 이미 진행/대기 중이면 중복 무시.
  void addLabelOnly(OrderModel order) {
    final id = order.orderId;
    final num = order.displayNum;
    if (_inFlightLabelOnly.contains(id)) {
      _life('[Label] $num 큐중복무시 (LABEL_ONLY, 진행/대기 중)');
      return;
    }
    _inFlightLabelOnly.add(id);
    _queue.add(LabelOnlyJob(order));
    _life('[Label] $num 큐추가 (LABEL_ONLY, 대기열: ${_queue.length})');
  }

  // 진행 중/대기 중 LabelOnlyJob 의 orderId 추적.
  final Set<String> _inFlightLabelOnly = <String>{};

  /// 사용자 재출력 요청 추가 (라벨 프린터 USB 경쟁 방지를 위해 동일 큐에 직렬화).
  /// 동일 orderId 의 ReprintJob 이 이미 대기 중이거나 처리 중이면 중복 추가를 무시한다.
  void addReprint(OrderModel order) {
    final id = order.orderId;
    final num = order.displayNum;
    if (_inFlightReprints.contains(id)) {
      _life('[Label] $num 큐중복무시 (REPRINT, 진행/대기 중)');
      return;
    }
    _inFlightReprints.add(id);
    _queue.add(ReprintJob(order));
    _life('[Label] $num 큐추가 (REPRINT, 대기열: ${_queue.length})');
  }

  // 진행 중/대기 중 ReprintJob 의 orderId 추적. _processItem 종료 시 제거.
  final Set<String> _inFlightReprints = <String>{};

  /// 사용자 영수증 재출력 요청 추가 (영수증 + 라벨 동시 재출력, 사운드 없음).
  /// 영수증/라벨 프린터의 USB 자원 경쟁 방지를 위해 동일 큐에 직렬화한다.
  void addReceiptReprint(OrderModel order) {
    final isCancelled = order.status == OrderStatus.CANCELLED;
    _queue.add(ReceiptReprintJob(order, isCancelReceipt: isCancelled));
    _life('[Label] ${order.displayNum} 큐추가 (RECEIPT_REPRINT'
        '${isCancelled ? ', 취소영수증' : ''}'
        ', 대기열: ${_queue.length})');
  }

  Future<void> _processItem(OutputJob job) async {
    final outputService = ref.read(outputAppServiceProvider);
    final num = job.order.displayNum;
    switch (job) {
      case NewOrderJob(
          order: final order,
          playSound: final playSound,
          printLabel: final printLabel
        ):
        _life('[Label] $num 큐시작 (NEW)');
        try {
          await outputService.notifyNewOrder(order,
              playSound: playSound, printLabel: printLabel);
        } finally {
          _inFlightNewOrders.remove(order.orderId);
        }
        _life('[Label] $num 큐완료 (NEW)');
      case LabelOnlyJob(order: final order):
        _life('[Label] $num 큐시작 (LABEL_ONLY)');
        try {
          await outputService.printOrderLabels(order);
        } finally {
          _inFlightLabelOnly.remove(order.orderId);
        }
        _life('[Label] $num 큐완료 (LABEL_ONLY)');
      case ReprintJob(order: final order):
        _life('[Label] $num 큐시작 (REPRINT)');
        try {
          await outputService.printOrderLabels(order, isReprint: true);
        } finally {
          _inFlightReprints.remove(order.orderId);
        }
        _life('[Label] $num 큐완료 (REPRINT)');
      case ReceiptReprintJob(order: final order, isCancelReceipt: final cancel):
        _life('[Label] $num 큐시작 (RECEIPT_REPRINT)');
        final printService = ref.read(printServiceProvider);
        await printService.printOrderReceipt(
          order: order,
          type: 'receipt',
          isCancelReceipt: cancel,
        );
        _life('[Label] $num 큐완료 (RECEIPT_REPRINT)');
    }
  }

  /// 큐 정리 (로그아웃 등)
  void clear() {
    _queue.clear();
    _inFlightNewOrders.clear();
    _inFlightLabelOnly.clear();
    _inFlightReprints.clear();
    _life('[Label] 큐 정리 완료');
  }
}

/// 전역 프로바이더 정의
final outputQueueServiceProvider = Provider<OutputQueueService>((ref) {
  return OutputQueueService(ref);
});
