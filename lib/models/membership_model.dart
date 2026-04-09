// lib/models/membership_model.dart
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/utils/model_parse_utils.dart';

class CouponInfo {
  final String couponId;
  final String couponTitle;
  final String couponDiscount;
  final DateTime issueDate;
  final DateTime expireDate;

  CouponInfo({
    required this.couponId,
    required this.couponTitle,
    required this.couponDiscount,
    required this.issueDate,
    required this.expireDate,
  });

  factory CouponInfo.fromJson(Map<String, dynamic> json) {
    return CouponInfo(
      couponId: json['coupon_id']?.toString() ?? '',
      couponTitle: json['coupon_title']?.toString() ?? '제목 없음',
      couponDiscount: json['coupon_discount']?.toString() ?? '0',
      issueDate: parseTimestamp(json['issue_date']),
      expireDate: parseTimestamp(json['expire_date']),
    );
  }

  factory CouponInfo.fromAppFitJson(Map<String, dynamic> json) {
    return CouponInfo(
      couponId: json['couponNo']?.toString() ?? '',
      couponTitle: json['couponTitle']?.toString() ?? '제목 없음',
      couponDiscount:
          (json['discountValue'] as num?)?.toInt().toString() ?? '0',
      issueDate: DateTime.tryParse(json['issuedAt']?.toString() ?? '') ??
          DateTime.now(),
      expireDate: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'CouponInfo{couponId: $couponId, couponTitle: $couponTitle, couponDiscount: $couponDiscount, issueDate: $issueDate, expireDate: $expireDate}';
  }
}

class MembershipInfo {
  final bool isAppMember;
  final String userName;
  String phoneNumber;
  final int stampCount;
  final int couponCount;
  final List<CouponInfo> coupons;
  final int totalPoint;
  final String id;
  final String barcode;
  final List<RecentOrderInfo> recentOrders;

  MembershipInfo({
    required this.isAppMember,
    required this.userName,
    this.phoneNumber = '',
    required this.stampCount,
    required this.couponCount,
    required this.coupons,
    required this.totalPoint,
    this.id = '',
    this.barcode = '',
    this.recentOrders = const [],
  });

  factory MembershipInfo.fromJson(Map<String, dynamic> json) {
    // 쿠폰 목록 파싱
    List<CouponInfo> parseCoupons(dynamic couponList) {
      if (couponList is List) {
        try {
          return couponList
              .map((couponJson) =>
                  CouponInfo.fromJson(couponJson as Map<String, dynamic>))
              .toList();
        } catch (e, s) {
          logger.e('Error parsing coupon list', error: e, stackTrace: s);
          return [];
        }
      }
      return [];
    }

    return MembershipInfo(
      isAppMember: json['app_member'] == 'Y',
      userName: json['user_name']?.toString() ?? '이름 없음',
      stampCount: parseIntSafe(json['stamp_count']),
      couponCount: parseIntSafe(json['coupon_count']),
      coupons: parseCoupons(json['coupons']),
      totalPoint: parseIntSafe(json['total_point']),
    );
  }

