import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_core/appfit_core.dart' show MonitoringService;
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/label_printer/fast_menu_policy.dart';
import 'package:appfit_order_agent/services/label_printer/label_target.dart';
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

/// 준비가 끝난 주문의 **한 타깃(제조 구역) 몫**을 인쇄하는 내부 job.
///
/// 준비 큐가 상세조회·타깃 분할을 마친 뒤 타깃별 큐로 흘려보낸다.
/// [order] 는 이미 메뉴가 보강된 상태라 인쇄 단계에서 다시 조회하지 않는다.
final class _TargetLabelJob extends OutputJob {
  const _TargetLabelJob(
    super.order, {
    required this.target,
    required this.isReprint,
    required this.kind,
    required this.onDone,
  });

  final LabelTarget target;
  final bool isReprint;

  /// 로그 표기용 원래 작업 종류 (LABEL_ONLY / REPRINT / NEW_LABEL).
  final String kind;

  /// 이 주문의 마지막 타깃 작업이 끝났을 때 호출 — 중복 방지 해제용.
  final void Function() onDone;
}

/// 출력 작업 관리를 위한 큐 서비스.
///
/// 영수증/사운드와 라벨을 별도 직렬 큐로 분리해 두 프린터가 독립 병렬 동작하도록 한다.
/// 같은 NewOrderJob 안에서는 라벨 부분을 영수증 await 보다 먼저 라벨 큐에 enqueue
/// 하므로 영수증 PrinterJobQueue 의 backoff(최대 137s) / 라벨떼기(PAPERNOFETCH)
/// 무한 대기가 서로를 막지 않는다. 두 프린터가 별개 본체이므로 출력 순서는 보장하지
/// 않는다 — 라벨이 영수증보다 먼저 나올 수 있음.
///
/// ## 라벨은 2단계 파이프라인이다
///
/// ```
/// _labelPrepQueue (직렬 1개)        _labelQueues[타깃] (타깃마다 1개)
///   상세조회 · 타깃 분할       →      렌더 + 인쇄 + 완료 대기
/// ```
///
/// **왜 나눴나.** 라벨 프린터가 여러 대일 때, 한 대에서 운영자가 라벨을 안 떼면
/// 펌웨어가 다음 장을 보류한다(정상 동작). 큐가 하나면 그 대기가 **다른 프린터로
/// 갈 라벨까지** 막는다 — 구역을 나눈 의미가 사라진다. 타깃마다 큐를 두면 막힌
/// 구역만 기다린다.
///
/// **왜 앞단을 직렬로 남겼나.** 상세조회를 타깃별로 각자 하면 (a) 같은 주문을 여러 번
/// 조회하고, 더 나쁘게는 (b) 한쪽만 실패했을 때 그쪽이 `markPendingReprint` 를 걸어
/// **성공한 쪽까지 재발행되어 라벨이 중복된다.** 그리고 준비 단계가 직렬이라야
/// 타깃 큐로 들어가는 순서가 도착 순서를 따른다. 준비는 종이를 기다리지 않으므로
/// 여기서 막히지 않는다.
///
/// **타깃이 하나면 큐도 하나다.** 구역을 안 나눈 매장(대다수)에서는 큐 맵에
/// `primary` 하나만 생겨 종전과 동일하게 동작한다.
///
/// 큐 종류:
/// - `_receiptQueue`: NewOrderJob (영수증+사운드 부분), ReceiptReprintJob
/// - `_labelPrepQueue`: LabelOnlyJob, ReprintJob, _NewOrderLabelTail
/// - `_labelQueues[타깃]`: _TargetLabelJob
///
/// 자체 구현 [SerialAsyncQueue] (lib/utils/serial_async_queue.dart) 를 사용합니다.
class OutputQueueService {
  final Ref ref;
  late final SerialAsyncQueue<OutputJob> _receiptQueue;
  late final SerialAsyncQueue<OutputJob> _labelPrepQueue;

  /// 타깃 id → 인쇄 큐. 필요할 때 만든다.
  final Map<String, SerialAsyncQueue<OutputJob>> _labelQueues = {};

