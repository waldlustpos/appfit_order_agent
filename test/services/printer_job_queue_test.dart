import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appfit_order_agent/services/printer_job_queue.dart';
import 'package:appfit_order_agent/services/printer_transport.dart';

class _ScriptedTransport implements PrinterTransport {
  _ScriptedTransport(this.script);

  /// 각 [send] 호출 시 차례대로 반환할 결과들.
  final List<PrinterTransportResult> script;
  final List<String> sentJobs = [];

  @override
  Future<PrinterTransportResult> send(Uint8List bytes, String jobName) async {
    sentJobs.add(jobName);
    if (script.isEmpty) {
      return const PrinterTransportError('script exhausted');
    }
    return script.removeAt(0);
  }
}

void main() {
  // logToFile 이 platform_service.dart 의 MethodChannel 을 호출하므로 stub 필요.
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('co.kr.waldlust.order.receive.appfit_order_agent');

  setUp(() {
    PrinterJobQueue.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    PrinterJobQueue.instance.backoffsForTest = const [
      Duration.zero,
      Duration(milliseconds: 5),
      Duration(milliseconds: 10),
    ];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PrinterJobQueue.instance.resetForTest();
  });

  Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

  test('첫 시도 성공 시 1회만 호출되고 true 반환', () async {
    final t = _ScriptedTransport([const PrinterSuccess()]);
    PrinterJobQueue.instance.setTransport(t);

    final ok = await PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('a'), jobName: 'J1', kind: 'order'),
    );

    expect(ok, isTrue);
    expect(t.sentJobs, ['J1']);
  });

  test('busy 2회 후 success -> 3회 호출 후 true', () async {
    final t = _ScriptedTransport([
      const PrinterBusy('claim failed'),
      const PrinterBusy('claim failed'),
      const PrinterSuccess(),
    ]);
    PrinterJobQueue.instance.setTransport(t);

    final ok = await PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('a'), jobName: 'J1', kind: 'order'),
    );

    expect(ok, isTrue);
    expect(t.sentJobs.length, 3);
  });

  test('busy 3회 -> false, onFinalFailure 1회 호출', () async {
    final t = _ScriptedTransport([
      const PrinterBusy('1'),
      const PrinterBusy('2'),
      const PrinterBusy('3'),
    ]);
    PrinterJobQueue.instance.setTransport(t);

    PrinterTransportResult? failureResult;
    int failureCount = 0;
    PrinterJobQueue.instance.onFinalFailure = (job, r) {
      failureCount++;
      failureResult = r;
    };

    final ok = await PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('a'), jobName: 'J1', kind: 'order'),
    );

    expect(ok, isFalse);
    expect(t.sentJobs.length, 3);
    expect(failureCount, 1);
    expect(failureResult, isA<PrinterBusy>());
  });

  test('잡 순서 보존: 3건 동시 enqueue -> 1->2->3 순으로 transport 호출', () async {
    final t = _ScriptedTransport([
      const PrinterSuccess(),
      const PrinterSuccess(),
      const PrinterSuccess(),
    ]);
    PrinterJobQueue.instance.setTransport(t);

    final f1 = PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('a'), jobName: 'A', kind: 'order'));
    final f2 = PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('b'), jobName: 'B', kind: 'order'));
    final f3 = PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('c'), jobName: 'C', kind: 'order'));

    final results = await Future.wait([f1, f2, f3]);
    expect(results, [true, true, true]);
    expect(t.sentJobs, ['A', 'B', 'C']);
  });

  test('첫 잡 최종 실패가 다음 잡 처리를 막지 않는다', () async {
    final t = _ScriptedTransport([
      const PrinterBusy('1'),
      const PrinterBusy('2'),
      const PrinterBusy('3'),
      const PrinterSuccess(),
    ]);
    PrinterJobQueue.instance.setTransport(t);

    final fA = PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('a'), jobName: 'A', kind: 'order'));
    final fB = PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('b'), jobName: 'B', kind: 'order'));

    expect(await fA, isFalse);
    expect(await fB, isTrue);
    expect(t.sentJobs, ['A', 'A', 'A', 'B']);
  });

  test('transport 미주입 상태에서 enqueue -> false, noDevice 로 최종 실패', () async {
    PrinterTransportResult? failureResult;
    PrinterJobQueue.instance.onFinalFailure = (job, r) {
      failureResult = r;
    };

    final ok = await PrinterJobQueue.instance.enqueue(
      PrinterJob(bytes: bytes('a'), jobName: 'X', kind: 'order'),
    );
    expect(ok, isFalse);
    expect(failureResult, isA<PrinterNoDevice>());
  });
}
