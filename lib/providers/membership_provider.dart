import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/exceptions/api_exceptions.dart';
import 'dart:math' as math;

part 'membership_provider.g.dart';

// State class to hold membership screen data
class MembershipState {
  final String customerName;
  final String customerPhone;
  final int stampCount;
  final int couponCount;
  final int totalPoint;
  final MembershipInfo? membershipInfo;
  final List<StampInfo> stampHistory;
  final List<CouponHistoryInfo> couponHistory;
  final List<PointHistoryInfo> pointSaveHistory;
  final List<PointHistoryInfo> pointUseHistory;
  final bool isLoading; // Loading state for the initial search
  final bool isLoadingRewardHistory; // Loading state for history data
  final String? errorMessage;
  final String? successMessage; // <<< Add success message field
  final int stampHistoryCurrentPage;
  final int couponHistoryCurrentPage;
  final int availableCouponsCurrentPage;
  final int pointSaveHistoryCurrentPage;
  final int pointUseHistoryCurrentPage;
  final String? loadingActionId;
  final String? rewardType;

  static const int itemsPerPage = 10;

  MembershipState({
    this.customerName = '',
    this.customerPhone = '',
    this.stampCount = 0,
    this.couponCount = 0,
    this.totalPoint = 0,
    this.membershipInfo,
    this.stampHistory = const [],
    this.couponHistory = const [],
    this.pointSaveHistory = const [],
    this.pointUseHistory = const [],
    this.isLoading = false,
    this.isLoadingRewardHistory = false,
    this.errorMessage,
    this.successMessage,
    this.stampHistoryCurrentPage = 0,
    this.couponHistoryCurrentPage = 0,
    this.availableCouponsCurrentPage = 0,
    this.pointSaveHistoryCurrentPage = 0,
    this.pointUseHistoryCurrentPage = 0,
    this.loadingActionId,
    this.rewardType,
  });

  MembershipState copyWith({
    String? customerName,
    String? customerPhone,
    int? stampCount,
    int? couponCount,
    int? totalPoint,
    MembershipInfo? membershipInfo,
    List<StampInfo>? stampHistory,
    List<CouponHistoryInfo>? couponHistory,
    List<PointHistoryInfo>? pointSaveHistory,
    List<PointHistoryInfo>? pointUseHistory,
    bool? isLoading,
    bool? isLoadingRewardHistory,
    String? errorMessage,
    String? successMessage,
    bool clearErrorMessage = false,
    bool clearSuccessMessage = false,
    int? stampHistoryCurrentPage,
    int? couponHistoryCurrentPage,
    int? availableCouponsCurrentPage,
    int? pointSaveHistoryCurrentPage,
    int? pointUseHistoryCurrentPage,
    String? loadingActionId,
    bool clearLoadingActionId = false,
    String? rewardType,
  }) {
    return MembershipState(
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      stampCount: stampCount ?? this.stampCount,
      couponCount: couponCount ?? this.couponCount,
      totalPoint: totalPoint ?? this.totalPoint,
      membershipInfo: membershipInfo ?? this.membershipInfo,
      stampHistory: stampHistory ?? this.stampHistory,
      couponHistory: couponHistory ?? this.couponHistory,
      pointSaveHistory: pointSaveHistory ?? this.pointSaveHistory,
      pointUseHistory: pointUseHistory ?? this.pointUseHistory,
      isLoading: isLoading ?? this.isLoading,
      isLoadingRewardHistory:
          isLoadingRewardHistory ?? this.isLoadingRewardHistory,
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      successMessage: clearSuccessMessage
          ? null
          : successMessage ?? this.successMessage, // <<< Update copyWith
      stampHistoryCurrentPage:
          stampHistoryCurrentPage ?? this.stampHistoryCurrentPage,
      couponHistoryCurrentPage:
          couponHistoryCurrentPage ?? this.couponHistoryCurrentPage,
      availableCouponsCurrentPage:
          availableCouponsCurrentPage ?? this.availableCouponsCurrentPage,
      pointSaveHistoryCurrentPage:
          pointSaveHistoryCurrentPage ?? this.pointSaveHistoryCurrentPage,
      pointUseHistoryCurrentPage:
          pointUseHistoryCurrentPage ?? this.pointUseHistoryCurrentPage,
      loadingActionId:
          clearLoadingActionId ? null : loadingActionId ?? this.loadingActionId,
      rewardType: rewardType ?? this.rewardType,
    );
  }