  /// 주문별 남은 타깃 작업 수. 0 이 되면 중복 방지 플래그를 푼다.
  ///
  /// 작업 하나가 끝날 때마다 풀면, 아직 다른 타깃이 인쇄 중인데 같은 주문이 다시
  /// 큐에 들어올 수 있다 — 그게 곧 중복 인쇄다.
  final Map<String, int> _pendingTargetJobs = {};

  OutputQueueService(this.ref) {
    _receiptQueue = SerialAsyncQueue(
      onProcess: _processReceiptItem,
      onError: (item, error, stack) {
        final num = item.order.displayNum;
        logger.e('[ReceiptQueue] $num 처리 실패', error: error, stackTrace: stack);
        logToFile(
            tag: LogTag.ERROR, message: '[ReceiptQueue] $num 처리 실패: $error');
        MonitoringService.instance.captureError(
          error,
          stack,
          hint: '[ReceiptQueue] 처리 실패',
          extras: {'orderNo': item.order.orderNo, 'displayNum': num},
        );
      },
    );
    _labelPrepQueue = SerialAsyncQueue(
      onProcess: _processLabelPrepItem,
      onError: (item, error, stack) =>
          _reportLabelQueueError('[LabelPrep]', item, error, stack),
    );
  }

  /// 타깃별 인쇄 큐. 없으면 만든다.
  ///
  /// 큐를 미리 다 만들지 않는 이유: 구역을 안 나눈 매장에서는 `primary` 하나만
  /// 생겨야 종전과 같은 단일 큐 동작이 된다.
  SerialAsyncQueue<OutputJob> _labelQueueFor(LabelTarget target) {
    return _labelQueues.putIfAbsent(
      target.id,
      () => SerialAsyncQueue(
        onProcess: _processLabelItem,
        onError: (item, error, stack) => _reportLabelQueueError(
            '[LabelQueue:${target.id}]', item, error, stack),
      ),
    );
  }

  void _reportLabelQueueError(
      String prefix, OutputJob item, Object error, StackTrace stack) {
    final num = item.order.displayNum;
    logger.e('$prefix $num 처리 실패', error: error, stackTrace: stack);
    logToFile(tag: LogTag.ERROR, message: '$prefix $num 처리 실패: $error');
    MonitoringService.instance.captureError(
      error,
      stack,
      hint: '$prefix 처리 실패',
      extras: {'orderNo': item.order.orderNo, 'displayNum': num},
    );
  }

  /// 핵심 라이프사이클 한 줄. 호출 측에서 prefix(`[ReceiptQueue]` /
  /// `[LabelQueue]`) 를 메시지에 포함시킨다.
  ///
  /// 보수적 축약: '완료' 계열만 파일에 남기고 '시작'/'enqueue' 단계는
  /// 콘솔(logger.d)로만 기록해 운영 로그 노이즈를 줄인다. (에러/누락은
  /// 호출 측에서 별도 WARNING/ERROR 태그로 직접 기록.)
  void _life(String message) {
    if (message.contains('완료')) {
      logToFile(tag: LogTag.PLATFORM, message: message);
    } else {
      logger.d(message);
    }
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
    _enqueueLabel(LabelOnlyJob(order), order, 'LABEL_ONLY');
  }

