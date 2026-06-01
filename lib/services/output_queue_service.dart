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
/// [forceOrderReceipt] true 면 KDS 자동접수 OFF 라도 주문서 출력 진입.
/// 외부 디바이스 접수로 발생한 PREPARING 이벤트 처리용.
final class NewOrderJob extends OutputJob {
  const NewOrderJob(super.order,
      {this.playSound = true,
      this.printLabel = true,
      this.forceOrderReceipt = false});
  final bool playSound;
  final bool printLabel;
  final bool forceOrderReceipt;
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

/// [NewOrderJob] 의 라벨 부분만 표현하는 내부 tail job.
/// 영수증/사운드를 영수증 큐에서 await 한 뒤 라벨 큐로 enqueue 된다.
/// 외부 호출자는 사용하지 않음 — `OutputQueueService` 내부 라우팅 전용.
final class _NewOrderLabelTail extends OutputJob {
  const _NewOrderLabelTail(super.order);
}

/// 출력 작업 관리를 위한 큐 서비스.
///
/// 영수증/사운드와 라벨을 별도 직렬 큐로 분리해 두 프린터가 독립 병렬 동작하도록 한다.
/// 같은 NewOrderJob 안에서는 라벨 부분을 영수증 await 보다 먼저 라벨 큐에 enqueue
/// 하므로 영수증 PrinterJobQueue 의 backoff(최대 137s) / 라벨떼기(PAPERNOFETCH)
/// 무한 대기가 서로를 막지 않는다. 두 프린터가 별개 본체이므로 출력 순서는 보장하지
/// 않는다 — 라벨이 영수증보다 먼저 나올 수 있음.
///
/// 큐 종류:
/// - `_receiptQueue`: NewOrderJob (영수증+사운드 부분), ReceiptReprintJob
/// - `_labelQueue`: LabelOnlyJob, ReprintJob, _NewOrderLabelTail
///
/// 자체 구현 [SerialAsyncQueue] (lib/utils/serial_async_queue.dart) 를 사용합니다.
class OutputQueueService {
  final Ref ref;
  late final SerialAsyncQueue<OutputJob> _receiptQueue;
  late final SerialAsyncQueue<OutputJob> _labelQueue;

  OutputQueueService(this.ref) {
    _receiptQueue = SerialAsyncQueue(
      onProcess: _processReceiptItem,
      onError: (item, error, stack) {
        final num = item.order.displayNum;
        logger.e('[ReceiptQueue] $num 처리 실패', error: error, stackTrace: stack);
        logToFile(
            tag: LogTag.ERROR, message: '[ReceiptQueue] $num 처리 실패: $error');
      },
    );
    _labelQueue = SerialAsyncQueue(
      onProcess: _processLabelItem,
      onError: (item, error, stack) {
        final num = item.order.displayNum;
        logger.e('[LabelQueue] $num 처리 실패', error: error, stackTrace: stack);
        logToFile(
            tag: LogTag.ERROR, message: '[LabelQueue] $num 처리 실패: $error');
      },
    );
  }

  /// 핵심 라이프사이클 한 줄 — [PLATFORM] 태그로 기록. 호출 측에서 prefix
  /// (`[ReceiptQueue]` / `[LabelQueue]`) 를 메시지에 포함시킨다.
  void _life(String message) {
    logToFile(tag: LogTag.PLATFORM, message: message);
  }

  /// 신규 주문 출력 작업 추가.
  /// 동일 orderId 의 NewOrderJob 이 이미 진행/대기 중이면 중복 추가를 무시한다
  /// (WebSocket+폴링 이중 트리거 안전망).
  void add(OrderModel order,
      {bool playSound = true,
      bool printLabel = true,
      bool forceOrderReceipt = false}) {
    final id = order.orderId;
    if (_inFlightNewOrders.contains(id)) return;
    _inFlightNewOrders.add(id);
    _receiptQueue.add(NewOrderJob(order,
        playSound: playSound,
        printLabel: printLabel,
        forceOrderReceipt: forceOrderReceipt));
  }

  // 진행 중/대기 중 NewOrderJob 의 orderId 추적 (영수증/사운드 단계). 영수증 종료 시 제거.
  final Set<String> _inFlightNewOrders = <String>{};

  // 진행 중/대기 중 _NewOrderLabelTail 의 orderId 추적. label tail 종료 시 제거.
  final Set<String> _inFlightLabelTail = <String>{};

  /// 라벨 단독 출력 작업 추가 (KDS PREPARING / 일반 수동접수 등).
  /// 동일 orderId 가 이미 진행/대기 중이면 중복 무시.
  void addLabelOnly(OrderModel order) {
    final id = order.orderId;
    if (_inFlightLabelOnly.contains(id)) return;
    _inFlightLabelOnly.add(id);
    _labelQueue.add(LabelOnlyJob(order));
  }

  // 진행 중/대기 중 LabelOnlyJob 의 orderId 추적.
  final Set<String> _inFlightLabelOnly = <String>{};

  /// 사용자 재출력 요청 추가 (라벨 프린터 USB 경쟁 방지를 위해 라벨 큐에 직렬화).
  /// 동일 orderId 의 ReprintJob 이 이미 대기 중이거나 처리 중이면 중복 추가를 무시한다.
  void addReprint(OrderModel order) {
    final id = order.orderId;
    if (_inFlightReprints.contains(id)) return;
    _inFlightReprints.add(id);
    _labelQueue.add(ReprintJob(order));
  }

