import 'dart:io';

import 'package:flutter/services.dart';
import 'package:appfit_order_agent/services/com_port_print_service.dart';
import 'package:appfit_order_agent/services/label_printer/windows/windows_label_printer_backend.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/services/windows_print_service.dart';
import '../models/order_model.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import '../services/preference_service.dart';

class PrinterStatus {
  final bool isExternalConnected;
  final bool isLabelConnected;

  PrinterStatus({
    this.isExternalConnected = false,
    this.isLabelConnected = false,
  });
}

final printerStatusProvider =
    StateProvider<PrinterStatus>((ref) => PrinterStatus());

class PrintService {
  final Ref ref;
  final PreferenceService _preferenceService;

  // 프린터 설정값 캐시
  bool? _cachedBuiltinPrinter;
  bool? _cachedExternalPrinter;
  bool? _cachedLabelPrinter;

  var tag = '프린트';

  PrintService(this.ref) : _preferenceService = PreferenceService() {
    // 초기 설정값 로드
    _loadPrinterSettings();
    // USB 디바이스 확인.
    // Riverpod provider build 도중 ref.read(...).state= 가 동기적으로 실행되면
    // assertion 위반 (Providers 가 build 중 다른 provider 수정 금지).
    // Android 흐름은 첫 라인이 await PlatformService.getConnectedUsbDevices()
    // 라 항상 microtask 로 yield 되어 안전했지만, Windows 분기는 _cachedLabelPrinter
    // 가 false 거나 backend.isOpen=true 면 첫 await 없이 state 가 갱신될 수 있다.
    // 다음 microtask 으로 deferred 해서 provider build 종료 후 실행되게 한다.
    Future.microtask(checkConnection);
  }

  // 프린터 설정값 로드
  void _loadPrinterSettings() {
    _cachedBuiltinPrinter = _preferenceService.getUseBuiltinPrinter();
    _cachedExternalPrinter = _preferenceService.getUseExternalPrinter();
    _cachedLabelPrinter = _preferenceService.getUseLabelPrinter();
    logToFile(
        tag: LogTag.PLATFORM,
        message:
            '프린터 설정 업데이트: 내장=${_cachedBuiltinPrinter}, 외부=${_cachedExternalPrinter}, 라벨=${_cachedLabelPrinter}');
  }

  // 프린터 연결 상태 관리
  Future<void> checkConnection() async {
    // Windows: USB enumerate (PlatformService.getConnectedUsbDevices) 가 Android
    // MethodChannel 전용이라 Windows 에서는 빈 리스트 반환 -> 라벨 프린터를 못
    // 잡는다. autoreplyprint SDK 의 CP_Port_EnumUsb 가 라벨 프린터를 직접 enumerate
    // 하므로 backend.warmupOpen 결과를 그대로 사용. 외부 영수증 프린터(PR800 등)는
    // 설정된 COM 포트가 현재 SerialPort.getAvailablePorts() 결과에 있는지로 판정.
    if (Platform.isWindows) {
      bool isLabelConnected = false;
      bool isExternalConnected = false;
      try {
        if (_cachedLabelPrinter == true) {
          final backend = WindowsLabelPrinterBackend.instance;
          bool open = false;
          try {
            open = backend.isOpen;
          } catch (e, s) {
            logger.w('[PrintService] backend.isOpen 예외',
                error: e, stackTrace: s);
          }
          if (open) {
            isLabelConnected = true;
          } else {
            final mode = _preferenceService.getLabelAutoReplyMode();
            isLabelConnected =
                await backend.warmupOpen(autoReplyMode: mode);
          }
        }
        if (_cachedExternalPrinter == true) {
          final configuredPort = _preferenceService.getComPortName();
          if (configuredPort != null && configuredPort.isNotEmpty) {
            final availablePorts = ComPortPrintService.getAvailableComPorts();
            isExternalConnected = availablePorts.contains(configuredPort);
          }
        }
        logToFile(
            tag: LogTag.PLATFORM,
            message:
                '[PrintService] Windows checkConnection: label=$isLabelConnected, external=$isExternalConnected '
                '(cachedLabel=$_cachedLabelPrinter, cachedExternal=$_cachedExternalPrinter)');
      } catch (e, s) {
        logger.e('[PrintService] Windows checkConnection 예외',
            error: e, stackTrace: s);
        logToFile(
            tag: LogTag.ERROR,
            message: '[PrintService] Windows checkConnection 예외: $e');
      }
      ref.read(printerStatusProvider.notifier).state = PrinterStatus(
        isExternalConnected: isExternalConnected,
        isLabelConnected: isLabelConnected,
      );
      return;
    }
    try {
      final devices = await PlatformService.getConnectedUsbDevices();

      bool isExternalConnected = false;
      bool isLabelConnected = false;

      if (devices.isNotEmpty) {
        for (var device in devices) {
          final vendorId = device['vendorId'];
          final productId = device['productId'];
          final manufacturer = device['manufacturerName'] ?? 'Unknown';
          final productName =
              (device['productName'] ?? 'Unknown').toLowerCase();

          String identification = '';

          // 1. 라벨 프린터 식별 (LabelPrinter.java 및 LabelPrint 2 참조)
          // VID:0x4B43(19267), PID:0x3538(13624)
          // VID:0x4B43(19267), PID:0x3830(14384)
          // VID:0x0FE6(4070), PID:0x811E(33054)
          // VID:0x067B(1659), PID:0x2303(8963)
          bool isKnownLabelPrinter = (vendorId == 0x4B43 &&
                  (productId == 0x3538 || productId == 0x3830)) ||
              (vendorId == 0x0FE6 && productId == 0x811E) ||
              (vendorId == 0x067B && productId == 0x2303);

          if (isKnownLabelPrinter) {
            isLabelConnected = true;
            identification = ' [라벨 프린터 식별됨]';
          }
          // 2. 외부 영수증 프린터 식별
          // Posbank VID: 0x1552 (5458)
          // 또는 제품명에 printer, pos, mpos 등이 포함된 경우 외부 프린터로 간주
          else if (vendorId == 0x1552 ||
              vendorId == 5458 ||
              productName.contains('printer') ||
              productName.contains('pos') ||
              productName.contains('mpos')) {
            isExternalConnected = true;
            identification = ' [외부 영수증 프린터 식별됨]';
          }

          if (identification.isNotEmpty) {
            logToFile(
              tag: LogTag.PLATFORM,
              message:
                  ' - ${device['productName'] ?? 'Unknown'} ($manufacturer): VID=$vendorId, PID=$productId$identification',
            );
          }
        }
      } else {
        logToFile(tag: LogTag.PLATFORM, message: '연결된 USB 디바이스가 없습니다.');
        logger.d('연결된 USB 디바이스가 없습니다.');
      }

      // 상태 업데이트
      ref.read(printerStatusProvider.notifier).state = PrinterStatus(
        isExternalConnected: isExternalConnected,
        isLabelConnected: isLabelConnected,
      );
    } catch (e, s) {
      logger.e('USB 디바이스 확인 중 오류 발생', error: e, stackTrace: s);
    }
  }

