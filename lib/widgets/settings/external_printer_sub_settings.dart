import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_styles.dart';
import '../../providers/providers.dart';
import '../../services/platform_service.dart';
import '../../services/preference_service.dart';
import '../../services/print_service.dart';
import 'settings_connection_status.dart';

// Windows COM 포트 enumerate 는 안드로이드 빌드에서 win32 native init (kernel32.dll
// lookup) 을 트리거하므로 deferred 로 격리 — Windows 분기 안에서만 loadLibrary.
import '../../services/external_receipt_printer_windows.dart'
    deferred as win_transport;

/// "외부 프린터 사용" 토글의 additionalContent.
///
/// - 모든 플랫폼: 연결상태 (기존 [SettingsConnectionStatus]).
/// - Windows + 외부 프린터 ON: COM 포트 / Baud rate 선택 (PR800 직결).
/// - 외부 프린터 ON: "테스트 출력" 버튼 + 결과 텍스트.
class ExternalPrinterSubSettings extends ConsumerStatefulWidget {
  const ExternalPrinterSubSettings({
    super.key,
    required this.isUseExternalPrinter,
    required this.printOrder,
    required this.printReceipt,
    required this.onPrintOrderChanged,
    required this.onPrintReceiptChanged,
  });

  final bool isUseExternalPrinter;

  /// 매트릭스: 주문서 출력 여부.
  final bool printOrder;

  /// 매트릭스: 영수증 출력 여부.
  final bool printReceipt;

  final void Function(bool) onPrintOrderChanged;
  final void Function(bool) onPrintReceiptChanged;

  @override
  ConsumerState<ExternalPrinterSubSettings> createState() =>
      _ExternalPrinterSubSettingsState();
}

