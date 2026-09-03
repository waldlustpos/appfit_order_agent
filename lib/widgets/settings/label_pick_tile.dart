import 'package:flutter/material.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';

/// 라벨 설정 화면(카테고리 / 서브정보 옵션그룹)의 선택 행.
///
/// 앱에 `CheckboxListTile` 전례가 없어(설정 화면은 전부 `SettingsItemWidget` +
/// `CustomSwitch`) 두 화면이 공유하는 최소 행 위젯을 따로 둔다.
///
/// [orderBadge] 가 주어지면 체크 표시 대신 순번을 그린다 — 서브정보처럼 **고른
/// 순서가 곧 인쇄 순서**인 설정에서 그 순서를 화면에 드러내기 위한 것.
class LabelPickTile extends StatelessWidget {
  const LabelPickTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.orderBadge,
    this.enabled = true,
  });

  final String title;

  /// 코드·소속 옵션 예시 등 보조 설명. 없으면 표시하지 않는다.
  final String? subtitle;

  final bool selected;

  /// 1부터 시작하는 선택 순번. null 이면 체크 아이콘을 쓴다.
  final int? orderBadge;

  /// false 면 흐리게 표시하고 탭을 막는다(최대 개수 도달 등).
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = AppStyles.kMainColor;
    return Opacity(
      opacity: enabled || selected ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled || selected ? onTap : null,
        borderRadius: AppRadius.bSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              _buildMarker(accent),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        color: AppStyles.gray9,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        subtitle!,
                        style: AppTextStyles.caption
                            .copyWith(color: AppStyles.gray6),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarker(Color accent) {
    final bool numbered = orderBadge != null;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? accent : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? accent : AppStyles.gray4,
          width: 2,
        ),
      ),
      child: !selected
          ? null
          : numbered
              ? Text(
                  '$orderBadge',
                  style: AppTextStyles.bodySm.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : const Icon(Icons.check, size: 18, color: Colors.white),
    );
  }
}