  // Helper getters for pagination
  int get stampHistoryTotalPages => (stampHistory.length / itemsPerPage).ceil();
  List<StampInfo> get pagedStampHistory {
    final totalPages = stampHistoryTotalPages;
    int currentPage = stampHistoryCurrentPage;
    if (currentPage >= totalPages && totalPages > 0) {
      currentPage = totalPages - 1;
    }
    if (currentPage < 0) currentPage = 0;
    final startIndex = currentPage * itemsPerPage;
    final endIndex = math.min(startIndex + itemsPerPage, stampHistory.length);
    return (startIndex < endIndex)
        ? stampHistory.sublist(startIndex, endIndex)
        : [];
  }

  int get couponHistoryTotalPages {
    final filtered = couponHistory
        .where((c) => c.status.toUpperCase() == 'USED' || c.status == '9')
        .toList();
    return (filtered.length / itemsPerPage).ceil();
  }

  List<CouponHistoryInfo> get pagedCouponHistory {
    final filtered = couponHistory
        .where((c) => c.status.toUpperCase() == 'USED' || c.status == '9')
        .toList();
    final totalPages = couponHistoryTotalPages;
    int currentPage = couponHistoryCurrentPage;
    if (currentPage >= totalPages && totalPages > 0) {
      currentPage = totalPages - 1;
    }
    if (currentPage < 0) currentPage = 0;
    final startIndex = currentPage * itemsPerPage;
    final endIndex = math.min(startIndex + itemsPerPage, filtered.length);
    return (startIndex < endIndex)
        ? filtered.sublist(startIndex, endIndex)
        : [];
  }

  int get availableCouponsTotalPages =>
      ((membershipInfo?.coupons.length ?? 0) / itemsPerPage).ceil();
  List<CouponInfo> get pagedAvailableCoupons {
    final coupons = membershipInfo?.coupons ?? [];
    final totalPages = availableCouponsTotalPages;
    int currentPage = availableCouponsCurrentPage;
    if (currentPage >= totalPages && totalPages > 0) {
      currentPage = totalPages - 1;
    }
    if (currentPage < 0) currentPage = 0;
    final startIndex = currentPage * itemsPerPage;
    final endIndex = math.min(startIndex + itemsPerPage, coupons.length);
    return (startIndex < endIndex) ? coupons.sublist(startIndex, endIndex) : [];
  }

  int get pointSaveHistoryTotalPages =>
      (pointSaveHistory.length / itemsPerPage).ceil();
  List<PointHistoryInfo> get pagedPointSaveHistory {
    final totalPages = pointSaveHistoryTotalPages;
    int currentPage = pointSaveHistoryCurrentPage;
    if (currentPage >= totalPages && totalPages > 0) {
      currentPage = totalPages - 1;
    }
    if (currentPage < 0) currentPage = 0;
    final startIndex = currentPage * itemsPerPage;
    final endIndex =
        math.min(startIndex + itemsPerPage, pointSaveHistory.length);
    return (startIndex < endIndex)
        ? pointSaveHistory.sublist(startIndex, endIndex)
        : [];
  }

  int get pointUseHistoryTotalPages =>
      (pointUseHistory.length / itemsPerPage).ceil();
  List<PointHistoryInfo> get pagedPointUseHistory {
    final totalPages = pointUseHistoryTotalPages;
    int currentPage = pointUseHistoryCurrentPage;
    if (currentPage >= totalPages && totalPages > 0) {
      currentPage = totalPages - 1;
    }
    if (currentPage < 0) currentPage = 0;
    final startIndex = currentPage * itemsPerPage;
    final endIndex =
        math.min(startIndex + itemsPerPage, pointUseHistory.length);
    return (startIndex < endIndex)
        ? pointUseHistory.sublist(startIndex, endIndex)
        : [];
  }
}

// Notifier class
@riverpod
class Membership extends _$Membership {
  late ApiService _apiService;
  late String _storeId;

