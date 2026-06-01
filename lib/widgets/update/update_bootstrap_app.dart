import 'package:flutter/material.dart';

import 'package:appfit_order_agent/widgets/update/update_progress_dialog.dart';

/// 시작 시 업데이트 플로우를 보여주기 위한 부트스트랩 앱.
/// `runStartupUpdateFlow()`([app_startup_updater.dart](../../utils/app_startup_updater.dart))가
/// 본 앱 실행 전에 `runApp` 으로 띄운다. 첫 프레임 직후 [UpdateProgressDialog] 를 표시하고,
/// 다이얼로그가 닫히면 [onDone] 을 호출한다.
class UpdateBootstrapApp extends StatefulWidget {
  final VoidCallback onDone;
  const UpdateBootstrapApp({super.key, required this.onDone});

  @override
  State<UpdateBootstrapApp> createState() => _UpdateBootstrapAppState();
}

class _UpdateBootstrapAppState extends State<UpdateBootstrapApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
  }

  Future<void> _showDialog() async {
    if (_dialogShown) return;
    _dialogShown = true;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      widget.onDone();
      return;
    }

    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (_) => const UpdateProgressDialog(),
    );

    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      home: const Scaffold(
        backgroundColor: Colors.white,
        body: SizedBox.expand(),
      ),
    );
  }
}