  // 진행 중/대기 중 ReprintJob 의 orderId 추적. _processLabelItem 종료 시 제거.
  final Set<String> _inFlightReprints = <String>{};

  /// 사용자 영수증 재출력 요청 추가 (영수증 + 라벨 동시 재출력, 사운드 없음).
  /// 영수증/라벨 프린터의 USB 자원 경쟁 방지를 위해 영수증 큐에 직렬화한다.
  void addReceiptReprint(OrderModel order) {
    final isCancelled = order.status == OrderStatus.CANCELLED;
    _receiptQueue.add(ReceiptReprintJob(order, isCancelReceipt: isCancelled));
  }

  /// 영수증 큐 처리: NewOrderJob 의 영수증/사운드, ReceiptReprintJob.
  /// NewOrderJob 의 라벨 부분은 영수증 await 전에 라벨 큐로 enqueue 되어 병렬 진행.
  Future<void> _processReceiptItem(OutputJob job) async {
    final outputService = ref.read(outputAppServiceProvider);
    final num = job.order.displayNum;
    switch (job) {
      case NewOrderJob(
          order: final order,
          playSound: final playSound,
          printLabel: final printLabel,
          forceOrderReceipt: final forceOrderReceipt,
        ):
        // 라벨 부분을 영수증 await 보다 먼저 라벨 큐에 enqueue.
        // 두 큐가 진짜 병렬 동작하려면 enqueue 시점이 영수증 backoff(최대 137s)
        // 와 독립이어야 한다. 라벨/영수증은 별개 본체·별개 큐 worker 라
        // 동시 진행이 안전.
        // (이전 구현: 영수증 await 후 enqueue → 큐 분리에도 불구하고 사실상
        // 직렬화되어 외부 영수증 오프라인 시 라벨이 137s 동안 안 나오는 사고 발생.)
        if (printLabel) {
          final tailId = order.orderId;
          if (!_inFlightLabelTail.contains(tailId)) {
            _inFlightLabelTail.add(tailId);
            _labelQueue.add(_NewOrderLabelTail(order));
            _life('[LabelQueue] $num NEW_LABEL tail enqueue');
          }
        }

        _life('[ReceiptQueue] $num NEW_RECEIPT 시작');
        try {
          // 영수증/사운드만 처리. 라벨은 이미 라벨 큐에서 독립 진행 중.
          await outputService.notifyNewOrder(order,
              playSound: playSound,
              printLabel: false,
              forceOrderReceipt: forceOrderReceipt);
        } finally {
          _inFlightNewOrders.remove(order.orderId);
        }
        _life('[ReceiptQueue] $num NEW_RECEIPT 완료');
      case ReceiptReprintJob(order: final order, isCancelReceipt: final cancel):
        _life('[ReceiptQueue] $num RECEIPT_REPRINT 시작');
        final printService = ref.read(printServiceProvider);
        await printService.printOrderReceipt(
          order: order,
          type: 'receipt',
          isCancelReceipt: cancel,
        );
        _life('[ReceiptQueue] $num RECEIPT_REPRINT 완료');
      case LabelOnlyJob():
      case ReprintJob():
      case _NewOrderLabelTail():
        // 라우팅 오류 — 라벨 큐 전용 job 이 영수증 큐에 들어왔을 때 안전망.
        // sealed switch exhaustiveness 보장용. 정상 흐름에서는 도달 불가.
        logToFile(
            tag: LogTag.WARNING,
            message: '[ReceiptQueue] $num 잘못된 job 라우팅: $job');
    }
  }

  /// 라벨 큐 처리: LabelOnlyJob, ReprintJob, _NewOrderLabelTail.
  Future<void> _processLabelItem(OutputJob job) async {
    final outputService = ref.read(outputAppServiceProvider);
    final num = job.order.displayNum;
    switch (job) {
      case LabelOnlyJob(order: final order):
        _life('[LabelQueue] $num LABEL_ONLY 시작');
        try {
          await outputService.printOrderLabels(order);
        } finally {
          _inFlightLabelOnly.remove(order.orderId);
        }
        _life('[LabelQueue] $num LABEL_ONLY 완료');
      case ReprintJob(order: final order):
        _life('[LabelQueue] $num REPRINT 시작');
        try {
          await outputService.printOrderLabels(order, isReprint: true);
        } finally {
          _inFlightReprints.remove(order.orderId);
        }
        _life('[LabelQueue] $num REPRINT 완료');
      case _NewOrderLabelTail(order: final order):
        _life('[LabelQueue] $num NEW_LABEL 시작');
        try {
          await outputService.printOrderLabels(order);
        } finally {
          _inFlightLabelTail.remove(order.orderId);
        }
        _life('[LabelQueue] $num NEW_LABEL 완료');
      case NewOrderJob():
      case ReceiptReprintJob():
        // 라우팅 오류 — 영수증 큐 전용 job 이 라벨 큐에 들어왔을 때 안전망.
        logToFile(
            tag: LogTag.WARNING,
            message: '[LabelQueue] $num 잘못된 job 라우팅: $job');
    }
  }

  /// 큐 정리 (로그아웃 등)
  void clear() {
    _receiptQueue.clear();
    _labelQueue.clear();
    _inFlightNewOrders.clear();
    _inFlightLabelOnly.clear();
    _inFlightReprints.clear();
    _inFlightLabelTail.clear();
    _life('[OutputQueue] 큐 정리 완료');
  }
}

/// 전역 프로바이더 정의
final outputQueueServiceProvider = Provider<OutputQueueService>((ref) {
  return OutputQueueService(ref);
});
