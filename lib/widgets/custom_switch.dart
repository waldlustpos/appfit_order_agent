import 'package:flutter/material.dart';
import '../constants/app_styles.dart';

class CustomSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final Color inactiveColor;
  final String activeText;
  final String inactiveText;
  final Duration debounceTime;

  const CustomSwitch({
    Key? key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor = AppStyles.gray4,
    this.activeText = 'ON',
    this.inactiveText = 'OFF',
    this.debounceTime = const Duration(milliseconds: 1000),
  }) : super(key: key);

  @override
  State<CustomSwitch> createState() => _CustomSwitchState();
}

class _CustomSwitchState extends State<CustomSwitch> {
  static const double _trackW = 70.0;
  static const double _trackH = 30.0;
  static const double _thumbD = 26.0;
  static const double _thumbPad = 2.0;
  static const double _textPad = 8.0;

  bool _isChanging = false;

  void _handleTap() {
    if (_isChanging) return;
    setState(() => _isChanging = true);
    widget.onChanged(!widget.value);
    Future.delayed(widget.debounceTime, () {
      if (mounted) setState(() => _isChanging = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOn = widget.value;
    return GestureDetector(
      onTap: _handleTap,
      child: Opacity(
        opacity: _isChanging ? 0.7 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _trackW,
          height: _trackH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_trackH / 2),
            color: isOn
                ? (widget.activeColor ?? AppStyles.kMainColor)
                : widget.inactiveColor,
          ),
          child: Stack(
            children: [
              // ON/OFF 레이블
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: isOn ? _textPad : _trackW / 2,
                right: isOn ? _trackW / 2 : _textPad,
                top: 0,
                bottom: 0,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isOn ? widget.activeText : widget.inactiveText,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              // 슬라이딩 썸
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                left: isOn ? _trackW - _thumbD - _thumbPad : _thumbPad,
                top: _thumbPad,
                child: Container(
                  width: _thumbD,
                  height: _thumbD,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
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
