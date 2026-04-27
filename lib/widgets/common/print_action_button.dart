import 'dart:async';

import 'package:flutter/material.dart';
import 'action_button_shell.dart';

/// 출력류(영수증/라벨 재출력 등) 전용 다이얼로그 버튼.
///
/// - 클릭 직후 [debounce](기본 1초) 동안 자기 자신만 비활성 + 진행 인디케이터 표시.
/// - 같은 다이얼로그의 다른 버튼에는 영향이 없다.
/// - 실제 출력은 [onPressed] 가 OutputQueueService 큐에 enqueue 만 하고
///   즉시 반환하는 동기 트리거 형태를 가정한다. 큐가 USB 자원 경쟁을 직렬화한다.
class PrintActionButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final Duration debounce;
  final bool isMainAction;
  final ButtonStyle? styleOverride;

  const PrintActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.debounce = const Duration(seconds: 1),
    this.isMainAction = false,
    this.styleOverride,
  });

  @override
  State<PrintActionButton> createState() => _PrintActionButtonState();
}

class _PrintActionButtonState extends State<PrintActionButton> {
  bool _busy = false;
  Timer? _timer;

  void _trigger() {
    if (_busy) return;
    setState(() => _busy = true);
    widget.onPressed();
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (mounted) setState(() => _busy = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ActionButtonShell(
      text: widget.text,
      busy: _busy,
      isMainAction: widget.isMainAction,
      styleOverride: widget.styleOverride,
      onPressed: _busy ? null : _trigger,
    );
  }
}
