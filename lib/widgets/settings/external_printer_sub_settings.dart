import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/com_port_descriptor.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/services/printer_transport.dart'
    show DebugPrinterFault;
import 'package:appfit_order_agent/widgets/settings/settings_connection_status.dart';

// Windows COM 포트 enumerate 는 안드로이드 빌드에서 win32 native init (kernel32.dll
// lookup) 을 트리거하므로 deferred 로 격리 — Windows 분기 안에서만 loadLibrary.
import 'package:appfit_order_agent/services/external_receipt_printer_windows.dart'
    deferred as win_transport;

/// "외부 프린터 사용" 토글의 additionalContent.
///
/// - 모든 플랫폼: 연결상태 + 재연결 ([SettingsConnectionStatus]).
/// - Windows + 외부 프린터 ON: COM 포트 / Baud rate 선택 (PR800 직결).
/// - 외부 프린터 ON: "테스트 출력" 버튼 + 결과 텍스트.
///
/// 재연결은 **버튼 하나로 열거 → 연결까지** 끝낸다 (별도 "포트 다시 검색"
/// 아이콘은 역할이 겹쳐 제거됨). Windows 흐름은 [_reconnectWindows] 참조:
/// COM 포트를 다시 열거하고, 저장된 포트를 우선으로 순차 probe 해서 응답한
/// 포트를 채택한다. USB 재삽입으로 포트 번호가 바뀌어도 복구된다.
class ExternalPrinterSubSettings extends ConsumerStatefulWidget {
  const ExternalPrinterSubSettings({
    super.key,
    required this.isUseExternalPrinter,
    required this.printOrder,
    required this.printReceipt,
    required this.printCall,
    required this.onPrintOrderChanged,
    required this.onPrintReceiptChanged,
    required this.onPrintCallChanged,
  });

  final bool isUseExternalPrinter;

  /// 매트릭스: 주문서 출력 여부.
  final bool printOrder;

  /// 매트릭스: 영수증 출력 여부.
  final bool printReceipt;

  /// 매트릭스: 기기 호출 알림 출력 여부.
  final bool printCall;

  final void Function(bool) onPrintOrderChanged;
  final void Function(bool) onPrintReceiptChanged;
  final void Function(bool) onPrintCallChanged;

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
  static const int _defaultBaudRate = 115200; // PR800 시리얼 고정값, CDC 는 무시

  /// 재연결 스캔의 포트별 DLE EOT 핑 재시도 상한.
  ///
  /// 저장된 포트는 "이게 맞는 포트인데 프린터가 회복 중"일 수 있으므로 기본값
  /// 그대로 넉넉히 재시도한다. 나머지 후보는 "응답하나?" 만 보면 되므로 1회 —
  /// 무응답 포트당 ~1.9초가 ~0.6초로 줄어 포트가 여러 개인 PC 에서도 스캔이
  /// 몇 초 안에 끝난다.
  ///
  /// 5 는 `ComPortPrintService._probeMaxAttempts` 와 같은 값이다. private 이라
  /// 참조할 수 없고, 참조하면 안드로이드에서 win32 static init 이 트리거되므로
  /// (아래 `_defaultComPort` 주석과 같은 이유) 여기 복제한다 — 함께 유지할 것.
  static const int _probeAttemptsSavedPort = 5;
  static const int _probeAttemptsScan = 1;

  late final PreferenceService _pref;

  List<ComPortDescriptor> _comPorts = const [];
  String _selectedComPort = _defaultComPort;
  int _baudRate = _defaultBaudRate;
  bool _isReconnecting = false;

