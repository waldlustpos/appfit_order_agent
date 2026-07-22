// Sentry Crons(check-in 모니터) 동작 검증용 보조 도구 (개발용, 앱 코드와 무관).
//
//   dart run tool/cron_heartbeat_test.dart                 -- heartbeat 무한 루프
//                                                             (Ctrl-C 중단 = "기기 죽음" 시뮬레이션)
//   dart run tool/cron_heartbeat_test.dart --count 3       -- 3회 전송 후 종료(중단 = 죽음)
//   dart run tool/cron_heartbeat_test.dart --send-fail     -- status:error 단발 전송(즉시 이슈 유발)
//
// 옵션:
//   --dsn <DSN>       Sentry DSN. 미지정 시 .env 의 SENTRY_DSN= 라인을 파싱한다.
//   --slug <slug>     모니터 slug (기본 order-agent-crons-test)
//   --interval <sec>  heartbeat 전송 주기 초 (기본 30)
//   --count <n>       n회 전송 후 종료. 미지정 시 무한 루프.
//   --env <name>      environment 태그 (기본 crons-test)
//
// Sentry 인제스트 envelope 엔드포인트에 check_in 아이템을 보내고, monitor_config 로
// 모니터를 자동 upsert 한다(대시보드 수동 생성/인증 토큰 불필요). dart:io 만 사용해
// 외부 의존성이 없고 앱 빌드와 무관하다. 반드시 저장소 루트에서 실행할 것(.env 상대경로).
//
// 검증 흐름:
//   1) 실행 -> 202 응답 반복 확인, Crons 대시보드에서 모니터 green/OK.
//   2) 중단(heartbeat 정지) -> 약 2분(다음 기대 1분 + margin 1분) 뒤 missed 판정 -> 이슈 생성.
//   3) 이슈가 기존 catch-all 규칙으로 #appfit-alert-test 슬랙에 라우팅되는지 확인.
//      (store_id 태그를 심지 않으므로 catch-all 로 간다.)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const String _cronsDashboard = 'https://waldlust.sentry.io/crons/';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);

  final dsn = opts['dsn'] ?? _readDsnFromEnv();
  if (dsn == null || dsn.isEmpty) {
    stderr.writeln('SENTRY_DSN 을 찾을 수 없습니다. --dsn 인자를 주거나 .env 에 '
        'SENTRY_DSN= 를 넣고 저장소 루트에서 실행하세요.');
    exit(1);
  }

  final parsed = _parseDsn(dsn);
  if (parsed == null) {
    stderr.writeln('DSN 파싱 실패: $dsn');
    exit(1);
  }
  final (host, projectId, publicKey) = parsed;

  final slug = opts['slug'] ?? 'order-agent-crons-test';
  final env = opts['env'] ?? 'crons-test';
  final intervalSec = int.tryParse(opts['interval'] ?? '') ?? 30;
  final count = int.tryParse(opts['count'] ?? '');
  final sendFail = opts.containsKey('send-fail');

  final endpoint = Uri.parse('https://$host/api/$projectId/envelope/');
  final client = HttpClient();

  Future<void> sendCheckIn(String status) async {
    final itemPayload = jsonEncode({
      'check_in_id': _hex32(),
      'monitor_slug': slug,
      'status': status,
      'environment': env,
      'monitor_config': {
        'schedule': {'type': 'interval', 'value': 1, 'unit': 'minute'},
        'checkin_margin': 1,
        'max_runtime': 5,
        'timezone': 'Asia/Seoul',
        'failure_issue_threshold': 1,
        'recovery_threshold': 1,
      },
    });
    final body =
        '${jsonEncode({'sent_at': DateTime.now().toUtc().toIso8601String()})}\n'
        '${jsonEncode({'type': 'check_in'})}\n'
        '$itemPayload\n';

    try {
      final req = await client.postUrl(endpoint);
      req.headers
          .set(HttpHeaders.contentTypeHeader, 'application/x-sentry-envelope');
      req.headers.set(
          'X-Sentry-Auth',
          'Sentry sentry_version=7, sentry_key=$publicKey, '
              'sentry_client=cron-heartbeat-test/1.0');
      req.add(utf8.encode(body));
      final resp = await req.close();
      await resp.drain<void>();
      final ts = DateTime.now().toIso8601String().substring(11, 19);
      // envelope 엔드포인트는 200/202 모두 접수 성공.
      final ok = (resp.statusCode >= 200 && resp.statusCode < 300)
          ? ' OK'
          : ' (실패: 2xx 기대)';
      stdout.writeln(
          '[$ts] check_in status=$status -> HTTP ${resp.statusCode}$ok');
    } catch (e) {
      stderr.writeln('전송 실패: $e');
    }
  }

  stdout.writeln('== Sentry Crons heartbeat 테스트 ==');
  stdout.writeln('monitor slug : $slug');
  stdout.writeln('environment  : $env');
  stdout.writeln('endpoint     : $endpoint');
  stdout.writeln('대시보드      : $_cronsDashboard');
  stdout.writeln('');

  // --send-fail: 즉시 이슈 유발(missed 대기 없이 이슈/Slack 경로 확인).
  if (sendFail) {
    stdout.writeln('--send-fail: status=error 단발 전송 (즉시 이슈 유발 시도)');
    await sendCheckIn('error');
    stdout.writeln('전송 완료. Crons 대시보드/이슈에서 확인하세요.');
    client.close();
    return;
  }

  final loopDesc = count != null ? '$count회 전송 후 종료' : '무한 루프';
  stdout.writeln('heartbeat ${intervalSec}s 주기 전송 시작 ($loopDesc). '
      '중단 = "기기 죽음" 시뮬레이션.');
  stdout.writeln('중단 후 약 2분 내 (다음 기대 1분 + margin 1분) missed 판정 예상.');
  stdout.writeln('');

  void printDeathNotice() {
    stdout.writeln('');
    stdout.writeln('heartbeat 정지 = 기기 죽음 시뮬레이션.');
    stdout.writeln('약 2분 뒤 $_cronsDashboard 에서 "$slug" 가 missed/failed 로 바뀌고');
    stdout.writeln('이슈가 생성되는지 확인하세요. (#appfit-alert-test 슬랙 라우팅도 확인)');
  }

  var sent = 0;

  // Ctrl-C: 루프 중단 후 안내.
  late StreamSubscription<ProcessSignal> sigint;
  sigint = ProcessSignal.sigint.watch().listen((_) async {
    await sigint.cancel();
    printDeathNotice();
    client.close();
    exit(0);
  });

  await sendCheckIn('ok'); // 즉시 1회: 모니터 upsert + 첫 green.
  sent++;
  if (count != null && sent >= count) {
    await sigint.cancel();
    printDeathNotice();
    client.close();
    return;
  }

  final completer = Completer<void>();
  Timer.periodic(Duration(seconds: intervalSec), (timer) async {
    await sendCheckIn('ok');
    sent++;
    if (count != null && sent >= count) {
      timer.cancel();
      await sigint.cancel();
      printDeathNotice();
      client.close();
      if (!completer.isCompleted) completer.complete();
    }
  });
  await completer.future;
}