  @override
  MembershipState build() {
    _apiService = ref.watch(apiServiceProvider);
    // Read initial rewardType and storeId from storeProvider
    final storeInfo = ref.watch(storeProvider).value;
    _storeId = storeInfo?.storeId ?? '';
    final rewardType = storeInfo?.rewardType ?? 'STAMP';

    return MembershipState(rewardType: rewardType);
  }

  // --- Search and Data Fetching ---
  Future<bool> search(String phone) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(errorMessage: '매장 ID를 찾을 수 없습니다.');
      return false;
    }

    try {
      logger.d('Membership search started. Setting isLoading = true');

      // 1. Fetch User Profile via AppFit API (ApiService now handles encryption)
      final profileResponse = await _apiService.getUserProfile(_storeId, phone);
      final profileData = profileResponse['data'] as Map<String, dynamic>?;

      if (profileData == null) {
        state = state.copyWith(
          errorMessage: '회원 정보를 찾을 수 없습니다.',
          isLoading: false,
        );
        return false;
      }

      // 3. Use factory to create MembershipInfo from AppFit data
      final membershipData = MembershipInfo.fromAppFitJson(profileData);

      state = state.copyWith(
        membershipInfo: membershipData,
        customerName: membershipData.userName,
        customerPhone: phone,
        stampCount: membershipData.stampCount,
        couponCount: membershipData.couponCount,
        totalPoint: membershipData.totalPoint,
        isLoading: false, // Stop initial loading
        isLoadingRewardHistory: true, // Start history loading
        clearErrorMessage: true,
        clearSuccessMessage: true,
      );
      // +++ Log state change after membership info fetch +++
      logger.d(
          'Membership info fetched. Setting isLoading = false, isLoadingRewardHistory = true');
      logToFile(tag: LogTag.API, message: '멤버십 정보 조회 성공: $membershipData');

      // 4. Fetch Reward History (Parallel fetch for performance)
      logger.i('Fetching STAMP & COUPON history...');

      final results = await Future.wait([
        _apiService.getStampHistory(phone, _storeId),
        _apiService.getCouponHistory(_storeId, phone, size: 50)
      ]);

      final stampHistoryData = results[0];
      final couponHistoryData = results[1];

      final stampDataRaw = stampHistoryData['content'] as List<dynamic>? ?? [];
      final couponDataRaw =
          couponHistoryData['content'] as List<dynamic>? ?? [];

      final stampData = stampDataRaw
          .map((s) => StampInfo.fromAppFitJson(s as Map<String, dynamic>))
          .toList();
      final couponData = couponDataRaw
          .map((c) =>
              CouponHistoryInfo.fromAppFitJson(c as Map<String, dynamic>))
          .toList();

      stampData.sort((a, b) => b.logDate.compareTo(a.logDate));
      couponData.sort((a, b) => b.useDate.compareTo(a.useDate));

      state = state.copyWith(
        stampHistory: stampData,
        couponHistory: couponData,
        isLoadingRewardHistory: false,
      );
      logger.i(
          'STAMP history fetch success: ${stampData.length} stamps, ${couponData.length} coupons');
      return true; // Search successful
    } on ApiException catch (e) {
      logger.e('API Exception during membership search: ${e.message}');
      state = state.copyWith(
        errorMessage: e.message,
        isLoading: false,
        isLoadingRewardHistory: false,
      );
      return false;
    } catch (e, s) {
      logger.e('Unexpected error during membership search: $e');
      state = state.copyWith(
        errorMessage: '회원 조회 중 알 수 없는 오류가 발생했습니다.',
        isLoading: false,
        isLoadingRewardHistory: false,
      );
      return false;
    }
  }

  // --- Actions (Coupon Use/Cancel, Point Cancel, Stamp Save) ---
  Future<bool> useCoupon(String userId, String couponId) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(
          errorMessage: '매장 ID를 찾을 수 없습니다.',
          clearSuccessMessage: true); // Clear success on error
      return false;
    }
    // Clear previous messages and set loading
    state = state.copyWith(
        loadingActionId: couponId,
        clearErrorMessage: true,
        clearSuccessMessage: true);
    try {
      final successData =
          await _apiService.useCoupon(couponId, _storeId, items: []);
      final success = successData.isNotEmpty;
      if (success) {
        logger.i('쿠폰 사용 성공: $couponId');
        // Set success message BEFORE refreshing data
        state = state.copyWith(
            successMessage: '쿠폰 사용이 완료되었습니다.', clearLoadingActionId: true);
        await search(userId); // Refresh data
        return true; // Return true after state is set
      } else {
        logger.w('쿠폰 사용 실패 (API 반환 false?): $couponId');
        state = state.copyWith(
            errorMessage: '쿠폰 사용에 실패했습니다. (API)', clearLoadingActionId: true);
        return false;
      }
    } on ApiException catch (e) {
      logger.e('API Exception during coupon use: ${e.message}');
      state =
          state.copyWith(errorMessage: e.message, clearLoadingActionId: true);
      return false;
    } catch (e, s) {
      logger.e('Unexpected error during coupon use: $e');
      state = state.copyWith(
          errorMessage: '쿠폰 사용 중 오류가 발생했습니다.', clearLoadingActionId: true);
      return false;
    }
  }

  Future<bool> cancelCoupon(String userId, String couponId) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(
          errorMessage: '매장 ID를 찾을 수 없습니다.', clearSuccessMessage: true);
      return false;
    }
    state = state.copyWith(
        loadingActionId: couponId,
        clearErrorMessage: true,
        clearSuccessMessage: true);
    try {
      await _apiService.cancelCouponUse(couponId, _storeId);
      final success =
          true; // cancelCouponUse throws on failure, so success is true if reached here
      if (success) {
        logger.i('쿠폰 취소 성공: $couponId');
        state = state.copyWith(
            successMessage: '쿠폰 사용 취소가 완료되었습니다.', clearLoadingActionId: true);
        await search(userId); // Refresh data
        return true;
      } else {
        logger.w('쿠폰 취소 실패 (API 반환 false?): $couponId');
        state = state.copyWith(
            errorMessage: '쿠폰 사용 취소에 실패했습니다. (API)',
            clearLoadingActionId: true);
        return false;
      }
    } on ApiException catch (e) {
      logger.e('API Exception during coupon cancel: ${e.message}');
      state =
          state.copyWith(errorMessage: e.message, clearLoadingActionId: true);
      return false;
    } catch (e, s) {
      logger.e('Unexpected error during coupon cancel: $e');
      state = state.copyWith(
          errorMessage: '쿠폰 취소 중 오류가 발생했습니다.', clearLoadingActionId: true);
      return false;
    }
  }

  Future<bool> cancelStamp(String rewardId) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(
          errorMessage: '매장 ID를 찾을 수 없습니다.', clearSuccessMessage: true);
      return false;
    }
    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );

    try {
      final success = await _apiService.cancelStamp(rewardId);
      if (success) {
        logger.i('스탬프 적립 취소 성공: $rewardId');
        state = state.copyWith(
          successMessage: '스탬프 적립이 취소되었습니다.',
          isLoading: false,
        );
        final userId =
            state.customerPhone; // Using customerPhone as userId for now
        if (userId.isNotEmpty) {
          await search(userId); // Refresh data
        }
        return true;
      } else {
        logger.w('스탬프 적립 취소 실패: $rewardId');
        state = state.copyWith(
          errorMessage: '스탬프 적립 취소에 실패했습니다.',
          isLoading: false,
        );
        return false;
      }
    } on ApiException catch (e) {
      logger.e('API Exception during cancelStamp: ${e.message}');
      state = state.copyWith(errorMessage: e.message, isLoading: false);
      return false;
    } catch (e, s) {
      logger.e('Unexpected error during cancelStamp: $e');
      state = state.copyWith(
          errorMessage: '스탬프 적립 취소 중 오류가 발생했습니다.', isLoading: false);
      return false;
    }
  }

  // <<< Modify saveStamp method >>>
  Future<bool> saveStamp(String stampCount) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(
          errorMessage: '매장 ID를 찾을 수 없습니다.', clearSuccessMessage: true);
      return false;
    }
    final userId = state.customerPhone;
    if (userId.isEmpty) {
      state = state.copyWith(
          errorMessage: '회원 정보를 먼저 조회해주세요.', clearSuccessMessage: true);
      return false;
    }

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );

    try {
      final stampCountInt = int.tryParse(stampCount) ?? 0;
      final orderId = 'MANUAL_${DateTime.now().millisecondsSinceEpoch}';
      final success =
          await _apiService.earnStamp(userId, _storeId, orderId, stampCountInt);
      if (success) {
        logger.i('스탬프 적립 성공: $stampCount 개 for $userId');
        state = state.copyWith(
          successMessage: '$stampCount 개의 스탬프가 적립되었습니다.',
          isLoading: false,
        );
        await search(userId); // Refresh data
        return true;
      } else {
        logger.w('스탬프 적립 실패 for $userId');
        state = state.copyWith(
          errorMessage: '스탬프 적립에 실패했습니다.',
          isLoading: false,
        );
        return false;
      }
    } on ApiException catch (e) {
      logger.e('API Exception during saveStamp: ${e.message}');
      state = state.copyWith(
        errorMessage: e.message,
        isLoading: false,
      );
      return false;
    } catch (e, s) {
      logger.e('Unexpected error during saveStamp: $e');
      state = state.copyWith(
        errorMessage: '스탬프 적립 중 오류가 발생했습니다.',
        isLoading: false,
      );
      return false;
    }
  }

  Future<bool> cancelSavedStamp(String rewardId) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(errorMessage: '매장 ID를 찾을 수 없습니다.');
      return false;
    }
    final userId = state.customerPhone;
    if (userId.isEmpty) {
      state = state.copyWith(errorMessage: '회원 정보를 먼저 조회해주세요.');
      return false;
    }

    state = state.copyWith(
        loadingActionId: rewardId,
        clearErrorMessage: true,
        clearSuccessMessage: true);
    try {
      final success = await _apiService.cancelStamp(rewardId);
      if (success) {
        state = state.copyWith(
            successMessage: '스탬프 적립 취소가 완료되었습니다.', clearLoadingActionId: true);
        await search(userId);
        return true;
      } else {
        state = state.copyWith(
            errorMessage: '스탬프 취소에 실패했습니다.', clearLoadingActionId: true);
        return false;
      }
    } catch (e, s) {
      state = state.copyWith(
          errorMessage: '스탬프 취소 중 오류가 발생했습니다.', clearLoadingActionId: true);
      return false;
    }
  }

  // --- Pagination & Other UI Helpers ---
  void setStampHistoryPage(int page) {
    state = state.copyWith(stampHistoryCurrentPage: page);
  }

  void setCouponHistoryPage(int page) {
    state = state.copyWith(couponHistoryCurrentPage: page);
  }

  void setAvailableCouponsPage(int page) {
    state = state.copyWith(availableCouponsCurrentPage: page);
  }

  Future<Map<String, dynamic>?> validateCoupon(String couponNo) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(errorMessage: '매장 ID를 찾을 수 없습니다.');
      return null;
    }

    state = state.copyWith(
        isLoading: true, clearErrorMessage: true, clearSuccessMessage: true);

    try {
      // NOTE: items는 현재 비어있는 리스트로 전달 (AGENT에서 단순 조회 용도)
      // 실제 주문 시에는 주문 내역의 items가 포함되어야 함
      final couponData = await _apiService.validateCoupon(
        couponNo,
        _storeId,
        items: [],
      );
      state = state.copyWith(isLoading: false);
      return couponData;
    } catch (e, s) {
      logger.e('쿠폰 검증 중 오류 발생', error: e, stackTrace: s);
      state = state.copyWith(
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
        isLoading: false,
      );
      return null;
    }
  }

  void clearError() {
    state = state.copyWith(clearErrorMessage: true);
  }

  void clearSuccessMessage() {
    state = state.copyWith(clearSuccessMessage: true);
  }

  void clearMessages() {
    state = state.copyWith(clearErrorMessage: true, clearSuccessMessage: true);
  }

  void clearMembership() {
    state = MembershipState(rewardType: state.rewardType);
  }

  // useCouponDirectly removed as useCouponWithoutUserID was unimplemented and deleted.
}
