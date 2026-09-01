import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/enums/order_cancel_reason.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_core/appfit_core.dart';

/// 공통 다이얼로그 위젯
/// 상태 변경 및 확인용 다이얼로그
class CommonDialog {
  /// 동일 내용의 정보/에러 다이얼로그가 이미 떠 있으면 중복 표시를 막기 위한 활성 키 집합.
  /// 다이얼로그가 닫히면(=showDialog future 완료) finally 에서 키를 해제한다.
  static final Set<String> _activeDialogKeys = <String>{};

  /// 확인/취소 버튼이 있는 기본 다이얼로그.
  ///
  /// [onConfirm] 이 주어지면 confirm 버튼이 비동기 액션을 직접 실행한다.
  /// 실행 동안 confirm 버튼에 진행 인디케이터가 표시되고 cancel 버튼은 비활성화되며,
  /// 액션 완료 시 다이얼로그가 자동으로 닫히면서 결과(true)가 반환된다.
  /// 액션이 예외를 던지면 다이얼로그는 닫히지 않고 confirm 버튼이 다시 활성화된다.
  ///
  /// [onConfirm] 이 null 이면 종전 동작과 동일 — confirm 클릭 시 즉시 true 반환.
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    String confirmText = '',
    String cancelText = '',
    Future<void> Function()? onConfirm,
  }) async {
    final resolvedConfirm =
        confirmText.isEmpty ? t.common.confirm : confirmText;
    final resolvedCancel = cancelText.isEmpty ? t.common.cancel : cancelText;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _ConfirmDialog(
          title: title,
          content: content,
          confirmText: resolvedConfirm,
          cancelText: resolvedCancel,
          onConfirm: onConfirm,
        );
      },
    );
  }

  /// 취소 사유 선택 다이얼로그.
  /// 선택된 사유(`OrderCancelReason`)를 반환, 바깥 탭/닫기 시 null 반환.
  static Future<OrderCancelReason?> showCancelReasonDialog({
    required BuildContext context,
    required String displayNum,
  }) async {
    return await showDialog<OrderCancelReason>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.bLg,
          ),
          title: _dialogTitleWithClose(
            title: Text(
              t.order_detail.dialog_cancel_reason_title,
              style: AppTextStyles.title,
            ),
            onClose: () => Navigator.of(context).pop(),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            AppSpacing.s24,
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s8,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.s24,
            AppSpacing.s16,
            AppSpacing.s24,
            AppSpacing.s8,
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.order_detail.dialog_cancel_reason_content(n: displayNum),
                  style: AppTextStyles.body.copyWith(fontSize: 17),
                ),
                const SizedBox(height: AppSpacing.s16),
                ..._selectableCancelReasons.map(
                  (reason) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: AppStyles.outlinedButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s20,
                            vertical: AppSpacing.s12,
                          ),
                          minimumSize: const Size(double.infinity, 45),
                        ),
                        onPressed: () => Navigator.of(context).pop(reason),
                        child: Text(
                          _cancelReasonLabel(reason),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 상품 카드(= 동일 상품명 그룹)의 상태 변경 다이얼로그.
  /// 선택된 상태(`ProductStatus`)를 반환, 닫힘/취소 시 null 반환.
  ///
  /// **버튼 구성이 멤버 수로 갈린다.**
  ///  - 멤버 1개: 기존과 동일하게 현재 상태의 반대편 토글 버튼 1개.
  ///  - 멤버 2개 이상: '전체 판매'/'전체 품절' 2개를 **항상** 낸다. 일부만 품절인
  ///    그룹은 표시상 '판매중'이라(all-or-nothing 정책), 반대편 버튼만 내면 남은
  ///    품절 멤버를 되돌릴 방법이 사라진다.
  ///
  /// 가격 목록은 읽기 전용이다 — 가격별 개별 토글은 만들지 않는다.
  /// [priceLabels] 는 **이미 통화 포맷이 적용된** 문자열이다. 이 클래스는 static 이라
  /// `currencySymbolProvider` 를 읽을 수 없어 위젯 계층이 포맷해서 넘긴다.
  static Future<ProductStatus?> showBulkStatusChangeDialog({
    required BuildContext context,
    required String itemName,
    required ProductStatus currentStatus,
    required int memberCount,
    List<String> priceLabels = const [],
    List<String> categoryNames = const [],
  }) async {
    final bool isBulk = memberCount > 1;

    return await showDialog<ProductStatus>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: _dialogTitleWithClose(
            title: Text(
              isBulk
                  ? t.dialog.status_change.bulk_title
                  : t.dialog.status_change.title,
              style: AppTextStyles.title,
            ),
            onClose: () => Navigator.of(context).pop(null),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            AppSpacing.s24,
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s8,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.s24,
            AppSpacing.s16,
            AppSpacing.s24,
            0,
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBulk
                      ? t.dialog.status_change
                          .bulk_content(item: itemName, n: memberCount)
                      : t.dialog.status_change.content(item: itemName),
                  style: AppTextStyles.body.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(t.dialog.status_change.current,
                        style:
                            const TextStyle(fontSize: 14, color: Colors.grey)),
                    Text(
                      _statusKoreanLabel(currentStatus),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                // 묶인 카드는 가격을 감추고 '동일상품 N개'만 보여주므로, 개별
                // 가격을 확인할 수 있는 곳이 여기뿐이다 — 가격이 1종이어도 낸다.
                if (isBulk && priceLabels.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    t.dialog.status_change.bulk_prices(n: priceLabels.length),
                    style:
                        AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  // 가격 종류가 많아도 다이얼로그가 화면을 넘지 않게 한다.
                  // Android 가로는 세로가 짧아 고정 px 상한만으로는 부족하다.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (MediaQuery.sizeOf(context).height * 0.30)
                          .clamp(72.0, 180.0),
                    ),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: AppSpacing.s8,
                        runSpacing: AppSpacing.s8,
                        children: [
                          for (final label in priceLabels) _priceChip(label),
                        ],
                      ),
                    ),
                  ),
                ],
                // 카테고리 A 에서 눌렀는데 B 의 카드도 함께 바뀌는 것은 예측하기
                // 어려운 부작용이다 — 이 한 줄이 유일한 설명 지점이다.
                if (categoryNames.length > 1) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    t.dialog.status_change
                        .bulk_categories(names: categoryNames.join(', ')),
                    style:
                        AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
                  ),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s24,
            vertical: AppSpacing.s24,
          ),
          actions: <Widget>[
            if (!isBulk)
              // 단일 상품: 현재 상태의 반대편 버튼 1개 (기존 동작 유지)
              _statusActionButton(
                context: context,
                target: currentStatus == ProductStatus.sale
                    ? ProductStatus.soldOut
                    : ProductStatus.sale,
                label: currentStatus == ProductStatus.sale
                    ? t.dialog.status_change.sold_out
                    : t.dialog.status_change.sale,
                destructive: currentStatus == ProductStatus.sale,
              )
            else ...[
              _statusActionButton(
                context: context,
                target: ProductStatus.sale,
                label: t.dialog.status_change.bulk_sale,
                destructive: false,
              ),
              _statusActionButton(
                context: context,
                target: ProductStatus.soldOut,
                label: t.dialog.status_change.bulk_sold_out,
                destructive: true,
              ),
            ],
          ],
        );
      },
    );
  }

  /// 종료 확인 다이얼로그
  static Future<bool> showExitDialog({
    required BuildContext context,
    String? title,
    String? content,
    String? cancelText,
    String? confirmText,
  }) async {
    // showConfirmDialog 결과를 await 하고 null이면 false 반환
    final result = await showConfirmDialog(
      context: context,
      title: title ?? t.dialog.exit.title,
      content: content ?? t.dialog.exit.content,
      confirmText: confirmText ?? t.dialog.exit.confirm,
      cancelText: cancelText ?? t.common.cancel,
    );
    return result ?? false;
  }

  /// 정보 표시용 다이얼로그 (확인 버튼만 있음)
  static Future<void> showInfoDialog({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmText,
    String? dedupeKey,
  }) async {
    confirmText ??= t.common.confirm;
    // 같은 내용의 정보 다이얼로그가 이미 떠 있으면 중복 표시를 막는다.
    final key = dedupeKey ?? 'info\u0000$title\u0000$content';
    if (_activeDialogKeys.contains(key)) return;
    _activeDialogKeys.add(key);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: _dialogTitleWithClose(
              title: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppStyles.kMainColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 22)),
                  ),
                ],
              ),
              onClose: () => Navigator.of(context).pop(),
            ),
            titlePadding: const EdgeInsets.fromLTRB(
              AppSpacing.s24,
              AppSpacing.s16,
              AppSpacing.s16,
              0,
            ),
            contentPadding: const EdgeInsets.fromLTRB(
              AppSpacing.s24,
              AppSpacing.s16,
              AppSpacing.s24,
              AppSpacing.s8,
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 400),
              child: Text(
                content,
                style: const TextStyle(fontSize: 18, color: Colors.black87),
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s24,
              vertical: AppSpacing.s24,
            ),
            actions: <Widget>[
              ElevatedButton(
                style: AppStyles.primaryButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s24,
                    vertical: AppSpacing.s12,
                  ),
                  minimumSize: const Size(100, 45),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  confirmText!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      _activeDialogKeys.remove(key);
    }
  }

  /// 에러 전용 다이얼로그 (빨간색 강조)
  static Future<void> showErrorDialog({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmText,
    String? dedupeKey,
  }) async {
    confirmText ??= t.common.confirm;
    // 같은 내용의 에러 다이얼로그가 이미 떠 있으면 중복 표시를 막는다.
    final key = dedupeKey ?? 'error $title $content';
    if (_activeDialogKeys.contains(key)) return;
    _activeDialogKeys.add(key);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: _dialogTitleWithClose(
              title: Row(
                children: [
                  Icon(Icons.error_outline, color: AppStyles.kRed, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: AppStyles.kRed)),
                  ),
                ],
              ),
              onClose: () => Navigator.of(context).pop(),
            ),
            titlePadding: const EdgeInsets.fromLTRB(
              AppSpacing.s24,
              AppSpacing.s16,
              AppSpacing.s16,
              0,
            ),
            contentPadding: const EdgeInsets.fromLTRB(
              AppSpacing.s24,
              AppSpacing.s16,
              AppSpacing.s24,
              AppSpacing.s8,
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 400),
              child: Text(
                content,
                style: const TextStyle(fontSize: 18, color: Colors.black87),
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s24,
              vertical: AppSpacing.s24,
            ),
            actions: <Widget>[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppStyles.kRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s24,
                    vertical: AppSpacing.s12,
                  ),
                  minimumSize: const Size(100, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.bSm,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  confirmText!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      _activeDialogKeys.remove(key);
    }
  }

  /// 업데이트 진행 상황 다이얼로그
  static Future<bool?> showUpdateProgressDialog({
    required BuildContext context,
    required dynamic updateInfo,
    required Function(
            String downloadUrl,
            String destinationFilename,
            Function(dynamic event) onEvent,
            VoidCallback onDone,
            Function(String error) onError)
        onStartUpdate,
    VoidCallback? onCancel,
  }) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _UpdateProgressDialog(
          updateInfo: updateInfo,
          onStartUpdate: onStartUpdate,
          onCancel: onCancel,
        );
      },
    );
  }
}

