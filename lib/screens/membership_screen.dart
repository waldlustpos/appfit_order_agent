import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appfit_order_agent/widgets/common/app_loading_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
          message: '바코드 스캔 결과: ${CommonUtil.maskTail(scanResult)}',
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

      if (previous?.customerName != next.customerName ||
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
                      : customerName.isEmpty
                          ? t.membership.customer.status_none
                          : t.membership.customer.honorific(name: customerName),
                  style: AppTextStyles.titleSm
                      .copyWith(color: AppStyles.kMainColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.s8),
                child: Text(
                  isLoading || customerName.isEmpty
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
      final customerName =
          ref.watch(membershipProvider.select((s) => s.customerName));
      if (customerName.isNotEmpty) {
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
        final isCustomerSearched = customerName.isNotEmpty;
        final hintText = isCustomerSearched
            ? t.membership.search.hint_searched
            : t.membership.search.hint;

        return TextField(
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
          keyboardType:
              isCustomerSearched ? TextInputType.number : TextInputType.none,
          decoration: AppStyles.outlinedInputDecoration(
            hintText: hintText,
            hintStyle: AppTextStyles.body.copyWith(color: AppStyles.gray6),
          ).copyWith(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s16,
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeypadAndButtons() {
    return Column(
      children: [
        Expanded(
          child: NumericKeypadWidget(
            onKeyPressed: _onKeypadPressed,
            onClear: _onClearPressed,
            onDelete: _onDeletePressed,
            clearLabel: t.membership.keypad.clear,
            deleteLabel: t.membership.keypad.delete,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _inputController,
          builder: (context, textValue, child) {
            final membershipState = ref.watch(membershipProvider);
            final isLoading = membershipState.isLoading;
            final customerName = membershipState.customerName;
            final inputText = textValue.text;
            final isCustomerSearched = customerName.isNotEmpty;
            final hasInput = inputText.isNotEmpty;

            // 회원이 이미 조회된 상태: 스탬프 적립 단일 버튼(가로 full-width).
            if (isCustomerSearched) {
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

            // 회원 미조회 상태: 자동 판정 없이 [회원조회]/[쿠폰사용] 을 모두 노출하고
            // 입력이 있으면 둘 다 활성화한다(사용자가 명시 선택). Sunmi 내장 스캐너가
            // 있으면 위에 [바코드 스캔] 트리거를 둔다.
            // 바코드 스캔 버튼 노출: Android Sunmi 내장 스캐너 또는 Windows 토스프런트(waldpos).
            final hasScanner =
                (ref.watch(hasBuiltinScannerProvider).valueOrNull ?? false) ||
                    ref.watch(waldposScanAvailableProvider);
            final isScanning = ref.watch(waldposScanProvider).isScanning;
            final actionEnabled = !isLoading && hasInput;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasScanner) ...[
                  SizedBox(
                    width: double.infinity,
                    child:
                        _scanTriggerButton(enabled: !isLoading && !isScanning),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _primaryActionButton(
                        label: t.membership.search.btn_search,
                        icon: Icons.search,
                        color: AppStyles.kMainColor,
                        onPressed: actionEnabled ? _searchMembership : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
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
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: isLoading || isLoadingHistory
                  ? const Center(child: AppLoadingIndicator(size: 32))
                  : TabBarView(children: [
                      _buildStampHistoryTab(),
                      _buildCouponHistoryTab(),
                      _buildAvailableCouponsTab(),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      indicatorPadding: const EdgeInsets.only(bottom: 4),
      dividerColor: Colors.transparent,
      isScrollable: false,
      labelColor: AppStyles.gray9,
      unselectedLabelColor: AppStyles.gray6,
      indicatorColor: AppStyles.kMainColor,
      tabs: [
        _tab(t.membership.tabs.stamps),
        _tab(t.membership.tabs.coupons),
        _tab(t.membership.tabs.available),
      ],
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

    return MembershipHistoryList<StampInfo>(
      items: items,
      hasMore: hasMore,
      onLoadMore: () =>
          ref.read(membershipProvider.notifier).loadMoreStampHistory(),
      emptyIcon: Icons.stars_outlined,
      emptyMessage: t.membership.history.no_stamps,
      itemBuilder: (_, stamp, __) => StampHistoryCard(
        stamp: stamp,
        isLoading: loadingActionId == stamp.seq,
        onCancel: () => _cancelSavedStamp(stamp),
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

  void _onKeypadPressed(String value) {
    final currentText = _inputController.text;

    final customerName =
        ref.read(membershipProvider.select((state) => state.customerName));
    final rewardType =
        ref.read(membershipProvider.select((state) => state.rewardType));
    final isCustomerSearched = customerName.isNotEmpty;

    if (isCustomerSearched && currentText.isEmpty && value == '0') {
      return;
    }

    if (isCustomerSearched &&
        rewardType == 'STAMP' &&
        currentText.length >= 2) {
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
  /// stamp-mode 규칙(선행 0 거부·2자리 제한)이 동일하게 적용된다.
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    // KeyDownEvent 만 처리(KeyRepeat/KeyUp 무시) → 키 홀드/스캐너 중복 입력 방지.
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isLoading =
        ref.read(membershipProvider.select((state) => state.isLoading));
    final key = event.logicalKey;

    // Enter / NumpadEnter → 무동작. 자동 제출하지 않고(스캐너 종단 Enter 포함)
    // 입력란 값은 그대로 둔 채 사용자가 버튼으로 조작한다. handled 로 소비해
    // 기본 동작·미처리 비프음만 막는다.
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.handled;
    }

    // Backspace → 마지막 글자 삭제.
    if (key == LogicalKeyboardKey.backspace) {
      if (!isLoading) _onDeletePressed();
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
    logToFile(
        tag: LogTag.API,
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
      // 회원바코드는 뒤 4자리만 노출하여 마스킹(쿠폰번호는 정책상 원문 유지).
      logToFile(
          tag: LogTag.UI_ACTION,
          message: 'waldpos 스캔 결과: ${CommonUtil.maskTail(result.barcode)}');
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
      // 회원이 조회돼 있으면(예: 스캔 시) 그 id 로 사용 후 내역을 갱신하고,
      // 없으면(키패드/스캔 직접 입력) 익명으로 사용한다.
      final membership = ref.read(membershipProvider).membershipInfo;
      final success = await ref
          .read(membershipProvider.notifier)
          .useCoupon(membership?.id ?? '', couponCode);
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
    if (stamp.rewardId.isEmpty || stamp.seq.isEmpty) {
      logger.w(
          'Cannot cancel stamp: rewardId or seq is empty for stamp at ${stamp.logDate}');
      CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error,
          content: t.membership.dialog.store_info_missing);
      return;
    }

    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            'Cancel Saved Stamp button pressed. Reward ID: ${stamp.rewardId}, Seq: ${stamp.seq}');

    final confirmed = await CommonDialog.showConfirmDialog(
      context: context,
      title: t.membership.dialog.cancel_stamp_title,
      content: t.membership.dialog.cancel_stamp_content(
          date: DateFormat('yyyy-MM-dd HH:mm').format(stamp.logDate),
          count: stamp.stampCount.toString()),
    );

    if (confirmed == true && mounted) {
      await ref.read(membershipProvider.notifier).cancelStamp(stamp.rewardId);
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

    if (stampCount > 20) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.input_error_title,
        content: t.membership.dialog.stamp_limit_error,
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
