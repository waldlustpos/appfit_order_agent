import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/exceptions/api_exceptions.dart';

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
  final int stampHistoryVisibleCount;
  final int couponHistoryVisibleCount;
  final int availableCouponsVisibleCount;
  final String? loadingActionId;
  final String? rewardType;

  /// 무한 스크롤 페이지 단위.
  static const int pageSize = 20;

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
    this.stampHistoryVisibleCount = pageSize,
    this.couponHistoryVisibleCount = pageSize,
    this.availableCouponsVisibleCount = pageSize,
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
    int? stampHistoryVisibleCount,
    int? couponHistoryVisibleCount,
    int? availableCouponsVisibleCount,
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
      successMessage:
          clearSuccessMessage ? null : successMessage ?? this.successMessage,
      stampHistoryVisibleCount:
          stampHistoryVisibleCount ?? this.stampHistoryVisibleCount,
      couponHistoryVisibleCount:
          couponHistoryVisibleCount ?? this.couponHistoryVisibleCount,
      availableCouponsVisibleCount:
          availableCouponsVisibleCount ?? this.availableCouponsVisibleCount,
      loadingActionId:
          clearLoadingActionId ? null : loadingActionId ?? this.loadingActionId,
      rewardType: rewardType ?? this.rewardType,
    );
  }

  // ─── 무한 스크롤 슬라이딩 윈도우 ──────────────────────────────────────────
  //
  // 서버가 전체 목록을 한 번에 돌려주므로, 클라이언트 측에서 visibleCount 만큼
  // 잘라서 보여주고 스크롤 하단 도달 시 pageSize 씩 늘린다.

  List<StampInfo> get visibleStampHistory =>
      stampHistory.take(stampHistoryVisibleCount).toList();
  bool get hasMoreStampHistory =>
      stampHistoryVisibleCount < stampHistory.length;

  List<CouponHistoryInfo> get visibleCouponHistory =>
      couponHistory.take(couponHistoryVisibleCount).toList();
  bool get hasMoreCouponHistory =>
      couponHistoryVisibleCount < couponHistory.length;

  List<CouponInfo> get visibleAvailableCoupons =>
      (membershipInfo?.coupons ?? [])
          .take(availableCouponsVisibleCount)
          .toList();
  bool get hasMoreAvailableCoupons =>
      availableCouponsVisibleCount < (membershipInfo?.coupons.length ?? 0);
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
      // 두 API 모두 ApiService 내부에서 slice.last까지 페이지를 순회하며
      // 누적된 List를 반환한다(pageSize 500).
      logger.i('Fetching STAMP & COUPON history...');

      final results = await Future.wait([
        _apiService.getStampHistory(phone, _storeId),
        _apiService.getCouponHistory(_storeId, phone),
      ]);

      final stampData = results[0] as List<StampInfo>;
      final couponData = results[1] as List<CouponHistoryInfo>;

      stampData.sort((a, b) => b.logDate.compareTo(a.logDate));
      couponData.sort((a, b) => b.useDate.compareTo(a.useDate));

      state = state.copyWith(
        stampHistory: stampData,
        couponHistory: couponData,
        isLoadingRewardHistory: false,
        stampHistoryVisibleCount: MembershipState.pageSize,
        couponHistoryVisibleCount: MembershipState.pageSize,
        availableCouponsVisibleCount: MembershipState.pageSize,
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
      final successData = await _apiService.useCoupon(couponId, _storeId);
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

  // --- 무한 스크롤 ---
  void loadMoreStampHistory() {
    if (!state.hasMoreStampHistory) return;
    state = state.copyWith(
      stampHistoryVisibleCount:
          state.stampHistoryVisibleCount + MembershipState.pageSize,
    );
  }

  void loadMoreCouponHistory() {
    if (!state.hasMoreCouponHistory) return;
    state = state.copyWith(
      couponHistoryVisibleCount:
          state.couponHistoryVisibleCount + MembershipState.pageSize,
    );
  }

  void loadMoreAvailableCoupons() {
    if (!state.hasMoreAvailableCoupons) return;
    state = state.copyWith(
      availableCouponsVisibleCount:
          state.availableCouponsVisibleCount + MembershipState.pageSize,
    );
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