/// AlertDialog 의 `title` 에 넣을 "타이틀 + 우측 상단 X" Row.
/// 주문상세 팝업과 동일한 닫기 경험을 공용 다이얼로그에 통일하기 위한 헬퍼.
/// [onClose] 가 null 이면 IconButton 이 자동 비활성화된다(진행 중 닫기 차단 등).
Widget _dialogTitleWithClose({
  required Widget title,
  required VoidCallback? onClose,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: title),
      // 탭 영역 40x40 확보(키오스크 터치) + 아이콘은 우측 모서리에 가깝게.
      IconButton(
        icon: const Icon(Icons.close, size: 24),
        splashRadius: AppSpacing.s20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: onClose,
      ),
    ],
  );
}

/// 취소 사유 다이얼로그에 노출할 항목(표시 순서 고정).
const List<OrderCancelReason> _selectableCancelReasons = [
  OrderCancelReason.SOLD_OUT,
  OrderCancelReason.ORDER_SURGE,
  OrderCancelReason.SHOP_CLOSED,
  OrderCancelReason.SHOP_REQUEST,
  OrderCancelReason.CUSTOMER_REQUEST,
];

String _cancelReasonLabel(OrderCancelReason reason) {
  switch (reason) {
    case OrderCancelReason.SHOP_REQUEST:
      return t.order_detail.cancel_reason_shop_request;
    case OrderCancelReason.SHOP_CLOSED:
      return t.order_detail.cancel_reason_shop_closed;
    case OrderCancelReason.CUSTOMER_REQUEST:
      return t.order_detail.cancel_reason_customer_request;
    case OrderCancelReason.SOLD_OUT:
      return t.order_detail.cancel_reason_sold_out;
    case OrderCancelReason.INGREDIENT_SHORTAGE:
      return t.order_detail.cancel_reason_ingredient_shortage;
    case OrderCancelReason.SYSTEM_ERROR:
      return t.order_detail.cancel_reason_system_error;
    case OrderCancelReason.ORDER_SURGE:
      return t.order_detail.cancel_reason_order_surge;
  }
}

