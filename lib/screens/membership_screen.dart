import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for TextInputFormatter
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart'; // DateFormat 사용 위해 추가
import 'package:appfit_order_agent/providers/providers.dart'; // providers import
import 'package:appfit_order_agent/models/membership_model.dart'; // Membership 모델 import
import 'package:appfit_order_agent/utils/logger.dart'; // Logger import
import 'package:appfit_order_agent/widgets/common/common_dialog.dart';
import 'package:appfit_order_agent/i18n/strings.g.dart';
import '../services/platform_service.dart'; // <<< Import logToFile
import '../constants/app_styles.dart';
import '../widgets/membership/numeric_keypad_widget.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  // Local controller to prevent recreation on each build
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  String? _previousError;
  String? _previousSuccess; // Local cache for success message

  // Define a common button style
  ButtonStyle get _actionButtonStyle => AppStyles.outlinedPrimaryButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(80, 36),
      ).copyWith(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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

        // 스캔 결과에 따라 회원조회 또는 쿠폰조회 실행
        if (scanResult.startsWith('37400013')) {
          // 회원조회 코드
          _searchMembership(memberId: scanResult);
        } else if (scanResult.startsWith('313')) {
          // 쿠폰조회 코드
          _useCouponDirectly(scanResult);
        } else {
          // 알 수 없는 형식의 바코드인 경우
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
    // Get only necessary state using select to reduce rebuilds
    final isLoading =
        ref.watch(membershipProvider.select((state) => state.isLoading));

    logger.d('MembershipScreen build triggered. isLoading: $isLoading');

    // Listen to provider state changes for side effects (dialogs, focus)
    ref.listen<MembershipState>(membershipProvider, (previous, next) {
      // Avoid showing dialogs or managing focus if the widget is disposed
      if (!mounted) return;

      // Use nullable previous state for safety
      final prevErrorMessage = previous?.errorMessage;
      final prevSuccessMessage = previous?.successMessage;

      // --- Focus Management ---
      // Refocus after loading ends (unless dialog handles it) or customer changes
      bool shouldRefocus = false;
      // Check if main loading finished (no dialog was triggered by message change)
      if (previous?.isLoading == true &&
          next.isLoading == false &&
          next.errorMessage == null &&
          next.successMessage == null &&
          prevErrorMessage == null &&
          prevSuccessMessage == null) {
        shouldRefocus = true;
        // Check if action loading finished (no dialog was triggered by message change)
      } else if (previous?.loadingActionId != null &&
          next.loadingActionId == null &&
          next.errorMessage == null &&
          next.successMessage == null &&
          prevErrorMessage == null &&
          prevSuccessMessage == null) {
        shouldRefocus = true;
      } else if (previous?.customerName != next.customerName ||
          previous?.rewardType != next.rewardType) {
        // Refocus after customer search/change if input was cleared
        if (_inputController.text.isEmpty) {
          // Check if input was actually cleared
          shouldRefocus = true;
        }
      }

      if (shouldRefocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Check mounted again inside callback
            FocusScope.of(context).requestFocus(_inputFocusNode);
            logger.d('Refocus requested after state change (no dialog)');
          }
        });
      }

      // --- Dialog Management (Independent of isLoading checks) ---
      // Show Error Dialog if errorMessage appears or changes
      if (next.errorMessage != null &&
          next.errorMessage!.isNotEmpty &&
          next.errorMessage != prevErrorMessage) {
        CommonDialog.showInfoDialog(
          context: context,
          title: t.common.error,
          content: next.errorMessage!,
        ).then((_) {
          // After dialog dismissal
          if (mounted) {
            ref.read(membershipProvider.notifier).clearError();
            // Clear input field on error during search/use coupon/save stamp
            _inputController.clear();
            FocusScope.of(context).requestFocus(_inputFocusNode);
            logger.d('Error dialog dismissed, input cleared, focus requested.');
          }
        });
        // Show Success Dialog if successMessage appears or changes
      } else if (next.successMessage != null &&
          next.successMessage!.isNotEmpty &&
          next.successMessage != prevSuccessMessage) {
        CommonDialog.showInfoDialog(
          context: context,
          title: t.membership.dialog.processing_complete,
          content: next.successMessage!,
        ).then((_) {
          // After dialog dismissal
          if (mounted) {
            ref.read(membershipProvider.notifier).clearSuccessMessage();
            // Do NOT clear input field on generic success (e.g., after search)
            // Input is cleared specifically in _saveStamp on success
            // Focus back to input field
            FocusScope.of(context).requestFocus(_inputFocusNode);
            logger.d('Success dialog dismissed, focus requested.');
          }
        });
      }

      // --- Input Clearing on Customer Change ---
      // Moved focus logic above, only clear input here
      if (previous?.customerName != next.customerName ||
          previous?.rewardType != next.rewardType) {
        // If customer info changes (e.g., after search), reset input field
        _inputController.clear();
        logger.d('Input cleared due to customer change.');
        // Focus is handled in the focus management section above
      }
    });

    return Scaffold(
      // appBar: AppBar(title: const Text('멤버십 조회')), // 필요 시 AppBar 추가
      body: Container(
        color: AppStyles.gray1,
        child: Row(
          children: [
            // --- 좌측 영역: 입력 및 검색 ---
            Expanded(
              flex: 1, // 좌측 영역 비율
              child: _buildLeftPanel(),
            ),
            // 구분선
            const VerticalDivider(width: 1, thickness: 1),
            // --- 우측 영역: 조회 결과 (탭) ---
            Expanded(
              flex: 2, // 우측 영역 비율 (좌측보다 넓게)
              child: _buildRightPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildCustomerInfoDisplay() {
    // Watch needed states efficiently
    final customerName =
        ref.watch(membershipProvider.select((state) => state.customerName));
    final stampCount =
        ref.watch(membershipProvider.select((state) => state.stampCount));
    final couponCount =
        ref.watch(membershipProvider.select((state) => state.couponCount));
    final isLoading =
        ref.watch(membershipProvider.select((state) => state.isLoading));

    // Always return the same structure, control visibility with Opacity
    return SizedBox(
      height: 40, // 고정된 높이 설정
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Opacity(
          opacity: isLoading ? 0.0 : 1.0, // Hide content when loading
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                // Allow customer name to shrink if needed
                child: Text(
                  isLoading
                      ? ' '
                      : customerName.isEmpty
                          ? t.membership.customer.status_none
                          : t.membership.customer.honorific(name: customerName),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppStyles.kMainColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Display Stamp/Point and Coupon count based on rewardType
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  isLoading || customerName.isEmpty
                      ? ' '
                      : t.membership.customer.summary(
                          stamps: stampCount.toString(),
                          coupons: couponCount.toString()),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20, top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 고정 높이 영역: 회원 정보 표시
          buildCustomerInfoDisplay(),

          // 다른 회원 조회 버튼
          Consumer(builder: (context, ref, _) {
            final customerName =
                ref.watch(membershipProvider.select((s) => s.customerName));
            if (customerName.isNotEmpty) {
              return Container(
                height: 30,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.person_search_outlined, size: 18),
                    label: Text(t.membership.search.btn_other_member,
                        style: const TextStyle(fontSize: 13)),
                    onPressed: () {
                      logToFile(
                          tag: LogTag.UI_ACTION,
                          message: 'Clear membership button pressed.');
                      ref.read(membershipProvider.notifier).clearMembership();
                      _inputController.clear();
                      FocusScope.of(context).requestFocus(_inputFocusNode);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              );
            }
            return const SizedBox(height: 30);
          }),

          const SizedBox(height: 20),

          // 입력 필드
          Consumer(
            builder: (context, ref, _) {
              final customerName =
                  ref.watch(membershipProvider.select((s) => s.customerName));
              final isCustomerSearched = customerName.isNotEmpty;
              String hintText = t.membership.search.hint;
              TextInputType keyboardType = TextInputType.none;

              if (isCustomerSearched) {
                hintText = t.membership.search.hint_searched;
                keyboardType = TextInputType.number;
              }

              return TextField(
                style: const TextStyle(fontSize: 20),
                controller: _inputController,
                focusNode: _inputFocusNode,
                readOnly: true,
                showCursor: true,
                autofocus: true,
                decoration: AppStyles.outlinedInputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(fontSize: 15),
                ).copyWith(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 16),
                ),
              );
            },
          ),

          const SizedBox(height: 40),

          // 키패드 영역 - Expanded로 남은 공간 모두 사용
          Expanded(
            child: _buildKeypadAndButtons(),
          ),
        ],
      ),
    );
  }

  // --- 키패드 및 버튼 위젯 빌드 ---
  Widget _buildKeypadAndButtons() {
    return Column(
      children: [
        // --- 키패드 영역 ---
        Expanded(
          child: NumericKeypadWidget(
            onKeyPressed: _onKeypadPressed,
            onClear: _onClearPressed,
            onDelete: _onDeletePressed,
            clearLabel: t.membership.keypad.clear,
            deleteLabel: t.membership.keypad.delete,
          ),
        ),

        // --- 하단 버튼 영역 ('바코드 촬영', '조회') ---
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _inputController,
          builder: (context, textValue, child) {
            final membershipState =
                ref.watch(membershipProvider); // 전체 상태 watch
            final isLoading = membershipState.isLoading;
            final customerName = membershipState.customerName;
            final inputText = textValue.text;
            final isCustomerSearched = customerName.isNotEmpty;

            // 버튼 상태 및 라벨 결정 로직
            bool isButtonEnabled = !isLoading && inputText.isNotEmpty;
            String buttonText = t.membership.search.btn_search;
            IconData buttonIcon = Icons.search;
            VoidCallback? onPressedAction;

            if (isCustomerSearched) {
              // 고객 조회된 상태
              buttonText = t.membership.search.btn_save_stamp;
              buttonIcon = Icons.add_circle_outline; // 스탬프 아이콘 (임의)
              onPressedAction = () => _saveStamp(inputText);
              // 고객 조회 후에는 입력값이 없어도 적립 가능하도록 isButtonEnabled 재조정?
              // 여기서는 스탬프/포인트 '개수/금액'을 입력해야 하므로 inputText.isNotEmpty 유지
              isButtonEnabled = !isLoading && inputText.isNotEmpty;
            } else {
              // 고객 조회 안 된 상태
              final isCouponMode = inputText.isNotEmpty && inputText[0] != '0';
              if (isCouponMode) {
                buttonText = t.membership.search.btn_use_coupon;
                buttonIcon = Icons.sell_outlined;
                onPressedAction = () => _useCouponDirectly(inputText);
              } else {
                // 회원조회
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
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      borderColor: Colors.grey[300]!,
                    ).copyWith(
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? Colors.grey[400]
                            : Colors.white,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? Colors.white70
                            : Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(buttonIcon),
                    label: Text(buttonText),
                    onPressed: isButtonEnabled ? onPressedAction : null,
                    style: AppStyles.primaryButton(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) {
                          if (states.contains(WidgetState.disabled)) {
                            return Colors.grey[400];
                          }
                          return isCouponMode
                              ? Colors.orange
                              : AppStyles.kMainColor;
                        },
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? Colors.white70
                            : Colors.white,
                      ),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  // --- 키패드 입력 처리 ---
  void _onKeypadPressed(String value) {
    final currentText = _inputController.text;

    final customerName =
        ref.read(membershipProvider.select((state) => state.customerName));
    final rewardType =
        ref.read(membershipProvider.select((state) => state.rewardType));
    final isCustomerSearched = customerName.isNotEmpty;

    if (isCustomerSearched && currentText.isEmpty && value == '0') {
      // 회원 조회된 상태에서 첫 글자로 0 입력 방지 (스탬프/포인트 적립 시)
      return;
    }

    // 스탬프 타입일 때만 두 자리 입력 제한 (스탬프 적립 시)
    if (isCustomerSearched &&
        rewardType == 'STAMP' &&
        currentText.length >= 2) {
      // 스탬프 타입에서 이미 두 자리가 입력된 경우 추가 입력 방지
      return;
    }

    // TODO: 입력 길이 제한 등 추가 로직 구현 가능
    _inputController.text = currentText + value;
    // 입력 후 커서를 맨 뒤로 이동
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
  }

  void _searchMembership({String memberId = ''}) async {
    final phoneNumber =
        memberId.isEmpty ? _inputController.text.trim() : memberId.trim();
    logToFile(
        tag: LogTag.API,
        message:
            'Search membership. Input: *******${phoneNumber.substring(phoneNumber.length - 4, phoneNumber.length)}'); // <<< Log search button press
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

  Widget _buildRightPanel() {
    // Use select for precise state watching
    // rewardType은 이제 무시하고 항상 스탬프 모드로 동작
    final isLoading =
        ref.watch(membershipProvider.select((state) => state.isLoading));
    final isLoadingHistory = ref.watch(
        membershipProvider.select((state) => state.isLoadingRewardHistory));

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // Tab Bar - Always Stamp mode
          _buildTabBar(),
          // Tab Content
          Expanded(
            child: isLoading || isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _buildStampHistoryTab(), // 스탬프내역
                    _buildCouponHistoryTab(), // 쿠폰사용내역
                    _buildAvailableCouponsTab(), // 보유쿠폰
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
        indicatorPadding: const EdgeInsets.only(bottom: 10),
        dividerColor: Colors.transparent,
        isScrollable: false, // 탭 스크롤 비활성화
        labelColor: Colors.black, // 선택된 탭 텍스트 색상
        unselectedLabelColor: Colors.grey, // 선택되지 않은 탭 텍스트 색상
        indicatorColor: AppStyles.kMainColor, // 하단 인디케이터 색상
        tabs: [
          getTab(t.membership.tabs.stamps),
          getTab(t.membership.tabs.coupons),
          getTab(t.membership.tabs.available),
        ]);
  }

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
      return Center(child: Text(t.membership.history.no_stamps));
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: SizedBox(
              // Ensure DataTable tries to fill width
              width: double.infinity,
              child: DataTable(
                headingRowColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) {
                    return Colors.grey[200]!;
                  },
                ),
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: [
                  DataColumn(
                      label: Center(
                        child: Text(
                          t.membership.history.col_date,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(
                      label: Center(
                        child: Text(
                          t.membership.history.col_count,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      numeric: true, // 숫자 정렬 (오른쪽 정렬)
                      headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(
                      label: Center(
                        child: Text(
                          t.membership.history.col_remark,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      headingRowAlignment: MainAxisAlignment.center),
                ],
                rows: pagedHistory.asMap().entries.map((entry) {
                  final index = entry.key; // 페이지 내에서의 인덱스 (0~9)
                  final stamp = entry.value;
                  final isLoading = loadingActionId == stamp.seq;

                  // 조건부 스타일 및 텍스트
                  String stampCountText = stamp.stampCount.toString();
                  TextStyle stampCountStyle =
                      const TextStyle(fontSize: 16); // 기본 스타일
                  Widget remarkWidget;

                  switch (stamp.status.toUpperCase()) {
                    case 'SUCCESS':
                    case 'ACCRUED':
                    case '0': // Legacy support
                      stampCountText = '+${stamp.stampCount}';
                      remarkWidget = ElevatedButton(
                        onPressed:
                            isLoading ? null : () => _cancelSavedStamp(stamp),
                        style: _actionButtonStyle,
                        child: isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.deepOrange),
                              )
                            : Text(
                                t.membership.history.btn_cancel_save,
                                style: const TextStyle(fontSize: 16),
                              ),
                      );
                      break;
                    case 'CANCELLED':
                    case 'CANCELED':
                    case '7': // Legacy support
                      stampCountText = '-${stamp.stampCount}';
                      stampCountStyle = const TextStyle(
                          color: AppStyles.kMainColor, fontSize: 16);
                      remarkWidget = Text(t.membership.history.status_cancelled,
                          style: const TextStyle(
                              color: AppStyles.kMainColor, fontSize: 16));
                      break;
                    case 'CONVERTED':
                    case '9': // Legacy support
                      remarkWidget =
                          Text(t.membership.history.status_converted);
                      break;
                    case 'ISSUED':
                      remarkWidget = Text(t.membership.history.status_issued);
                      break;
                    default:
                      final textToShow = stamp.memo.isNotEmpty
                          ? stamp.memo
                          : (stamp.status.isNotEmpty ? stamp.status : '-');
                      remarkWidget = Text(textToShow,
                          style: const TextStyle(color: Colors.grey));
                      break;
                  }

                  return DataRow(
                      // 교차 배경색 (페이지 내 인덱스 기준)
                      color: WidgetStateProperty.resolveWith<Color?>(
                        (Set<WidgetState> states) {
                          return index.isEven
                              ? Colors.grey[100]
                              : null; // 짝수 행 연한 회색
                        },
                      ),
                      cells: [
                        DataCell(
                          Center(
                            child: Text(
                              DateFormat('yyyy-MM-dd HH:mm')
                                  .format(stamp.logDate),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        // --- 적립 개수 셀 수정 (동일) ---
                        DataCell(
                          Center(
                              child:
                                  Text(stampCountText, style: stampCountStyle)),
                        ),
                        // --- 비고 셀 수정 (동일) -> remarkWidget 사용
                        DataCell(
                          Center(child: remarkWidget),
                        ),
                      ]);
                }).toList(),
              ),
            ),
          ),
          // Pagination
          if (totalPages > 1)
            _buildPaginationControls(
              currentPage: currentPage,
              totalPages: totalPages,
              onPageChanged: (page) {
                ref.read(membershipProvider.notifier).setStampHistoryPage(page);
              },
            ),
        ],
      ),
    );
  }

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
      // Check mounted before calling provider
      await ref.read(membershipProvider.notifier).cancelStamp(stamp.rewardId);
      // Success/Error message is handled by the listener in build()
    }
  }

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
      return Center(child: Text(t.membership.history.no_coupons));
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: SizedBox(
              // Ensure DataTable tries to fill width
              width: double.infinity,
              child: DataTable(
                headingRowColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) {
                    return Colors.grey[200]!;
                  },
                ),
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: [
                  DataColumn(
                      label: Center(
                          child: Text(
                        t.membership.history.col_coupon,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      )),
                      headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(
                      label: Center(
                          child: Text(
                        t.membership.history.col_use_date,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      )),
                      headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(
                      label: Center(
                          child: Text(
                        t.membership.history.col_remark,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      )),
                      headingRowAlignment: MainAxisAlignment.center),
                ],
                rows: pagedHistory.asMap().entries.map((entry) {
                  final index = entry.key;
                  final coupon = entry.value;
                  return DataRow(
                      color: WidgetStateProperty.resolveWith<Color?>(
                        // 교차 배경색 (페이지 내 인덱스 기준)
                        (Set<WidgetState> states) {
                          return index.isEven ? Colors.grey[100] : null;
                        },
                      ),
                      cells: [
                        DataCell(Center(
                            child: Text(
                          coupon.title,
                          style: const TextStyle(fontSize: 16),
                        ))),
                        DataCell(Center(
                            child: Text(
                                DateFormat('yyyy-MM-dd HH:mm')
                                    .format(coupon.useDate),
                                style: const TextStyle(fontSize: 16)))),
                        // --- 비고 셀 수정 (동일) ---
                        DataCell(Center(
                          child: _buildCouponHistoryRemark(
                              coupon, loadingActionId), // 상태에 따라 다른 위젯 반환 함수 호출
                        )),
                      ]);
                }).toList(),
              ),
            ),
          ),
          // Pagination
          if (totalPages > 1)
            _buildPaginationControls(
              currentPage: currentPage,
              totalPages: totalPages,
              onPageChanged: (page) {
                ref
                    .read(membershipProvider.notifier)
                    .setCouponHistoryPage(page);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCouponHistoryRemark(
      CouponHistoryInfo coupon, String? loadingActionId) {
    final isLoading = loadingActionId == coupon.couponId;

    switch (coupon.status.toUpperCase()) {
      case 'USED':
      case '9': // Legacy support
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
              : Text(t.membership.history.btn_cancel_use,
                  style: const TextStyle(fontSize: 16)),
        );
      case 'EXPIRED':
      case '7': // Legacy support
        return Text(t.membership.history.status_expired,
            style: const TextStyle(color: Colors.grey, fontSize: 16));
      case 'ISSUED':
        return Text(t.membership.history.status_issued,
            style: const TextStyle(color: Colors.blue, fontSize: 16));
      case 'CANCELLED':
      case 'CANCELED':
        return Text(t.membership.history.status_cancelled,
            style: const TextStyle(color: AppStyles.kMainColor, fontSize: 16));
      default:
        return Text(
            coupon.status.isNotEmpty ? coupon.status : t.common.unknown);
    }
  }

  Future<void> _cancelCoupon(CouponHistoryInfo coupon) async {
    logToFile(
        tag: LogTag.UI_ACTION,
        message:
            'Cancel Coupon button pressed. Coupon ID: ${coupon.couponId}'); // <<< Log button press

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
      return Center(child: Text(t.membership.history.no_available));
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: SizedBox(
              // Ensure DataTable tries to fill width
              width: double.infinity,
              child: DataTable(
                headingRowColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) {
                    return Colors.grey[200]!;
                  },
                ),
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: [
                  DataColumn(
                      label: Center(
                          child: Text(
                        t.membership.history.col_coupon,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      )),
                      headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(
                      label: Center(
                          child: Text(
                        t.membership.history.col_expiry,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      )),
                      headingRowAlignment: MainAxisAlignment.center),
                  DataColumn(
                      label: Center(
                          child: Text(
                        t.membership.history.col_remark,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      )),
                      headingRowAlignment: MainAxisAlignment.center),
                ],
                rows: pagedCoupons.asMap().entries.map((entry) {
                  final index = entry.key;
                  final coupon = entry.value;
                  final isLoading = loadingActionId == coupon.couponId;

                  return DataRow(
                    color: index.isEven
                        ? WidgetStateProperty.all(Colors.grey[100])
                        : null,
                    cells: [
                      DataCell(Center(
                          child: Text(coupon.couponTitle,
                              style: const TextStyle(fontSize: 16)))),
                      DataCell(Center(
                          child: Text(
                              coupon.expireDate.toString().substring(0, 10),
                              style: const TextStyle(fontSize: 16)))),
                      DataCell(
                        Center(
                          child: ElevatedButton(
                            onPressed:
                                isLoading ? null : () => _useCoupon(coupon),
                            style: _actionButtonStyle, // <<< Use common style
                            child: isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppStyles.kMainColor),
                                  )
                                : Text(t.membership.history.btn_use,
                                    style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          // Pagination
          if (totalPages > 1)
            _buildPaginationControls(
              currentPage: currentPage,
              totalPages: totalPages,
              onPageChanged: (page) {
                ref
                    .read(membershipProvider.notifier)
                    .setAvailableCouponsPage(page);
              },
            ),
        ],
      ),
    );
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

  Widget _buildPaginationControls({
    required int currentPage,
    required int totalPages,
    required Function(int) onPageChanged,
  }) {
    const int maxPageNumbersToShow = 5;
    List<Widget> pageNumberWidgets = [];
    int startPage;
    int endPage;

    if (totalPages <= maxPageNumbersToShow) {
      startPage = 0;
      endPage = totalPages - 1;
    } else {
      int halfMax = maxPageNumbersToShow ~/ 2;
      startPage = currentPage - halfMax;
      endPage = currentPage + halfMax - (maxPageNumbersToShow % 2 == 0 ? 1 : 0);

      if (startPage < 0) {
        startPage = 0;
        endPage = maxPageNumbersToShow - 1;
      }
      if (endPage >= totalPages) {
        endPage = totalPages - 1;
        startPage = endPage - maxPageNumbersToShow + 1;
        if (startPage < 0) startPage = 0;
      }
    }

    for (int i = startPage; i <= endPage; i++) {
      final bool isCurrent = i == currentPage;
      pageNumberWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.all(8), // 버튼 패딩
              minimumSize: const Size(36, 36), // 버튼 최소 크기
              backgroundColor:
                  isCurrent ? AppStyles.kMainColor : Colors.transparent,
              foregroundColor: isCurrent ? Colors.white : Colors.black54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(
                  color:
                      isCurrent ? AppStyles.kMainColor : Colors.grey.shade300,
                  width: 1,
                ),
              ),
            ),
            onPressed: () {
              onPageChanged(i);
            },
            child: Text('${i + 1}'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_left),
            onPressed: currentPage > 0
                ? () {
                    // <<< Log previous page
                    onPageChanged(currentPage - 1);
                  }
                : null,
            tooltip: t.membership.history.prev_page,
          ),
          ...pageNumberWidgets,
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_right),
            onPressed: currentPage < totalPages - 1
                ? () {
                    onPageChanged(currentPage + 1);
                  }
                : null,
            tooltip: t.membership.history.next_page,
          ),
        ],
      ),
    );
  }

  // --- Clear 버튼 처리 ---
  void _onClearPressed() {
    _inputController.clear();
  }

  // --- Delete 버튼 처리 ---
  void _onDeletePressed() {
    final currentText = _inputController.text;
    if (currentText.isNotEmpty) {
      _inputController.text = currentText.substring(0, currentText.length - 1);
      // 삭제 후 커서를 맨 뒤로 이동
      _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
    }
  }

  void _scanBarcode() async {
    logToFile(tag: LogTag.UI_ACTION, message: '바코드 스캔 버튼 터치');
    try {
      // Sunmi QR 스캐너 앱 실행
      await platform.invokeMethod('startQRScan');
      // 스캔 결과는 _setupMethodChannel에서 처리됨
    } catch (e, s) {
      // QR 스캐너를 지원하지 않는 경우 에러 메시지 표시
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

    // 스토어 아이디 가져오기
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

  Future<void> _saveStamp(String stampCountStr) async {
    // 입력값 유효성 검사 (숫자, 0보다 큰 값, 20 이하)
    final stampCount = int.tryParse(stampCountStr);
    logToFile(tag: LogTag.UI_ACTION, message: '스탬프 적립 버튼 클릭: $stampCount 개');

    if (stampCount == null || stampCount <= 0) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.input_error_title,
        content: t.membership.dialog.stamp_input_error,
      );
      // Request focus after showing the dialog
      FocusScope.of(context).requestFocus(_inputFocusNode);
      return;
    }

    // 20 초과 검증 추가
    if (stampCount > 20) {
      CommonDialog.showInfoDialog(
        context: context,
        title: t.membership.dialog.input_error_title,
        content: t.membership.dialog.stamp_limit_error,
      );
      // Request focus after showing the dialog
      FocusScope.of(context).requestFocus(_inputFocusNode);
      return;
    }

    FocusScope.of(context).unfocus();

    // Provider 호출
    final success =
        await ref.read(membershipProvider.notifier).saveStamp(stampCountStr);

    if (success && mounted) {
      // 성공 시 입력 필드 클리어
      _inputController.clear();
      // 성공 메시지는 Provider의 listener에서 처리됨
      // Focus back after dialog handled by listener
    } else if (!success && mounted) {
      // Focus back immediately on failure if no dialog shown by listener
      FocusScope.of(context).requestFocus(_inputFocusNode);
    }
    // Focus is handled by listener callbacks or here on immediate failure
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

  Tab getTab(String tabName) {
    return Tab(
        height: 60.0,
        child: Text(tabName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)));
  }
}