  /// 라벨 큐 투입 단일 지점. 전량 빠른 메뉴 주문이면 대기 중인 일반 작업을
  /// 추월시킨다 (설정 mode=2 일 때만. [FastMenuPolicy.isFastOrder] 가 게이팅).
  ///
  /// 재출력(`ReprintJob`/`ReceiptReprintJob`)은 이 경로를 쓰지 않는다 —
  /// 운영자가 방금 누른 명시 요청이라 재정렬 대상이 아니다.
  void _enqueueLabel(OutputJob job, OrderModel order, String kind) {
    final num = order.displayNum;
    if (_isPriorityOrder(order)) {
      // 우선 판정은 준비 큐가 아니라 **인쇄 큐**에서 의미가 있다(준비는 종이를
      // 기다리지 않아 금방 끝난다). 그래서 여기서 판정해 두고 아래
      // _dispatchTargets 가 인쇄 큐에 우선으로 넣는다.
      _priorityOrders.add(order.orderId);
      _labelPrepQueue.addPriority(job);
      // 우선 판정은 파일에 남긴다. 순서가 뒤집힌 사유를 나중에 로그만으로
      // 설명할 수 있어야 "왜 뒷 주문이 먼저 나왔나" 문의에 답할 수 있다.
      logToFile(
          tag: LogTag.PLATFORM,
          message: '[LabelQueue] $num $kind PRIORITY enqueue (빠른 메뉴 주문)');
      return;
    }
    _labelPrepQueue.add(job);
    // 일반 enqueue 도 파일에 남긴다. PRIORITY 줄만 파일에 있으면 "왜 이 순서로
    // 나왔나" 를 파일 로그만으로 재구성할 수 없다 — 추월당한 쪽이 언제 큐에
    // 들어왔는지가 없으면 굶주림 가드가 정상인지 판정 자체가 불가능하다.
    // (2026-08-12 현장 테스트에서 실제로 막힌 지점.)
    logToFile(
        tag: LogTag.PLATFORM, message: '[LabelQueue] $num $kind enqueue (일반)');
  }

  /// 우선 투입 대상인지. **설정 조회 실패는 전부 '일반'으로 흡수한다.**
  ///
  /// 이 판정은 부가 기능(출력 순서 조정)일 뿐인데, 예외가 그대로 올라가면
  /// enqueue 자체가 죽어 그 주문의 라벨이 통째로 사라진다. 기능이 기본 OFF 인
  /// 것을 감안하면 "판정 못 하면 종전 순서" 가 유일하게 안전한 실패 방향이다.
  bool _isPriorityOrder(OrderModel order) {
    try {
      final policy = ref.read(fastMenuPolicyProvider);
      // 메뉴가 비어 있으면 판정 자체가 불가능하다. 여기서 상세 캐시를 뒤지지는
      // 않는다 — 그러려면 `orderProvider.notifier` 를 읽어야 하고, 그러면 출력
      // 큐가 주문 프로바이더 생명주기(AudioPlayer·소켓·타이머)에 묶인다.
      // 상세 보강은 **호출부**(order_provider 의 `_withCachedMenus`)가 담당한다.
      final judged = order;
      final isFast = policy.isFastOrder(judged);
      // 기능을 켜 둔 매장에서만, **우선 처리가 안 된 이유**를 남긴다.
      // "모드 2 켰는데 순서가 그대로" 문의는 대부분 여기서 끝난다:
      // 상세가 아직 없거나(자동접수 경로), 지정하지 않은 상품이 섞여 있거나.
      if (!isFast && policy.mode.overtakesQueue && policy.isConfigured) {
        // 캐시 대체 후에도 메뉴가 없으면 진짜로 판정 불가다.
        final reason = judged.menus.isEmpty
            ? '메뉴 미로드 (캐시에도 없음)'
            : '미지정 상품 포함: '
                '${judged.menus.where((m) => !policy.isFast(m)).map((m) => m.shopItemId).join(",")}';
        logToFile(
            tag: LogTag.PLATFORM,
            message: '[LabelQueue] ${order.displayNum} 빠른 메뉴 아님 ($reason)');
      }
      return isFast;
    } catch (e) {
      logToFile(
          tag: LogTag.WARNING,
          message:
              '[LabelQueue] ${order.displayNum} 빠른 메뉴 판정 실패 — 일반 순서로 처리: $e');
      return false;
    }
  }

  // 진행 중/대기 중 LabelOnlyJob 의 orderId 추적.
  final Set<String> _inFlightLabelOnly = <String>{};

  /// 준비 단계에서 '빠른 메뉴' 로 판정된 주문. 인쇄 큐에 우선 투입할 때 읽는다.
  final Set<String> _priorityOrders = <String>{};

  /// 재출력처럼 추월당하면 안 되는 주문.
  final Set<String> _protectedOrders = <String>{};