  // 프린터 설정값 업데이트
  void updatePrinterSettings({
    bool? builtinPrinter,
    bool? externalPrinter,
    bool? labelPrinter,
  }) {
    if (builtinPrinter != null) {
      _cachedBuiltinPrinter = builtinPrinter;
    }
    if (externalPrinter != null) {
      _cachedExternalPrinter = externalPrinter;
    }
    if (labelPrinter != null) {
      _cachedLabelPrinter = labelPrinter;
    }
    logToFile(
        tag: LogTag.PLATFORM,
        message:
            '프린터 설정 수동 업데이트: 내장=${_cachedBuiltinPrinter}, 외부=${_cachedExternalPrinter}, 라벨=${_cachedLabelPrinter}');
  }

  // 주문 정보를 JSON으로 변환하여 네이티브 프린트 기능 호출
  Future<bool> printOrderReceipt({
    required OrderModel order,
    String type = 'order',
    bool isCancelReceipt = false,
  }) async {
    try {
      // 사용자 이름이 없는 경우 처리 (이미 API에서 userNickname을 받아오지만, 없을 경우를 대비한 로직은 유지 가능)
      /*
      if (order.userName == null &&
          order.userId.isNotEmpty &&
          order.userId != '3740002700000000') {
         // fetchUserName API call removed
      }
      */

      final store = ref.read(storeProvider);
      final orderWithStore = order.copyWith(storeName: store.value?.name);
      // OrderModel 에는 storePhone 필드를 추가하지 않고 toSunmiJson 출력 맵에 직접
      // 주입한다. WindowsPrintService.printReceiptFromJson 이 'storePhone' 키를
      // 읽어 매장명 아래에 TEL 줄로 출력. (사업자번호는 /v0/shop 응답에 미포함.)
      final orderMap = orderWithStore.toSunmiJson();
      final storePhone = store.value?.phone;
      if (storePhone != null && storePhone.isNotEmpty) {
        orderMap['storePhone'] = storePhone;
      }
      final orderJson = jsonEncode(orderMap);

      // 캐시된 설정값이 없는 경우에만 로드
      if (_cachedBuiltinPrinter == null || _cachedExternalPrinter == null) {
        _loadPrinterSettings();
      }

      // 영수증 재출력이고 두 프린터가 모두 켜져있는 경우 외부 프린터만 사용
      bool useBuiltin = _cachedBuiltinPrinter ?? false;
      bool useExternal = _cachedExternalPrinter ?? false;

      if (type == 'receipt' && useBuiltin && useExternal) {
        useBuiltin = false;
        logToFile(
            tag: LogTag.PLATFORM,
            message: '영수증 재출력: 내부/외부 프린터 모두 켜져있어 외부 프린터만 사용');
      }

      logger.d(
          '${type == 'order' ? '주문서출력' : '영수증출력'}: displayNum=${order.displayNum}\n--------------------------------------------------------------------------------------------------------------\n');

      logToFile(
          tag: LogTag.PLATFORM,
          message:
              '${type == 'order' ? '주문서출력' : '영수증출력'}: displayNum=${order.displayNum}\n--------------------------------------------------------------------------------------------------------------\n');

      if (Platform.isWindows) {
        final svc = WindowsPrintService();
        if (type == 'receipt') {
          return await svc.printReceiptFromJson(orderJson, isCancelReceipt);
        }
        return await svc.printOrderFromJson(orderJson, isCancelReceipt);
      }

      await platform.invokeMethod('printOrder', {
        'orderJson': orderJson,
        'type': type,
        'isCancel': isCancelReceipt,
        'useBuiltinPrint': useBuiltin,
        'useExternalPrint': useExternal
      });
      return true;
    } on PlatformException catch (e, s) {
      logger.e('Failed to print order', error: e, stackTrace: s);
      rethrow;
    }
  }