class _ExternalPrinterSubSettingsState
    extends ConsumerState<ExternalPrinterSubSettings> {
  static const List<int> _baudRateOptions = [9600, 19200, 38400, 57600, 115200];
  // 안드로이드에서 ComPortPrintService 정적 reference 가 발생하면 serial_port_win32
  // → win32 → kernel32.dll 체인이 로딩돼 dlopen 실패하므로 하드코딩으로 분리.
  // (Windows 분기 안에서만 deferred 로 호출.)
  static const String _defaultComPort = 'COM3';
  static const int _defaultBaudRate = 9600;

  final PreferenceService _pref = PreferenceService();

  List<String> _comPorts = const [];
  String _selectedComPort = _defaultComPort;
  int _baudRate = _defaultBaudRate;
  bool _isRefreshing = false;
  String? _testResult;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _baudRate = _pref.getComPortBaudRate();
    _selectedComPort = _pref.getComPortName() ?? _defaultComPort;
    if (Platform.isWindows) {
      // _refreshComPorts 끝에서 printerStatusProvider 를 변경하는 checkConnection()
      // 을 호출한다. 외부 프린터 OFF 등으로 도중 await 가 한 번도 yield 되지
      // 않으면 build phase 에서 provider mutation 이 일어나 Riverpod 가 throw.
      // PrintService 생성자([print_service.dart:48]) 와 동일한 패턴으로 microtask
      // 으로 defer 한다.
      Future.microtask(_refreshComPorts);
    }
  }

  Future<void> _refreshComPorts() async {
    if (!Platform.isWindows) return;
    setState(() => _isRefreshing = true);
    try {
      await win_transport.loadLibrary();
      final ports = win_transport.getAvailableComPorts();
      final saved = _pref.getComPortName();
      final selected = (saved != null && ports.contains(saved))
          ? saved
          : (ports.isNotEmpty ? ports.first : _defaultComPort);
      if (!mounted) return;
      setState(() {
        _comPorts = ports;
        _selectedComPort = selected;
        _isRefreshing = false;
      });
      if (selected != saved && ports.isNotEmpty) {
        await _pref.setComPortName(selected);
      }
      logToFile(
        tag: LogTag.PLATFORM,
        message: 'COM 포트 스캔: ${ports.length}개, 선택=$selected',
      );
      // 연결상태 표시 갱신 (포트 enumerate 결과 기반). 외부만 갱신.
      if (mounted) {
        await ref
            .read(printServiceProvider)
            .checkConnection(external: true, label: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
        _testResult = 'COM 포트 조회 실패: $e';
      });
    }
  }

  Future<void> _handleTestPrint() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
      _testResult = '출력 중...';
    });
    logToFile(
      tag: LogTag.UI_ACTION,
      message: Platform.isWindows
          ? '테스트 출력 시도: COM=$_selectedComPort, baud=$_baudRate'
          : '테스트 출력 시도 (Android)',
    );
    bool ok = false;
    try {
      ok = await ref
          .read(printServiceProvider)
          .printTestPage(targetExternalOnly: true);
    } catch (e) {
      ok = false;
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testResult = '테스트 출력 실패: $e';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testResult = ok ? '테스트 출력 성공' : '테스트 출력 실패';
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(printerStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsConnectionStatus(
          isConnected: status.isExternalConnected,
          onReconnect: () async {
            // Android: UsbReceiptPrinter.discover() 가 한 번 비어있던 상태(권한 거부 /
            // 늦은 핫플러그)를 회복할 수 있도록 재탐색을 먼저 트리거. Windows 는 COM
            // 포트 enumerate 만으로 충분.
            //
            // label: false 로 호출해 라벨 status 가 외부 재연결로 같이 토글되는
            // sync 이슈 회피. (라벨은 별도 재연결 버튼이 갱신.)
            final ps = ref.read(printServiceProvider);
            if (Platform.isAndroid) {
              await ps.reconnectExternalPrinter();
            }
            await ps.checkConnection(external: true, label: false);
          },
        ),
        if (widget.isUseExternalPrinter) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildMatrixRow(
            label: '주문서 출력',
            value: widget.printOrder,
            onChanged: widget.onPrintOrderChanged,
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildMatrixRow(
            label: '영수증 출력',
            value: widget.printReceipt,
            onChanged: widget.onPrintReceiptChanged,
          ),
        ],
        if (widget.isUseExternalPrinter && Platform.isWindows) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildComPortPicker(),
        ],
        if (widget.isUseExternalPrinter) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildTestPrintRow(),
        ],
      ],
    );
  }

  // ── 매트릭스 row (주문서/영수증 출력 여부) ──────────────────────────────────
  Widget _buildMatrixRow({
    required String label,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    final enabled = widget.isUseExternalPrinter;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySm.copyWith(
              color: enabled ? AppStyles.gray9 : AppStyles.gray4,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeColor: AppStyles.kMainColor,
        ),
      ],
    );
  }

  // ── COM 포트 / Baud rate 선택 카드 (Windows 전용) ─────────────────────────
  Widget _buildComPortPicker() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: AppStyles.gray1,
        borderRadius: AppRadius.bSm,
        border: Border.all(color: AppStyles.gray3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'COM 포트 설정 (PR800)',
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppStyles.gray9,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'COM 포트 다시 검색',
                onPressed: _isRefreshing ? null : _refreshComPorts,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_comPorts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: Text(
                _isRefreshing ? '검색 중…' : 'COM 포트를 찾을 수 없습니다. (프린터가 연결되어 있나요?)',
                style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
              ),
            )
          else ...[
            Text(
              'COM 포트 선택',
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
            const SizedBox(height: AppSpacing.s4),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppStyles.gray3),
                borderRadius: AppRadius.bSm,
                color: Colors.white,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _comPorts.contains(_selectedComPort)
                      ? _selectedComPort
                      : _comPorts.first,
                  items: _comPorts
                      .map((port) => DropdownMenuItem<String>(
                            value: port,
                            child: Text(port),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedComPort = value;
                      _testResult = null;
                    });
                    _pref.setComPortName(value);
                    logToFile(
                      tag: LogTag.UI_ACTION,
                      message: 'COM 포트 선택 -> $value',
                    );
                    // 선택 직후 연결상태 즉시 반영 (외부만).
                    ref
                        .read(printServiceProvider)
                        .checkConnection(external: true, label: false);
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'BAUD RATE',
              style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
            ),
            const SizedBox(height: AppSpacing.s4),
            Wrap(
              spacing: AppSpacing.s8,
              children: _baudRateOptions
                  .map((rate) => ChoiceChip(
                        label: Text('$rate'),
                        selected: _baudRate == rate,
                        onSelected: (selected) {
                          if (!selected) return;
                          setState(() {
                            _baudRate = rate;
                            _testResult = null;
                          });
                          _pref.setComPortBaudRate(rate);
                          logToFile(
                            tag: LogTag.UI_ACTION,
                            message: 'BAUD RATE 선택 -> $rate',
                          );
                        },
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          Text(
            '※ COM 포트로 직접 ESC/POS 명령을 전송합니다. 프린터가 로컬 COM 포트에 연결되어야 합니다.',
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
        ],
      ),
    );
  }

  // ── 테스트 출력 버튼 + 결과 텍스트 ──────────────────────────────────────
  Widget _buildTestPrintRow() {
    final result = _testResult;
    Color resultColor = AppStyles.gray6;
    if (result != null) {
      if (result.contains('성공')) {
        resultColor = AppStyles.green100;
      } else if (result == '출력 중...') {
        resultColor = AppStyles.gray6;
      } else {
        resultColor = AppStyles.kRed;
      }
    }
    final isWindowsWithoutPort =
        Platform.isWindows && _comPorts.isEmpty && !_isRefreshing;

    return Row(
      children: [
        ElevatedButton.icon(
          onPressed:
              (_isTesting || isWindowsWithoutPort) ? null : _handleTestPrint,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('테스트 출력'),
        ),
        const SizedBox(width: AppSpacing.s12),
        if (result != null)
          Expanded(
            child: Text(
              result,
              style: AppTextStyles.bodySm.copyWith(color: resultColor),
            ),
          ),
      ],
    );
  }
}
