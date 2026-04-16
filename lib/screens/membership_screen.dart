import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/common/app_loading_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import '../services/platform_service.dart';
import '../constants/app_styles.dart';
import '../widgets/membership/numeric_keypad_widget.dart';
import '../widgets/membership/membership_history_table.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  ButtonStyle get _actionButtonStyle => AppStyles.outlinedPrimaryButton(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        minimumSize: const Size(80, 36),
      ).copyWith(
        textStyle: WidgetStatePropertyAll(
          AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w600),
        ),
      );

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onQRScanResult') {
        String scanResult = call.arguments;
        logToFile(
          tag: LogTag.UI_ACTION,
          message: '바코드 스캔 결과: $scanResult',
        );

        if (scanResult.startsWith('37400013')) {
          _searchMembership(memberId: scanResult);
        } else if (scanResult.startsWith('313')) {
          _useCouponDirectly(scanResult);
        } else {
          if (mounted) {
            CommonDialog.showInfoDialog(
              context: context,
              title: t.membership.dialog.notification,
              content: t.membership.dialog.invalid_barcode,
            );
          }
        }
      }
      return null;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
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
            FocusScope.of(context).requestFocus(_inputFocusNode);
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
            FocusScope.of(context).requestFocus(_inputFocusNode);
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
            FocusScope.of(context).requestFocus(_inputFocusNode);
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

    return Scaffold(
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
          height: 30,
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.person_search_outlined, size: 18),
              label: Text(
                t.membership.search.btn_other_member,
                style: AppTextStyles.bodySm,
              ),
              onPressed: () {
                logToFile(
                    tag: LogTag.UI_ACTION,
                    message: 'Clear membership button pressed.');
                ref.read(membershipProvider.notifier).clearMembership();
                _inputController.clear();
                FocusScope.of(context).requestFocus(_inputFocusNode);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppStyles.gray6,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
              ),
            ),
          ),
        );
      }
      return const SizedBox(height: 30);
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
          controller: _inputController,
          focusNode: _inputFocusNode,
          readOnly: true,
          showCursor: true,
          autofocus: true,
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
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _inputController,
          builder: (context, textValue, child) {
            final membershipState = ref.watch(membershipProvider);
            final isLoading = membershipState.isLoading;
            final customerName = membershipState.customerName;
            final inputText = textValue.text;
            final isCustomerSearched = customerName.isNotEmpty;

            bool isButtonEnabled = !isLoading && inputText.isNotEmpty;
            String buttonText = t.membership.search.btn_search;
            IconData buttonIcon = Icons.search;
            VoidCallback? onPressedAction;

            if (isCustomerSearched) {
              buttonText = t.membership.search.btn_save_stamp;
              buttonIcon = Icons.add_circle_outline;
              onPressedAction = () => _saveStamp(inputText);
              isButtonEnabled = !isLoading && inputText.isNotEmpty;
            } else {
              final isCouponMode = inputText.isNotEmpty && inputText[0] != '0';
              if (isCouponMode) {
                buttonText = t.membership.search.btn_use_coupon;
                buttonIcon = Icons.sell_outlined;
                onPressedAction = () => _useCouponDirectly(inputText);
              } else {
                buttonText = t.membership.search.btn_search;
                buttonIcon = Icons.search;
                onPressedAction = _searchMembership;
              }
              isButtonEnabled = !isLoading && inputText.isNotEmpty;
            }

            final isCouponMode = !isCustomerSearched &&
                inputText.isNotEmpty &&
                inputText[0] != '0';

            return Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(
                        isCouponMode ? Icons.fact_check : Icons.barcode_reader),
                    label: Text(isCouponMode
                        ? t.membership.search.btn_validate_coupon
                        : t.membership.search.btn_scan),
                    onPressed: isLoading
                        ? null
                        : (isCouponMode
                            ? () => _validateCoupon(inputText)
                            : (isCustomerSearched ? null : _scanBarcode)),
                    style: AppStyles.outlinedButton(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.s16),
                      borderColor: AppStyles.gray3,
                    ).copyWith(
                      textStyle: WidgetStatePropertyAll(
                        AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.w500),
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
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(buttonIcon),
                    label: Text(buttonText),
                    onPressed: isButtonEnabled ? onPressedAction : null,
                    style: AppStyles.primaryButton(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.s16),
                      elevation: 2,
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) {
                          if (states.contains(WidgetState.disabled)) {
                            return AppStyles.gray3;
                          }
                          return isCouponMode
                              ? AppStyles.kAmber
                              : AppStyles.kMainColor;
                        },
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? AppStyles.gray6
                            : Colors.white,
                      ),
                      textStyle: WidgetStatePropertyAll(
                        AppTextStyles.body
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
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
      indicatorPadding: const EdgeInsets.only(bottom: 10),
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
    final pagedHistory = ref
        .watch(membershipProvider.select((state) => state.pagedStampHistory));
    final totalPages = ref.watch(
        membershipProvider.select((state) => state.stampHistoryTotalPages));
    final currentPage = ref.watch(
        membershipProvider.select((state) => state.stampHistoryCurrentPage));
    final loadingActionId =
        ref.watch(membershipProvider.select((state) => state.loadingActionId));

    if (pagedHistory.isEmpty) {
      return Center(
        child: Text(
          t.membership.history.no_stamps,
          style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
        ),
      );
    }

    return MembershipHistoryTable(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (page) =>
          ref.read(membershipProvider.notifier).setStampHistoryPage(page),
      prevPageTooltip: t.membership.history.prev_page,
      nextPageTooltip: t.membership.history.next_page,
      columns: [
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_date),
          headingRowAlignment: MainAxisAlignment.center,
        ),
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_count),
          numeric: true,
          headingRowAlignment: MainAxisAlignment.center,
        ),
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_remark),
          headingRowAlignment: MainAxisAlignment.center,
        ),
      ],
      rows: pagedHistory.asMap().entries.map((entry) {
        final index = entry.key;
        final stamp = entry.value;
        final isLoading = loadingActionId == stamp.seq;

        String stampCountText = stamp.stampCount.toString();
        TextStyle stampCountStyle = AppTextStyles.body;
        Widget remarkWidget;

        switch (stamp.status.toUpperCase()) {
          case 'SUCCESS':
          case 'ACCRUED':
          case '0':
            stampCountText = '+${stamp.stampCount}';
            remarkWidget = ElevatedButton(
              onPressed: isLoading ? null : () => _cancelSavedStamp(stamp),
              style: _actionButtonStyle,
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppStyles.kMainColor),
                    )
                  : Text(t.membership.history.btn_cancel_save),
            );
            break;
          case 'CANCELLED':
          case 'CANCELED':
          case '7':
            stampCountText = '-${stamp.stampCount}';
            stampCountStyle =
                AppTextStyles.body.copyWith(color: AppStyles.kMainColor);
            remarkWidget = Text(
              t.membership.history.status_cancelled,
              style: AppTextStyles.body.copyWith(color: AppStyles.kMainColor),
            );
            break;
          case 'CONVERTED':
          case '9':
            remarkWidget = Text(t.membership.history.status_converted,
                style: AppTextStyles.body);
            break;
          case 'ISSUED':
            remarkWidget = Text(t.membership.history.status_issued,
                style: AppTextStyles.body);
            break;
          default:
            final textToShow = stamp.memo.isNotEmpty
                ? stamp.memo
                : (stamp.status.isNotEmpty ? stamp.status : '-');
            remarkWidget = Text(textToShow,
                style: AppTextStyles.body.copyWith(color: AppStyles.gray6));
            break;
        }

        return DataRow(
          color: membershipRowColor(index),
          cells: [
            DataCell(Center(
              child: Text(
                DateFormat('yyyy-MM-dd HH:mm').format(stamp.logDate),
                style: AppTextStyles.body,
              ),
            )),
            DataCell(Center(
              child: Text(stampCountText, style: stampCountStyle),
            )),
            DataCell(Center(child: remarkWidget)),
          ],
        );
      }).toList(),
    );
  }

  // ─── 쿠폰사용내역 탭 ──────────────────────────────────────────────────────

  Widget _buildCouponHistoryTab() {
    final pagedHistory = ref
        .watch(membershipProvider.select((state) => state.pagedCouponHistory));
    final totalPages = ref.watch(
        membershipProvider.select((state) => state.couponHistoryTotalPages));
    final currentPage = ref.watch(
        membershipProvider.select((state) => state.couponHistoryCurrentPage));
    final loadingActionId =
        ref.watch(membershipProvider.select((state) => state.loadingActionId));

    if (pagedHistory.isEmpty) {
      return Center(
        child: Text(
          t.membership.history.no_coupons,
          style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
        ),
      );
    }

    return MembershipHistoryTable(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (page) =>
          ref.read(membershipProvider.notifier).setCouponHistoryPage(page),
      prevPageTooltip: t.membership.history.prev_page,
      nextPageTooltip: t.membership.history.next_page,
      columns: [
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_coupon),
          headingRowAlignment: MainAxisAlignment.center,
        ),
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_use_date),
          headingRowAlignment: MainAxisAlignment.center,
        ),
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_remark),
          headingRowAlignment: MainAxisAlignment.center,
        ),
      ],
      rows: pagedHistory.asMap().entries.map((entry) {
        final index = entry.key;
        final coupon = entry.value;
        return DataRow(
          color: membershipRowColor(index),
          cells: [
            DataCell(Center(
              child: Text(coupon.title, style: AppTextStyles.body),
            )),
            DataCell(Center(
              child: Text(
                DateFormat('yyyy-MM-dd HH:mm').format(coupon.useDate),
                style: AppTextStyles.body,
              ),
            )),
            DataCell(Center(
              child: _buildCouponHistoryRemark(coupon, loadingActionId),
            )),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildCouponHistoryRemark(
      CouponHistoryInfo coupon, String? loadingActionId) {
    final isLoading = loadingActionId == coupon.couponId;

    switch (coupon.status.toUpperCase()) {
      case 'USED':
      case '9':
        return ElevatedButton(
          onPressed: isLoading ? null : () => _cancelCoupon(coupon),
          style: _actionButtonStyle,
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppStyles.kMainColor),
                )
              : Text(t.membership.history.btn_cancel_use),
        );
      case 'EXPIRED':
      case '7':
        return Text(
          t.membership.history.status_expired,
          style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
        );
      case 'ISSUED':
        return Text(
          t.membership.history.status_issued,
          style: AppTextStyles.body.copyWith(color: AppStyles.kBlue),
        );
      case 'CANCELLED':
      case 'CANCELED':
        return Text(
          t.membership.history.status_cancelled,
          style: AppTextStyles.body.copyWith(color: AppStyles.kMainColor),
        );
      default:
        return Text(
          coupon.status.isNotEmpty ? coupon.status : t.common.unknown,
          style: AppTextStyles.body,
        );
    }
  }

  // ─── 보유쿠폰 탭 ──────────────────────────────────────────────────────────

  Widget _buildAvailableCouponsTab() {
    final pagedCoupons = ref.watch(
        membershipProvider.select((state) => state.pagedAvailableCoupons));
    final totalPages = ref.watch(
        membershipProvider.select((state) => state.availableCouponsTotalPages));
    final currentPage = ref.watch(membershipProvider
        .select((state) => state.availableCouponsCurrentPage));
    final loadingActionId =
        ref.watch(membershipProvider.select((state) => state.loadingActionId));

    if (pagedCoupons.isEmpty) {
      return Center(
        child: Text(
          t.membership.history.no_available,
          style: AppTextStyles.body.copyWith(color: AppStyles.gray6),
        ),
      );
    }

    return MembershipHistoryTable(
      currentPage: currentPage,
      totalPages: totalPages,
      onPageChanged: (page) =>
          ref.read(membershipProvider.notifier).setAvailableCouponsPage(page),
      prevPageTooltip: t.membership.history.prev_page,
      nextPageTooltip: t.membership.history.next_page,
      columns: [
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_coupon),
          headingRowAlignment: MainAxisAlignment.center,
        ),
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_expiry),
          headingRowAlignment: MainAxisAlignment.center,
        ),
        DataColumn(
          label: membershipTableHeader(t.membership.history.col_remark),
          headingRowAlignment: MainAxisAlignment.center,
        ),
      ],
      rows: pagedCoupons.asMap().entries.map((entry) {
        final index = entry.key;
        final coupon = entry.value;
        final isLoading = loadingActionId == coupon.couponId;

        return DataRow(
          color: membershipRowColor(index),
          cells: [
            DataCell(Center(
              child: Text(coupon.couponTitle, style: AppTextStyles.body),
            )),
            DataCell(Center(
              child: Text(
                coupon.expireDate.toString().substring(0, 10),
                style: AppTextStyles.body,
              ),
            )),
            DataCell(
              Center(
                child: ElevatedButton(
                  onPressed: isLoading ? null : () => _useCoupon(coupon),
                  style: _actionButtonStyle,
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppStyles.kMainColor),
                        )
                      : Text(t.membership.history.btn_use),
                ),
              ),
            ),
          ],
        );
      }).toList(),
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

  // ─── 회원 조회 ────────────────────────────────────────────────────────────

  void _searchMembership({String memberId = ''}) async {
    final phoneNumber =
        memberId.isEmpty ? _inputController.text.trim() : memberId.trim();
    logToFile(
        tag: LogTag.API,
        message:
            'Search membership. Input: *******${phoneNumber.substring(phoneNumber.length - 4, phoneNumber.length)}');
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
      final membership = ref.read(membershipProvider).membershipInfo;
      if (membership == null) return;
      final success = await ref
          .read(membershipProvider.notifier)
          .useCoupon(membership.id, couponCode);
      if (success && mounted) {
        _inputController.clear();
      }
    }
  }

  Future<void> _validateCoupon(String couponCode) async {
    if (couponCode.isEmpty) {
      CommonDialog.showInfoDialog(
          context: context,
          title: t.membership.dialog.notification,
          content: t.membership.dialog.enter_coupon_code);
      return;
    }

    logToFile(tag: LogTag.UI_ACTION, message: '쿠폰검증 버튼 클릭: $couponCode');

    final couponData =
        await ref.read(membershipProvider.notifier).validateCoupon(couponCode);

    if (couponData != null && mounted) {
      final title = couponData['couponTitle'] ?? '알 수 없는 쿠폰';
      final discount = couponData['discountAmount'] ?? 0;
      final method = couponData['discountMethod'] == 'FIXED' ? '원 할인' : '% 할인';

      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.coupon_info_title,
        content: t.membership.dialog
            .coupon_info_content(name: title, benefit: '$discount$method'),
      );
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
      FocusScope.of(context).requestFocus(_inputFocusNode);
      return;
    }

    if (stampCount > 20) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.input_error_title,
        content: t.membership.dialog.stamp_limit_error,
      );
      FocusScope.of(context).requestFocus(_inputFocusNode);
      return;
    }

    FocusScope.of(context).unfocus();

    final success =
        await ref.read(membershipProvider.notifier).saveStamp(stampCountStr);

    if (success && mounted) {
      _inputController.clear();
    } else if (!success && mounted) {
      FocusScope.of(context).requestFocus(_inputFocusNode);
    }
  }
}
