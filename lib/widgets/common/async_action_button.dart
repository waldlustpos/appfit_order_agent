import 'package:flutter/material.dart';
import 'action_button_shell.dart';

/// API류(주문 접수/완료/취소, 상태 변경 등) 전용 다이얼로그 버튼.
///
/// - [onPressed] 가 반환하는 Future 가 끝날 때까지 자기 자신만 비활성 +
///   진행 인디케이터 표시.
/// - 같은 다이얼로그의 다른 버튼(닫기, 다른 액션 등)에는 영향이 없다.
/// - 예외는 호출자가 책임지며, busy 상태는 try/finally + mounted 가드로
///   항상 안전하게 복원된다.
class AsyncActionButton extends StatefulWidget {
  final String text;
  final Future<void> Function() onPressed;
  final bool isMainAction;
  final bool enabled;
  final ButtonStyle? styleOverride;

  const AsyncActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isMainAction = false,
    this.enabled = true,
    this.styleOverride,
  });

  @override
  State<AsyncActionButton> createState() => _AsyncActionButtonState();
}

class _AsyncActionButtonState extends State<AsyncActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || !widget.enabled;
    return ActionButtonShell(
      text: widget.text,
      busy: _busy,
      isMainAction: widget.isMainAction,
      styleOverride: widget.styleOverride,
      onPressed: disabled ? null : _run,
    );
  }
}
