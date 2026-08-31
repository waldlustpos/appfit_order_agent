import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
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
  final List<StampHistoryEntry> stampHistory;
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

  /// 조회한 번호가 **미가입**(서버 404 `NOT_FOUND_USER`)인지.
  ///
  /// 미가입도 "조회 절차는 끝난" 상태다. 회원 정보만 없을 뿐 [customerPhone]
  /// 에는 조회에 쓴 번호가 그대로 들어 있어서, 적립·쿠폰 API 는 정상 회원과
  /// 똑같이 그 번호로 나간다.
  ///
  /// [customerName] 에 '미가입' 같은 문자열을 넣지 않는 이유: 그 값이
  /// `honorific(name:)` 을 타면 "미가입님"이 되고, 로캘마다 문자열 비교가
  /// 깨진다. 상태는 이 bool 이 정본이다.
  final bool isUnregistered;

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
    this.isUnregistered = false,
  });

  MembershipState copyWith({
    String? customerName,
    String? customerPhone,
    int? stampCount,
    int? couponCount,
    int? totalPoint,
    MembershipInfo? membershipInfo,

    /// [membershipInfo] 를 null 로 되돌린다. `membershipInfo ?? this.membershipInfo`
    /// 로는 지울 수 없어서, A회원 조회 성공 뒤 B번호가 미가입이면 A의 보유쿠폰이
    /// 화면에 그대로 남는다. clearErrorMessage/clearSuccessMessage 와 같은 패턴.
    bool clearMembershipInfo = false,
    List<StampHistoryEntry>? stampHistory,
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
    bool? isUnregistered,
  }) {
    return MembershipState(
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      stampCount: stampCount ?? this.stampCount,
      couponCount: couponCount ?? this.couponCount,
      totalPoint: totalPoint ?? this.totalPoint,
      membershipInfo:
          clearMembershipInfo ? null : membershipInfo ?? this.membershipInfo,
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
      isUnregistered: isUnregistered ?? this.isUnregistered,
    );
  }

  /// 조회 절차가 끝났는지 — 정상 회원이거나 미가입으로 판정된 상태.
  ///
  /// 화면이 "[회원조회] 화면인가, 조회 후 조작 화면인가"를 물을 때 쓰는 단일
  /// 진입점이다. `customerName.isNotEmpty` 만 보면 미가입에서 화면이 조회 전
  /// 상태로 되돌아간다(서버 nickname 이 비어도 '회원' 이 들어가므로 정상
  /// 회원은 항상 non-empty).
  bool get hasSearchedMember => customerName.isNotEmpty || isUnregistered;

  // ─── 무한 스크롤 슬라이딩 윈도우 ──────────────────────────────────────────
  //
  // 서버가 전체 목록을 한 번에 돌려주므로, 클라이언트 측에서 visibleCount 만큼
  // 잘라서 보여주고 스크롤 하단 도달 시 pageSize 씩 늘린다.

  List<StampHistoryEntry> get visibleStampHistory =>
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

  /// 입력한 번호(전화번호 또는 바코드)로 회원을 조회한다.
  ///
  /// 미가입 번호(서버 404 `NOT_FOUND_USER`)는 **실패가 아니다** — 이름 없이
  /// [MembershipState.isUnregistered] 상태로 들어가고 `true` 를 돌려준다.
  /// 그 뒤의 적립·쿠폰 API 는 정상 회원과 똑같이 이 번호로 나간다.
  /// 통신 오류·5xx 는 기존대로 `errorMessage` + `false` 다.
  Future<bool> search(String phone) async {
    if (_storeId.isEmpty) {
      state = state.copyWith(errorMessage: '매장 ID를 찾을 수 없습니다.');
      return false;
    }
    // 빈 식별자로는 조회하지 않는다. 서버는 빈 userSearchNo 에도 404
    // NOT_FOUND_USER 를 주므로, 막지 않으면 customerPhone 이 '' 인 유령
    // 미가입 상태가 만들어진다(cancelCoupon 경로가 빈 userId 로 들어온다).
    if (phone.trim().isEmpty) {
      logger.w('Membership search 건너뜀: 빈 식별자');
      return false;
    }

    // isLoading 을 실제로 세운다. 이전에는 아래 로그 문구만 "Setting isLoading
    // = true" 라고 말하고 대입이 없어서, 조회 중에도 버튼이 잠기지 않았다
    // (`actionEnabled = !isLoading && hasInput`). 두 번 탭하면 두 조회가
    // 교차하고, 늦게 도착한 404 가 성공한 조회를 조용히 '미가입' 으로 덮는다.
    //
    // 메시지는 여기서 지우지 않는다 — saveStamp/useCoupon 이 성공 메시지를 세운
    // 직후 재조회로 이 함수를 부르는데, 여기서 지우면 화면의 ref.listen 이
    // "성공/에러 메시지 없음" 상태를 보고 이미 열려 있는 다이얼로그 위로
    // 하드웨어 키 포커스를 되찾아간다. 정리는 기존대로 성공 경로에서 한다.
    state = state.copyWith(isLoading: true);

    try {
      logger.d('Membership search started. Setting isLoading = true');

      // 1. Fetch User Profile via AppFit API (ApiService now handles encryption)
      final profileResponse = await _apiService.getUserProfile(_storeId, phone);
      final profileData = profileResponse['data'] as Map<String, dynamic>?;

      if (profileData == null) {
        state = state.copyWith(
          errorMessage: '회원 정보를 찾을 수 없습니다.',
          isLoading: false,
          // 조회가 실패했으면 직전 '미가입' 판정도 무효다 — 아래 주석 참고.
          isUnregistered: false,
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
        // 미가입 → 정상회원 전이 복구. 명시하지 않으면 이전 미가입 조회의
        // 플래그가 남아 이름이 있는데도 '미가입' 화면이 뜬다.
        isUnregistered: false,
      );
      // +++ Log state change after membership info fetch +++
      logger.d(
          'Membership info fetched. Setting isLoading = false, isLoadingRewardHistory = true');
      // 조회 버튼의 '결과' 줄이라 클릭 로그와 같은 UI_ACTION 으로 맞춘다.
      // [API] 로 두면 성공 케이스가 파일 화이트리스트를 통과하지 못해, 클릭은
      // 남는데 결과가 없는 반쪽 기록이 된다.
      logToFile(
          tag: LogTag.UI_ACTION, message: '멤버십 정보 조회 성공: $membershipData');

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

      final mergedStampHistory = StampHistoryEntry.mergeAndSort(stampData);
      couponData.sort((a, b) => b.useDate.compareTo(a.useDate));

      state = state.copyWith(
        stampHistory: mergedStampHistory,
        couponHistory: couponData,
        isLoadingRewardHistory: false,
        stampHistoryVisibleCount: MembershipState.pageSize,
        couponHistoryVisibleCount: MembershipState.pageSize,
        availableCouponsVisibleCount: MembershipState.pageSize,
      );
      logger.i(
          'STAMP history fetch success: ${stampData.length} stamps, ${couponData.length} coupons');
      return true; // Search successful
    } on MemberNotFoundException {
      // ⚠️ 반드시 `on ApiException` 보다 **앞**에 있어야 한다. 하위 타입이라
      // 뒤에 두면 절대 도달하지 않고 조용히 에러 다이얼로그로 빠진다.
      _enterUnregistered(phone);
      return true; // 조회 절차 자체는 정상 완료
    } on ApiException catch (e) {
      logger.e('API Exception during membership search: ${e.message}');
      state = state.copyWith(
        errorMessage: e.message,
        isLoading: false,
        isLoadingRewardHistory: false,
        isUnregistered: false,
      );
      return false;
    } catch (e, s) {
      logger.e('Unexpected error during membership search: $e');
      state = state.copyWith(
        errorMessage: '회원 조회 중 알 수 없는 오류가 발생했습니다.',
        isLoading: false,
        isLoadingRewardHistory: false,
        isUnregistered: false,
      );
      return false;
    }
  }

  // ⚠️ 위 실패 3분기가 모두 `isUnregistered: false` 를 세우는 이유:
  //
  //   1) 010-1111 조회 → 404 → 미가입 (customerPhone = 010-1111)
  //   2) 010-2222 조회 → 타임아웃 → 에러 다이얼로그
  //   3) 다이얼로그를 닫으면 입력란만 지워지고, 되돌리지 않으면 화면은 여전히
  //      '미가입' + [스탬프 적립] 이며 customerPhone 은 010-1111 이다
  //   4) 점주가 개수를 넣고 적립 → **010-1111 에게 적립된다**
  //
  // 정상 회원일 때는 이름이 떠 있어 점주가 알아채지만, '미가입' 라벨은 어느
  // 번호든 글자가 똑같아 식별 정보가 0이다. 조회가 실패했으면 "이 번호가
  // 미가입"이라는 판정 자체가 성립하지 않으므로 조회 전 상태로 되돌린다
  // ([스탬프 적립] 버튼이 사라져 오적립 경로가 끊긴다).

  /// 미가입 번호로 조회가 끝났을 때의 상태 전이.
  ///
  /// 다이얼로그를 띄우지 않는다 — 미가입은 장애가 아니라 정상 운영 상황이고,
  /// 점주는 이름란의 '미가입 (…뒤4자리)' 표시만 보고 바로 적립/쿠폰 조작으로
  /// 넘어간다.
  ///
  /// ## 이 화면이 미가입을 접수하는 근거 (서버 정책)
  ///
  /// **서버가 미가입 번호의 스탬프 적립을 받아주고, 그 과정에서 회원을 내부적
  /// 으로 가입시킨다** — 매머드 **1차 브랜드**(매머드커피, 그룹 ID 는
  /// `MembershipConfig.shopGroupMammothCoffee`) 기준으로 확인된 정책이다.
  /// 그래서 적립 직후의 재조회(`saveStamp` → `search`)는 404 가 아니라 정상
  /// 회원으로 응답하고, 화면은 `isUnregistered: false` 로 자연히 복귀한다.
  ///
  /// **브랜드로 막지 않는다(의도).** 정책 확인은 1차 브랜드에서 됐지만, 스탬프
  /// 운영 매장이면 어디서든 이 흐름을 쓸 수 있게 열어 두고 관찰한다 —
  /// `MembershipConfig` 의 설계 철학(기본은 허용, 확인된 것만 제한)과 같은
  /// 방향이고, 다른 브랜드 서버가 거부하더라도 에러 다이얼로그만 뜰 뿐 적립은
  /// 일어나지 않기 때문이다(fail-safe). 거부하는 브랜드가 있으면
  /// `BenignApiLogFilter` 가 `/stamp/earn` 의 `NOT_FOUND_USER` 를 일부러
  /// Sentry 에 남겨 두었으므로 알림으로 바로 드러난다. 그때 브랜드 게이트를
  /// 검토한다.
  ///
  /// ## 내역 2종(스탬프·쿠폰)을 호출하지 않는 이유
  ///
  /// 처음에는 "서버가 과거 이력을 갖고 있을 수 있다"고 보고 태웠는데, 실기기
  /// 로그가 그 가정을 반증했다 — `/v0/stamps/history` 와 `/v0/coupons/history`
  /// 도 프로필과 **똑같이** `404 NOT_FOUND_USER` 를 준다. 유저 단위 판정이라
  /// 번호가 달라도 결과가 같으므로 성공할 수 없는 호출이고, 조회 1건당 왕복
  /// 2회와 404 2건이 순수 낭비였다. 매장 네트워크가 열화된 환경에서는 이 왕복
  /// 자체가 비용이다.
  ///
  /// 건너뛰어도 이력이 유실되지 않는 것은 위 자동가입 정책 덕이다. 적립하면
  /// 회원이 생기고, 그 다음 조회부터는 정상 경로가 내역을 가져온다.
  void _enterUnregistered(String phone) {
    // 이전 회원의 잔재를 확실히 끊는다. clearMembershipInfo 가 없으면 A회원
    // 조회 성공 뒤 B번호가 미가입일 때 A의 보유쿠폰이 그대로 남는다.
    state = state.copyWith(
      isUnregistered: true,
      customerName: '',
      customerPhone: phone,
      stampCount: 0,
      couponCount: 0,
      totalPoint: 0,
      clearMembershipInfo: true,
      stampHistory: const [],
      couponHistory: const [],
      isLoading: false,
      // 내역 호출을 건너뛰므로 로딩 상태로 두지 않는다. true 로 두면 우측
      // 카드 스피너가 영원히 돌아간다.
      isLoadingRewardHistory: false,
      // 성공 경로(위)와 대칭 — 직전 액션의 메시지를 그대로 물려받지 않는다.
      clearErrorMessage: true,
      clearSuccessMessage: true,
      stampHistoryVisibleCount: MembershipState.pageSize,
      couponHistoryVisibleCount: MembershipState.pageSize,
      availableCouponsVisibleCount: MembershipState.pageSize,
    );
    // 전화번호는 마스킹(로그 파일은 Slack/로그서버로 기기 밖에 나간다).
    logToFile(
      tag: LogTag.UI_ACTION,
      message: '멤버십 조회 — 미가입 번호: ${CommonUtil.maskTail(phone)}',
    );
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
        // 회원 컨텍스트가 있을 때만 내역을 갱신한다. 키패드/스캔으로 쿠폰번호만
        // 입력하는 직접 사용(익명)은 조회할 회원이 없고, 빈 userId 로 search 하면
        // "회원 정보를 찾을 수 없습니다" 에러가 방금 띄운 성공 메시지를 덮어쓴다.
        if (userId.isNotEmpty) {
          await search(userId); // Refresh data
        }
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
        logger.i('스탬프 적립 성공: $stampCount 개 for ${CommonUtil.maskTail(userId)}');
        state = state.copyWith(
          successMessage: '$stampCount 개의 스탬프가 적립되었습니다.',
          isLoading: false,
        );
        await search(userId); // Refresh data
        return true;
      } else {
        logger.w('스탬프 적립 실패 for ${CommonUtil.maskTail(userId)}');
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
