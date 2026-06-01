import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:appfit_order_agent/widgets/update/update_progress_dialog.dart';

/// main()의 runApp(MyApp) 직전에 호출한다.
/// Windows가 아니면 즉시 반환.
/// 업데이트가 없거나 사용자가 '나중에'를 선택하면 반환 후 호출부가 본 앱을 계속 실행.
/// 업데이트 설치가 시작되면 앱이 exit(0) 되므로 이 함수는 반환하지 않는다.
Future<void> runStartupUpdateFlow() async {
  if (!Platform.isWindows) return;

  final completer = Completer<void>();

  runApp(_UpdateBootstrapApp(onDone: () {
    if (!completer.isCompleted) completer.complete();
  }));

  await completer.future;
}

class _UpdateBootstrapApp extends StatefulWidget {
  final VoidCallback onDone;
  const _UpdateBootstrapApp({required this.onDone});

  @override
  State<_UpdateBootstrapApp> createState() => _UpdateBootstrapAppState();
}

class _UpdateBootstrapAppState extends State<_UpdateBootstrapApp> {
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
