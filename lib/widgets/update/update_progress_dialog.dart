import 'package:flutter/material.dart';

import '../../constants/app_styles.dart';
import '../../models/update_info.dart';
import '../../services/platform_service.dart';
import '../../services/windows_update_service.dart';

enum _UiStage { checking, prompt, downloading, installing, error, noUpdate }

/// 앱 시작 시점 Windows 업데이트 진행 다이얼로그.
///
/// pop 시 반환값 없음 — 호출부는 Completer로 완료 시점만 받고 본 앱을 이어 실행한다.
/// install() 성공 시 앱이 exit(0) 되어 이 다이얼로그는 반환하지 않는다.
class UpdateProgressDialog extends StatefulWidget {
  const UpdateProgressDialog({super.key});

  @override
  State<UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<UpdateProgressDialog> {
  final WindowsUpdateService _service = WindowsUpdateService();

  _UiStage _stage = _UiStage.checking;
  double _progress = 0.0;
  int _latestVersion = 0;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final info = await _service.checkForUpdate();
    if (!mounted) return;

    if (info == null || !info.hasUpdate) {
      Navigator.of(context).pop();
      return;
    }

    // 직전에 업데이트를 적용했는데도 current < latest 라면 빌드 파이프라인
    // (version_windows.txt vs pubspec.yaml vs 서버 JSON) 어딘가가 어긋난 상태.
    // 재발 진단을 위해 즉시 로그로 남긴다.
    logToFile(
      tag: LogTag.SYSTEM,
      message:
          '업데이트 다이얼로그 prompt: current=${info.currentVersion}, '
          'latest=${info.latestVersion} → 사용자에게 노출',
    );

    setState(() {
      _stage = _UiStage.prompt;
      _latestVersion = info.latestVersion;
    });
  }

  Future<void> _startDownload() async {
    setState(() {
      _stage = _UiStage.downloading;
      _progress = 0.0;
    });

    await _service.downloadUpdate(
      onStatus: (status, progress) {
        if (!mounted) return;
        if (status == UpdateStatus.downloading) {
          setState(() => _progress = progress);
        } else if (status == UpdateStatus.readyToInstall) {
          setState(() {
            _progress = 1.0;
            _stage = _UiStage.installing;
          });
          _install();
        }
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _stage = _UiStage.error;
          _errorMsg = msg;
        });
      },
    );
  }

  Future<void> _install() async {
    await _service.install(
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _stage = _UiStage.error;
          _errorMsg = msg;
        });
      },
    );
  }

  void _dismiss() {
    _service.cancelUpdate();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          _titleForStage(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 25,
          ),
        ),
        titlePadding:
            const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
        contentPadding: const EdgeInsets.fromLTRB(30.0, 20.0, 30.0, 0),
        content: SizedBox(
          width: 400,
          child: _buildContent(),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 30.0, vertical: 30.0),
        actions: _buildActions(),
      ),
    );
  }

  String _titleForStage() {
    switch (_stage) {
      case _UiStage.checking:
        return '업데이트 확인 중';
      case _UiStage.prompt:
        return '새 버전이 있습니다';
      case _UiStage.downloading:
        return '업데이트 다운로드 중';
      case _UiStage.installing:
        return '업데이트 설치 중';
      case _UiStage.error:
        return '업데이트 오류';
      case _UiStage.noUpdate:
        return '';
    }
  }

  Widget _buildContent() {
    switch (_stage) {
      case _UiStage.checking:
        return SizedBox(
          height: 80,
          child: Center(
            child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppStyles.kMainColor),
            ),
          ),
        );
      case _UiStage.prompt:
        return SizedBox(
          height: 80,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '새 버전(빌드 $_latestVersion)이 출시되었습니다.\n지금 업데이트하시겠습니까?',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        );
      case _UiStage.downloading:
        final percent = (_progress * 100).round();
        return SizedBox(
          height: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppStyles.kMainColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppStyles.kMainColor,
                ),
              ),
            ],
          ),
        );
      case _UiStage.installing:
        return SizedBox(
          height: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 1.0,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppStyles.kMainColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '앱을 재시작합니다...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
        );
      case _UiStage.error:
        return SizedBox(
          width: 400,
          height: 100,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '업데이트 중 오류가 발생했습니다.\n$_errorMsg',
              style: const TextStyle(fontSize: 18),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      case _UiStage.noUpdate:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildActions() {
    switch (_stage) {
      case _UiStage.prompt:
        return [
          _cancelButton(label: '나중에', onPressed: _dismiss),
          _primaryButton(label: '업데이트', onPressed: _startDownload),
        ];
      case _UiStage.downloading:
        return [
          _cancelButton(label: '취소', onPressed: _dismiss),
        ];
      case _UiStage.error:
        return [
          _primaryButton(label: '확인', onPressed: _dismiss),
        ];
      case _UiStage.checking:
      case _UiStage.installing:
      case _UiStage.noUpdate:
        return const [];
    }
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(100, 45),
        backgroundColor: AppStyles.kMainColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _cancelButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(100, 45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade400),
        ),
        backgroundColor: Colors.white,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
