import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // [OPTIMIZATION] listEquals 사용
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../constants/card_types.dart';
import '../../models/order_model.dart';
import '../../providers/kds_unified_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/logger.dart';
import 'kds_button_widget.dart';
import 'kds_card_widget.dart';
import 'kds_menu_list_widget.dart';
import 'kds_scroll_button_widget.dart';
import '../order/order_detail_popup.dart';
import 'w_kds_card_skeleton.dart'; // [NEW] Skeleton Widget

class KdsCardGridLayoutWidget extends ConsumerStatefulWidget {
  final List<OrderModel> items;
  final CardType cardType;
  final int maxInitialItemsToProcess; // 초기에 _groupItems에 전달할 최대 아이템 수 (선택적 최적화)
  final ScrollController? scrollController; // 외부에서 전달받을 스크롤 컨트롤러

  const KdsCardGridLayoutWidget({
    super.key,
    required this.items,
    this.maxInitialItemsToProcess = 100,
    required this.cardType,
    this.scrollController,
  });

  @override
  ConsumerState<KdsCardGridLayoutWidget> createState() =>
      _KdsCardGridLayoutWidgetState();
}

class _KdsCardGridLayoutWidgetState
    extends ConsumerState<KdsCardGridLayoutWidget> {
  late ScrollController _scrollController;
  List<List<OrderModel>> _groupedOrderColumns = []; // 그룹핑된 주문 열 저장
  // bool _isLoadingMore = false; // 선택적: 더 많은 아이템을 비동기로 그룹핑할 경우

  @override
  void initState() {
    super.initState();
    // 외부에서 전달받은 스크롤 컨트롤러가 있으면 사용, 없으면 새로 생성
    _scrollController = widget.scrollController ?? ScrollController();
    // 초기 아이템 그룹핑
    _prepareGroupedData();
  }

  @override
  void didUpdateWidget(KdsCardGridLayoutWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [OPTIMIZATION] listEquals를 사용하여 실제 배열 내용이 바뀔 때만 그룹핑 수행
    // widget.items 참조가 변경되었더라도 요소들이 동일하면 재계산 방지
    if (!listEquals(widget.items, oldWidget.items)) {
      _prepareGroupedData();
    }
  }

  @override
  void dispose() {
    // 외부에서 전달받은 스크롤 컨트롤러가 아닌 경우에만 dispose
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _prepareGroupedData() {
    // widget.items가 매우 클 경우, 여기서도 부분적으로 처리하는 로직 추가 가능
    // 예: final itemsToProcess = widget.items.take(widget.maxInitialItemsToProcess).toList();
    // setState(() {
    //   _groupedOrderColumns = _groupItems(itemsToProcess);
    // });
    setState(() {
      _groupedOrderColumns = _groupItems(widget.items);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_groupedOrderColumns.isEmpty && widget.items.isNotEmpty) {
      // 데이터는 있으나 아직 그룹핑되지 않은 경우 (예: initState 직후)
      // 또는 _prepareGroupedData가 비동기일 경우 로딩 인디케이터 표시
      return const Center(child: CircularProgressIndicator());
    }
    if (_groupedOrderColumns.isEmpty && widget.items.isEmpty) {
      return const Center(child: Text("표시할 주문이 없습니다."));
    }

    return LayoutBuilder(builder: (context, constraints) {
      // 화면 높이 전체를 사용하도록 계산
      final screenHeight = MediaQuery.of(context).size.height;
      final availableHeight =
          constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? constraints.maxHeight - 17 // 최소한의 패딩만 고려
              : screenHeight; // 화면 전체 높이 사용

      return Padding(
        padding: const EdgeInsets.all(0.0),
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            // 스크롤이 끝에 도달했는지 확인 (여유분 200px)
            if (scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 200) {
              // 추가 로딩 요청 (Debounce 처리는 Provider 내부 로직이나 여기서 수행 가능)
              // 여기서는 간단히 호출 (Provider에서 isLoading 체크함)
              ref.read(orderProvider.notifier).loadMoreOrders();
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: _groupedOrderColumns.length,
            itemBuilder: (BuildContext context, int index) {
              final columnGroup = _groupedOrderColumns[index];
              // 각 열의 너비를 여기서 지정. 모든 열이 동일한 너비를 가질 수도 있고,
              // columnGroup의 내용에 따라 다른 너비를 가질 수도 있습니다.
              // 여기서는 _OptimizedCardColumn 내부의 카드 너비(250)를 기준으로 설정한다고 가정합니다.
              const double columnWidth = 260; // 카드 너비 + 간격 등 고려

              return SizedBox(
                width: columnWidth,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4.0), // 열 간 간격
                  child: _OptimizedCardColumn(
                    // key: ValueKey('column_${index}'), // index 기반 키도 가능, 또는 그룹의 고유 ID 사용
                    key: ValueKey(
                        'column_${columnGroup.isNotEmpty ? columnGroup.first.orderId : index}'), // 그룹 내 첫 아이템 ID 사용 (고유성 확보)
                    // context는 이제 itemBuilder의 context 사용
                    group: columnGroup,
                    availableHeight: availableHeight,
                    cardType: widget.cardType,
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
  }

  /// items → column 단위로 그룹핑 (이 함수는 유지)
  List<List<OrderModel>> _groupItems(List<OrderModel> items) {
    // [FIX] 카드를 무조건 가로로 나열하기 위해 (1열 1카드) 그룹핑 로직 제거
    return items.map((item) => [item]).toList();
  }
}

class _OptimizedCardColumn extends ConsumerWidget {
  final List<OrderModel> group;
  final double availableHeight;
  final CardType cardType;

  const _OptimizedCardColumn({
    Key? key,
    required this.group,
    required this.availableHeight,
    required this.cardType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 컬럼이 전체 높이를 사용하도록 설정
    return SizedBox(
      height: availableHeight,
      child: Column(
        mainAxisSize: MainAxisSize.max, // 전체 높이 사용
        mainAxisAlignment: MainAxisAlignment.start,
        children: group.map((order) {
          // [FIX] 개별 카드가 열 전체 높이를 제약으로 가지되, 실제 배치는 내용에 따르도록 수정
          return Align(
            alignment: Alignment.topCenter,
            child: _OptimizedOrderCard(
              key: ValueKey('card_${order.orderId}'),
              order: order,
              availableHeight: availableHeight, // 열 전체 높이를 제약으로 전달
              cardType: cardType,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _OptimizedOrderCard extends ConsumerStatefulWidget {
  final OrderModel order;
  final double availableHeight;
  final CardType cardType;

  const _OptimizedOrderCard({
    Key? key,
    required this.order,
    required this.availableHeight,
    required this.cardType,
  }) : super(key: key);

  @override
  ConsumerState<_OptimizedOrderCard> createState() =>
      _OptimizedOrderCardState();
}

class _OptimizedOrderCardState extends ConsumerState<_OptimizedOrderCard> {
// ScrollController를 KdsScreen의 맵에서 가져오거나 새로 생성
  // 이 컨트롤러는 State 내에서 관리되어야 함
  ScrollController? _internalScrollController;
  late String _orderId;

  @override
  void initState() {
    super.initState();
    _orderId = widget.order.orderId;

    _triggerFetchIfNeeded();

    // 먼저 기존 컨트롤러가 있는지 확인
    _internalScrollController = ref
        .read(kdsScrollControllerMapProvider.notifier)
        .getExistingController(_orderId);

    if (_internalScrollController == null) {
      // 컨트롤러가 없으면, 빌드 완료 후 생성 및 Provider 업데이트
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // 위젯이 여전히 트리에 있는지 확인
          // 이 시점에서 다시 한번 컨트롤러가 생성되지 않았는지 확인 (동시성 문제 방지)
          var controller = ref
              .read(kdsScrollControllerMapProvider.notifier)
              .getExistingController(_orderId);
          controller ??= ref
              .read(kdsScrollControllerMapProvider.notifier)
              .getOrCreateController(_orderId);
          if (mounted) {
            // setState는 mounted 컨텍스트에서만 호출
            setState(() {
              _internalScrollController = controller;
            });
            _internalScrollController?.addListener(_scrollListener);

            // 컨트롤러가 준비된 후 약간의 지연을 두고 초기화
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _restoreScrollPosition(); // 컨트롤러 설정 후 위치 복원
                _updateScrollButtonVisibilityBasedOnControllerState(); // 초기 버튼 상태
              }
            });
          }
        }
      });
    } else {
      // 컨트롤러가 이미 존재하면 바로 리스너 추가 및 초기화
      _internalScrollController?.addListener(_scrollListener);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // 컨트롤러가 준비된 후 약간의 지연을 두고 초기화
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _restoreScrollPosition();
              _updateScrollButtonVisibilityBasedOnControllerState();
            }
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(_OptimizedOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order.orderId != oldWidget.order.orderId ||
        !widget.order.isDetailLoaded) {
      _triggerFetchIfNeeded();
    }
  }

  void _triggerFetchIfNeeded() {
    if (!widget.order.isDetailLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 이미 로딩 중인지 체크는 Provider 내부에서 함
        if (mounted) {
          logger.d(
              'KDS: 주문 카드 표시됨(업데이트), 상세 정보 로드 트리거 - ${widget.order.orderId}');
          ref
              .read(orderProvider.notifier)
              .fetchOrderDetail(widget.order.orderId);
        }
      });
    }
  }

  void _scrollListener() {
    if (mounted &&
        _internalScrollController != null &&
        _internalScrollController!.hasClients) {
      try {
        _updateScrollButtonVisibilityBasedOnControllerState();

        // 스크롤 가능한 내용이 있을 때만 위치 저장
        final position = _internalScrollController!.position;
        final hasScrollableContent = position.maxScrollExtent > 0;

        if (hasScrollableContent) {
          // 스크롤 위치 저장 (Provider에서 중복 체크 수행)
          final currentOffset = _internalScrollController!.offset;
          ref
              .read(kdsScrollPositionsProvider.notifier)
              .saveScrollPosition(_orderId, currentOffset);
        }
      } catch (e) {
        logger.d('KDS: 스크롤 리스너 오류 - $_orderId: $e');
      }
    }
  }

  // 스크롤 컨트롤러 상태에 따라 스크롤 버튼 가시성 업데이트
  void _updateScrollButtonVisibilityBasedOnControllerState() {
    if (_internalScrollController == null ||
        !_internalScrollController!.hasClients) {
      // 컨트롤러가 준비되지 않았으면 버튼 숨김 (또는 기본 상태)
      ref
          .read(kdsScrollButtonStatesProvider.notifier)
          .updateScrollButtons(_orderId, false, false);
      return;
    }

    try {
      final controller = _internalScrollController!;
      final position = controller.position;

      // SingleChildScrollView의 스크롤 가능 여부를 정확히 체크
      // maxScrollExtent가 0보다 크면 스크롤 가능한 내용이 있음
      final hasScrollableContent = position.maxScrollExtent > 0;

      if (!hasScrollableContent) {
        // 스크롤할 내용이 없을 때
        ref
            .read(kdsScrollButtonStatesProvider.notifier)
            .updateScrollButtons(_orderId, false, false);
        return;
      }

      // 스크롤 가능한 내용이 있을 때 버튼 상태 계산
      // SingleChildScrollView에서는 minScrollExtent는 항상 0
      bool canScrollUp = position.pixels > 5.0; // 5픽셀 이상 스크롤된 경우
      bool canScrollDown = position.pixels <
          position.maxScrollExtent - 5.0; // 맨 아래에서 5픽셀 이상 여유가 있는 경우

      ref
          .read(kdsScrollButtonStatesProvider.notifier)
          .updateScrollButtons(_orderId, canScrollUp, canScrollDown);
    } catch (e) {
      // 오류 발생 시 버튼 숨김
      logger.d('KDS: 스크롤 버튼 상태 업데이트 오류 - $_orderId: $e');
      ref
          .read(kdsScrollButtonStatesProvider.notifier)
          .updateScrollButtons(_orderId, false, false);
    }
  }

  void _restoreScrollPosition() {
    if (mounted &&
        _internalScrollController != null &&
        _internalScrollController!.hasClients) {
      try {
        final maxScrollExtent =
            _internalScrollController!.position.maxScrollExtent;
        final hasScrollableContent = maxScrollExtent > 0;

        logger.d(
            'KDS: 스크롤 위치 복원 시도 - $_orderId: 스크롤 가능=${hasScrollableContent}, maxExtent=${maxScrollExtent.toStringAsFixed(1)}');

        // 스크롤 가능한 내용이 있을 때만 위치 복원
        if (hasScrollableContent) {
          final savedPosition = ref
              .read(kdsScrollPositionsProvider.notifier)
              .getScrollPosition(_orderId);

          if (savedPosition > 0.0) {
            if (savedPosition <= maxScrollExtent) {
              // jumpTo를 사용해야 스크롤 리스너가 중복 호출되는 것을 방지
              _internalScrollController!.jumpTo(savedPosition);
              logger.d(
                  'KDS: 스크롤 위치 복원 완료 - $_orderId: ${savedPosition.toStringAsFixed(1)}');
            } else {
              // 저장된 위치가 최대 스크롤 범위를 초과하면 맨 아래로
              _internalScrollController!.jumpTo(maxScrollExtent);
              logger.d(
                  'KDS: 스크롤 위치 조정 완료 - $_orderId: ${maxScrollExtent.toStringAsFixed(1)} (원래: ${savedPosition.toStringAsFixed(1)})');
            }
          } else {
            logger.d('KDS: 저장된 스크롤 위치 없음 - $_orderId');
          }
        } else {
          logger.d('KDS: 스크롤 불가능한 내용 - 위치 복원 스킵 - $_orderId');
        }

        // 위치 복원 후 버튼 상태 즉시 업데이트
        _updateScrollButtonVisibilityBasedOnControllerState();
      } catch (e) {
        logger.d('KDS: 스크롤 위치 복원 오류 - $_orderId: $e');
        // 오류 발생 시에도 버튼 상태는 업데이트
        _updateScrollButtonVisibilityBasedOnControllerState();
      }
    }
  }

  @override
  void dispose() {
    _internalScrollController?.removeListener(_scrollListener);
    // ScrollController는 kdsScrollControllerMapProvider에서 관리하므로 여기서 dispose하지 않음
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    // [FIX] 로딩 중(상세 정보 없음)일 때는 항상 Simple Card(Type 1)로 표시
    final orderType = !order.isDetailLoaded ? 1 : order.kdsOrderType;

    if (orderType == 1) {
      return _buildSimpleCard(
        context,
        order,
        widget.cardType,
        height: widget.availableHeight,
      );
    } else {
      return _buildScrollableCard(
        context,
        order,
        widget.cardType,
        widget.availableHeight,
      );
    }
  }

  Widget _buildSimpleCard(
    BuildContext context,
    OrderModel order,
    CardType cardType, {
    double? height,
  }) {
    // 상세 정보 로딩 여부에 관계없이 카드의 기본 틀(헤더 등)은 표시
    // 상세 정보가 없을 때(로딩 중)는 메뉴 리스트 대신 스켈레톤을 표시

    // 애니메이션 상태 가져오기 (테두리 + 투명도)
    final animationState = ref
        .watch(kdsCardAnimationsProvider.select((map) => map[order.orderId]));
    final borderColor = animationState?.borderColor ?? AppStyles.gray3;
    final opacity = animationState?.opacity ?? 1.0;

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 500),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 250,
          constraints: BoxConstraints(
            minHeight: (height ?? 300) / 2,
            maxHeight: height ?? 300,
          ),
          decoration: BoxDecoration(
            color: Colors.white, // 선택 시 배경색 변경
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor, // 애니메이션 상태에 따른 테두리 색상
              width: 1.5, // 원래 테두리 두께
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // [FIX] 단순 카드는 내용물만큼만 차지하도록 (간격 제거)
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KdsCardHeaderWidget(
                    order: order,
                    detailedOrder: order,
                    cardType: cardType,
                  ),
                  const Divider(
                      color: AppStyles.gray3, thickness: 1, height: 0.5),
                  if (_buildMemoSection(order) != null)
                    _buildMemoSection(order)!,

                  // [FIX] Expanded 제거하여 메뉴와 버튼 사이의 강제 간격 해소
                  Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: !order.isDetailLoaded
                        ? const KdsMenuSkeleton() // 로딩 중이면 스켈레톤
                        : KdsMenuListWidget(
                            // 로딩 완료되면 메뉴 리스트
                            menuList: order.orderMenuList,
                            order: order,
                            cardType: cardType,
                          ),
                  ),
                ],
              ),
              // [FIX] 로딩 중(상세 정보 없음)일 때는 버튼 숨기기
              if (order.isDetailLoaded)
                _buildBottomButtons(context, order, cardType),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableCard(
    BuildContext context,
    OrderModel order,
    CardType cardType,
    double totalCardHeight, // 이 카드가 차지할 전체 높이 (패딩 포함)
    // required Set<int> checkedItems, // 내부에서 watch
    // required ScrollButtonState scrollButtonState, // 내부에서 watch
  ) {
    // 상세 정보 로딩 여부에 관계없이 카드의 기본 틀 표시

    // 스크롤 버튼 상태를 watch하여 실시간으로 업데이트
    final scrollButtonState = ref.watch(
        kdsScrollButtonStatesProvider.select((map) => map[order.orderId]));
    final canScrollUp = scrollButtonState?.canScrollUp ?? false;
    final canScrollDown = scrollButtonState?.canScrollDown ?? false;

    // 애니메이션 상태 가져오기 (테두리 + 투명도)
    final animationState = ref
        .watch(kdsCardAnimationsProvider.select((map) => map[order.orderId]));
    final borderColor = animationState?.borderColor ?? AppStyles.gray3;
    final opacity = animationState?.opacity ?? 1.0;

    // 디버깅을 위한 로그 (필요시 제거)
    if (scrollButtonState != null) {
      logger.d(
          'KDS: 스크롤 버튼 상태 - ${order.orderId}: up=$canScrollUp, down=$canScrollDown');
    }

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 500),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic, // 더 부드러운 스크롤/확장 느낌을 위해 커브 추가
          width: 250,
          // [FIX] 메뉴 개수가 적을 때를 대비해 기본 높이를 최대 높이의 절반으로 설정
          constraints: BoxConstraints(
            minHeight: totalCardHeight / 2,
            maxHeight: totalCardHeight,
          ),
          decoration: BoxDecoration(
            color: Colors.white, // 선택 시 배경색 변경
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor, // 애니메이션 상태에 따른 테두리 색상
              width: 1.5, // 원래 테두리 두께
            ),
          ),
          child: Stack(
            children: [
              // 1. 컨텐츠 영역 (내용물에 따라 높이 가변)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KdsCardHeaderWidget(
                    order: order,
                    detailedOrder: order,
                    cardType: cardType,
                  ),
                  const Divider(
                      color: AppStyles.gray3, thickness: 1, height: 1),
                  if (_buildMemoSection(order) != null)
                    _buildMemoSection(order)!,

                  // 메뉴 리스트 영역: 최대 높이를 제한하여 오버플로우 방지
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      // 전체 카드 높이에서 헤더, 메모, 버튼 영역(약 165)을 제외한 높이
                      maxHeight: totalCardHeight - 165,
                    ),
                    child: Stack(
                      children: [
                        // 스크롤 가능한 메뉴 리스트
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: !order.isDetailLoaded
                              ? const KdsMenuSkeleton() // 로딩 중이면 스켈레톤
                              : SingleChildScrollView(
                                  controller: _internalScrollController,
                                  physics: const BouncingScrollPhysics(),
                                  child: KdsMenuListWidget(
                                    menuList: order.orderMenuList,
                                    order: order,
                                    cardType: cardType,
                                  ),
                                ),
                        ),
                        // 스크롤 버튼 오버레이
                        if (canScrollUp || canScrollDown) ...[
                          if (canScrollUp)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: KdsScrollUpButtonWidget(
                                orderId: order.orderId,
                                scrollControllers:
                                    ref.read(kdsScrollControllerMapProvider),
                                updateScrollButtonVisibility: (orderId) {
                                  _updateScrollButtonVisibilityBasedOnControllerState();
                                },
                              ),
                            ),
                          if (canScrollDown)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: KdsScrollDownButtonWidget(
                                orderId: order.orderId,
                                scrollControllers:
                                    ref.read(kdsScrollControllerMapProvider),
                                updateScrollButtonVisibility: (orderId) {
                                  _updateScrollButtonVisibilityBasedOnControllerState();
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  // 하단 버튼이 위치할 공간 확보 (Stack의 Positioned 버튼과 겹침 방지)
                  if (order.isDetailLoaded) const SizedBox(height: 55),
                ],
              ),

              // 2. 하단 버튼 영역 (카드의 실제 높이에 상관없이 맨 아래 고정)
              if (order.isDetailLoaded)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomButtons(context, order, cardType),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget? _buildMemoSection(OrderModel order) {
  String editNote(String? note) {
    if (note == null) return '';
    note = note.replaceAll('\\n', ' ');
    return note.replaceAll(RegExp(r'(\n\s*)+$'), '');
  }

  if (order.note?.isEmpty != false) return null;
  return Container(
    width: double.infinity,
    height: 45,
    color: AppStyles.gray1,
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: TextField(
        readOnly: true,
        enabled: false,
        decoration: InputDecoration(
          border: InputBorder.none,
          disabledBorder: InputBorder.none,
          label: Center(
            child: Text(
              editNote(order.note!),
              style: const TextStyle(
                color: Colors.black,
                fontSize: AppStyles.kOrderCardTimeSize,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildBottomButtons(
    BuildContext context, OrderModel order, CardType cardType) {
  switch (cardType) {
    case CardType.progress:
      return KdsProgressBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
    case CardType.pickup:
      return KdsPickupBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
    case CardType.completed:
      return KdsCompletedBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
    case CardType.cancelled:
      return KdsCancelledBottomButtonsWidget(
        order: order,
        onOrderDetailTap: () =>
            _showOrderDetail(context, order, cardType: cardType),
      );
  }
}

void _showOrderDetail(BuildContext context, OrderModel order,
    {CardType? cardType}) {
  showDialog(
    context: context,
    builder: (context) => OrderDetailPopup(
      order: order,
      isFromKds: true,
      isFromAllTab: cardType == null,
      isFromCompletedOrCancelled:
          cardType == CardType.completed || cardType == CardType.cancelled,
    ),
  );
}
