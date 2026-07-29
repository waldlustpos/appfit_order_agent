import 'dart:async';
import 'dart:io' show File, FileMode, Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 전용 플로팅 버블 + 트레이 서비스.
///
/// 전환 흐름:
/// - 최소화(enterBubbleMode): 창을 Windows 기본 최소화 애니메이션으로 사라지게
///   한 뒤, 짧은 지연 후 80x80 always-on-top 프레임리스 버블로 다시 나타남.
///   작업표시줄에는 아이콘이 남지 않고(`skipTaskbar=true`) 트레이에만 표시된다.
/// - 복원(exitBubbleMode): 버블을 먼저 hide로 즉시 제거한 뒤 짧은 지연 후
///   원래 창 크기/스타일로 복원하고 show.
class WindowsBubbleService with WindowListener, TrayListener {
  WindowsBubbleService._();
  static final WindowsBubbleService instance = WindowsBubbleService._();

  static const double _bubbleSize = 80.0;
  // init 전 창이 준비되기 전까지의 폴백용. 실제 크기는 main.cpp가 생성하고
  // init()에서 windowManager.getSize()로 측정해 _originalSize에 덮어쓴다.
  static const Size _defaultWindowSize = Size(1280, 720);
  static const Duration _blinkInterval = Duration(milliseconds: 500);

  // 최소화 애니메이션이 완료된 직후 버블이 나타나도록 약간의 지연을 둔다.
  static const Duration _enterTransitionDelay = Duration(milliseconds: 500);
  // 버블을 숨긴 뒤 원본 창이 나타나기까지 짧은 지연.
  static const Duration _exitTransitionDelay = Duration(milliseconds: 220);

  static const String _keyBubbleX = 'APPFIT_BUBBLE_X';
  static const String _keyBubbleY = 'APPFIT_BUBBLE_Y';

  final ValueNotifier<bool> isBubbleMode = ValueNotifier<bool>(false);
  final StreamController<bool> _blinkController =
      StreamController<bool>.broadcast();

  Stream<bool> get blinkStream => _blinkController.stream;

  Size _originalSize = _defaultWindowSize;
  Offset? _originalPosition;

  /// 일반 모드 창 크기. main.dart에서 메인 앱 child를 size-lock하는 데 사용.
  /// 버블 모드 동안 윈도우가 80x80으로 줄어도 child가 이 사이즈로 layout되어
  /// KDS 카드의 AnimatedContainer가 height 변화를 인식하지 않게 한다.
  Size get originalSize => _originalSize;
  Timer? _blinkTimer;
  bool _blinkState = true;
  bool _initialized = false;
  bool _transitioning = false;

  // 실기기 디버깅용 파일 로그. 위치: Documents/appfit_window_debug.log
  // 콘솔/Sentry가 안 닿는 실기기 환경에서 창 크기 계산 과정을 추적한다.
  static const String _debugLogFileName = 'appfit_window_debug.log';
  File? _debugLogFileCached;