  /// 라벨 한 장 인쇄. 네이티브 [LabelPrinter.printBitmap] 의 boolean 결과를 그대로 반환.
  /// false 반환 시 호출자가 재시도/누락 로깅 결정.
  ///
  /// rethrow 대신 `return false` 로 처리: 한 라벨 실패가 OutputService 의 catch 블록을
  /// 트리거해 같은 주문의 나머지 라벨까지 막는 것을 방지하기 위함. 실패는 반환값으로 표현.
  Future<bool> printLabel(Uint8List imageBytes,
      {String orderNo = '-', int labelIndex = 1, int totalLabels = 1}) async {
    try {
      if (_cachedExternalPrinter == null) {
        _loadPrinterSettings();
      }

      bool useLabel = _cachedLabelPrinter ?? false;

      if (!useLabel) {
        logger.w('Label printer is disabled in settings.');
        return false;
      }

      final result = await platform.invokeMethod<bool>('printLabel', {
        'imageBytes': imageBytes,
        'autoReplyMode': _preferenceService.getLabelAutoReplyMode(),
        'useFeedToTear': _preferenceService.getLabelUseFeedToTear(),
        'useBackToPrint': _preferenceService.getLabelUseBackToPrint(),
        'useCalibrate': _preferenceService.getLabelUseCalibrate(),
        'orderNo': orderNo,
        'labelIndex': labelIndex,
        'totalLabels': totalLabels,
      });
      return result ?? false;
    } on PlatformException catch (e, s) {
      logger.e('Failed to print label', error: e, stackTrace: s);
      return false;
    }
  }

  /// 설정 화면 "테스트 출력" 버튼용. 플랫폼별로 분기.
  ///
  /// - Windows: 저장된 COM 포트/baud rate 로 [ComPortPrintService.printTestPage]
  ///   호출. COM 포트가 미설정이면 false 반환 (사용자가 먼저 포트를 골라야 함).
  /// - Android: 더미 테스트 주문 JSON 을 기존 'printOrder' MethodChannel 에 송신해
  ///   현재 활성 프린터(내장/외부 토글) 기준으로 출력.
  Future<bool> printTestPage() async {
    if (Platform.isWindows) {
      final comPort = _preferenceService.getComPortName();
      if (comPort == null || comPort.isEmpty) {
        logger.w('[PrintService] COM 포트 미설정 — 테스트 출력 생략');
        return false;
      }
      return await ComPortPrintService.printTestPage(
        comPort: comPort,
        baudRate: _preferenceService.getComPortBaudRate(),
      );
    }

    // Android: 기존 routing(useBuiltin/useExternal) 활용
    if (_cachedBuiltinPrinter == null || _cachedExternalPrinter == null) {
      _loadPrinterSettings();
    }
    final testJson = jsonEncode({
      'displayOrderNum': 'TEST',
      'ordrSimpleId': 'TEST',
      'storeName': '테스트 매장',
      'ordrDtm': DateTime.now().toString(),
      'userName': null,
      'kioskId': null,
      'ordrMemo': '테스트 출력입니다.',
      'ordrPrdList': [
        {
          'prdNm': '테스트 메뉴',
          'ordrCnt': 1,
          'prdPrc': 0,
          'optPrdList': <Map<String, dynamic>>[],
        },
      ],
      'exceptTaxPrice': '0',
      'taxPrice': '0',
      'ordrPrc': '0',
      'discPrc': '0',
      'payPrc': '0',
    });
    try {
      await platform.invokeMethod('printOrder', {
        'orderJson': testJson,
        'type': 'order',
        'isCancel': false,
        'useBuiltinPrint': _cachedBuiltinPrinter ?? false,
        'useExternalPrint': _cachedExternalPrinter ?? false,
      });
      return true;
    } on PlatformException catch (e, s) {
      logger.e('[PrintService] Android 테스트 출력 실패',
          error: e, stackTrace: s);
      return false;
    }
  }

  // 서비스 정리
  void dispose() {
    _cachedBuiltinPrinter = null;
    _cachedExternalPrinter = null;
  }
}
