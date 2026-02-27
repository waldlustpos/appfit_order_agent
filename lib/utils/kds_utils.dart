import 'dart:math';
import '../models/order_model.dart';
import '../models/order_menu_model.dart';
import '../providers/order_history_provider.dart';

// 간단한 주문인지 판단하는 헬퍼 함수 (가중치 기반)
bool _isSimpleOrder(int menuCount, int totalOptions) {
  // 기본 임계값 설정 (카드에 표시될 수 있는 최대 복잡도)
  const double maxComplexityScore = 130.0;

  // 복잡도 점수 계산
  final complexityScore = _calculateComplexityScore(menuCount, totalOptions);

  return complexityScore < maxComplexityScore;
}

// 복잡도 점수 계산 함수
double _calculateComplexityScore(int menuCount, int totalOptions) {
  // 가중치 설정
  const double menuWeight = 25.0; // 메뉴 1개당 25점
  const double optionWeight = 25.0; // 옵션 1개당 8점
  const double dividerWeight = 5.0; // 메뉴 구분선 1개당 5점
  // 기본 점수 계산
  double baseScore = (menuCount * menuWeight) + (totalOptions * optionWeight);

  // Divider 점수 (메뉴가 2개 이상일 때 메뉴 사이에 divider 생성)
  double dividerScore = menuCount > 1 ? (menuCount - 1) * dividerWeight : 0;

  final totalScore = baseScore + dividerScore;

  return totalScore;
}

// 주문 타입 결정 함수 - 메뉴/옵션 개수 기반
int determineOrderType(
    OrderModel order, Map<String, OrderModel> detailedOrders) {
  final counts = calculateMenuAndOptionCount(order, detailedOrders);
  final menuCount = counts['menuCount']!;
  final totalOptions = counts['totalOptions']!;

  // 간단한 주문 판정 (가중치 기반)
  if (_isSimpleOrder(menuCount, totalOptions)) {
    return 1;
  }

  return 2;
}

// 상품/옵션 개수에 따라 카드의 너비를 미세하게 조절
int calculateCrossAxisCellCount(int menuCount, int totalOptions) {
  final itemCount = menuCount + totalOptions;
  const minCell = 2;
  const maxCell = 13;
  // sqrt(0) = 0, sqrt(40) ≈ 6.3
  final ratio = (sqrt(itemCount) / sqrt(40)).clamp(0, 1);
  final cellCount = minCell + (maxCell - minCell) * ratio;
  return cellCount.round();
}

// 메뉴/옵션 개수 계산 함수
Map<String, int> calculateMenuAndOptionCount(
    OrderModel order, Map<String, OrderModel> detailedOrders) {
  final detailedOrder = detailedOrders[order.orderId] ?? order;
  final menuCount = detailedOrder.orderMenuList.length;

  int totalOptions = 0;
  for (final menu in detailedOrder.orderMenuList) {
    totalOptions += menu.options.length;
  }

  return {
    'menuCount': menuCount,
    'totalOptions': totalOptions,
  };
}

// 주문 정렬 함수
void sortOrders(List<OrderModel> orders, OrderSortDirection direction) {
  if (direction == OrderSortDirection.ASC) {
    // 오름차순 (오래된 주문순) - simpleNum 기준
    orders.sort((a, b) {
      final numA = int.tryParse(a.shopOrderNo) ?? 0;
      final numB = int.tryParse(b.shopOrderNo) ?? 0;
      return numA.compareTo(numB);
    });
  } else {
    // 내림차순 (최신 주문순) - simpleNum 기준
    orders.sort((a, b) {
      final numA = int.tryParse(a.shopOrderNo) ?? 0;
      final numB = int.tryParse(b.shopOrderNo) ?? 0;
      return numB.compareTo(numA);
    });
  }
}

// 타입3 카드용 컬럼 계산
List<List<int>> calculateColumns(List<OrderMenuModel> menuList) {
  List<double> itemHeights = [];
  for (int i = 0; i < menuList.length; i++) {
    final menu = menuList[i];
    double height = 23.0;
    if (menu.options.isNotEmpty) {
      height += menu.options.length * 16.0;
    }
    itemHeights.add(height);
  }

  const double maxColumnHeight = 300.0;
  List<List<int>> columns = [<int>[]];
  double currentHeight = 0.0;
  int currentColumn = 0;

  for (int i = 0; i < menuList.length; i++) {
    if (currentHeight + itemHeights[i] > maxColumnHeight) {
      currentColumn++;
      columns.add(<int>[]);
      currentHeight = 0.0;
    }
    columns[currentColumn].add(i);
    currentHeight += itemHeights[i];
  }

  return columns;
}

// 아이템 높이 계산
List<double> calculateItemHeights(List<OrderMenuModel> menuList) {
  List<double> itemHeights = [];
  for (int i = 0; i < menuList.length; i++) {
    final menu = menuList[i];
    double height = 23.0;
    if (menu.options.isNotEmpty) {
      height += menu.options.length * 16.0;
    }
    itemHeights.add(height);
  }
  return itemHeights;
}
