import 'package:flutter/material.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/models/order_model.dart';

/// KDS 카드 메모 영역.
///
/// 좌측 4px 핑크 액센트 바로 메모를 시각적으로 구분한다.
/// 노트가 비어 있으면 [SizedBox.shrink]를 반환하므로 호출 측에서 분기 불필요.
class KdsMemoWidget extends StatelessWidget {
  final OrderModel order;

  const KdsMemoWidget({super.key, required this.order});

  static String _normalize(String? note) {
    if (note == null) return '';
    return note.replaceAll('\\n', ' ').replaceAll(RegExp(r'(\n\s*)+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final note = order.note;
    if (note == null || note.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: AppStyles.gray1,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      // IntrinsicHeight 없이 Row(crossAxisAlignment: stretch)를 쓰면 부모(Column
      // mainAxisSize.min) 안에서 vertical constraint가 unbounded가 되어 layout
      // 어쌔션이 터지고, 카드 전체가 사일런트하게 사라진다.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: AppStyles.kMainColor,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                _normalize(note),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: AppStyles.kOrderCardTimeSize,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
