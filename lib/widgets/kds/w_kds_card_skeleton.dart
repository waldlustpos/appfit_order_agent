import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../constants/app_styles.dart';

// 전체 카드 스켈레톤 (더 이상 사용 안함, 하위 호환성 위해 유지하거나 제거 가능)
class KdsCardSkeleton extends StatelessWidget {
  final double width;
  final double height;

  const KdsCardSkeleton({
    Key? key,
    this.width = 250,
    this.height = 300,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppStyles.gray3,
            width: 1.5,
          ),
        ),
        child: const KdsMenuSkeleton(),
      ),
    );
  }
}

// 메뉴 리스트 부분만 Shimmer 처리하는 위젯
class KdsMenuSkeleton extends StatelessWidget {
  const KdsMenuSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(4, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 메뉴 아이콘/번호 영역
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 메뉴 텍스트 영역
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 120,
                          height: 12,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  )
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