  factory MembershipInfo.fromAppFitJson(Map<String, dynamic> json) {
    final data = json; // Actual data object

    final nickname = data['nickname']?.toString() ?? '';
    return MembershipInfo(
      isAppMember: true,
      id: data['id']?.toString() ?? '',
      barcode: data['barcode']?.toString() ?? '',
      userName: nickname.isEmpty ? '회원' : nickname,
      phoneNumber: data['phoneNumber']?.toString() ?? '',
      stampCount: (data['stampCount'] as num?)?.toInt() ?? 0,
      couponCount: (data['couponCount'] as num?)?.toInt() ?? 0,
      totalPoint: (data['points'] as num?)?.toInt() ?? 0,
      coupons: (data['activeCoupons'] as List<dynamic>? ?? [])
          .map((c) => CouponInfo.fromAppFitJson(c as Map<String, dynamic>))
          .toList(),
      recentOrders: (data['recentOrders'] as List<dynamic>? ?? [])
          .map((o) => RecentOrderInfo.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  String toString() {
    return 'MembershipInfo{isAppMember: $isAppMember, userName: $userName, phoneNumber: *******${phoneNumber.substring(phoneNumber.length - 4, phoneNumber.length)}, stampCount: $stampCount, couponCount: $couponCount, coupons: $coupons, totalPoint: $totalPoint}';
  }
}

// TODO: 스탬프 내역 모델 추가 (API 확인 후)
class StampInfo {
  final DateTime logDate; // 이벤트 발생 일시 (적립 또는 사용)
  final int stampCount; // 관련된 스탬프 개수
  final String status; // 상태 코드 (원시값: '7', '9' 등)
  final String memo; // 비고 (상태 또는 유형)
  final String seq; // 취소 시 사용할 고유 시퀀스 번호
  final String rewardId; // 취소 시 사용할 리워드 ID

  StampInfo({
    required this.logDate,
    required this.stampCount,
    required this.status, // status 필드 추가
    required this.memo, // memo 유지 (API 응답에 따라 결정)
    required this.seq, // seq 추가
    required this.rewardId, // rewardId 추가
  });

  factory StampInfo.fromJson(Map<String, dynamic> json) {
    return StampInfo(
      logDate: parseTimestamp(
          json['issue_date']), // Try multiple potential date keys
      stampCount: parseIntSafe(
          json['stamp_count']), // Try multiple potential count keys
      status: json['status']?.toString() ?? '', // Try status or reward_type
      memo: json['memo']?.toString() ?? '', // API 응답에 'memo' 필드가 있다면 사용, 없다면 ''
      seq: json['seq']?.toString() ?? '', // seq 파싱 추가
      rewardId: json['id']?.toString() ?? '', // rewardId
    );
  }

  factory StampInfo.fromAppFitJson(Map<String, dynamic> json) {
    return StampInfo(
      logDate: DateTime.tryParse(json['occurredAt']?.toString() ?? '') ??
          DateTime.now(),
      stampCount: (json['stampCount'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? '',
      memo: json['memo']?.toString() ?? '',
      seq: json['seq']?.toString() ?? '',
      rewardId: json['referenceId']?.toString() ?? '',
    );
  }
}

class CouponHistoryInfo {
  final String uid; // 쿠폰명
  final String title; // 쿠폰명
  final DateTime issueDate; // 사용일
  final DateTime useDate; // 사용일
  final String status; // 상태 코드 (원시값: '9', '7' 등)
  final String couponId; // 쿠폰 ID 추가
  final String seq; // 필요 시 시퀀스 번호 추가

  CouponHistoryInfo({
    required this.uid,
    required this.title,
    required this.issueDate,
    required this.useDate,
    required this.status, // 타입 String으로 유지
    required this.couponId, // couponId 추가
    required this.seq,
  });

  factory CouponHistoryInfo.fromJson(Map<String, dynamic> json) {
    return CouponHistoryInfo(
      uid: json['uid']?.toString() ?? '제목 없음',
      title: json['title']?.toString() ?? '제목 없음',
      issueDate: parseTimestamp(json['issue_date']), // 발급일 기준
      useDate: parseTimestamp(json['use_date']), // 사용일 기준
      status: json['status']?.toString() ?? '', // 원시 상태 코드 저장
      // API 응답의 쿠폰 ID 키 이름 확인 필요 (예: 'id', 'coupon_id')
      couponId: json['id']?.toString() ?? '', // 쿠폰 ID 파싱
      seq: json['seq']?.toString() ?? '',
    );
  }

  factory CouponHistoryInfo.fromAppFitJson(Map<String, dynamic> json) {
    return CouponHistoryInfo(
      uid: json['couponId']?.toString() ?? '', // AppFit internal ID
      title: json['title']?.toString() ??
          json['couponTitle']?.toString() ??
          '제목 없음',
      issueDate: DateTime.tryParse(json['issuedAt']?.toString() ?? '') ??
          DateTime.now(),
      useDate: DateTime.tryParse(json['usedAt']?.toString() ??
              json['issuedAt']?.toString() ??
              '') ??
          DateTime.now(),
      status: json['status']?.toString() ?? '',
      couponId: json['couponNo']?.toString() ?? '', // AppFit display number
      seq: json['seq']?.toString() ?? '',
    );
  }
}

// --- 포인트 내역 모델 추가 ---
class PointHistoryInfo {
  final String uid;
  final String phone;
  final String appMember; // 'Y' or 'N'
  final String type; // 'point'
  final String seq; // 취소 시 필요할 수 있는 고유 ID
  final String rewardType; // '1', '3', '11', '13' 등
  final DateTime rewardDate; // 타임스탬프 (초 단위)
  final int rewardPoint; // 포인트 값
  final String? orderId; // 관련 주문 ID (nullable)

  PointHistoryInfo({
    required this.uid,
    required this.phone,
    required this.appMember,
    required this.type,
    required this.seq,
    required this.rewardType,
    required this.rewardDate,
    required this.rewardPoint,
    this.orderId,
  });

  factory PointHistoryInfo.fromJson(Map<String, dynamic> json) {
    return PointHistoryInfo(
      uid: json['uid']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      appMember: json['app_member']?.toString() ?? 'N',
      type: json['type']?.toString() ?? '',
      seq: json['seq']?.toString() ?? '', // seq 필드 파싱
      rewardType: json['reward_type']?.toString() ?? '',
      rewardDate: parseTimestamp(json['reward_date']), // reward_date 파싱
      rewardPoint: parseIntSafe(json['reward_point']), // reward_point 파싱
      orderId: json['order_id']?.toString(), // order_id 파싱 (nullable)
    );
  }
}

class RecentOrderInfo {
  final String orderNo;
  final String orderName;
  final String orderStatus;
  final String type;
  final DateTime createdAt;

  RecentOrderInfo({
    required this.orderNo,
    required this.orderName,
    required this.orderStatus,
    required this.type,
    required this.createdAt,
  });

  factory RecentOrderInfo.fromJson(Map<String, dynamic> json) {
    return RecentOrderInfo(
      orderNo: json['orderNo']?.toString() ?? '',
      orderName: json['orderName']?.toString() ?? '',
      orderStatus: json['orderStatus']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
