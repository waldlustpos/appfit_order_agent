import 'package:flutter/material.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';

/// 라벨 출력 카테고리 선택 화면의 카드 한 장.
///
/// 선택 표현은 상품관리의 품절 카드와 같은 규약을 따른다 — **배경 tint + 테두리
/// 강조**([ProductCardWidget] 참조). 거기에 우상단 원형 체크를 더해 다중 선택임을
/// 드러낸다(품절 카드는 상태 표시라 체크가 없다).
class LabelCategoryCard extends StatelessWidget {
  const LabelCategoryCard({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
    this.code,
  });

  final String name;

  /// POS 카테고리 코드. 서버가 `categoryPosId` 를 안 주는 매장이 있어 nullable —
  /// 비면 줄 자체를 그리지 않는다.
  final String? code;

  final bool selected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // kMainColor 는 브랜드별로 주입되는 static **변수**라 const 로 못 만든다.
    final accent = AppStyles.kMainColor;
    final hasCode = code != null && code!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.08) : Colors.white,
        borderRadius: AppRadius.bLg,
        border: Border.all(
          color: selected ? accent : AppStyles.gray3,
          width: selected ? 1.5 : 1.0,
        ),
      ),
      // Material 을 Container **안**에 둬야 잉크 스플래시가 라운딩 안쪽에 갇힌다.
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.bLg,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.bLg,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSm.copyWith(
                          color: AppStyles.gray9,
                          // 배경 tint + 테두리가 이미 선택 신호라 색까지 바꾸지
                          // 않는다 — 굵기만 올린다(상품 카드와 같은 절제).
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (hasCode) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          code!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption
                              .copyWith(color: AppStyles.gray6),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                _buildCheck(accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 우상단 체크 배지.
  ///
  /// 미선택이면 아무것도 그리지 않되 **자리는 그대로 차지한다** — 탭할 때마다
  /// 이름 영역 폭이 밀리는 것을 막는다. `Positioned` 로 띄우지 않는 이유이기도
  /// 하다(그랬다면 이름이 배지 밑으로 들어가지 않게 오른쪽 여백을 따로
  /// 예약해야 한다).
  Widget _buildCheck(Color accent) {
    return SizedBox(
      width: 28,
      height: 28,
      child: selected
          ? DecoratedBox(
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 18, color: Colors.white),
            )
          : null,
    );
  }
}
