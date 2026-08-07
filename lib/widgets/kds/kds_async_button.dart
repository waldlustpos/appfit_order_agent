import 'package:flutter/material.dart';

/// KDS 카드 하단의 비동기 액션 버튼 (픽업 요청 / 완료 처리).
///
/// [onPressed] 가 반환하는 Future 가 끝날 때까지 **자기 자신만** 잠기고 그 자리에
/// 진행 인디케이터를 띄운다. 같은 카드의 다른 버튼(상세 등)에는 영향이 없다.
///
/// 이 위젯이 필요한 이유: 네트워크가 느릴 때 상태변경 PUT 이 20초 넘게 걸리는데,
/// 그동안 버튼이 아무 반응도 없이 계속 눌렸다. 운영자는 실패한 줄 알고 연타했고
/// 그만큼 요청이 중복 발사됐다. 진행 표시와 재진입 차단은 같은 문제의 양면이라
/// 한 위젯에서 함께 다룬다.
///
/// 잠금은 [AbsorbPointer] 로 건다. `onPressed: null` 로 끄면 [ElevatedButton] 이
/// disabled 팔레트로 다시 칠해져 버튼 색이 회색으로 바뀌는데, 주방 화면에서는
/// 그 깜빡임이 오히려 오작동처럼 보인다. 색을 유지한 채 입력만 막는다.
/// (`_busy` 가드는 그래도 남겨 둔다 — 이중 안전)
///
/// **로컬 `_busy` 만으로는 부족하다** (2026-08-08 에뮬레이터 실검증에서 발견):
/// KDS 카드는 `isDetailLoaded`/`kdsOrderType` 에 따라 Simple/Scrollable 트리를
/// 통째로 교체하고 하단 버튼도 조건부라, 진행 중에 이 State 가 재생성되면
/// `_busy` 가 리셋돼 재탭이 관통했다. 그래서 [externalBusy] 로 provider 의
/// 주문별 in-flight 상태를 함께 받는다 — State 가 몇 번 죽었다 살아나든
/// 진실은 provider 에 있으므로 관통이 불가능하다.
///
/// 참고: [AsyncActionButton] 과 동작이 같지만 그쪽은 `ActionButtonShell` 기반
/// 다이얼로그 전용 치수라 KDS 카드에 그대로 쓸 수 없다.
class KdsAsyncButton extends StatefulWidget {
  final String text;
  final Future<void> Function() onPressed;
  final ButtonStyle style;
  final Color textColor;

  /// 위젯 밖(provider)에서 관리되는 busy 상태. true 면 로컬 [_KdsAsyncButtonState._busy]
  /// 와 무관하게 잠그고 스피너를 표시한다. State 재생성에도 살아남는 정본.
  final bool externalBusy;

  const KdsAsyncButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.style,
    this.textColor = Colors.white,
    this.externalBusy = false,
  });

  @override
  State<KdsAsyncButton> createState() => _KdsAsyncButtonState();
}

class _KdsAsyncButtonState extends State<KdsAsyncButton> {
  bool _busy = false;

  bool get _locked => _busy || widget.externalBusy;

  Future<void> _run() async {
    if (_locked) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _locked,
      child: ElevatedButton(
        style: widget.style,
        onPressed: _run,
        child: _locked
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(widget.textColor),
                ),
              )
            : Text(
                widget.text,
                style: TextStyle(color: widget.textColor, fontSize: 16),
              ),
      ),
    );
  }
}