  /// 재연결 결과 문구. 테스트 출력 결과([_testResult])와 분리해 서로 덮어쓰지
  /// 않게 한다 (두 버튼이 같은 카드 안에 있어 섞이면 오해를 부른다).
  String? _reconnectResult;
  String? _testResult;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _pref = ref.read(preferenceServiceProvider);
    _baudRate = _pref.getComPortBaudRate();
    _selectedComPort = _pref.getComPortName() ?? _defaultComPort;
    if (Platform.isWindows) {
      // _initialEnumerate 끝에서 printerStatusProvider 를 변경하는
      // checkConnection() 을 호출한다. 외부 프린터 OFF 등으로 도중 await 가 한 번도
      // yield 되지 않으면 build phase 에서 provider mutation 이 일어나 Riverpod 가
      // throw. PrintService 생성자([print_service.dart:48]) 와 동일한 패턴으로
      // microtask 으로 defer 한다.
      Future.microtask(_initialEnumerate);
    }
  }

  /// 화면 진입 시: 포트 목록/장치명만 채우고 연결상태를 한 번 갱신한다.
  ///
  /// 포트를 실제로 열어보는 probe 스캔은 하지 않는다 — 설정 화면을 열 때마다
  /// 캐시드로어·저울 같은 다른 COM 장비까지 핑하게 되고, 수 초씩 걸린다.
  /// 스캔은 사용자가 재연결을 명시적으로 눌렀을 때만.
  Future<void> _initialEnumerate() async {
    if (!Platform.isWindows) return;
    try {
      await _enumeratePorts();
      if (!mounted) return;
      await ref
          .read(printServiceProvider)
          .checkConnection(external: true, label: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconnectResult = 'COM 포트 조회 실패: $e');
    }
  }

  /// COM 포트 열거 + 장치 식별 정보 조회. 포트를 열지 않는다.
  ///
  /// 저장된 포트가 목록에 없어도 선택값을 바꾸지 않는다 — 잠깐 사라진 것뿐일 수
  /// 있는데 조용히 다른 포트로 갈아타면 엉뚱한 장비로 출력될 수 있다.
  /// 포트 전환은 probe 응답을 받은 [_reconnect] 에서만 일어난다.
  Future<List<ComPortDescriptor>> _enumeratePorts() async {
    await win_transport.loadLibrary();
    final ports = win_transport.listComPorts();
    if (mounted) setState(() => _comPorts = ports);
    logToFile(
      tag: LogTag.PLATFORM,
      message: 'COM 포트 열거: ${ports.length}개 '
          '[${ports.map((p) => p.displayLabel).join(' | ')}], '
          '저장=${_pref.getComPortName() ?? "(미설정)"}',
    );
    return ports;
  }

  /// 재연결 버튼의 유일한 핸들러: 포트 재열거 → 순차 probe → 연결까지.
  Future<void> _reconnect() async {
    if (_isReconnecting) return;
    final ps = ref.read(printServiceProvider);
    setState(() {
      _isReconnecting = true;
      _reconnectResult = null;
    });
    logToFile(tag: LogTag.UI_ACTION, message: '외부 프린터 재연결 요청');
    try {
      if (Platform.isWindows) {
        await _reconnectWindows();
      } else if (Platform.isAndroid) {
        // UsbReceiptPrinter.discover() 재탐색 — 권한 거부 / 늦은 핫플러그로 한 번
        // 비어있던 상태를 회복시킨다.
        await ps.reconnectExternalPrinter();
      }
      // label: false 로 호출해 라벨 status 가 외부 재연결로 같이 토글되는 sync
      // 이슈 회피. (라벨은 별도 재연결 버튼이 갱신.)
      // printerStatusProvider 갱신 경로는 PrintService 하나로 유지한다.
      await ps.checkConnection(external: true, label: false);
    } catch (e) {
      if (mounted) setState(() => _reconnectResult = '재연결 실패: $e');
    } finally {
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  /// Windows 재연결: 열거 → 저장 포트 우선 순차 probe → 응답한 포트 채택.
  Future<void> _reconnectWindows() async {
    final ports = await _enumeratePorts();
    final saved = _pref.getComPortName();
    final candidates =
        orderProbeCandidates(ports.map((p) => p.portName).toList(), saved);

    if (candidates.isEmpty) {
      if (!mounted) return;
      setState(() =>
          _reconnectResult = 'COM 포트가 하나도 없습니다. 케이블·USB-Serial 드라이버를 확인하세요.');
      return;
    }

    String? hit;
    for (final port in candidates) {
      final attempts =
          (port == saved) ? _probeAttemptsSavedPort : _probeAttemptsScan;
      bool ok = false;
      try {
        ok = await win_transport.probeComPort(
          port,
          baudRate: _baudRate,
          maxAttempts: attempts,
        );
      } catch (e) {
        logToFile(
          tag: LogTag.WARNING,
          message: '재연결 probe 예외: $port — $e',
        );
      }
      logToFile(
        tag: LogTag.PLATFORM,
        message: '재연결 probe $port ($attempts회, baud=$_baudRate) '
            '→ ${ok ? "응답" : "무응답"}',
      );
      if (ok) {
        hit = port;
        break;
      }
      // 설정 화면이 닫혔으면 남은 포트까지 열어볼 이유가 없다.
      if (!mounted) return;
    }

    if (hit == null) {
      // 저장값은 그대로 둔다 — 프린터 전원이 잠깐 꺼진 것뿐일 수 있고,
      // 사용자가 고른 포트를 말없이 바꾸면 나중에 더 혼란스럽다.
      if (!mounted) return;
      setState(() => _reconnectResult =
          '프린터를 찾지 못했습니다 (${candidates.length}개 포트 확인: ${candidates.join(", ")}). '
          '전원·케이블을 확인하거나 BAUD RATE 를 바꿔 다시 시도하세요.');
      return;
    }

    if (hit != saved) {
      await _pref.setComPortName(hit);
      logToFile(
        tag: LogTag.PLATFORM,
        message: '외부 프린터 COM 포트 자동 전환: ${saved ?? "(미설정)"} → $hit',
      );
    }
    final desc = ports.firstWhere(
      (p) => p.portName == hit,
      orElse: () => ComPortDescriptor(portName: hit!),
    );
    if (!mounted) return;
    setState(() {
      _selectedComPort = hit!;
      _testResult = null;
      _reconnectResult = '연결됨 — ${desc.displayLabel}';
    });
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

    // 점유 충돌 등으로 PrinterJobQueue backoff(최대 137s) 가 다이얼로그 잠금을
    // 길게 끌지 않도록 8초 timeout 부여. 시간 초과 시 잠금 해제 + 안내 표시,
    // 백그라운드 큐는 계속 재시도(점유 풀리면 그때 자연 출력될 수 있음).
    const testTimeout = Duration(seconds: 8);
    bool ok = false;
    bool timedOut = false;
    try {
      ok = await ref
          .read(printServiceProvider)
          .printTestPage(targetExternalOnly: true)
          .timeout(testTimeout);
    } on TimeoutException {
      timedOut = true;
    } catch (e) {
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
      if (timedOut) {
        _testResult = '응답 지연 — 프린터 점유/오프라인 확인 후 다시 시도 (백그라운드 재시도 진행 중)';
      } else {
        _testResult = ok ? '테스트 출력 성공' : '테스트 출력 실패';
      }
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
          isBusy: _isReconnecting,
          onReconnect: _reconnect,
        ),
        if (_reconnectResult != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            _reconnectResult!,
            style: AppTextStyles.bodySm.copyWith(
              color: _reconnectResult!.startsWith('연결됨')
                  ? AppStyles.green100
                  : AppStyles.kRed,
            ),
          ),
        ],
        if (widget.isUseExternalPrinter) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildMatrixRow(
            label: '주문서 출력',
            value: widget.printOrder,
            onChanged: (v) {
              ref
                  .read(printServiceProvider)
                  .updatePrinterSettings(externalPrintOrder: v);
              widget.onPrintOrderChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildMatrixRow(
            label: '영수증 출력',
            value: widget.printReceipt,
            onChanged: (v) {
              ref
                  .read(printServiceProvider)
                  .updatePrinterSettings(externalPrintReceipt: v);
              widget.onPrintReceiptChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildMatrixRow(
            label: '기기 호출 알림 출력',
            value: widget.printCall,
            onChanged: (v) {
              ref
                  .read(printServiceProvider)
                  .updatePrinterSettings(externalPrintCall: v);
              widget.onPrintCallChanged(v);
            },
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
        if (kDebugMode && widget.isUseExternalPrinter) ...[
          const SizedBox(height: AppSpacing.s12),
          _buildDebugBusyInjector(),
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
          activeThumbColor: AppStyles.kMainColor,
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
              Text(
                _isReconnecting ? '검색 중…' : '포트 ${_comPorts.length}개',
                style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_comPorts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: Text(
                _isReconnecting
                    ? '검색 중…'
                    : 'COM 포트를 찾을 수 없습니다. 케이블·USB-Serial 드라이버를 확인한 뒤 재연결을 누르세요.',
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
                  value: _comPorts.any((p) => p.portName == _selectedComPort)
                      ? _selectedComPort
                      : _comPorts.first.portName,
                  items: _comPorts
                      .map((port) => DropdownMenuItem<String>(
                            value: port.portName,
                            child: Text(
                              port.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: _isReconnecting
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedComPort = value;
                            _testResult = null;
                            _reconnectResult = null;
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
          ],
          // BAUD RATE 는 포트 목록 유무와 무관한 설정이다. 포트가 안 잡혔다고
          // 함께 사라지면 "무응답이니 baud 를 바꿔보라" 는 복구 경로가 막힌다.
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
                          _reconnectResult = null;
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
          const SizedBox(height: AppSpacing.s8),
          Text(
            '※ 재연결을 누르면 COM 포트를 다시 검색하고, 프린터가 응답하는 포트로 자동 연결합니다.\n'
            '※ 포트 이름 옆은 Windows 가 인식한 장치명(USB-Serial 어댑터 기준)이며 프린터 모델명과 다를 수 있습니다.',
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
        Platform.isWindows && _comPorts.isEmpty && !_isReconnecting;

    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: (_isTesting || _isReconnecting || isWindowsWithoutPort)
              ? null
              : _handleTestPrint,
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

  // Android USB Host API 는 claimInterface(force=true) 라 외부 도구만으로
  // 점유 충돌을 재현할 수 없다. 디버그 빌드에서 다음 N 회 송출을 강제
  // PrinterBusy 로 만들어 PrinterJobQueue 의 0/2/5/10/20/40/60s backoff 7단계
  // 전 구간을 결정적으로 검증할 수 있게 한다.
  Widget _buildDebugBusyInjector() {
    const presets = [0, 1, 3, 7];
    final remaining = DebugPrinterFault.remaining;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
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
                '[DEBUG] 다음 N회 외부 강제 BUSY',
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppStyles.gray9,
                ),
              ),
              const Spacer(),
              Text(
                '잔여: $remaining',
                style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            children: presets
                .map((n) => ChoiceChip(
                      label: Text(n == 0 ? 'Off' : '$n'),
                      selected: remaining == n,
                      onSelected: (selected) {
                        if (!selected) return;
                        setState(() {
                          DebugPrinterFault.schedule(n);
                        });
                        logToFile(
                          tag: LogTag.UI_ACTION,
                          message:
                              '[DEBUG] DebugPrinterFault.schedule($n) — 다음 $n회 강제 BUSY',
                        );
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            '※ 디버그 빌드 전용. 테스트 출력 시 카운터만큼 PrinterBusy 반환 → '
            'PrinterJobQueue 가 0/2/5/10/20/40/60s 백오프(누적 ~137s)로 재시도.',
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
        ],
      ),
    );
  }
}
