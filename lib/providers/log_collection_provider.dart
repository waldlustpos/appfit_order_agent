import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/services/log_collection/log_collection_service.dart';
import 'package:appfit_order_agent/services/log_collection/log_upload_sink.dart';
import 'package:appfit_order_agent/services/log_collection/slack_direct_sink.dart';
import 'package:appfit_order_agent/services/monitoring/device_identity_service.dart';
import 'package:appfit_order_agent/services/monitoring/device_status_reporter.dart';

/// 로그 업로드 sink.
///
/// 하이브리드 설계의 단일 교체 지점: 현재는 Slack 직전송([SlackDirectSink]).
/// 백엔드 중계(BackendRelaySink) 준비 시 이 provider 의 반환만 바꾸면 수집/UI
/// 로직은 그대로 둔 채 목적지가 전환된다.
final logUploadSinkProvider = Provider<LogUploadSink>((ref) {
  return SlackDirectSink();
});

/// 로그 수집 오케스트레이터(flush -> 열거 -> zip -> sink).
final logCollectionServiceProvider = Provider<LogCollectionService>((ref) {
  return LogCollectionService(ref.watch(logUploadSinkProvider));
});

/// 기기 식별 서비스(매장명+매장코드+시리얼/installId).
final deviceIdentityServiceProvider = Provider<DeviceIdentityService>((ref) {
  return DeviceIdentityService(ref.watch(preferenceServiceProvider));
});

/// 기기 상태 보고 서비스 (스캐폴딩: 스냅샷 생성까지).
final deviceStatusReporterProvider = Provider<DeviceStatusReporter>((ref) {
  return DeviceStatusReporter(ref.watch(deviceIdentityServiceProvider));
});
