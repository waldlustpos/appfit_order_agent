import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/constants/app_styles.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/external_printer_target.dart';
import 'package:appfit_order_agent/services/external_receipt_printer.dart'
    show ExternalReceiptPrinter;
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/print_service.dart';
import 'package:appfit_order_agent/services/printer_transport.dart'
    show DebugPrinterFault;
import 'package:appfit_order_agent/services/receipt_escpos_builder.dart'
    show ReceiptEscPosBuilder;
import 'package:appfit_order_agent/widgets/settings/settings_connection_status.dart';

// Windows 장치 enumerate(COM / usbprint) 는 안드로이드 빌드에서 win32 native init
// (kernel32.dll lookup) 을 트리거하므로 deferred 로 격리 — Windows 분기 안에서만
// loadLibrary.
import 'package:appfit_order_agent/services/external_receipt_printer_windows.dart'
    deferred as win_transport;

/// "외부 프린터 사용" 토글의 additionalContent.
///
/// - 모든 플랫폼: 연결상태 + 재연결 ([SettingsConnectionStatus]).
/// - Windows + 외부 프린터 ON: 연결 대상 선택 + Baud rate.
/// - 외부 프린터 ON: "테스트 출력" 버튼 + 결과 텍스트.
///
/// 재연결은 **버튼 하나로 열거 → 연결까지** 끝낸다 (별도 "포트 다시 검색"
/// 아이콘은 역할이 겹쳐 제거됨). Windows 흐름은 [_reconnectWindows] 참조:
/// **케이블 종류를 가리지 않고** COM(시리얼/가상COM)과 usbprint(USB 프린터 클래스)를
/// 함께 열거하고, 저장 대상을 우선으로 순차 probe 해서 응답한 장치를 채택한다.
/// USB 재삽입으로 포트 번호나 장치 경로가 바뀌어도 복구된다.
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

  /// COM + usbprint 를 합친 연결 후보 목록. 사용자는 케이블 종류를 의식하지
  /// 않고 이 목록만 본다.
  List<ExternalPrinterTarget> _targets = const [];

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
    if (Platform.isAndroid) {
      // Android 는 연결 대상 선택 UI 가 없다(네이티브가 알아서 잡는다). 폭
      // 프리시드만 네이티브에 VID/PID 를 물어 처리한다 — 폭 설정이 생기기 전에
      // 설치된 PR800 단말이 기본값(42)으로 떨어지지 않게 하기 위함.
      Future.microtask(_preseedColumnsAndroid);
    }
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
      final targets = await _enumerateAll();
      // 이미 쓰고 있던 대상의 폭을 여기서도 프리시드한다. 폭 설정이 생기기 전에
      // 설치된 단말은 저장값이 null 이라 기본값(42)으로 떨어지는데, PR800 처럼
      // 넓은 기종은 재연결을 누르지 않아도 설정 화면을 여는 것만으로 48 을
      // 되찾아야 한다. (설정이 비어 있을 때만 개입하므로 멱등하다.)
      final saved = _savedTarget();
      if (saved != null) {
        final enriched = targets.where((t) => t.sameAs(saved)).firstOrNull;
        if (enriched != null) await _preseedColumns(enriched);
      }
      if (!mounted) return;
      await ref
          .read(printServiceProvider)
          .checkConnection(external: true, label: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconnectResult = '프린터 장치 조회 실패: $e');
    }
  }

  /// 지금 설정에 저장돼 있는 연결 대상. 없으면 null.
  ///
  /// 저장 형태는 "종류 + 종류별 식별자" 두 키로 나뉘어 있다
  /// (`PreferenceService.getExternalPrinterConnection` + 각 식별자). 여기서 한
  /// 값으로 합쳐 UI/스캔이 종류를 의식하지 않게 한다.
  ExternalPrinterTarget? _savedTarget() {
    final isUsb = _pref.getExternalPrinterConnection() ==
        PreferenceService.extPrinterConnUsbPrint;
    final id =
        isUsb ? _pref.getUsbPrintDevicePath() : _pref.getComPortName();
    if (id == null || id.isEmpty) return null;
    // 목록에 같은 대상이 있으면 그쪽 라벨(장치명 포함)을 쓴다. 없으면 식별자만.
    final known = _targets
        .where((t) =>
            t.kind ==
                (isUsb
                    ? ExternalPrinterKind.usbPrint
                    : ExternalPrinterKind.com) &&
            t.id.toLowerCase() == id.toLowerCase())
        .firstOrNull;
    return known ??
        ExternalPrinterTarget(
          kind: isUsb
              ? ExternalPrinterKind.usbPrint
              : ExternalPrinterKind.com,
          id: id,
          label: id,
        );
  }

  /// 채택 확정 — 종류와 식별자를 함께 저장한다. 두 값이 어긋나면 전송이 엉뚱한
  /// 경로로 가므로 반드시 쌍으로 쓴다.
  ///
  /// 폭은 **설정이 비어 있을 때만** 프리시드한다. 사용자가 한 번이라도 고른
  /// 뒤에는 재연결로 대상이 바뀌어도 덮지 않는다 — 자동 추정이 사용자의 명시적
  /// 선택을 이기면 "설정을 만진 적 없는데 출력이 바뀐다" 가 되기 때문.
  Future<void> _latch(ExternalPrinterTarget t) async {
    await _pref.setExternalPrinterConnection(t.kind.prefValue);
    if (t.kind == ExternalPrinterKind.usbPrint) {
      await _pref.setUsbPrintDevicePath(t.id);
    } else {
      await _pref.setComPortName(t.id);
    }
    logToFile(
      tag: LogTag.PLATFORM,
      message: '외부 프린터 연결 대상 확정 -> ${t.kind.prefValue}:${t.id} (${t.label})',
    );

    await _preseedColumns(t);
  }

  /// 알려진 기종이면 폭을 프리시드한다. **설정이 비어 있을 때만** 개입.
  ///
  /// COM 후보는 포트명에 VID/PID 가 없어 `hardwareId` 로만 기종을 알 수 있다 —
  /// 그래서 [ExternalPrinterTarget.hardwareId] 를 들고 다닌다. 기본값 42 는
  /// POSBANK 계열 기준이고, PR800 처럼 넓은 기종이 이 경로로 48 을 되찾는다.
  /// Android 판 프리시드. 연결 대상 선택 UI 가 없어 네이티브에 VID/PID 를 묻는다.
  /// Windows 와 같은 테이블([knownColumnsForDeviceString])을 쓴다.
  Future<void> _preseedColumnsAndroid() async {
    if (_pref.getExternalPrinterColumns() != null) return;
    try {
      final idString = await ExternalReceiptPrinter().connectedUsbIdString();
      final known = knownColumnsForDeviceString(idString);
      if (known == null) return;
      await _pref.setExternalPrinterColumns(known);
      if (mounted) setState(() {});
      logToFile(
        tag: LogTag.PLATFORM,
        message: '외부 프린터 용지 폭 프리시드 -> $known칸 '
            '($idString, 알려진 기종, 설정이 비어 있었음)',
      );
    } catch (e) {
      logToFile(tag: LogTag.WARNING, message: '용지 폭 프리시드 실패(Android): $e');
    }
  }

  Future<void> _preseedColumns(ExternalPrinterTarget t) async {
    if (_pref.getExternalPrinterColumns() != null) return;
    final known = t.knownColumns;
    if (known == null) return;
    await _pref.setExternalPrinterColumns(known);
    if (mounted) setState(() {});
    logToFile(
      tag: LogTag.PLATFORM,
      message: '외부 프린터 용지 폭 프리시드 -> $known칸 '
          '(${t.uiValue}, 알려진 기종, 설정이 비어 있었음)',
    );
  }

  /// COM + usbprint 양쪽을 열거해 한 목록으로 합친다. **장치를 열지 않는다** —
  /// COM 은 레지스트리 조회, usbprint 는 `DIGCF_PRESENT` 조회뿐이라 값싸다.
  /// 실제로 열어보는 probe 는 재연결 버튼에서만.
  Future<List<ExternalPrinterTarget>> _enumerateAll() async {
    await win_transport.loadLibrary();

    // 한쪽 열거가 실패해도 다른 쪽 목록은 살린다 — 드라이버 문제로 COM 조회가
    // 깨졌다고 USB 프린터까지 못 쓰게 될 이유가 없다.
    List<ExternalPrinterTarget> usb = const [];
    try {
      usb = win_transport
          .listUsbPrintDevices()
          .map((d) => ExternalPrinterTarget(
                kind: ExternalPrinterKind.usbPrint,
                id: d.devicePath,
                label: d.displayLabel,
              ))
          .toList();
    } catch (e) {
      logToFile(tag: LogTag.WARNING, message: 'USB 프린터 열거 실패: $e');
    }

    List<ExternalPrinterTarget> com = const [];
    try {
      com = win_transport
          .listComPorts()
          .map((p) => ExternalPrinterTarget(
                kind: ExternalPrinterKind.com,
                id: p.portName,
                label: p.displayLabel,
                // 기종별 폭 프리시드가 COM 경로에서도 동작하려면 VID/PID 가
                // 필요한데, COM 은 포트명에 그게 없어 hardwareId 로만 알 수 있다.
                hardwareId: p.hardwareId,
              ))
          .toList();
    } catch (e) {
      logToFile(tag: LogTag.WARNING, message: 'COM 포트 열거 실패: $e');
    }

    final all = [...usb, ...com];
    if (mounted) setState(() => _targets = all);
    logToFile(
      tag: LogTag.PLATFORM,
      message: '외부 프린터 후보 열거: USB ${usb.length}개 + COM ${com.length}개 '
          '[${all.map((t) => t.displayLabel).join(' | ')}], '
          '저장=${_savedTarget()?.uiValue ?? "(미설정)"}',
    );
    return all;
  }

  /// 재연결 버튼의 유일한 핸들러: 장치 재열거 → 순차 probe → 연결까지.
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

  /// Windows 재연결: **케이블 종류를 가리지 않는 통합 스캔**.
  ///
  /// 열거(COM + usbprint) → 저장 대상 우선, 그다음 usbprint, 그다음 COM 순서로
  /// 순차 probe → **응답한 첫 장치를 채택**한다. 사용자는 시리얼인지 USB인지
  /// 알 필요가 없다.
  ///
  /// 자동 채택이 Winspool 금지에 저촉되지 않는 이유: Winspool 이 위험했던 건
  /// "OS 기본 프린터" 라는 *무엇이든 가리킬 수 있는 추상*(PDF 라이터 · 네트워크
  /// 프린터 · 라벨)을 썼기 때문이다. 여기서는 ① 라벨 프린터 VID 가 열거 단계에서
  /// 빠지고 ② **ESC/POS 응답을 실제로 받은** 장치만 채택한다. 이 두 관문 중
  /// 하나라도 빼면 그때는 저촉된다.
  ///
  /// 스캔이 무관한 장비(캐시드로어 · 저울)를 건드릴 수 있으므로 **재연결 버튼을
  /// 눌렀을 때만** 돈다 — 화면 진입 시 자동 스캔은 하지 않는다.
  Future<void> _reconnectWindows() async {
    final targets = await _enumerateAll();
    if (!mounted) return;

    final saved = _savedTarget();
    final candidates = orderScanCandidates(targets, saved);

    if (candidates.isEmpty) {
      setState(() => _reconnectResult = '프린터를 찾을 수 없습니다. 전원·케이블과 '
          'USB-Serial 드라이버를 확인하세요. (라벨 프린터는 목록에서 제외됩니다)');
      return;
    }

    ExternalPrinterTarget? hit;
    for (final t in candidates) {
      final ok = await _probeTarget(t, isSaved: t.sameAs(saved));
      if (ok) {
        hit = t;
        break;
      }
      // 설정 화면이 닫혔으면 남은 후보까지 열어볼 이유가 없다.
      if (!mounted) return;
    }

    if (hit == null) {
      // 저장값은 그대로 둔다 — 프린터 전원이 잠깐 꺼진 것뿐일 수 있고,
      // 쓰던 대상을 말없이 지우면 나중에 더 혼란스럽다.
      setState(() => _reconnectResult =
          '프린터를 찾지 못했습니다 (${candidates.length}개 후보 확인). '
              '전원·케이블을 확인하거나, 시리얼 프린터라면 BAUD RATE 를 바꿔 다시 시도하세요.');
      return;
    }

    if (!hit.sameAs(saved)) {
      await _latch(hit);
    }
    if (!mounted) return;
    setState(() {
      _testResult = null;
      _reconnectResult = '연결됨 — ${hit!.displayLabel}';
    });
  }

  /// 후보 1건 probe. 종류에 맞는 서비스로 위임한다.
  ///
  /// [isSaved] 면 COM 재시도를 넉넉히 준다 — "이게 맞는 포트인데 프린터가 회복
  /// 중" 일 수 있기 때문. 나머지 후보는 "응답하나?" 만 보면 되므로 1회다
  /// (무응답 포트당 ~1.9초가 ~0.6초로 줄어 후보가 많은 PC 에서도 몇 초 안에 끝난다).
  /// usbprint 는 열거 자체가 생존 신호라 재시도 개념이 없다.
  Future<bool> _probeTarget(ExternalPrinterTarget t,
      {required bool isSaved}) async {
    bool ok = false;
    try {
      if (t.kind == ExternalPrinterKind.usbPrint) {
        ok = await win_transport.probeUsbPrintDevice(t.id);
      } else {
        ok = await win_transport.probeComPort(
          t.id,
          baudRate: _baudRate,
          maxAttempts:
              isSaved ? _probeAttemptsSavedPort : _probeAttemptsScan,
        );
      }
    } catch (e) {
      logToFile(
        tag: LogTag.WARNING,
        message: '재연결 probe 예외: ${t.uiValue} — $e',
      );
    }
    logToFile(
      tag: LogTag.PLATFORM,
      message: '재연결 probe ${t.uiValue}'
          '${t.kind == ExternalPrinterKind.com ? " (baud=$_baudRate)" : ""} '
          '→ ${ok ? "응답" : "무응답"}',
    );
    return ok;
  }

  /// "용지 폭 확인" — 후보 폭별 눈금자를 뽑는다.
  ///
  /// 테스트 출력과 같은 큐/타임아웃 규율을 따른다. 결과 문구도 [_testResult] 를
  /// 공유한다 — 두 버튼이 같은 진단 흐름의 앞뒤라 문구가 따로 놀 이유가 없다.
  Future<void> _handleRuler() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
      _testResult = '용지 폭 확인 출력 중...';
    });
    logToFile(tag: LogTag.UI_ACTION, message: '용지 폭 확인 출력 요청');

    const timeout = Duration(seconds: 8);
    bool ok = false;
    bool timedOut = false;
    try {
      ok = await ref
          .read(printServiceProvider)
          .printWidthRuler()
          .timeout(timeout);
    } on TimeoutException {
      timedOut = true;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testResult = '용지 폭 확인 실패: $e';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      if (timedOut) {
        _testResult = '응답 지연 — 프린터 점유/오프라인 확인 후 다시 시도 (백그라운드 재시도 진행 중)';
      } else {
        _testResult = ok ? '넘치지 않은 가장 위의 막대 칸수를 선택하세요' : '용지 폭 확인 실패';
      }
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
      message: !Platform.isWindows
          ? '테스트 출력 시도 (Android)'
          : '테스트 출력 시도: ${_savedTarget()?.uiValue ?? "(대상 미설정)"}'
              '${_savedTarget()?.kind == ExternalPrinterKind.com ? ", baud=$_baudRate" : ""}',
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
          _buildDevicePicker(),
        ],
        if (widget.isUseExternalPrinter) ...[
          // 폭은 플랫폼 무관 — 같은 A8 이 Sunmi 단말에 물려도 42 컬럼이다.
          const SizedBox(height: AppSpacing.s12),
          _buildColumnsPicker(),
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

  // ── 용지 폭 카드 (전 플랫폼) ─────────────────────────────────────────────
  //
  // 기종마다 실효 컬럼이 다르다 — PR800 48, POSBANK A8 42. ESC/POS 에는 "몇
  // 컬럼이냐" 를 묻는 표준 질의가 없어서(`GS W` 는 쓰기 전용) 자동 판별이
  // 불가능하다. 그래서 ① 알려진 USB 기종은 첫 연결 시 프리시드하고 ② 나머지는
  // 눈금자를 뽑아 사람이 고른다.
  //
  // Windows 전용이 아니다 — 같은 A8 을 Sunmi 단말에 물려도 42 컬럼이다.
  Widget _buildColumnsPicker() {
    final current =
        _pref.getExternalPrinterColumns() ?? ReceiptEscPosBuilder.defaultColumns;
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
                '용지 폭 (한 줄 글자 수)',
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppStyles.gray9,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: (_isTesting || _isReconnecting) ? null : _handleRuler,
                icon: const Icon(Icons.straighten, size: 18),
                label: const Text('용지 폭 확인'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            spacing: AppSpacing.s8,
            children: ReceiptEscPosBuilder.columnOptions
                .map((n) => ChoiceChip(
                      label: Text('$n칸'),
                      selected: current == n,
                      onSelected: (selected) {
                        if (!selected || current == n) return;
                        _pref.setExternalPrinterColumns(n);
                        setState(() {
                          _testResult = null;
                        });
                        logToFile(
                          tag: LogTag.UI_ACTION,
                          message: '외부 프린터 용지 폭 선택 -> $n칸',
                        );
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            '※ "용지 폭 확인"을 누르면 48/42/32칸 막대가 출력됩니다. '
            '다음 줄로 넘치지 않은 가장 위의 막대가 이 프린터의 폭입니다.\n'
            '※ 막대 왼쪽에 빈칸이 생긴다면 폭이 아니라 프린터의 좌측 여백 설정 문제입니다.\n'
            '※ 폭이 실제보다 크면 구분선과 수량 칸이 다음 줄로 밀리고, 작으면 오른쪽 여백이 남습니다.',
            style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
          ),
        ],
      ),
    );
  }

  // ── 연결 대상 선택 카드 (Windows 전용) ───────────────────────────────────
  //
  // COM 시리얼과 USB 프린터를 **한 목록으로** 보여준다. 두 경로는 서로소 집합이라
  // (물리 RS-232 프린터는 usbprint 에 안 나오고, usbprint.sys 에 바인딩된 프린터는
  // COM 을 안 만든다) 사용자가 종류를 고를 이유가 없다 — 재연결이 양쪽을 훑어
  // 응답하는 장치를 잡는다. 이 드롭다운은 그 결과를 보여주고, 여러 대가 물린
  // 매장에서 수동 교정할 수단을 남기는 용도다.
  Widget _buildDevicePicker() {
    final saved = _savedTarget();
    final selectedValue = _targets.any((t) => t.sameAs(saved))
        ? saved!.uiValue
        : null;
    // BAUD RATE 는 시리얼 후보가 하나라도 있거나 현재 대상이 COM 일 때만 의미가
    // 있다. 다만 "무응답이니 baud 를 바꿔보라" 는 복구 경로를 막지 않도록,
    // 목록이 비어 있을 때도 보여준다.
    final showBaud = _targets.isEmpty ||
        _targets.any((t) => t.kind == ExternalPrinterKind.com) ||
        saved?.kind == ExternalPrinterKind.com;

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
                '프린터 연결 설정',
                style: AppTextStyles.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppStyles.gray9,
                ),
              ),
              const Spacer(),
              Text(
                _isReconnecting ? '검색 중…' : '후보 ${_targets.length}개',
                style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          if (_targets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: Text(
                _isReconnecting
                    ? '검색 중…'
                    : '연결 가능한 프린터를 찾을 수 없습니다. 전원·케이블과 USB-Serial 드라이버를 '
                        '확인한 뒤 재연결을 누르세요.',
                style: AppTextStyles.bodySm.copyWith(color: AppStyles.gray6),
              ),
            )
          else ...[
            Text(
              '연결 대상',
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
                // 목록 첫 항목으로 자동으로 떨어뜨리지 않는다 — 미설정은 미설정으로
                // 남아야 "고르지도 probe 하지도 않은 장치로 영수증이 나가는" 일이 없다.
                // 채택은 재연결(= ESC/POS 응답 확인) 또는 사용자의 명시 선택으로만.
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedValue,
                  hint: const Text('재연결을 눌러 자동으로 찾거나, 직접 선택하세요'),
                  items: _targets
                      .map((t) => DropdownMenuItem<String>(
                            value: t.uiValue,
                            child: Text(
                              t.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: _isReconnecting
                      ? null
                      : (value) {
                          if (value == null) return;
                          final picked = _targets
                              .where((t) => t.uiValue == value)
                              .firstOrNull;
                          if (picked == null) return;
                          setState(() {
                            _testResult = null;
                            _reconnectResult = null;
                          });
                          _latch(picked);
                          logToFile(
                            tag: LogTag.UI_ACTION,
                            message: '외부 프린터 수동 선택 -> ${picked.uiValue}',
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
          if (showBaud) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              'BAUD RATE (시리얼 연결에만 적용)',
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
          ],
          const SizedBox(height: AppSpacing.s8),
          Text(
            '※ 재연결을 누르면 시리얼·USB 양쪽을 다시 검색하고, 프린터가 응답하는 장치로 자동 연결합니다.\n'
            '※ 목록의 "· USB" 는 Windows 프린터 큐(스풀러)를 거치지 않고 장치로 직접 출력하는 연결입니다.\n'
            '※ 라벨 프린터는 영수증이 잘못 송출되지 않도록 목록에서 제외됩니다.\n'
            '※ 시리얼 항목의 장치명은 USB-Serial 어댑터 기준이라 프린터 모델명과 다를 수 있습니다.',
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
    // 보낼 대상이 없으면 버튼을 잠근다. "후보는 있는데 아직 채택 안 됨" 도
    // 대상 없음이다 — 그 상태로 큐에 넣어봐야 PrinterNoDevice 로 137초 backoff 만
    // 돌 뿐이고, 사용자는 재연결을 눌러야 한다는 걸 알 수 없다.
    // (`WindowsTransport` 가 실제로 읽는 것도 이 저장값 하나다.)
    final isWindowsWithoutTarget =
        Platform.isWindows && !_isReconnecting && _savedTarget() == null;

    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: (_isTesting || _isReconnecting || isWindowsWithoutTarget)
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
