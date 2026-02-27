import 'package:flutter/material.dart';

class CustomSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  final Color inactiveColor;
  final String? activeText;
  final String? inactiveText;
  final Color activeTextColor;
  final Color inactiveTextColor;
  final Duration debounceTime;
  final double ratio;

  const CustomSwitch({
    Key? key,
    required this.value,
    required this.onChanged,
    this.activeColor = Colors.green,
    this.inactiveColor = Colors.grey,
    this.activeText = 'ON',
    this.inactiveText = 'OFF',
    this.activeTextColor = Colors.white,
    this.inactiveTextColor = Colors.white,
    this.ratio = 1.2,
    this.debounceTime = const Duration(milliseconds: 1000),
  }) : super(key: key);

  @override
  State<CustomSwitch> createState() => _CustomSwitchState();
}

class _CustomSwitchState extends State<CustomSwitch> {
  bool _isChanging = false;

  void _handleTap() {
    if (_isChanging) return; // 이미 변경 중이면 탭 무시

    setState(() {
      _isChanging = true;
    });

    widget.onChanged(!widget.value);

    // 일정 시간 후 탭 다시 활성화
    Future.delayed(widget.debounceTime, () {
      if (mounted) {
        setState(() {
          _isChanging = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Opacity(
        opacity: _isChanging ? 0.7 : 1.0, // 변경 중에는 약간 투명하게 표시
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 60.0 * widget.ratio, // 너비 약간 증가
          height: 28.0 * widget.ratio,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.0 * widget.ratio),
            color: widget.value ? widget.activeColor : widget.inactiveColor,
          ),
          child: Stack(
            children: [
              // ON/OFF 텍스트
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: widget.value ? 8.0 * widget.ratio : 32.0 * widget.ratio,
                right: widget.value ? 32.0 * widget.ratio : 8.0 * widget.ratio,
                top: 0,
                bottom: 0,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.value ? widget.activeText! : widget.inactiveText!,
                      style: TextStyle(
                        color: widget.value
                            ? widget.activeTextColor
                            : widget.inactiveTextColor,
                        fontSize: 9.0 * widget.ratio, // 글자 크기 약간 감소
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              // 슬라이딩 동그라미
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: widget.value ? 32.0 * widget.ratio : 2.0 * widget.ratio,
                right: widget.value ? 2.0 * widget.ratio : 32.0 * widget.ratio,
                top: 2.0 * widget.ratio,
                child: Container(
                  width: 24.0 * widget.ratio,
                  height: 24.0 * widget.ratio,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4.0,
                        spreadRadius: 1.0,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