/// 상태 변경 다이얼로그의 액션 버튼.
/// [destructive] 는 품절 계열(되돌리려면 다시 조작해야 하는 쪽)을 붉게 낸다.
Widget _statusActionButton({
  required BuildContext context,
  required ProductStatus target,
  required String label,
  required bool destructive,
}) {
  const padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.s20,
    vertical: AppSpacing.s12,
  );
  // 일괄 버튼은 라벨이 길어 최소 폭을 넉넉히 준다(Android 가로 + Windows 터치).
  const minimumSize = Size(120, 45);

  return ElevatedButton(
    style: destructive
        ? ElevatedButton.styleFrom(
            backgroundColor: AppStyles.kRed,
            foregroundColor: Colors.white,
            padding: padding,
            minimumSize: minimumSize,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.bSm),
          )
        : AppStyles.primaryButton(
            padding: padding,
            minimumSize: minimumSize,
          ),
    onPressed: () => Navigator.of(context).pop(target),
    child: Text(
      label,
      style: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}

/// 읽기 전용 가격 표시용 pill. 탭 대상이 아니라 터치 타겟 규격을 적용하지 않는다.
Widget _priceChip(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s12,
      vertical: AppSpacing.s4,
    ),
    decoration: BoxDecoration(
      color: AppStyles.gray1,
      borderRadius: AppRadius.bSm,
      border: Border.all(color: AppStyles.gray3),
    ),
    child: Text(
      label,
      style: AppTextStyles.body.copyWith(color: AppStyles.gray9),
    ),
  );
}

