import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';

/// 멤버십 이력 DataTable 공용 위젯.
///
/// 스탬프내역·쿠폰사용내역·보유쿠폰 탭에서 공유하는 외형(헤더 행 색상,
/// 행 높이, 텍스트 스타일)을 고정하고, 호출자는 [columns]·[rows]만 전달한다.
/// 페이지네이션 컨트롤도 내부에 포함돼 있어 중복 제거에 효과적이다.
class MembershipHistoryTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final String prevPageTooltip;
  final String nextPageTooltip;

  const MembershipHistoryTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    required this.prevPageTooltip,
    required this.nextPageTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Column(
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppStyles.gray2),
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: columns,
                rows: rows,
              ),
            ),
          ),
          if (totalPages > 1)
            _PaginationControls(
              currentPage: currentPage,
              totalPages: totalPages,
              onPageChanged: onPageChanged,
              prevTooltip: prevPageTooltip,
              nextTooltip: nextPageTooltip,
            ),
        ],
      ),
    );
  }
}

/// DataColumn 헤더 레이블을 일관된 스타일로 만드는 헬퍼.
Widget membershipTableHeader(String text) => Center(
      child: Text(
        text,
        style: AppTextStyles.body
            .copyWith(fontWeight: FontWeight.bold, color: AppStyles.gray9),
        textAlign: TextAlign.center,
      ),
    );

/// 교차 행 배경색(짝수 행: [AppStyles.gray1]).
WidgetStateProperty<Color?> membershipRowColor(int index) =>
    WidgetStateProperty.resolveWith<Color?>(
      (states) => index.isEven ? AppStyles.gray1 : null,
    );

class _PaginationControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final String prevTooltip;
  final String nextTooltip;

  const _PaginationControls({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    required this.prevTooltip,
    required this.nextTooltip,
  });

  @override
  Widget build(BuildContext context) {
    const int maxPageNumbersToShow = 5;
    int startPage;
    int endPage;

    if (totalPages <= maxPageNumbersToShow) {
      startPage = 0;
      endPage = totalPages - 1;
    } else {
      int halfMax = maxPageNumbersToShow ~/ 2;
      startPage = currentPage - halfMax;
      endPage = currentPage + halfMax - (maxPageNumbersToShow % 2 == 0 ? 1 : 0);

      if (startPage < 0) {
        startPage = 0;
        endPage = maxPageNumbersToShow - 1;
      }
      if (endPage >= totalPages) {
        endPage = totalPages - 1;
        startPage = endPage - maxPageNumbersToShow + 1;
        if (startPage < 0) startPage = 0;
      }
    }

    final pageWidgets = <Widget>[];
    for (int i = startPage; i <= endPage; i++) {
      final bool isCurrent = i == currentPage;
      pageWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.all(AppSpacing.s8),
              minimumSize: const Size(36, 36),
              backgroundColor:
                  isCurrent ? AppStyles.kMainColor : Colors.transparent,
              foregroundColor: isCurrent ? Colors.white : AppStyles.gray6,
              textStyle: AppTextStyles.bodySm,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.bSm,
                side: BorderSide(
                  color: isCurrent ? AppStyles.kMainColor : AppStyles.gray3,
                  width: 1,
                ),
              ),
            ),
            onPressed: () => onPageChanged(i),
            child: Text('${i + 1}'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_left),
            onPressed:
                currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
            tooltip: prevTooltip,
          ),
          ...pageWidgets,
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_right),
            onPressed: currentPage < totalPages - 1
                ? () => onPageChanged(currentPage + 1)
                : null,
            tooltip: nextTooltip,
          ),
        ],
      ),
    );
  }
}
