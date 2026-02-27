import 'menu_option_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';

class OrderMenuModel {
  final String orderNo;
  final String shopItemId;
  final int qty;
  final String itemName;
  final double itemPrice;
  final double totalAmount;
  final double
      discPrc; // discountAmount? Keeping discPrc for now if unrelated to payload direct map or rename to discountAmount
  final double vatPrc; // vatAmount
  final List<MenuOptionModel> options;

  OrderMenuModel({
    required this.orderNo,
    required this.shopItemId,
    required this.qty,
    required this.itemName,
    required this.itemPrice,
    required this.totalAmount,
    required this.discPrc,
    required this.vatPrc,
    required this.options,
  });

  factory OrderMenuModel.fromJson(Map<String, dynamic> json) {
    logger.d('OrderMenuModel.fromJson 입력: $json');

    List<MenuOptionModel> options = [];
    if (json.containsKey('options') && json['options'] != null) {
      try {
        final optionsList = json['options'] as List;
        options = optionsList.map((opt) {
          return MenuOptionModel.fromJson(opt);
        }).toList();
      } catch (e, s) {
        logger.e('옵션 목록 파싱 오류', error: e, stackTrace: s);
      }
    }

    // AppFit response uses 'qty'
    int parsedCount = 0;
    if (json['qty'] != null) {
      parsedCount = (json['qty'] as num).toInt();
    }

    final result = OrderMenuModel(
      orderNo: json['orderNo']?.toString() ?? '',
      shopItemId: json['shopItemId']?.toString() ?? '',
      qty: parsedCount,
      itemName: json['itemName']?.toString() ?? '',
      itemPrice: double.tryParse(json['itemPrice']?.toString() ?? '0') ?? 0.0,
      totalAmount:
          double.tryParse(json['totalAmount']?.toString() ?? '0') ?? 0.0,
      discPrc: double.tryParse(json['discPrc']?.toString() ?? '0') ?? 0.0,
      vatPrc: double.tryParse(json['vatPrc']?.toString() ?? '0') ?? 0.0,
      options: options,
    );

    return result;
  }

  Map<String, dynamic> toJson() {
    return {
      'orderNo': orderNo,
      'shopItemId': shopItemId,
      'qty': qty,
      'ordrCnt': qty, // Sunmi 호환용 추가
      'itemName': itemName,
      'prdNm': itemName, // Sunmi 호환용 추가
      'itemPrice': itemPrice,
      'prdPrc': itemPrice, // Sunmi 호환용 추가
      'totalAmount': totalAmount,
      'discPrc': discPrc,
      'vatPrc': vatPrc,
      'options': options.map((e) => e.toJson()).toList(),
      'optPrdList': options.map((e) => e.toJson()).toList(), // Sunmi 호환용 추가
    };
  }

  // 메뉴의 총 가격 (옵션 포함)
  double get totalPrice {
    double optionsPrice =
        options.fold(0, (prev, opt) => prev + (opt.optionPrice * opt.qty));
    return (itemPrice * qty) + optionsPrice;
  }

  @override
  String toString() {
    return '$shopItemId:$itemName:$itemPrice:$qty';
  }
}