  /// 사용자 재출력 요청 추가 (라벨 프린터 USB 경쟁 방지를 위해 라벨 큐에 직렬화).
  /// 동일 orderId 의 ReprintJob 이 이미 대기 중이거나 처리 중이면 중복 추가를 무시한다.
  void addReprint(OrderModel order) {
    final id = order.orderId;
    if (_inFlightReprints.contains(id)) {
      // 무음으로 버리지 않는다. 2026-08-10 실매장에서 큐가 복구대기로 멈춰 있는 동안
      // 운영자가 같은 주문의 재출력을 7번 눌렀는데, dedup 이 아무 흔적도 남기지 않아
      // 로그만 봐서는 "클릭이 있었는데 인쇄진입이 없다" 는 사실이 설명되지 않았다.
      logToFile(
          tag: LogTag.PLATFORM,
          message: '[LabelQueue] ${order.displayNum} REPRINT 중복요청 무시 '
              '(이미 대기/진행 중)');
      return;
    }
    _inFlightReprints.add(id);
    // 운영자가 방금 누른 명시 요청 — 프린터 앞에서 결과를 기다리고 있으므로
    // 뒤에 도착한 '빠른 메뉴' 주문에게 밀리면 안 된다. FIFO 자리는 지키되
    // 추월 면역으로 넣는다.
    _protectedOrders.add(id);
    _labelPrepQueue.add(ReprintJob(order), protectedFromPriority: true);
    // 큐 진입을 파일에 남긴다. 이 줄이 없으면 재출력이 어느 시점에 대기열에
    // 들어갔는지를 [UI_ACTION] 클릭 줄로 유추해야 해서, 우선 삽입과의 선후를
    // 로그만으로 확정할 수 없다.
    logToFile(
        tag: LogTag.PLATFORM,
        message: '[LabelQueue] ${order.displayNum} REPRINT enqueue (추월 면역)');
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
            _enqueueLabel(_NewOrderLabelTail(order), order, 'NEW_LABEL tail');
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
      case _TargetLabelJob():
        // 라우팅 오류 — 라벨 큐 전용 job 이 영수증 큐에 들어왔을 때 안전망.
        // sealed switch exhaustiveness 보장용. 정상 흐름에서는 도달 불가.
        logToFile(
            tag: LogTag.WARNING,
            message: '[ReceiptQueue] $num 잘못된 job 라우팅: $job');
    }
  }

  /// 준비 큐 처리: 상세조회 → 타깃 분할 → 타깃별 인쇄 큐로 분배.
  ///
  /// **인쇄를 하지 않는다.** 여기서 종이를 기다리면 준비 큐가 막혀 뒤 주문의
  /// 분배까지 멈추고, 큐를 나눈 의미가 사라진다.
  Future<void> _processLabelPrepItem(OutputJob job) async {
    final outputService = ref.read(outputAppServiceProvider);
    final num = job.order.displayNum;
    final (order, isReprint, kind, release) = switch (job) {
      LabelOnlyJob(order: final o) => (
          o,
          false,
          'LABEL_ONLY',
          () => _inFlightLabelOnly.remove(o.orderId)
        ),
      ReprintJob(order: final o) => (
          o,
          true,
          'REPRINT',
          () => _inFlightReprints.remove(o.orderId)
        ),
      _NewOrderLabelTail(order: final o) => (
          o,
          false,
          'NEW_LABEL',
          () => _inFlightLabelTail.remove(o.orderId)
        ),
      // 라우팅 오류 — 영수증 큐 전용 job 이 라벨 준비 큐에 들어왔을 때 안전망.
      _ => (job.order, false, '', null),
    };
    if (release == null) {
      logToFile(
          tag: LogTag.WARNING, message: '[LabelPrep] $num 잘못된 job 라우팅: $job');
      return;
    }

    bool dispatched = false;
    try {
      final prepared = await outputService.prepareOrderForLabels(order);
      if (prepared == null) return; // 생략 사유·복구 등록은 내부에서 처리됨

      final targets =
          await outputService.targetsForOrder(prepared, isReprint: isReprint);
      if (targets.isEmpty) {
        // 이 단말이 인쇄할 라벨이 없다. 스킵 로그는 printOrderLabels 가 남기므로
        // 여기서 중복해서 남기지 않는다.
        return;
      }

      _dispatchTargets(prepared, targets, isReprint, kind, release);
      dispatched = true;
    } finally {
      // 분배에 실패했으면(예외/생략) 여기서 중복 방지를 풀어야 한다. 분배됐으면
      // 마지막 타깃 작업이 끝날 때 풀린다 — 인쇄 중에 같은 주문이 다시 들어오면
      // 그게 곧 중복 인쇄다.
      if (!dispatched) {
        release();
        _priorityOrders.remove(order.orderId);
        _protectedOrders.remove(order.orderId);
      }
    }
  }

  /// 타깃별 인쇄 큐로 분배한다. 타깃이 하나면 큐도 하나 = 종전 동작.
  void _dispatchTargets(
    OrderModel order,
    Set<LabelTarget> targets,
    bool isReprint,
    String kind,
    void Function() release,
  ) {
    final id = order.orderId;
    final isPriority = _priorityOrders.remove(id);
    final isProtected = _protectedOrders.remove(id);
    _pendingTargetJobs[id] = targets.length;

    // 타깃 id 순으로 넣어 로그·출력 순서를 재현 가능하게 한다. Set 순회 순서에
    // 기대면 같은 주문이 실행마다 다른 순서로 분배돼 사후 분석이 어려워진다.
    final ordered = targets.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final target in ordered) {
      final job = _TargetLabelJob(
        order,
        target: target,
        isReprint: isReprint,
        kind: kind,
        onDone: () {
          final left = (_pendingTargetJobs[id] ?? 1) - 1;
          if (left <= 0) {
            _pendingTargetJobs.remove(id);
            release();
          } else {
            _pendingTargetJobs[id] = left;
          }
        },
      );
      final queue = _labelQueueFor(target);
      if (isPriority) {
        queue.addPriority(job);
      } else {
        queue.add(job, protectedFromPriority: isProtected);
      }
    }
    if (ordered.length > 1) {
      // 병렬 분배는 파일에 남긴다. 한 주문의 라벨이 두 기계에서 동시에 나오는
      // 것은 정상이지만, 로그에 흔적이 없으면 "왜 순서가 섞였나" 를 설명할 수 없다.
      logToFile(
          tag: LogTag.PLATFORM,
          message: '[LabelPrep] ${order.displayNum} $kind 타깃 ${ordered.length}개'
              ' 병렬 분배 (${ordered.map((t) => t.id).join(",")})');
    }
  }

  /// 타깃 인쇄 큐 처리: 그 타깃 몫의 라벨만 인쇄한다.
  Future<void> _processLabelItem(OutputJob job) async {
    if (job is! _TargetLabelJob) {
      logToFile(
          tag: LogTag.WARNING,
          message: '[LabelQueue] ${job.order.displayNum} 잘못된 job 라우팅: $job');
      return;
    }
    final outputService = ref.read(outputAppServiceProvider);
    final num = job.order.displayNum;
    final tag = '[LabelQueue:${job.target.id}] $num ${job.kind}';
    _life('$tag 시작');
    try {
      await outputService.printOrderLabels(
        job.order,
        isReprint: job.isReprint,
        onlyTarget: job.target,
      );
    } finally {
      job.onDone();
    }
    _life('$tag 완료');
  }

  /// 큐 정리 (로그아웃 등)
  void clear() {
    _receiptQueue.clear();
    _labelPrepQueue.clear();
    for (final q in _labelQueues.values) {
      q.clear();
    }
    _inFlightNewOrders.clear();
    _inFlightLabelOnly.clear();
    _inFlightReprints.clear();
    _inFlightLabelTail.clear();
    _pendingTargetJobs.clear();
    _priorityOrders.clear();
    _protectedOrders.clear();
    _life('[OutputQueue] 큐 정리 완료');
  }
}

/// 전역 프로바이더 정의
final outputQueueServiceProvider = Provider<OutputQueueService>((ref) {
  return OutputQueueService(ref);
});
