import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

/// KDS/홈 툴바에서 사용하는 40px 높이 통일 버튼.
///
/// - [AppToolbarButton.primary]: 주 액션 (채운 배경, kMainColor)
/// - [AppToolbarButton.secondary]: 보조 액션 (흰 배경, 회색 보더)
/// - [AppToolbarButton.ghost]: 비인터랙티브 정보 표시 (투명 배경, 연한 보더)
enum _AppToolbarVariant { primary, secondary, ghost }

class AppToolbarButton extends StatelessWidget {
  const AppToolbarButton._({
    Key? key,
    required _AppToolbarVariant variant,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
  })  : _variant = variant,
        super(key: key);

  /// 주 액션 — kMainColor 배경, 흰 텍스트 (예: 일괄 완료)
  const AppToolbarButton.primary({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) : this._(
          key: key,
          variant: _AppToolbarVariant.primary,
          label: label,
          icon: icon,
          onPressed: onPressed,
          isLoading: isLoading,
        );

  /// 보조 액션 — 흰 배경, 회색 보더 (예: 정렬, 날짜, 오늘)
  const AppToolbarButton.secondary({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) : this._(
          key: key,
          variant: _AppToolbarVariant.secondary,
          label: label,
          icon: icon,
          onPressed: onPressed,
          isLoading: isLoading,
        );

  /// 정보 표시 — 연한 배경, 인터랙션 없음 (예: 건수 표시)
  const AppToolbarButton.ghost({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) : this._(
          key: key,
          variant: _AppToolbarVariant.ghost,
          label: label,
          icon: icon,
          onPressed: onPressed,
          isLoading: isLoading,
        );

  final _AppToolbarVariant _variant;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  static const double _height = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: _buildByVariant(),
    );
  }

  Widget _buildByVariant() {
    switch (_variant) {
      case _AppToolbarVariant.primary:
        return _PrimaryToolbarButton(
          label: label,
          icon: icon,
          onPressed: onPressed,
          isLoading: isLoading,
        );
      case _AppToolbarVariant.secondary:
        return _SecondaryToolbarButton(
          label: label,
          icon: icon,
          onPressed: onPressed,
          isLoading: isLoading,
        );
      case _AppToolbarVariant.ghost:
        return _GhostToolbarButton(
          label: label,
          icon: icon,
          onPressed: onPressed,
        );
    }
  }
}

// ─── 내부 구현 위젯들 ──────────────────────────────────────────────────────────

class _PrimaryToolbarButton extends StatelessWidget {
  const _PrimaryToolbarButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppStyles.kMainColor,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        color: Colors.white,
      ),
    );
  }
}

class _SecondaryToolbarButton extends StatelessWidget {
  const _SecondaryToolbarButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppStyles.gray9,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppStyles.gray3),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: isLoading,
        color: AppStyles.gray9,
      ),
    );
  }
}

class _GhostToolbarButton extends StatelessWidget {
  const _GhostToolbarButton({
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppStyles.gray6,
        backgroundColor: AppStyles.gray2,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bSm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: false,
        color: AppStyles.gray6,
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.color,
    required this.isLoading,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }

    if (icon == null) {
      return Text(
        label,
        style: AppTextStyles.bodySm.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.s4),
        Text(
          label,
          style: AppTextStyles.bodySm.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