  Future<File?> _getDebugLogFile() async {
    if (_debugLogFileCached != null) return _debugLogFileCached;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _debugLogFileCached = File('${dir.path}\\$_debugLogFileName');
      return _debugLogFileCached;
    } catch (e, s) {
      logger.w('디버그 로그 파일 경로 해결 실패', error: e, stackTrace: s);
      return null;
    }
  }

  Future<void> _debugFileLog(String message) async {
    try {
      final file = await _getDebugLogFile();
      if (file == null) return;
      final ts = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$ts] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 로그 기록 실패는 앱 동작에 영향 주지 않도록 무시.
    }
  }

  /// 기본 디스플레이 가용 영역에 맞춰 창 크기를 결정한다.
  ///
  /// 로직:
  /// - 디자인 크기(1280x720)가 가용 영역의 85% 이하로 들어가면(FHD 이상
  ///   모니터) 디자인 크기를 그대로 사용 → 축소 없음.
  /// - 디자인 크기가 가용 영역에 꽉 차거나 넘치면(실기기 1920x1200 @
  ///   150% DPI = logical 1280x800 같은 작은 화면) 가용 영역의 87.5%
  ///   너비로 16:9 유지하여 축소 → 실기기에서 1120x630.
  ///
  /// 예상 결과:
  ///   - 실기기 (1280x800 logical): 1120x630 (87.5% x 78.75%)
  ///   - FHD PC (1920x1080): 1280x720
  ///   - 2K/4K: 1280x720
  ///
  /// 계산 실패 시 폴백 1120x630.
  Future<Size> _computeTargetWindowSize() async {
    await _debugFileLog('=== _computeTargetWindowSize 시작 ===');

    // 참고용: screen_retriever 결과도 함께 기록 (비교 디버깅).
    try {
      final srDisplay = await screenRetriever.getPrimaryDisplay();
      final srSize = srDisplay.size;
      final srVisible = srDisplay.visibleSize;
      await _debugFileLog('[screen_retriever] '
          'size=${srSize.width}x${srSize.height}, '
          'visibleSize=${srVisible?.width}x${srVisible?.height}, '
          'scaleFactor=${srDisplay.scaleFactor}');
    } catch (e) {
      await _debugFileLog('[screen_retriever] 조회 실패: $e');
    }

    try {
      // Flutter의 PlatformDispatcher.views.first.display 사용. screen_retriever가
      // Windows에서 scaleFactor를 제대로 주지 않는 경우가 있어, Flutter 엔진이
      // 직접 관리하는 display 정보가 더 신뢰할 수 있다.
      // display.size는 physical 픽셀, devicePixelRatio가 DPI 스케일.
      final view = PlatformDispatcher.instance.views.first;
      final display = view.display;
      final physicalSize = display.size;
      final dpr = display.devicePixelRatio > 0 ? display.devicePixelRatio : 1.0;
      final logicalW = physicalSize.width / dpr;
      final logicalH = physicalSize.height / dpr;

      await _debugFileLog('[flutter view.display] '
          'physicalSize=${physicalSize.width}x${physicalSize.height}, '
          'devicePixelRatio=$dpr, '
          'logical=${logicalW}x$logicalH');

      // 작업표시줄 영역 보정 (대략 48 logical).
      const taskbarHeight = 48.0;
      final availW = logicalW;
      final availH = logicalH - taskbarHeight;

      await _debugFileLog('[avail] W=$availW, H=$availH '
          '(taskbarHeight=$taskbarHeight)');

      // 디자인 크기가 가용 영역의 85% 이하면 여유 있는 큰 화면 → 디자인 크기 그대로.
      final ratioW = availW > 0 ? 1280.0 / availW : double.infinity;
      final ratioH = availH > 0 ? 720.0 / availH : double.infinity;
      await _debugFileLog('[ratio] 1280/availW=$ratioW, '
          '720/availH=$ratioH (threshold=0.85)');

      if (availW > 0 && availH > 0 && ratioW <= 0.85 && ratioH <= 0.85) {
        await _debugFileLog('[branch] 큰 화면 → 1280x720 반환');
        return const Size(1280, 720);
      }

      // 작은 화면: 가용 영역의 96.25% 크기로 16:9 유지하며 축소.
      // (실기기 1280x752 환경에서 1232x693 결과)
      const smallScreenRatio = 0.9625;
      double w = availW * smallScreenRatio;
      double h = w * 9.0 / 16.0;
      if (h > availH * smallScreenRatio) {
        h = availH * smallScreenRatio;
        w = h * 16.0 / 9.0;
      }
      if (w > 1280.0) {
        w = 1280.0;
        h = 720.0;
      }
      final result = Size(w.floorToDouble(), h.floorToDouble());
      await _debugFileLog(
          '[branch] 작은 화면 → ${result.width}x${result.height} 반환');
      return result;
    } catch (e, s) {
      await _debugFileLog('[error] _computeTargetWindowSize 예외: $e\n$s');
      logger.w('디스플레이 크기 조회 실패, 폴백 1120x630 사용', error: e, stackTrace: s);
      return const Size(1120, 630);
    }
  }

  Future<void> init() async {
    if (!Platform.isWindows) return;
    if (_initialized) return;
    _initialized = true;

    try {
      await _debugFileLog('===== WindowsBubbleService.init 호출 =====');
      // 디스플레이 가용 영역에 맞춰 16:9 창 크기 계산. 디자인 캔버스는
      // main.dart에서 1280x720 고정이며, 창이 그보다 작으면 FittedBox가
      // 비율 유지로 축소한다. 창·디자인 모두 16:9라 레터박스는 생기지 않음.
      final targetSize = await _computeTargetWindowSize();
      logger.i('창 타겟 크기 계산: $targetSize');
      await _debugFileLog(
          '[init] targetSize=${targetSize.width}x${targetSize.height}');

      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          center: true,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.hidden,
        ),
        () async {
          await windowManager.setAsFrameless();
          // D3D 스왑체인 첫 프레임 프리젠트는 WM_SIZE 이벤트에 의존한다.
          // WindowOptions.size를 지정하지 않고, 콜백 안에서 target과 다른
          // 크기로 한 번 setSize → target으로 복귀하여 WM_SIZE를 확실히
          // 발생시킨다. main.cpp는 1280x720으로 창을 만들어 두므로
          // setAsFrameless와 아래 2단 setSize 모두 크기 변동을 일으켜
          // 어떤 환경(FHD에서 target=1280x720 포함)에서도 흰 화면이
          // 발생하지 않는다.
          await windowManager.setSize(
            Size(targetSize.width + 10.0, targetSize.height + 10.0),
          );
          await windowManager.setSize(targetSize);
          await windowManager.center();
          await windowManager.show();
          await windowManager.focus();
        },
      );
      _originalSize = await windowManager.getSize();
      _originalPosition = await windowManager.getPosition();
      await _debugFileLog('[init] setSize 후 실측 '
          '_originalSize=${_originalSize.width}x${_originalSize.height}, '
          '_originalPosition=(${_originalPosition?.dx}, ${_originalPosition?.dy})');

      // setSize가 실기기 등 일부 환경에서 무시되는 이슈 대응.
      // 실측 크기가 targetSize와 다르면 setBounds로 위치+크기를 한 번에
      // 강제 설정. 그래도 안 되면 로그만 남기고 진행.
      final sizeMismatch =
          (_originalSize.width - targetSize.width).abs() > 2.0 ||
              (_originalSize.height - targetSize.height).abs() > 2.0;
      if (sizeMismatch) {
        await _debugFileLog('[init] size mismatch 감지, setBounds로 재시도');
        try {
          await windowManager.setBounds(
            null,
            size: targetSize,
          );
          await Future.delayed(const Duration(milliseconds: 150));
          await windowManager.center();
          _originalSize = await windowManager.getSize();
          _originalPosition = await windowManager.getPosition();
          await _debugFileLog('[init] setBounds 후 실측 '
              'size=${_originalSize.width}x${_originalSize.height}, '
              'pos=(${_originalPosition?.dx}, ${_originalPosition?.dy})');
        } catch (e) {
          await _debugFileLog('[init] setBounds 실패: $e');
        }
      }

      // setAsFrameless + show 직후 Flutter D3D 스왑체인이 즉시 첫 프레임을
      // 프리젠트하지 않아, 사용자가 창을 움직여야 내용이 그려지는 현상이
      // 발생한다. 엔진이 첫 프레임을 처리할 수 있도록 짧게 대기한 뒤,
      // 사이즈를 1px 키웠다가 targetSize로 돌려 WM_SIZE를 강제 발생시킨다.
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.setSize(
          Size(targetSize.width + 1, targetSize.height),
        );
        await windowManager.setSize(targetSize);
      } catch (_) {}

      // 창 크기 고정: 리사이즈/최대화 불가, min=max=targetSize.
      // 실측값(_originalSize)이 targetSize와 달라도 사이즈 락은 targetSize로
      // 걸어 의도한 크기가 유지되게 한다.
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setMinimumSize(targetSize);
      await windowManager.setMaximumSize(targetSize);
      // DWM 그림자 활성화 — frameless 창 외곽에 살짝 입체감.
      await windowManager.setHasShadow(true);

      windowManager.addListener(this);

      await _initTray();
      logger.i('WindowsBubbleService 초기화 완료 (size=$_originalSize)');
      // 초기화 후 실제 창 크기 재측정 (min/max 설정이 반영됐는지 확인).
      final finalSize = await windowManager.getSize();
      await _debugFileLog(
          '[init] 초기화 완료 (최종 측정 size=${finalSize.width}x${finalSize.height})');
    } catch (e, s) {
      logger.e('WindowsBubbleService 초기화 실패', error: e, stackTrace: s);
      await _debugFileLog('[init] 예외: $e\n$s');
    }
  }

  /// 트레이 아이콘 등록. logo.png를 임시 디렉토리로 복사 후 그 파일경로를
  /// 네이티브에 전달한다 (tray_manager Windows 구현은 exe 상대경로/절대경로
  /// 기반 LoadImage를 사용하므로 Flutter assets 경로를 직접 넘길 수 없다).
  Future<void> _initTray() async {
    try {
      final iconPath = await _extractTrayIcon();
      if (iconPath != null) {
        await trayManager.setIcon(iconPath);
      }
      await trayManager.setToolTip('Appfit 주문 에이전트');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'restore', label: '앱 열기'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '종료'),
      ]));
      trayManager.addListener(this);
      logger.i('트레이 아이콘 등록 완료');
    } catch (e, s) {
      logger.e('트레이 아이콘 등록 실패', error: e, stackTrace: s);
    }
  }

  Future<String?> _extractTrayIcon() async {
    // Windows 트레이는 멀티 사이즈 ICO를 가장 정확히 표시한다.
    // flutter_launcher_icons가 생성한 app_icon.ico를 우선 사용하고,
    // 로드 실패 시 PNG 폴백.
    final dir = await getApplicationSupportDirectory();
    final candidates = <({String asset, String fileName})>[
      (asset: 'assets/icons/app_icon.ico', fileName: 'tray_icon.ico'),
      (asset: 'assets/icons/app_icon.png', fileName: 'tray_icon.png'),
    ];

    for (final c in candidates) {
      try {
        final data = await rootBundle.load(c.asset);
        final target = File('${dir.path}/${c.fileName}');
        await target.writeAsBytes(data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ));
        logger.i('트레이 아이콘 추출: ${target.path}');
        return target.path;
      } catch (e) {
        logger.w('트레이 아이콘 로드 실패 (${c.asset}): $e');
      }
    }
    return null;
  }

  /// 최소화 버튼 → Windows 기본 최소화 애니메이션 → 지연 → 버블 등장.
  Future<void> enterBubbleMode() async {
    if (!Platform.isWindows) return;
    if (isBubbleMode.value || _transitioning) return;
    _transitioning = true;

    try {
      // 시스템 최소화 경로(작업표시줄 클릭 / Win+D)에서는 창이 이미 minimize
      // 상태로 들어온다. 이 상태에서 hide → show 사이클을 돌면 minimize 잔존
      // 상태로 인해 복귀 시 창이 보이지 않는다(작업표시줄 아이콘만 생김).
      // 먼저 normal로 복원하고 hide.
      try {
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
      } catch (_) {}

      try {
        _originalSize = await windowManager.getSize();
        _originalPosition = await windowManager.getPosition();
      } catch (_) {}

      // 1) 창을 즉시 숨기고 작업표시줄에서 제거.
      //    minimize()를 쓰면 뒤에 나오는 show() 호출 시 Windows가 자동으로
      //    minimize 이전 크기로 restore해서 setSize(80x80)이 무시된다.
      //    그래서 hide()만 사용.
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);

      // 2) 전환 지연 — "최소화 → 짧은 시간 → 버블 등장" UX.
      await Future.delayed(_enterTransitionDelay);

      // 3) 버블 속성 설정 (hide 상태이므로 사용자 눈에 보이지 않음).
      final bubblePos = await _loadBubblePosition();
      await windowManager.setAsFrameless();
      await windowManager.setResizable(false);
      // 일반 모드에서 min=max=_originalSize로 고정했으므로, 버블 크기로 먼저
      // 최대값을 풀어줘야 setSize가 정상 적용된다.
      await windowManager.setMaximumSize(const Size(_bubbleSize, _bubbleSize));
      await windowManager.setMinimumSize(const Size(_bubbleSize, _bubbleSize));
      await windowManager.setHasShadow(false);
      await windowManager.setAlwaysOnTop(true);
      // 창 배경을 투명화 — SVG 원형 바깥 모서리가 Windows 기본 clear color
      // (검정)로 비쳐 "검은 박스"처럼 보이던 문제 해결.
      await windowManager.setBackgroundColor(const Color(0x00000000));
      await windowManager.setSize(const Size(_bubbleSize, _bubbleSize));
      await windowManager.setPosition(bubblePos);

      // 4) Flutter가 버블 오버레이를 첫 프레임에 그리도록 플래그를 먼저 올리고
      //    한 프레임 대기. show 시점에 이미 80x80 버블이 그려진 프레임이
      //    준비되어 창의 검정 clear color가 노출되지 않는다.
      isBubbleMode.value = true;
      await WidgetsBinding.instance.endOfFrame;

      // 5) 창 표시.
      await windowManager.show();

      logger.i('버블 모드 진입 완료 (position=$bubblePos)');
    } catch (e, s) {
      logger.e('버블 모드 진입 실패', error: e, stackTrace: s);
    } finally {
      _transitioning = false;
    }
  }

  /// 버블 클릭 → hide로 즉시 사라짐 → 지연 → 원본 창 복원.
  Future<void> exitBubbleMode() async {
    if (!Platform.isWindows) return;
    if (!isBubbleMode.value || _transitioning) return;
    _transitioning = true;

    stopBlinking();

    try {
      // 0) 현재 버블 위치 저장.
      try {
        final pos = await windowManager.getPosition();
        await _saveBubblePosition(pos);
      } catch (_) {}

      // 1) 버블 창을 즉시 숨김 → 사용자에게는 "버블 사라짐"으로 보임.
      await windowManager.hide();
      isBubbleMode.value = false;

      // 2) 짧은 지연 — 사용자 요청 UX ("버블 사라짐 → 짧은 시간 → 앱 등장").
      await Future.delayed(_exitTransitionDelay);

      // 3) 원본 창 속성 복원 (hide 상태).
      // 일반 모드도 frameless로 유지 — setTitleBarStyle(normal) 호출하지 않음.
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setHasShadow(true);
      // 투명 → 흰색(불투명)으로 복원. 일반 앱 영역에서는 기본 배경 유지.
      await windowManager.setBackgroundColor(const Color(0xFFFFFFFF));
      // 고정 크기 복원: 버블용 max=80x80 제약을 _originalSize로 풀어준 뒤,
      // setSize → min/max를 _originalSize로 재고정.
      await windowManager.setMaximumSize(_originalSize);
      await windowManager.setMinimumSize(_originalSize);
      await windowManager.setSize(_originalSize);
      if (_originalPosition != null) {
        await windowManager.setPosition(_originalPosition!);
      } else {
        await windowManager.center();
      }
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setSkipTaskbar(false);

      // 4) 원본 UI가 첫 프레임에 그려지도록 대기 — show 직후 검정 clear color가
      //    노출되는 걸 방지.
      await WidgetsBinding.instance.endOfFrame;

      // 4-1) 안전망: 이전 사이클에서 minimize 상태가 잔존해 있으면 show가 작업
      //      표시줄 아이콘만 만들고 창은 보이지 않을 수 있다. restore로 normal
      //      상태를 보장.
      try {
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
      } catch (_) {}

      // 5) 원본 창 표시 + 포커스.
      await windowManager.show();
      await windowManager.focus();

      logger.i('버블 모드 종료 완료');
    } catch (e, s) {
      logger.e('버블 모드 종료 실패', error: e, stackTrace: s);
    } finally {
      _transitioning = false;
    }
  }

  /// 500ms 주기로 [blinkStream]에 true/false를 교대로 방출.
  void startBlinking() {
    if (!Platform.isWindows) return;
    if (_blinkTimer != null) return;

    _blinkState = true;
    _blinkController.add(_blinkState);
    _blinkTimer = Timer.periodic(_blinkInterval, (_) {
      _blinkState = !_blinkState;
      _blinkController.add(_blinkState);
    });
    logger.d('버블 점멸 시작');
  }

  void stopBlinking() {
    if (_blinkTimer == null) return;
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _blinkState = true;
    _blinkController.add(true);
    logger.d('버블 점멸 중지');
  }

  Future<void> saveBubblePosition(Offset pos) => _saveBubblePosition(pos);

  Future<Offset> _loadBubblePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_keyBubbleX);
      final y = prefs.getDouble(_keyBubbleY);
      final display = await screenRetriever.getPrimaryDisplay();
      final visible = display.visiblePosition ?? Offset.zero;
      final visibleSize = display.visibleSize ?? display.size;

      if (x != null && y != null) {
        final maxX = visible.dx + visibleSize.width - _bubbleSize;
        final maxY = visible.dy + visibleSize.height - _bubbleSize;
        final clampedX = x.clamp(visible.dx, maxX).toDouble();
        final clampedY = y.clamp(visible.dy, maxY).toDouble();
        return Offset(clampedX, clampedY);
      }

      final defaultX = visible.dx + visibleSize.width - _bubbleSize - 30;
      final defaultY = visible.dy + visibleSize.height - _bubbleSize - 30;
      return Offset(defaultX, defaultY);
    } catch (e, s) {
      logger.e('버블 위치 로드 실패', error: e, stackTrace: s);
      return const Offset(100, 100);
    }
  }

  Future<void> _saveBubblePosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyBubbleX, pos.dx);
      await prefs.setDouble(_keyBubbleY, pos.dy);
    } catch (e, s) {
      logger.e('버블 위치 저장 실패', error: e, stackTrace: s);
    }
  }

  /// 타이틀바 더블클릭 → 화면 중앙으로 창 이동.
  Future<void> restoreToDefaultPosition() async {
    if (!Platform.isWindows) return;
    if (isBubbleMode.value || _transitioning) return;
    try {
      await windowManager.center();
      _originalPosition = await windowManager.getPosition();
    } catch (e, s) {
      logger.w('창 위치 복귀 실패', error: e, stackTrace: s);
    }
  }

  // ---- WindowListener ----

  @override
  void onWindowMinimize() {
    // 작업표시줄 아이콘 클릭 / Win+D / 시스템 메뉴 등으로 최소화한 경우에도
    // 커스텀 최소화 버튼과 동일한 결과(트레이 + 버블 + 점멸 알림)가 되도록 라우팅.
    if (isBubbleMode.value || _transitioning) return;
    unawaited(enterBubbleMode());
  }

  @override
  void onWindowMoved() {
    if (!isBubbleMode.value) return;
    unawaited(() async {
      try {
        final pos = await windowManager.getPosition();
        await _saveBubblePosition(pos);
      } catch (_) {}
    }());
  }

  // ---- TrayListener ----

  @override
  void onTrayIconMouseDown() {
    unawaited(_handleTrayActivation());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'restore':
        unawaited(_handleTrayActivation());
        break;
      case 'exit':
        unawaited(_handleExit());
        break;
    }
  }

  Future<void> _handleTrayActivation() async {
    try {
      if (isBubbleMode.value) {
        await exitBubbleMode();
        return;
      }
      final visible = await windowManager.isVisible();
      if (!visible) {
        await windowManager.show();
      }
      await windowManager.focus();
    } catch (e, s) {
      logger.e('트레이 활성화 실패', error: e, stackTrace: s);
    }
  }

  Future<void> _handleExit() async {
    try {
      await trayManager.destroy();
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {}
  }

  /// 프로세스 재시작 직전 트레이 아이콘만 정리한다(창은 건드리지 않음 —
  /// exit(0)이 담당). trayManager.destroy() 를 호출하지 않고 exit(0) 하면
  /// 셸(Shell_NotifyIcon)에 좀비 아이콘이 남을 수 있어 필요하다.
  Future<void> releaseTrayForRestart() async {
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  void dispose() {
    _blinkTimer?.cancel();
    _blinkController.close();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }
}
