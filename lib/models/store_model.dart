import 'package:appfit_order_agent/config/membership_config.dart';

class StoreModel {
  final String storeId;
  final String name;
  final bool isOpen;
  late final String? rewardType;

  /// 매장 전화번호 (`/v0/shop` 응답의 `shopContact`).
  final String? phone;

  /// 사업자번호. /v0/shop 응답에 현재 미포함. 백엔드 추가 후 매핑 예정.
  final String? businessNumber;

  /// 매장이 속한 그룹 (`/v0/shop` 응답의 `shopGroupId`).
  /// 스탬프 적립 가능 여부 판정에만 쓴다([stampAccrualEnabled]).
  final String? shopGroupId;

  StoreModel({
    required this.storeId,
    required this.name,
    required this.isOpen,
    this.rewardType = '',
    this.phone,
    this.businessNumber,
    this.shopGroupId,
  });

  /// 멤버십 탭에서 스탬프를 **적립**할 수 있는지. 판정 규칙 정본은
  /// [MembershipConfig]. 스탬프내역 조회는 이 값과 무관하게 항상 가능하다.
  bool get stampAccrualEnabled =>
      MembershipConfig.stampAccrualEnabledFor(shopGroupId);

  /// 필수 필드(strId/name)가 누락/비문자열이면 [FormatException] throw.
  /// silent 기본값('')은 빈 storeId 가 초기 로드 가드를 조용히 통과하므로 더 위험.
  factory StoreModel.fromJson(Map<String, dynamic> json) {
    final strId = json['strId'];
    if (strId is! String) {
      throw FormatException(
          'StoreModel.fromJson: strId 누락/비문자열 (strId=$strId)');
    }
    final name = json['name'];
    if (name is! String) {
      throw FormatException('StoreModel.fromJson: name 누락/비문자열 (name=$name)');
    }
    return StoreModel(
      storeId: strId,
      name: name,
      // 서버가 '8' 문자열로 보내는 경우도 수용
      isOpen: int.tryParse(json['orderStatus']?.toString() ?? '') == 8,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': storeId,
      'name': name,
      'isOpen': isOpen,
      'phone': phone,
      'businessNumber': businessNumber,
      'shopGroupId': shopGroupId,
    };
  }

  StoreModel copyWith({
    String? storeId,
    String? name,
    bool? isOpen,
    String? rewardType,
    String? phone,
    String? businessNumber,
    String? shopGroupId,
  }) {
    return StoreModel(
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      isOpen: isOpen ?? this.isOpen,
      rewardType: rewardType ?? this.rewardType,
      phone: phone ?? this.phone,
      businessNumber: businessNumber ?? this.businessNumber,
      shopGroupId: shopGroupId ?? this.shopGroupId,
    );
  }
}
