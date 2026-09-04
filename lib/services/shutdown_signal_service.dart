import 'dart:io';

import 'package:appfit_core/appfit_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/services/platform_service.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 기기 전원종료·앱 종료 시 매장을 CLOSED(오더 준비중)로 내리는 신호 경로.
///
/// 네이티브 `ShutdownSalesOffBridge` 가 `ACTION_SHUTDOWN` 을 받아 이 서비스로
/// `requestSalesOff` 를 호출하고, 응답이 올 때까지 ordered broadcast 를 붙잡고
/// 있는다. 실제 요청은 Dart 가 보낸다 — 엔드포인트가 secure storage 의 JWT 와
/// Dio 인터셉터(401 리프레시 포함)를 타야 해서 네이티브 단독으로는 못 보낸다.
///
/// **전용 채널을 쓴다.** 공용 채널(`platform`)에는 회원조회 화면이
/// `setMethodCallHandler` 를 걸어두는데 채널당 핸들러는 하나뿐이라, 공용 채널에
/// 얹으면 그 화면을 한 번 열고 난 뒤부터 네이티브 → Dart 호출이 조용히 사라진다.
///
/// 커버 범위는 **정상 전원종료와 앱 종료 둘뿐**이다. 정전·플러그 뽑힘·강제
/// 리부트·네트워크 단절은 클라이언트에서 원리적으로 감지할 수 없다.
class ShutdownSignalService {
  static const MethodChannel channel =
      MethodChannel('co.kr.waldlust.order.receive.appfit_order_agent/shutdown');

  /// 네이티브 진단(요청 실패 시 DNS/TCP post-mortem)이 찔러볼 호스트를 현재
  /// 서버 설정으로 맞춘다. 서버는 런타임에 바뀌므로([AppFitConfig.configure]
  /// 호출부) 환경 전환 뒤에도 불러야 엉뚱한 호스트를 보지 않는다.
  static Future<void> syncProbeHost() async {
    if (!Platform.isAndroid) return;
    final baseUrl = AppFitConfig.baseUrl;
    if (baseUrl.isEmpty) return;
    try {
      final host = await channel
          .invokeMethod<String>('setProbeHost', {'baseUrl': baseUrl});
      logger.i('[ShutdownSalesOff] 진단 호스트 등록: $host');
    } catch (e) {
      // 진단용이라 실패해도 영업 OFF 동작에는 영향이 없다.
      logger.w('[ShutdownSalesOff] 진단 호스트 등록 실패: $e');
    }
  }
}

/// 영업 OFF 전송 본체. Riverpod `ref` 가 필요해 [ShutdownSignalService] 와
/// 분리돼 있다(호스트 동기화는 앱 부팅 초기, ProviderScope 밖에서도 불린다).
class ShutdownSalesOffSender {
  ShutdownSalesOffSender(this._ref);

  final Ref _ref;

  /// 전송 성공 여부. 성공했으면 다른 경로(전원종료 ↔ detached)가 또 보내지
  /// 않는다.
  bool _succeeded = false;

  /// 전송 진행 중. 두 경로가 수 ms 간격으로 겹칠 수 있어 중복 PUT 을 막는다.
  /// 실패로 끝나면 다시 풀리므로 남은 경로가 재시도할 수 있다.
  bool _inFlight = false;

  void attachNativeHandler() {
    ShutdownSignalService.channel.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'requestSalesOff') {
      final args = call.arguments;
      final reason =
          (args is Map && args['reason'] is String) ? args['reason'] as String : 'shutdown';
      return await sendSalesOff(reason: reason);
    }
    return null;
  }

  /// 매장을 CLOSED 로 전환한다.
  ///
  /// 반환값은 "이 기기가 해야 할 일을 마쳤는가"다 — KDS 보조단말처럼 애초에
  /// 보내면 안 되는 경우도 `true` 다(네이티브가 실패로 오해해 post-mortem 진단을
  /// 돌리지 않도록).
  Future<bool> sendSalesOff({required String reason}) async {
    if (_succeeded) return true;
    if (_inFlight) return false;

    final prefs = _ref.read(preferenceServiceProvider);

    // KDS 보조단말은 메인단말과 storeId 를 공유한다. 여기서 CLOSED 를 보내면
    // 멀쩡히 영업 중인 메인단말의 상태를 덮어쓴다. 규칙은 종료 버튼
    // (home_screen._exitApp) 과 동일하게 "메인모드 이거나 KDS+자동접수 ON".
    //
    // 판정에 provider 대신 영속 플래그를 쓰는 이유: 이 경로는 프로세스가 죽는
    // 중에 도는데 그때 provider 그래프 접근은 신뢰할 수 없다.
    final isKdsMode = prefs.getKdsMode();
    final isKdsAcceptOrders = prefs.getKdsAcceptOrders();
    if (isKdsMode && !isKdsAcceptOrders) {
      logToFile(
        tag: LogTag.LIFECYCLE,
        message: '[SALES_OFF] KDS 보조단말 — 영업 OFF 생략 (reason=$reason)',
      );
      return true;
    }

    final storeId = prefs.getActiveStoreId();
    if (storeId == null || storeId.isEmpty) {
      logToFile(
        tag: LogTag.LIFECYCLE,
        message: '[SALES_OFF] 매장 ID 없음(미로그인) — 생략 (reason=$reason)',
      );
      return true;
    }

    _inFlight = true;
    try {
      // KEY_ORDER_ON 은 건드리지 않는다. 다음 기동 때 home_screen 이 그 값으로
      // 서버 상태를 복원하므로, 여기서 false 로 덮으면 재부팅 후 매장이 닫힌
      // 채로 남는다. 종료 버튼 경로도 같은 이유로 API 만 호출한다.
      final ok = await _ref
          .read(apiServiceProvider)
          .updateShopOperatingStatus(storeId, false);
      _succeeded = ok;
      logToFile(
        tag: ok ? LogTag.LIFECYCLE : LogTag.WARNING,
        message: '[SALES_OFF] $storeId 영업 OFF ${ok ? "성공" : "실패"} (reason=$reason)',
      );
      return ok;
    } catch (e) {
      logToFile(
        tag: LogTag.WARNING,
        message: '[SALES_OFF] $storeId 영업 OFF 예외 (reason=$reason): $e',
      );
      return false;
    } finally {
      _inFlight = false;
    }
  }
}