/// `--key value` / `--flag` 형태를 맵으로 파싱. 불리언 플래그는 'true'.
Map<String, String> _parseArgs(List<String> args) {
  const flags = {'send-fail'};
  final map = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final key = a.substring(2);
    if (flags.contains(key)) {
      map[key] = 'true';
    } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      map[key] = args[++i];
    } else {
      map[key] = 'true';
    }
  }
  return map;
}

/// 저장소 루트의 .env 에서 SENTRY_DSN= 값을 읽는다.
String? _readDsnFromEnv() {
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('SENTRY_DSN=')) {
      return t.substring('SENTRY_DSN='.length).trim();
    }
  }
  return null;
}

/// DSN(`https://<publicKey>@<host>/<projectId>`) -> (host, projectId, publicKey).
(String, String, String)? _parseDsn(String dsn) {
  final uri = Uri.tryParse(dsn);
  if (uri == null) return null;
  final publicKey = uri.userInfo.split(':').first;
  final host = uri.host;
  final projectId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  if (publicKey.isEmpty || host.isEmpty || projectId.isEmpty) return null;
  return (host, projectId, publicKey);
}

/// 32자리 hex (check-in id 용).
String _hex32() {
  final rnd = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 32; i++) {
    sb.write(rnd.nextInt(16).toRadixString(16));
  }
  return sb.toString();
}
