import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/models/waldpos_scan_result.dart';
import 'package:appfit_order_agent/services/waldpos/waldpos_scan_service.dart';

part 'waldpos_scan_provider.g.dart';

/// 서비스 Provider. UI 는 이 provider 를 통해서만 서비스에 접근한다.
@Riverpod(keepAlive: true)
WaldposScanService waldposScanService(Ref ref) => WaldposScanService(ref);

/// Windows 토스프런트 스캔 가용 여부(버튼 노출 게이트).
/// Android Sunmi 경로(hasBuiltinScannerProvider)와 독립적이다.
final waldposScanAvailableProvider =
    Provider<bool>((ref) => Platform.isWindows);

/// 스캔 진행 상태(수동 모델).
class WaldposScanState {
  final bool isScanning;
  const WaldposScanState({this.isScanning = false});

  WaldposScanState copyWith({bool? isScanning}) =>
      WaldposScanState(isScanning: isScanning ?? this.isScanning);
}

/// 스캔 트리거 + 진행상태 Notifier.
@riverpod
class WaldposScan extends _$WaldposScan {
  @override
  WaldposScanState build() => const WaldposScanState();

  /// 바코드 스캔 1회 요청. 진행 중 재호출은 무시한다.
  Future<WaldposScanResult> requestBarcode() async {
    if (state.isScanning) {
      return WaldposScanResult.failure(WaldposScanError.unknown, '이미 스캔 중입니다.');
    }
    state = state.copyWith(isScanning: true);
    try {
      return await ref.read(waldposScanServiceProvider).requestBarcodeScan();
    } finally {
      state = state.copyWith(isScanning: false);
    }
  }
}
