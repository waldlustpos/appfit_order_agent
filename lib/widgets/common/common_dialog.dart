import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';
import '../../models/product_model.dart';
import '../../i18n/strings.g.dart';
import '../../services/ota_update_service.dart';

/// 공통 다이얼로그 위젯
/// 상태 변경 및 확인용 다이얼로그
class CommonDialog {
  /// 확인/취소 버튼이 있는 기본 다이얼로그
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    String confirmText = '',
    String cancelText = '',
  }) async {
    confirmText = confirmText.isEmpty ? t.common.confirm : confirmText;
    cancelText = cancelText.isEmpty ? t.common.cancel : cancelText;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppStyles.gray1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 25)),
          titlePadding:
              const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
          contentPadding: const EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 0),
          content: SizedBox(
            width: 400,
            height: 80,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                content,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
          actions: <Widget>[
            if (cancelText.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  minimumSize: const Size(100, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  backgroundColor: Colors.white,
                ),
                child: Text(
                  cancelText,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
            TextButton(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                minimumSize: const Size(100, 45),
                backgroundColor: AppStyles.kMainColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                confirmText,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  /// 상태 변경 다이얼로그 (판매/품절/미노출 선택)
  /// 선택된 상태(`ProductStatus`)를 반환, 닫힘/취소 시 null 반환
  static Future<ProductStatus?> showStatusChangeDialog({
    required BuildContext context,
    required String itemName,
    required ProductStatus currentStatus,
    String? title,
    List<ProductStatus>? selectableStatuses,
  }) async {
    final List<ProductStatus> options = selectableStatuses ??
        const [ProductStatus.sale, ProductStatus.soldOut, ProductStatus.hidden];

    return await showDialog<ProductStatus>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppStyles.gray1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title ?? t.dialog.status_change.title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 25)),
          titlePadding:
              const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
          contentPadding: const EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 0),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.dialog.status_change.content(item: itemName),
                  style: const TextStyle(fontSize: 18),
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
              ],
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
          actions: <Widget>[
            // 닫기
            TextButton(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                minimumSize: const Size(100, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade400),
                ),
                backgroundColor: Colors.white,
              ),
              child: Text(
                t.common.close,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.of(context).pop(null),
            ),

            // 품절/판매 토글
            Builder(
              builder: (context) {
                final bool showSale = currentStatus != ProductStatus.sale;
                final String label = showSale
                    ? t.dialog.status_change.sale
                    : t.dialog.status_change.sold_out;
                final ProductStatus target =
                    showSale ? ProductStatus.sale : ProductStatus.soldOut;
                final Color bg =
                    showSale ? AppStyles.kMainColor : Colors.redAccent;
                return TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    minimumSize: const Size(100, 45),
                    backgroundColor: bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => Navigator.of(context).pop(target),
                );
              },
            ),

            // 미노출
            if (options.contains(ProductStatus.hidden))
              TextButton(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  minimumSize: const Size(100, 45),
                  backgroundColor: Colors.grey[700],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  t.dialog.status_change.hidden_delete,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(ProductStatus.hidden),
              ),
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
  }) async {
    confirmText ??= t.common.confirm;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppStyles.gray1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: AppStyles.kMainColor, size: 28),
              const SizedBox(width: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 22)),
            ],
          ),
          titlePadding: const EdgeInsets.fromLTRB(30.0, 30.0, 30.0, 0),
          contentPadding: const EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 10.0),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 400),
            child: Text(
              content,
              style: const TextStyle(fontSize: 18, color: Colors.black87),
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 30.0, vertical: 25.0),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                backgroundColor: AppStyles.kMainColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                confirmText!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// 에러 전용 다이얼로그 (빨간색 강조)
  static Future<void> showErrorDialog({
    required BuildContext context,
    required String title,
    required String content,
    String? confirmText,
  }) async {
    confirmText ??= t.common.confirm;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppStyles.gray1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 28),
              const SizedBox(width: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.redAccent)),
            ],
          ),
          titlePadding: const EdgeInsets.fromLTRB(30.0, 30.0, 30.0, 0),
          contentPadding: const EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 10.0),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 400),
            child: Text(
              content,
              style: const TextStyle(fontSize: 18, color: Colors.black87),
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 30.0, vertical: 25.0),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                confirmText!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
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
  }) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _UpdateProgressDialog(
          updateInfo: updateInfo,
          onStartUpdate: onStartUpdate,
        );
      },
    );
  }
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

  const _UpdateProgressDialog({
    required this.updateInfo,
    required this.onStartUpdate,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppStyles.gray1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(t.dialog.update.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 25)),
      titlePadding:
          const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
      contentPadding: const EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 0),
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
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppStyles.kMainColor),
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
      actionsPadding:
          const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
      actions: [
        if (!_isDownloading && !_downloadComplete && !_downloadError) ...[
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              minimumSize: const Size(100, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              backgroundColor: Colors.white,
            ),
            child: Text(
              t.common.later,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              minimumSize: const Size(100, 45),
              backgroundColor: AppStyles.kMainColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              t.dialog.update.download,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            onPressed: _startDownload,
          ),
        ] else if (_downloadComplete) ...[
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              minimumSize: const Size(100, 45),
              backgroundColor: AppStyles.kMainColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              t.common.confirm,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ] else if (_downloadError) ...[
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              minimumSize: const Size(100, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              backgroundColor: Colors.white,
            ),
            child: Text(
              t.common.cancel,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              minimumSize: const Size(100, 45),
              backgroundColor: AppStyles.kMainColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              t.common.retry,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            onPressed: _startDownload,
          ),
        ] else ...[
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              minimumSize: const Size(100, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade400),
              ),
              backgroundColor: Colors.white,
            ),
            child: Text(
              t.common.cancel,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            onPressed:
                _isDownloading ? null : () => Navigator.of(context).pop(false),
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
          setState(() {
            _downloadComplete = true;
            _isDownloading = false;
            _downloadProgress = 1.0;
            _downloadStatus = '완료!';
          });
        },
        (error) {
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
