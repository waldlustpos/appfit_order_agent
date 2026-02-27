import 'package:flutter/services.dart';
import 'package:kokonut_order_agent/services/platform_service.dart';
import '../models/order_model.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import 'package:kokonut_order_agent/utils/logger.dart';
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
    // USB 디바이스 확인
    checkConnection();
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
    try {
      final devices = await PlatformService.getConnectedUsbDevices();

      bool isExternalConnected = false;
      bool isLabelConnected = false;

      if (devices.isNotEmpty) {
        logToFile(
            tag: LogTag.PLATFORM,
            message: '연결된 USB 디바이스 목록 (${devices.length}개):');

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

          logToFile(
            tag: LogTag.PLATFORM,
            message:
                ' - ${device['productName'] ?? 'Unknown'} ($manufacturer): VID=$vendorId, PID=$productId$identification',
          );
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
      final orderJson = jsonEncode(orderWithStore.toJson());

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

  Future<void> printLabel(Uint8List imageBytes) async {
    try {
      if (_cachedExternalPrinter == null) {
        _loadPrinterSettings();
      }

      // Default to external printer for labels if enabled, otherwise check settings?
      // Assuming labels are solely for the external label printer logic.
      // But we pass flags like useExternalPrint.

      bool useLabel = _cachedLabelPrinter ?? false;

      logToFile(tag: LogTag.PLATFORM, message: '라벨 출력 요청 (사용설정: $useLabel)');

      if (!useLabel) {
        logger.w('Label printer is disabled in settings.');
        return;
      }

      await platform.invokeMethod('printLabel', {
        'imageBytes': imageBytes,
      });
    } on PlatformException catch (e, s) {
      logger.e('Failed to print label', error: e, stackTrace: s);
      rethrow;
    }
  }

  // 서비스 정리
  void dispose() {
    _cachedBuiltinPrinter = null;
    _cachedExternalPrinter = null;
  }
}
