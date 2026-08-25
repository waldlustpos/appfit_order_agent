import 'package:flutter/foundation.dart';

import 'package:appfit_order_agent/models/menu_option_model.dart';
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

  /// POS 상품코드(예: 'M009000'). **v1 주문상세 응답에만 존재**하므로 nullable.
  final String? itemPosId;

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
    this.itemPosId,
  });

  factory OrderMenuModel.fromJson(Map<String, dynamic> json) {
    logger.d('OrderMenuModel.fromJson 입력: $json');

    // 옵션 목록 파싱 (항목별 격리: 1건 손상 시 해당 항목만 스킵, 정상 항목 유지)
    final List<MenuOptionModel> options = [];
    final optionsRaw = json['options'];
    if (optionsRaw is List) {
      for (final opt in optionsRaw) {
        try {
          options.add(MenuOptionModel.fromJson(opt));
        } catch (e, s) {
          logger.e('옵션 항목 파싱 오류 (스킵): $opt', error: e, stackTrace: s);
        }
      }
    } else if (optionsRaw != null) {
      logger.e('옵션 목록 파싱 오류: options 가 List 가 아님 ($optionsRaw)');
    }

    // AppFit response uses 'qty'
    final parsedCount = int.tryParse(json['qty']?.toString() ?? '0') ?? 0;

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
      itemPosId: json['itemPosId']?.toString(),
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
      if (itemPosId != null) 'itemPosId': itemPosId,
    };
  }

  // 메뉴의 총 가격 (옵션 포함)
  double get totalPrice {
    double optionsPrice =
        options.fold(0, (prev, opt) => prev + (opt.optionPrice * opt.qty));
    return (itemPrice * qty) + optionsPrice;
  }

  Map<String, dynamic> toJsonForSoundGraph() {
    return {
      // POS 상품코드가 정본. v1 주문상세 미경유 등으로 없을 때만 내부 ID 폴백.
      'skuNo': itemPosId ?? shopItemId,
      'menuTitle': itemName,
      'amount': itemPrice.toInt(),
      'cnt': qty,
      'options': options.map((o) => o.toJsonForSoundGraph()).toList(),
    };
  }

  @override
  String toString() {
    return '$shopItemId:$itemName:$itemPrice:$qty';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderMenuModel &&
        orderNo == other.orderNo &&
        shopItemId == other.shopItemId &&
        qty == other.qty &&
        itemName == other.itemName &&
        itemPrice == other.itemPrice &&
        totalAmount == other.totalAmount &&
        discPrc == other.discPrc &&
        vatPrc == other.vatPrc &&
        itemPosId == other.itemPosId &&
        listEquals(options, other.options);
  }

  @override
  int get hashCode => Object.hash(
        orderNo,
        shopItemId,
        qty,
        itemName,
        itemPrice,
        totalAmount,
        discPrc,
        vatPrc,
        itemPosId,
        Object.hashAll(options),
      );
}
