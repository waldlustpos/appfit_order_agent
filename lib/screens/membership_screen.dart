import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appfit_order_agent/widgets/common/app_loading_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/config/membership_config.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:appfit_order_agent/utils/common_util.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/widgets/membership/numeric_keypad_widget.dart';
import 'package:appfit_order_agent/widgets/membership/membership_history_list.dart';
import 'package:appfit_order_agent/widgets/membership/stamp_history_card.dart';
import 'package:appfit_order_agent/widgets/membership/coupon_history_card.dart';
import 'package:appfit_order_agent/widgets/membership/available_coupon_card.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  /// 외부 물리 키보드 / HID 키보드 모드 바코드 스캐너 입력을 가로채는 포커스 노드.
  /// 입력 필드(_inputFocusNode)는 canRequestFocus:false 로 두고, 화면 전체를 감싼
  /// Focus 가 primary focus 를 유지하며 하드웨어 키 이벤트를 직접 처리한다.
  final FocusNode _keyboardFocusNode =
      FocusNode(debugLabel: 'membershipHardwareKeys');

  /// 하드웨어 키 입력에서 허용할 한 자리 숫자.
  static final RegExp _digit = RegExp(r'^[0-9]$');

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
    // 첫 프레임 이후 하드웨어 키 캡처 노드에 포커스를 확보한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onQRScanResult') {
        final String scanResult = call.arguments as String;
        logToFile(
          tag: LogTag.UI_ACTION,
          // 회원바코드는 원문 유지 — 주문 상세 로그의 `회원바코드:` 와 같은 키로
          // 맞대조해야 스캔→조회→주문 경로를 추적할 수 있다.
          message: '바코드 스캔 결과: $scanResult',
        );
        // 자동 라우팅하지 않는다. 스캔 결과를 입력란에 채우고, 사용자가
        // [회원조회]/[쿠폰사용] 버튼으로 명시 조작한다.
        _fillInput(scanResult);
      }
      return null;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading =
        ref.watch(membershipProvider.select((state) => state.isLoading));

    logger.d('MembershipScreen build triggered. isLoading: $isLoading');

    ref.listen<MembershipState>(membershipProvider, (previous, next) {
      if (!mounted) return;

      final prevErrorMessage = previous?.errorMessage;
      final prevSuccessMessage = previous?.successMessage;

      bool shouldRefocus = false;
      if (previous?.isLoading == true &&
          next.isLoading == false &&
          next.errorMessage == null &&
          next.successMessage == null &&
          prevErrorMessage == null &&
          prevSuccessMessage == null) {
        shouldRefocus = true;
      } else if (previous?.loadingActionId != null &&
          next.loadingActionId == null &&
          next.errorMessage == null &&
          next.successMessage == null &&
          prevErrorMessage == null &&
          prevSuccessMessage == null) {
        shouldRefocus = true;
      } else if (previous?.customerName != next.customerName ||
          previous?.isUnregistered != next.isUnregistered ||
          previous?.rewardType != next.rewardType) {
        if (_inputController.text.isEmpty) {
          shouldRefocus = true;
        }
      }

      if (shouldRefocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FocusScope.of(context).requestFocus(_keyboardFocusNode);
            logger.d('Refocus requested after state change (no dialog)');
          }
        });
      }

      if (next.errorMessage != null &&
          next.errorMessage!.isNotEmpty &&
          next.errorMessage != prevErrorMessage) {
        CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error,
          content: next.errorMessage!,
        ).then((_) {
          if (context.mounted) {
            ref.read(membershipProvider.notifier).clearError();
            _inputController.clear();
            FocusScope.of(context).requestFocus(_keyboardFocusNode);
            logger.d('Error dialog dismissed, input cleared, focus requested.');
          }
        });
      } else if (next.successMessage != null &&
          next.successMessage!.isNotEmpty &&
          next.successMessage != prevSuccessMessage) {
        CommonDialog.showInfoDialog(
          context: context,
          title: t.membership.dialog.processing_complete,
          content: next.successMessage!,
        ).then((_) {
          if (context.mounted) {
            ref.read(membershipProvider.notifier).clearSuccessMessage();
            FocusScope.of(context).requestFocus(_keyboardFocusNode);
            logger.d('Success dialog dismissed, focus requested.');
          }
        });
      }

      // isUnregistered 도 함께 본다 — 미가입 진입은 customerName 이 '' 그대로라
      // 이름 비교만으로는 변화가 감지되지 않고, 조회에 쓴 전화번호가 입력란에
      // 남은 채로 적립 화면이 뜬다.
      if (previous?.customerName != next.customerName ||
          previous?.isUnregistered != next.isUnregistered ||
          previous?.rewardType != next.rewardType) {
        _inputController.clear();
        logger.d('Input cleared due to customer change.');
      }
    });

    // 화면 전체를 Focus 로 감싸 외부 키보드/HID 스캐너의 하드웨어 키를 직접 가로챈다.
    // onKeyEvent 가 KeyEventResult 를 반환하므로 처리한 키(숫자/Enter/Backspace)를
    // handled 로 소비해 기본 동작·미처리 비프음을 막는다.
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: Scaffold(
        body: ColoredBox(
          color: AppStyles.gray1,
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: _buildLeftCard(),
              ),
              Expanded(
                flex: 2,
                child: _buildRightCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 좌측 카드 ────────────────────────────────────────────────────────────

  Widget _buildLeftCard() {
    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.s12,
        top: AppSpacing.s4,
        bottom: AppSpacing.s4,
        right: AppSpacing.s4,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerInfoDisplay(),
            _buildOtherMemberButton(),
            const SizedBox(height: AppSpacing.s20),
            _buildInputField(),
            const SizedBox(height: AppSpacing.s32),
            Expanded(child: _buildKeypadAndButtons()),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfoDisplay() {
    final customerName =
        ref.watch(membershipProvider.select((state) => state.customerName));
    final stampCount =
        ref.watch(membershipProvider.select((state) => state.stampCount));
    final couponCount =
        ref.watch(membershipProvider.select((state) => state.couponCount));
    final isLoading =
        ref.watch(membershipProvider.select((state) => state.isLoading));
    final isUnregistered =
        ref.watch(membershipProvider.select((state) => state.isUnregistered));
    // 미가입 라벨은 어느 번호든 글자가 같아 식별 정보가 0이다. 조회에 쓴
    // 식별자의 뒤 4자리를 함께 찍어, 점주가 지금 누구에게 적립하려는지 화면에서
    // 확인할 수 있게 한다. 식별자는 전화번호일 수도 바코드일 수도 있어서
    // 전화번호 전용 포맷 대신 식별자 무관인 maskTail 을 쓴다.
    final customerPhone =
        ref.watch(membershipProvider.select((state) => state.customerPhone));

    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Opacity(
          opacity: isLoading ? 0.0 : 1.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  isLoading
                      ? ' '
                      : isUnregistered
                          ? (customerPhone.isEmpty
                              ? t.membership.customer.status_unregistered
                              : t.membership.customer
                                  .status_unregistered_with_id(
                                      id: CommonUtil.maskTail(customerPhone)))
                          : customerName.isEmpty
                              ? t.membership.customer.status_none
                              : t.membership.customer
                                  .honorific(name: customerName),
                  style: AppTextStyles.titleSm
                      .copyWith(color: AppStyles.kMainColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.s8),
                child: Text(
                  // 미가입은 요약을 비운다 — "미가입  스탬프 0 | 쿠폰 0" 은
                  // 정보가 없으면서 가입 회원처럼 읽힌다.
                  //
                  // 스탬프 개수는 적립 차단 매장에서도 그대로 보여준다. 회원은
                  // 브랜드를 넘나들며 같은 계정을 쓰므로, 여기서 적립만 못 할 뿐
                  // 보유 개수는 안내해야 할 정보다(스탬프내역 탭과 같은 이유).
                  isLoading || isUnregistered || customerName.isEmpty
                      ? ' '
                      : t.membership.customer.summary(
                          stamps: stampCount.toString(),
                          coupons: couponCount.toString()),
                  style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtherMemberButton() {
    return Consumer(builder: (context, ref, _) {
      // 미가입 상태에서도 노출한다 — 다른 번호로 넘어갈 유일한 출구다.
      final hasSearched =
          ref.watch(membershipProvider.select((s) => s.hasSearchedMember));
      if (hasSearched) {
        return SizedBox(
          height: 34,
          child: Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(
                t.membership.search.btn_other_member,
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                logToFile(
                    tag: LogTag.UI_ACTION,
                    message: 'Clear membership button pressed.');
                ref.read(membershipProvider.notifier).clearMembership();
                _inputController.clear();
                FocusScope.of(context).requestFocus(_keyboardFocusNode);
              },
              style: AppStyles.outlinedButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                ),
                minimumSize: const Size(0, 34),
              ).copyWith(
                foregroundColor: const WidgetStatePropertyAll(AppStyles.gray6),
                iconColor: const WidgetStatePropertyAll(AppStyles.gray6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        );
      }
      return const SizedBox(height: 34);
    });
  }

  Widget _buildInputField() {
    return Consumer(
      builder: (context, ref, _) {
        final customerName =
            ref.watch(membershipProvider.select((s) => s.customerName));
        final isUnregistered =
            ref.watch(membershipProvider.select((s) => s.isUnregistered));
        final stampAccrualEnabled = ref.watch(stampAccrualEnabledProvider);
        final isCustomerSearched = customerName.isNotEmpty;
        // 스탬프 미운영 매장에서는 회원 조회 후 입력란이 할 일이 없다.
        // "스탬프 개수를 입력해주세요" 안내를 지워 오조작을 유도하지 않는다.
        //
        // 미가입은 입력란이 적립 개수와 쿠폰번호를 겸하므로 전용 안내를 쓴다.
        final hintText = isUnregistered
            ? (stampAccrualEnabled
                ? t.membership.search.hint_unregistered
                : t.membership.dialog.enter_coupon_code)
            : isCustomerSearched
                ? (stampAccrualEnabled
                    ? t.membership.search
                        .hint_searched(max: MembershipConfig.maxStampPerAccrual)
                    : '')
                : t.membership.search.hint;

        return Stack(
          children: [
            TextField(
              style: AppTextStyles.title,
              textAlign: TextAlign.start,
              textAlignVertical: TextAlignVertical.center,
              controller: _inputController,
              focusNode: _inputFocusNode,
              readOnly: true,
              showCursor: true,
              // 화면을 감싼 Focus(_keyboardFocusNode)가 하드웨어 키를 처리하므로
              // 입력 필드는 절대 primary focus 를 가져가지 않게 한다. 이렇게 하면
              // IME 가 열리지 않아 소프트 키보드 차단이 더 견고하다.
              autofocus: false,
              canRequestFocus: false,
              enableInteractiveSelection: false,
              keyboardType: isCustomerSearched
                  ? TextInputType.number
                  : TextInputType.none,
              // hintText 는 InputDecoration 에 맡기지 않는다: 값 스타일(title,
              // 20px)과 힌트 스타일(body, 15px)의 크기가 달라 InputDecorator 가
              // 내부 슬롯을 값 스타일 기준으로 잡고 힌트를 그 안에서 다시 중앙
              // 정렬하면서, Pretendard 의 비대칭 ascent/descent 와 맞물려 힌트가
              // 미세하게 아래로 치우쳐 보이는 문제가 있었다(측정: 1.5px 편차).
              // 아래 Align 오버레이로 직접 그려 필드 박스 기준으로 바로 중앙
              // 정렬한다(측정: 0px 편차).
              decoration: AppStyles.outlinedInputDecoration().copyWith(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s16,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _inputController,
                  builder: (context, value, _) {
                    if (value.text.isNotEmpty || hintText.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s12,
                        ),
                        child: Text(
                          hintText,
                          style: AppTextStyles.body
                              .copyWith(color: AppStyles.gray6),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKeypadAndButtons() {
    final stampAccrualEnabled = ref.watch(stampAccrualEnabledProvider);
    final isCustomerSearchedNow =
        ref.watch(membershipProvider.select((s) => s.customerName.isNotEmpty));
    // 스탬프 미운영 매장 + 회원 조회 완료 = 입력할 것이 없는 상태.
    final inputDisabled = !stampAccrualEnabled && isCustomerSearchedNow;

    return Column(
      children: [
        Expanded(
          child: NumericKeypadWidget(
            onKeyPressed: _onKeypadPressed,
            onClear: _onClearPressed,
            onDelete: _onDeletePressed,
            clearLabel: t.membership.keypad.clear,
            deleteLabel: t.membership.keypad.delete,
            enabled: !inputDisabled,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _inputController,
          builder: (context, textValue, child) {
            final membershipState = ref.watch(membershipProvider);
            final isLoading = membershipState.isLoading;
            final customerName = membershipState.customerName;
            final isUnregistered = membershipState.isUnregistered;
            final inputText = textValue.text;
            final isCustomerSearched = customerName.isNotEmpty;
            final hasInput = inputText.isNotEmpty;

            // 회원이 이미 조회된 상태: 스탬프 적립 단일 버튼(가로 full-width).
            if (isCustomerSearched) {
              // 스탬프 미운영 매장에서는 적립 버튼 자체를 노출하지 않는다.
              if (!stampAccrualEnabled) return const SizedBox.shrink();
              return SizedBox(
                width: double.infinity,
                child: _primaryActionButton(
                  label: t.membership.search.btn_save_stamp,
                  icon: Icons.add_circle_outline,
                  color: AppStyles.kMainColor,
                  onPressed: (!isLoading && hasInput)
                      ? () => _saveStamp(inputText)
                      : null,
                ),
              );
            }

            // 미조회/미가입 공통: 자동 판정 없이 버튼을 모두 노출하고 입력이 있으면
            // 활성화한다(사용자가 명시 선택). Sunmi 내장 스캐너가 있으면 위에
            // [바코드 스캔] 트리거를 둔다.
            // 바코드 스캔 버튼 노출: Android Sunmi 내장 스캐너 또는 Windows 토스프런트(waldpos).
            final hasScanner =
                (ref.watch(hasBuiltinScannerProvider).valueOrNull ?? false) ||
                    ref.watch(waldposScanAvailableProvider);
            final isScanning = ref.watch(waldposScanProvider).isScanning;
            final actionEnabled = !isLoading && hasInput;

            // 미가입은 [회원조회] 자리를 [스탬프 적립]으로 바꾼다 — 이미 조회를
            // 마친 번호라 다시 조회할 일이 없고, 그 번호 그대로 적립해야 한다.
            // 잘못된 값으로 눌러도 기존 가드가 받는다([적립]은 _saveStamp 의
            // 1~10 검증, [쿠폰사용]은 _useCouponDirectly 의 전화번호 차단).
            final leftButton = isUnregistered
                ? _primaryActionButton(
                    label: t.membership.search.btn_save_stamp,
                    icon: Icons.add_circle_outline,
                    color: AppStyles.kMainColor,
                    onPressed:
                        actionEnabled ? () => _saveStamp(inputText) : null,
                  )
                : _primaryActionButton(
                    label: t.membership.search.btn_search,
                    icon: Icons.search,
                    color: AppStyles.kMainColor,
                    onPressed: actionEnabled ? _searchMembership : null,
                  );
            // 스탬프 미운영 매장 + 미가입 = 적립할 것이 없으므로 쿠폰만 남긴다.
            final showLeftButton = !isUnregistered || stampAccrualEnabled;

            // 미가입에서는 스캔 버튼을 감춘다. 스캔은 입력란을 채울 뿐인데
            // 이 상태의 좌측 버튼은 [회원조회]가 아니라 [스탬프 적립]이라,
            // 스캔한 바코드로 조회할 방법이 없다(누르면 개수 검증에 걸린다).
            // 다른 번호/쿠폰을 스캔하려면 [검색 초기화] 로 나간다.
            final showScanner = hasScanner && !isUnregistered;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showScanner) ...[
                  SizedBox(
                    width: double.infinity,
                    child:
                        _scanTriggerButton(enabled: !isLoading && !isScanning),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                ],
                Row(
                  children: [
                    if (showLeftButton) ...[
                      Expanded(child: leftButton),
                      const SizedBox(width: AppSpacing.s8),
                    ],
                    Expanded(
                      child: _primaryActionButton(
                        label: t.membership.search.btn_use_coupon,
                        icon: Icons.sell_outlined,
                        color: AppStyles.kAmber,
                        onPressed: actionEnabled
                            ? () => _useCouponDirectly(inputText)
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 하단 주요 액션 버튼(회원조회/쿠폰사용/스탬프적립) 공통 스타일.
  /// onPressed 가 null 이면 비활성(회색) 표시.
  Widget _primaryActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
      style: AppStyles.primaryButton(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
        elevation: 2,
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? AppStyles.gray3 : color,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppStyles.gray6
              : Colors.white,
        ),
        textStyle: WidgetStatePropertyAll(
          AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// Sunmi 내장 스캐너 트리거 버튼(outlined). 스캔 결과는 입력란만 채운다.
  Widget _scanTriggerButton({required bool enabled}) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.barcode_reader),
      label: Text(t.membership.search.btn_scan),
      onPressed: enabled ? _scanBarcode : null,
      style: AppStyles.outlinedButton(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
        borderColor: AppStyles.gray3,
      ).copyWith(
        textStyle: WidgetStatePropertyAll(
          AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppStyles.gray3
              : Colors.white,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? AppStyles.gray6
              : AppStyles.gray9,
        ),
      ),
    );
  }

  // ─── 우측 카드 ────────────────────────────────────────────────────────────

  Widget _buildRightCard() {
    final isLoading =
        ref.watch(membershipProvider.select((state) => state.isLoading));
    final isLoadingHistory = ref.watch(
        membershipProvider.select((state) => state.isLoadingRewardHistory));

    // 탭 라벨과 뷰를 한 리스트로 묶는다. 두 리터럴을 따로 두면 조건부 노출에서
    // 개수가 어긋나 엉뚱한 탭이 열릴 수 있다.
    //
    // 스탬프내역은 적립 차단 매장에서도 노출한다 — 조회는 아무것도 바꾸지 않고,
    // 2차 브랜드 매장에서도 손님의 스탬프 이력을 확인해줄 수 있어야 한다.
    // 그 탭 안의 [적립취소]만 _buildStampHistoryTab 에서 따로 막는다.
    final tabs = <(String, Widget)>[
      (t.membership.tabs.stamps, _buildStampHistoryTab()),
      (t.membership.tabs.coupons, _buildCouponHistoryTab()),
      (t.membership.tabs.available, _buildAvailableCouponsTab()),
    ];

    return Container(
      margin: const EdgeInsets.only(
        left: AppSpacing.s4,
        top: AppSpacing.s4,
        bottom: AppSpacing.s4,
        right: AppSpacing.s12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.bLg,
        boxShadow: AppElevation.soft,
      ),
      clipBehavior: Clip.antiAlias,
      // DefaultTabController 는 length 변경 시 컨트롤러를 교체하며 index 를
      // clamp 하므로(Flutter tab_controller.dart didUpdateWidget) 별도 key 가
      // 없어도 탭 개수가 줄어드는 전환이 안전하다.
      child: DefaultTabController(
        length: tabs.length,
        child: Column(
          children: [
            _buildTabBar(tabs.map((e) => e.$1).toList()),
            Expanded(
              child: isLoading || isLoadingHistory
                  ? const Center(child: AppLoadingIndicator(size: 32))
                  : TabBarView(
                      children: tabs.map((e) => e.$2).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(List<String> labels) {
    return TabBar(
      indicatorPadding: const EdgeInsets.only(bottom: 4),
      dividerColor: Colors.transparent,
      isScrollable: false,
      labelColor: AppStyles.gray9,
      unselectedLabelColor: AppStyles.gray6,
      indicatorColor: AppStyles.kMainColor,
      tabs: labels.map(_tab).toList(),
    );
  }

  Tab _tab(String label) => Tab(
        height: 48,
        child: Text(
          label,
          style: AppTextStyles.titleSm,
        ),
      );

  // ─── 스탬프내역 탭 ────────────────────────────────────────────────────────

  Widget _buildStampHistoryTab() {
    final items = ref
        .watch(membershipProvider.select((state) => state.visibleStampHistory));
    final hasMore = ref
        .watch(membershipProvider.select((state) => state.hasMoreStampHistory));
    final loadingActionId =
        ref.watch(membershipProvider.select((state) => state.loadingActionId));
    // 적립 차단 매장은 조회 전용이다. 여기 보이는 적립은 전부 1차 브랜드 매장에서
    // 발생한 건이라, 이 단말에서 되돌리게 두면 남의 매장 적립을 취소하게 된다.
    // onCancel 을 null 로 넘기면 카드가 [적립취소] 버튼 자체를 그리지 않는다.
    final canCancel = ref.watch(stampAccrualEnabledProvider);

    return MembershipHistoryList<StampHistoryEntry>(
      items: items,
      hasMore: hasMore,
      onLoadMore: () =>
          ref.read(membershipProvider.notifier).loadMoreStampHistory(),
      emptyIcon: Icons.stars_outlined,
      emptyMessage: t.membership.history.no_stamps,
      itemBuilder: (_, entry, __) => StampHistoryCard(
        entry: entry,
        isLoading: loadingActionId == entry.primary.rewardId,
        onCancel: canCancel ? () => _cancelSavedStamp(entry.primary) : null,
      ),
    );
  }

  // ─── 쿠폰사용내역 탭 ──────────────────────────────────────────────────────

  Widget _buildCouponHistoryTab() {
    final items = ref.watch(
        membershipProvider.select((state) => state.visibleCouponHistory));
    final hasMore = ref.watch(
        membershipProvider.select((state) => state.hasMoreCouponHistory));
    final loadingActionId =
        ref.watch(membershipProvider.select((state) => state.loadingActionId));

    return MembershipHistoryList<CouponHistoryInfo>(
      items: items,
      hasMore: hasMore,
      onLoadMore: () =>
          ref.read(membershipProvider.notifier).loadMoreCouponHistory(),
      emptyIcon: Icons.local_activity_outlined,
      emptyMessage: t.membership.history.no_coupons,
      itemBuilder: (_, coupon, __) => CouponHistoryCard(
        coupon: coupon,
        isLoading: loadingActionId == coupon.couponId,
        onCancelUse: () => _cancelCoupon(coupon),
      ),
    );
  }

  // ─── 보유쿠폰 탭 ──────────────────────────────────────────────────────────

  Widget _buildAvailableCouponsTab() {
    final items = ref.watch(
        membershipProvider.select((state) => state.visibleAvailableCoupons));
    final hasMore = ref.watch(
        membershipProvider.select((state) => state.hasMoreAvailableCoupons));
    final loadingActionId =
        ref.watch(membershipProvider.select((state) => state.loadingActionId));

    return MembershipHistoryList<CouponInfo>(
      items: items,
      hasMore: hasMore,
      onLoadMore: () =>
          ref.read(membershipProvider.notifier).loadMoreAvailableCoupons(),
      emptyIcon: Icons.confirmation_number_outlined,
      emptyMessage: t.membership.history.no_available,
      itemBuilder: (_, coupon, __) => AvailableCouponCard(
        coupon: coupon,
        isLoading: loadingActionId == coupon.couponId,
        onUse: () => _useCoupon(coupon),
      ),
    );
  }

  // ─── 키패드 처리 ──────────────────────────────────────────────────────────

  /// 스탬프 미운영 매장에서 회원 조회가 끝난 상태인지.
  /// 이 상태에서는 입력란에 넣을 값이 없으므로 키패드/하드웨어 키를 모두 막는다.
  bool _isInputDisabled(bool isCustomerSearched) =>
      isCustomerSearched && !ref.read(stampAccrualEnabledProvider);

  void _onKeypadPressed(String value) {
    final currentText = _inputController.text;

    final customerName =
        ref.read(membershipProvider.select((state) => state.customerName));
    final rewardType =
        ref.read(membershipProvider.select((state) => state.rewardType));
    final isCustomerSearched = customerName.isNotEmpty;

    // 스탬프 미운영 매장에서 회원 조회 후에는 입력 자체를 받지 않는다.
    // 키패드는 비활성이지만 이 콜백은 하드웨어 키 경로(_handleKeyEvent)와
    // 공유하므로 여기서도 막는다.
    if (_isInputDisabled(isCustomerSearched)) {
      return;
    }

    if (isCustomerSearched && currentText.isEmpty && value == '0') {
      return;
    }

    // 상한(1회 10개) 초과는 버튼을 누른 뒤 에러로 알리지 않고 입력 단계에서
    // 막는다. 자릿수가 아니라 값으로 판정한다 — "10" 은 받고 "11" 은 막아야 해
    // 자릿수 제한으로는 표현되지 않는다.
    if (isCustomerSearched &&
        rewardType == 'STAMP' &&
        !MembershipConfig.allowsStampDigit(currentText, value)) {
      return;
    }

    _inputController.text = currentText + value;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
  }

  void _onClearPressed() {
    _inputController.clear();
  }

  void _onDeletePressed() {
    final currentText = _inputController.text;
    if (currentText.isNotEmpty) {
      _inputController.text = currentText.substring(0, currentText.length - 1);
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
    }
  }

  /// 스캔 결과를 입력란에 채운다(교체). 자동 제출하지 않으며, 사용자가 버튼으로
  /// 회원조회/쿠폰사용을 선택한다. 하드웨어 키 캡처 포커스를 유지한다.
  void _fillInput(String code) {
    _inputController.text = code;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    if (mounted) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
    }
  }

  // ─── 하드웨어 키 입력(외부 키보드 / HID 스캐너) ────────────────────────────

  /// 화면을 감싼 Focus 의 onKeyEvent 핸들러.
  /// 외부 물리 키보드와 HID 키보드 모드 바코드 스캐너(문자를 빠르게 입력 후 Enter
  /// 전송)의 키를 처리한다. 숫자는 키패드 로직(_onKeypadPressed)을 그대로 재사용해
  /// stamp-mode 규칙(선행 0 거부·상한 초과 거부)이 동일하게 적용된다.
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    // KeyDownEvent 만 처리(KeyRepeat/KeyUp 무시) → 키 홀드/스캐너 중복 입력 방지.
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isLoading =
        ref.read(membershipProvider.select((state) => state.isLoading));
    final key = event.logicalKey;

    // 스탬프 미운영 매장 + 회원 조회 완료: 외부 키보드/HID 스캐너의 숫자·삭제
    // 키를 입력란에 반영하지 않는다. 키패드 위젯만 비활성화하면 이 경로로
    // 여전히 값이 들어간다. 숫자는 _onKeypadPressed 안에서 같은 판정으로
    // 걸러지므로 여기서는 Backspace 만 막으면 된다(둘 다 handled 로 소비해
    // 미처리 비프음 방지). Tab·방향키 등은 기존과 동일하게 통과시킨다.
    final isCustomerSearched =
        ref.read(membershipProvider.select((s) => s.customerName.isNotEmpty));
    final inputDisabled = _isInputDisabled(isCustomerSearched);

    // Enter / NumpadEnter → 무동작. 자동 제출하지 않고(스캐너 종단 Enter 포함)
    // 입력란 값은 그대로 둔 채 사용자가 버튼으로 조작한다. handled 로 소비해
    // 기본 동작·미처리 비프음만 막는다.
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.handled;
    }

    // Backspace → 마지막 글자 삭제.
    if (key == LogicalKeyboardKey.backspace) {
      if (!isLoading && !inputDisabled) _onDeletePressed();
      return KeyEventResult.handled;
    }

    // 숫자: number-row/numpad 둘 다 character 가 '0'..'9' 로 수렴.
    final ch = event.character;
    if (ch != null && ch.length == 1 && _digit.hasMatch(ch)) {
      if (!isLoading) _onKeypadPressed(ch);
      return KeyEventResult.handled;
    }

    // 그 외(Tab, 방향키, 문자, 스캐너 prefix 기호 등)는 통과.
    return KeyEventResult.ignored;
  }

  // ─── 회원 조회 ────────────────────────────────────────────────────────────

  void _searchMembership({String memberId = ''}) async {
    final phoneNumber =
        memberId.isEmpty ? _inputController.text.trim() : memberId.trim();
    // 태그는 UI_ACTION — 이 화면의 다른 버튼(초기화·바코드스캔·쿠폰사용/취소·
    // 스탬프적립/취소)과 같다. LogTag.API 로 두면 logger.d 로 떨어지는데,
    // 파일 화이트리스트의 [API] 분기는 ERROR/실패/오류 를 포함한 줄만 통과시켜서
    // 정상 조회는 콘솔에만 남고 로그파일에는 아예 기록되지 않는다.
    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            'Search membership. Input: ${CommonUtil.maskTail(phoneNumber)}');
    if (phoneNumber.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.membership.dialog.notification),
          content: Text(t.membership.dialog.enter_phone),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.common.confirm),
            ),
          ],
        ),
      );
      return;
    }

    final membershipNotifier = ref.read(membershipProvider.notifier);
    await membershipNotifier.search(phoneNumber);
  }

  void _scanBarcode() async {
    logToFile(tag: LogTag.UI_ACTION, message: '바코드 스캔 버튼 터치');
    // Windows: 토스프런트(waldpos_agent) 스캔 경로. Android 는 기존 Sunmi 경로 유지.
    if (Platform.isWindows) {
      await _scanWaldpos();
      return;
    }
    try {
      await platform.invokeMethod('startQRScan');
    } catch (e) {
      if (mounted) {
        CommonDialog.showInfoDialog(
          context: context,
          title: t.membership.dialog.notification,
          content: t.membership.dialog.scanner_not_supported,
        );
        logToFile(tag: LogTag.ERROR, message: '바코드 스캔 오류: $e');
      }
    }
  }

  /// Windows 토스프런트 스캔: waldpos_agent 로 바코드를 요청하고, 성공 시 입력란에
  /// 채운다(_fillInput). 사용자가 [회원조회]/[쿠폰사용] 버튼으로 명시 조작한다.
  /// UI 는 provider 만 경유한다.
  Future<void> _scanWaldpos() async {
    final result =
        await ref.read(waldposScanProvider.notifier).requestBarcode();
    if (!mounted) return;
    if (result.success && result.barcode.isNotEmpty) {
      // 회원바코드는 원문 유지 — 가명 식별자라 로그 대조 키로 쓴다(쿠폰번호도 원문).
      logToFile(
          tag: LogTag.UI_ACTION, message: 'waldpos 스캔 결과: ${result.barcode}');
      _fillInput(result.barcode);
      return;
    }
    CommonDialog.showInfoDialog(
      context: context,
      title: t.membership.dialog.notification,
      content: result.message.isNotEmpty
          ? result.message
          : t.membership.dialog.scanner_not_supported,
    );
  }

  // ─── 쿠폰 처리 ────────────────────────────────────────────────────────────

  Future<void> _useCouponDirectly(String couponCode) async {
    if (couponCode.isEmpty) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.notification,
        content: t.membership.dialog.enter_coupon_code,
      );
      return;
    }

    // 전화번호를 넣은 채 [쿠폰사용]을 누른 오조작 — 서버에 보내지 않고 여기서 끊는다.
    // 보내면 400 INVALID_REQUEST 가 나는데, 서버 메시지가 입력값을 그대로 되돌려줘서
    // (`Invalid couponNo: 010…`) 그 문구가 Sentry 이슈 제목 → Slack 알림까지 흘러가
    // 고객 전화번호가 노출된다. 로그에도 원문을 남기지 않으려고 마스킹해서 기록한다.
    if (CommonUtil.isLikelyPhoneNumber(couponCode)) {
      logToFile(
          tag: LogTag.UI_ACTION,
          message: '쿠폰사용 버튼 클릭 — 전화번호 오입력으로 차단: '
              '${CommonUtil.maskTail(couponCode)}');
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.notification,
        content: t.membership.dialog.coupon_code_looks_like_phone,
      );
      return;
    }

    logToFile(tag: LogTag.UI_ACTION, message: '쿠폰사용 버튼 클릭: $couponCode');

    final storeId = ref.read(storeProvider).value?.storeId ?? '';
    if (storeId.isEmpty) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.common.error,
        content: t.membership.dialog.store_info_missing,
      );
      return;
    }

    final confirmed = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.membership.dialog.use_coupon_title,
      content: t.membership.dialog.use_coupon_code_content(code: couponCode),
    );

    if (confirmed == true) {
      // use-without-item: 회원 조회 없이 쿠폰번호만으로 사용 처리한다.
      // 조회된 번호가 있으면(정상 회원이든 미가입이든) 그 번호로 내역을 갱신하고,
      // 없으면(키패드/스캔 직접 입력) 익명으로 사용한다.
      //
      // 넘기는 값은 customerPhone(= 조회에 쓴 전화번호/바코드)이다. 예전에는
      // membershipInfo.id(AppFit 내부 UUID)를 넘겼는데, 이 값은 그대로
      // search() → getUserProfile 의 userSearchNo 로 들어가서 조회가 실패했다.
      // 같은 재조회를 하는 _useCoupon/_cancelCoupon 은 원래 customerPhone 을
      // 쓰고 있었다 — 이쪽만 어긋나 있던 것.
      final phone = ref.read(membershipProvider).customerPhone;
      final success = await ref
          .read(membershipProvider.notifier)
          .useCoupon(phone, couponCode);
      if (success && mounted) {
        _inputController.clear();
      }
    }
  }

  Future<void> _cancelCoupon(CouponHistoryInfo coupon) async {
    logToFile(
        tag: LogTag.UI_ACTION,
        message: 'Cancel Coupon button pressed. Coupon ID: ${coupon.couponId}');

    final confirmed = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.membership.dialog.cancel_coupon_title,
      content: t.membership.dialog.cancel_coupon_content(title: coupon.title),
    );

    if (confirmed == true) {
      final phone = ref.read(membershipProvider).customerPhone;
      await ref
          .read(membershipProvider.notifier)
          .cancelCoupon(phone, coupon.couponId);
    }
  }

  Future<void> _useCoupon(CouponInfo coupon) async {
    logToFile(
        tag: LogTag.UI_ACTION,
        message: 'Use Coupon button pressed. Coupon ID: ${coupon.couponId}');

    final confirmed = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.membership.dialog.use_coupon_title,
      content:
          t.membership.dialog.use_coupon_content(title: coupon.couponTitle),
    );

    final phone = ref.read(membershipProvider).customerPhone;
    if (confirmed == true) {
      await ref
          .read(membershipProvider.notifier)
          .useCoupon(phone, coupon.couponId);
    }
  }

  // ─── 스탬프 처리 ──────────────────────────────────────────────────────────

  Future<void> _cancelSavedStamp(StampInfo stamp) async {
    if (stamp.rewardId.isEmpty) {
      logger.w(
          'Cannot cancel stamp: rewardId is empty for stamp at ${stamp.logDate}');
      CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error,
          content: t.membership.dialog.store_info_missing);
      return;
    }

    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            'Cancel Saved Stamp button pressed. Reward ID: ${stamp.rewardId}');

    final confirmed = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.membership.dialog.cancel_stamp_title,
      content: t.membership.dialog.cancel_stamp_content(
          date: DateFormat('yyyy-MM-dd HH:mm').format(stamp.logDate),
          count: stamp.stampCount.toString()),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(membershipProvider.notifier)
          .cancelSavedStamp(stamp.rewardId);
    }
  }

  Future<void> _saveStamp(String stampCountStr) async {
    final stampCount = int.tryParse(stampCountStr);
    logToFile(tag: LogTag.UI_ACTION, message: '스탬프 적립 버튼 클릭: $stampCount 개');

    if (stampCount == null || stampCount <= 0) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.input_error_title,
        content: t.membership.dialog.stamp_input_error,
      );
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
      return;
    }

    if (stampCount > MembershipConfig.maxStampPerAccrual) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.input_error_title,
        content: t.membership.dialog.stamp_limit_error(
          max: MembershipConfig.maxStampPerAccrual,
        ),
      );
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
      return;
    }

    FocusScope.of(context).unfocus();

    final success =
        await ref.read(membershipProvider.notifier).saveStamp(stampCountStr);

    if (success && mounted) {
      _inputController.clear();
    } else if (!success && mounted) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
    }
  }
}