String _statusKoreanLabel(ProductStatus status) {
  switch (status) {
    case ProductStatus.sale:
      return t.dialog.status_change.sale;
    case ProductStatus.soldOut:
      return t.dialog.status_change.sold_out;
    case ProductStatus.hidden:
      return t.dialog.status_change.hidden;
  }
}

// 제거: 상태 버튼 컬러 헬퍼는 현재 사용되지 않음

/// 업데이트 진행 상황 다이얼로그 위젯
class _UpdateProgressDialog extends StatefulWidget {
  final dynamic updateInfo;
  final Function(
      String downloadUrl,
      String destinationFilename,
      Function(dynamic event) onEvent,
      VoidCallback onDone,
      Function(String error) onError) onStartUpdate;

  /// 다운로드 진행 중 취소(X/취소 버튼) 또는 다이얼로그 dispose 시 호출.
  /// OTA 다운로드 태스크·폴링 타이머를 실제로 중단시키는 책임을 호출부에 위임한다.
  final VoidCallback? onCancel;

  const _UpdateProgressDialog({
    required this.updateInfo,
    required this.onStartUpdate,
    this.onCancel,
  });

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  bool _downloadComplete = false;
  bool _downloadError = false;
  String _errorMessage = '';

  /// 취소가 이미 처리됐는지(버튼 ↔ dispose 이중 호출 방지).
  bool _canceled = false;

