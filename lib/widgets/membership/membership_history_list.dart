import 'package:flutter/material.dart';
import '../../constants/app_styles.dart';
import '../common/app_empty_view.dart';
import '../common/app_loading_indicator.dart';

/// 멤버십 내역 3개 탭(스탬프·쿠폰사용·보유쿠폰)이 공유하는 카드 리스트 컨테이너.
///
/// - `ListView.separated` + `ScrollController` 기반 무한 스크롤
/// - 서버가 전체 목록을 한 번에 반환하므로, 실제 추가 fetch가 아닌 클라이언트
///   슬라이딩 윈도우(visibleCount 증가)로 `onLoadMore`가 호출된다.
/// - 하단 근접 시 1회 호출 보장을 위해 `_isRequestingMore` 플래그 사용.
class MembershipHistoryList<T> extends StatefulWidget {
  const MembershipHistoryList({
    super.key,
    required this.items,
    required this.hasMore,
    required this.onLoadMore,
    required this.itemBuilder,
    required this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
  });

  final List<T> items;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  State<MembershipHistoryList<T>> createState() =>
      _MembershipHistoryListState<T>();
}

class _MembershipHistoryListState<T> extends State<MembershipHistoryList<T>> {
  final ScrollController _controller = ScrollController();
  bool _isRequestingMore = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isRequestingMore || !widget.hasMore) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _isRequestingMore = true;
      widget.onLoadMore();
      // 다음 프레임에 플래그 해제 — 상태 반영 직후 재진입 허용
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isRequestingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return AppEmptyView(
        icon: widget.emptyIcon,
        message: widget.emptyMessage,
      );
    }

    final itemCount = widget.items.length + (widget.hasMore ? 1 : 0);

    return ListView.separated(
      controller: _controller,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s8),
      itemBuilder: (context, index) {
        if (index >= widget.items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
            child: Center(child: AppLoadingIndicator(size: 24)),
          );
        }
        return widget.itemBuilder(context, widget.items[index], index);
      },
    );
  }
}
