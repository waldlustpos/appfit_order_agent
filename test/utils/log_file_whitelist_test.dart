import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appfit_order_agent/utils/logger.dart';

/// 파일 기록 화이트리스트(`CustomLogOutput.output`) 규약.
///
/// 이 앱에서 `logger.i` 는 **파일에 남지 않는다** — 콘솔에만 뜬다. 태그가
/// 화이트리스트에 있거나 warning 이상일 때만 기기 로그 파일(원격 수집 zip 의
/// 원본)에 들어간다. 사후 판정을 로그로 하는 기능은 이 규약을 통과해야
/// 하는데, 통과 여부가 코드만 봐서는 안 보여서 실제로 한 번 걸린 적이 있다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel =
      MethodChannel('co.kr.waldlust.order.receive.appfit_order_agent');
  final written = <String>[];

  setUp(() {
    written.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'logBatchToFile') {
        written.addAll(
          (call.arguments['messages'] as List).cast<String>(),
        );
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<List<String>> capture(void Function() emit) async {
    emit();
    await flushLogBuffer();
    return written;
  }

  test('[INVENTORY] info 는 파일에 기록된다', () async {
    // 기기 대장은 7일에 1건이라 조용한 게 정상이다. 로그가 파일에 안 남으면
    // "스킵됐다" 와 "호출조차 안 됐다" 를 사후에 구분할 수 없다.
    final lines = await capture(
      () => logger.i('[INVENTORY] 보고 시도 — 첫 보고 · MMTH00101|SERIAL|1.0.0+1'),
    );
    expect(lines.where((l) => l.contains('[INVENTORY]')), hasLength(1));
  });

  test('태그가 없는 info 는 파일에 남지 않는다', () async {
    final lines = await capture(() => logger.i('그냥 정보 로그'));
    expect(lines.where((l) => l.contains('그냥 정보 로그')), isEmpty);
  });

  test('태그는 대소문자를 가린다 — 구 표기 [Inventory] 는 안 남는다', () async {
    final lines = await capture(() => logger.i('[Inventory] 소문자 표기'));
    expect(lines.where((l) => l.contains('소문자 표기')), isEmpty);
  });

  test('warning 이상은 태그와 무관하게 기록된다', () async {
    final lines = await capture(() => logger.w('[INVENTORY] 전송 드롭'));
    expect(lines.where((l) => l.contains('전송 드롭')), hasLength(1));
  });
}