  /// 다운로드 진행 중 X/취소 버튼 처리: OTA 태스크·폴링을 중단시키고 다이얼로그를 닫는다.
  void _cancelDownload() {
    if (_canceled) return;
    _canceled = true;
    widget.onCancel?.call();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    // 다른 경로(라우트 pop 등)로 다이얼로그가 사라져도 진행 중 다운로드가 남지 않도록 정리.
    if (_isDownloading && !_canceled) {
      _canceled = true;
      widget.onCancel?.call();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _dialogTitleWithClose(
        title: Text(t.dialog.update.title, style: AppTextStyles.title),
        onClose: _isDownloading
            ? _cancelDownload
            : () => Navigator.of(context).pop(false),
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s24,
        0,
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isDownloading && !_downloadComplete && !_downloadError) ...[
              Text(
                t.dialog.update.new_update,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              Text(
                t.dialog.update.ask_download,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ] else if (_isDownloading) ...[
              Text(t.dialog.update.downloading,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _downloadProgress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(AppStyles.kMainColor),
              ),
              const SizedBox(height: 8),
              Text('${(_downloadProgress * 100).round()}%',
                  style: const TextStyle(fontSize: 16)),
              if (_downloadStatus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _downloadStatus,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ] else if (_downloadComplete) ...[
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                t.dialog.update.download_complete,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                t.dialog.update.installing,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ] else if (_downloadError) ...[
              const Icon(
                Icons.error,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                t.dialog.update.fail,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s24,
        vertical: AppSpacing.s24,
      ),
      actions: [
        if (!_isDownloading && !_downloadComplete && !_downloadError) ...[
          ElevatedButton(
            style: AppStyles.outlinedButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 45),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              t.common.later,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: AppStyles.primaryButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 45),
            ),
            onPressed: _startDownload,
            child: Text(
              t.dialog.update.download,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ] else if (_downloadComplete) ...[
          ElevatedButton(
            style: AppStyles.primaryButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 45),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              t.common.confirm,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ] else if (_downloadError) ...[
          ElevatedButton(
            style: AppStyles.outlinedButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 45),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              t.common.cancel,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: AppStyles.primaryButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 45),
            ),
            onPressed: _startDownload,
            child: Text(
              t.common.retry,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ] else ...[
          ElevatedButton(
            style: AppStyles.outlinedButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 45),
            ),
            onPressed: _cancelDownload,
            child: Text(
              t.common.cancel,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  /// 다운로드 시작
  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = '연결 중...';
      _downloadComplete = false;
      _downloadError = false;
      _errorMessage = '';
    });

    try {
      // 파일명 추출
      final uri = Uri.parse(widget.updateInfo.downloadUrl);
      final apkFilename = uri.pathSegments.last;

      widget.onStartUpdate(
        widget.updateInfo.downloadUrl,
        apkFilename,
        (dynamic event) {
          if (!mounted) return;
          if (event is OtaDownloadEvent) {
            setState(() {
              if (event.status == OtaStatusType.downloading) {
                _downloadProgress = event.progress;
                _downloadStatus = '다운로드 중...';
              } else if (event.status == OtaStatusType.readyToInstall ||
                  event.status == OtaStatusType.installing) {
                _downloadProgress = 1.0;
                _downloadStatus = '설치 중...';
              }
            });
          }
        },
        () {
          if (!mounted) return;
          setState(() {
            _downloadComplete = true;
            _isDownloading = false;
            _downloadProgress = 1.0;
            _downloadStatus = '완료!';
          });
        },
        (error) {
          if (!mounted) return;
          setState(() {
            _downloadError = true;
            _errorMessage = error;
            _isDownloading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _downloadError = true;
        _errorMessage = e.toString();
        _isDownloading = false;
      });
    }
  }
}

/// confirm/cancel 버튼이 있는 다이얼로그 본체.
/// onConfirm 이 주어지면 confirm 버튼이 자체적으로 비동기 액션을 실행하고,
/// 실행 동안 자기 자신만 비활성화되며 진행 인디케이터를 표시한다.
class _ConfirmDialog extends StatefulWidget {
  final String title;
  final String content;
  final String confirmText;
  final String cancelText;
  final Future<void> Function()? onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.content,
    required this.confirmText,
    required this.cancelText,
    required this.onConfirm,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _busy = false;

  Future<void> _handleConfirm() async {
    final action = widget.onConfirm;
    if (action == null) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _dialogTitleWithClose(
        title: Text(widget.title, style: AppTextStyles.title),
        onClose: _busy ? null : () => Navigator.of(context).pop(false),
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s24,
        0,
      ),
      content: SizedBox(
        width: 400,
        height: 80,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.content,
            style: AppTextStyles.body.copyWith(fontSize: 17),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s24,
        vertical: AppSpacing.s24,
      ),
      actions: <Widget>[
        if (widget.cancelText.isNotEmpty)
          ElevatedButton(
            style: AppStyles.outlinedButton(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s20,
                vertical: AppSpacing.s12,
              ),
              minimumSize: const Size(100, 45),
            ),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(widget.cancelText,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ElevatedButton(
          style: AppStyles.primaryButton(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20,
              vertical: AppSpacing.s12,
            ),
            minimumSize: const Size(100, 45),
          ),
          onPressed: _busy ? null : _handleConfirm,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: _busy ? 0.0 : 1.0,
                child: Text(widget.confirmText,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              if (_busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
