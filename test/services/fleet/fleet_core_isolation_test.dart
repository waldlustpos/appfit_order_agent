import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/services/fleet/core/` 는 appfit_core 로 승격될 예정이다.
///
/// 승격이 "파일 이동 + import 헤더 치환"으로 끝나려면 이 디렉터리가 앱 코드를
/// 참조하지 않아야 한다. 규율을 주석으로만 적어두면 반드시 깨지므로 테스트로
/// 고정한다 — 이 테스트가 빨개지면 승격 비용이 재설계로 뛴 것이다.
///
/// 허용 import:
///   - `dart:*`
///   - `package:appfit_core/...`  (승격 후에는 같은 패키지 내부가 된다)
///   - `package:dio/...`, `package:connectivity_plus/...`  (core 가 이미 의존)
///   - `package:appfit_order_agent/services/fleet/core/...`  (형제 파일)
void main() {
  const coreDir = 'lib/services/fleet/core';

  /// core 가 이미 의존하는 패키지만. 여기 없는 패키지를 쓰면 승격 시
  /// appfit_core/pubspec.yaml 에 새 의존성이 필요해지고, 그건 3앱 공유
  /// 라이브러리에 버전 충돌 위험을 들이는 일이라 별도 판단이 필요하다.
  const allowedPackages = {
    'appfit_core',
    'dio',
    'connectivity_plus',
    'flutter',
  };

  late List<File> files;

  setUpAll(() {
    final dir = Directory(coreDir);
    expect(dir.existsSync(), isTrue, reason: '$coreDir 가 있어야 한다');
    files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
  });

  test('core/ 는 core/ 바깥의 앱 코드를 import 하지 않는다', () {
    final violations = <String>[];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = RegExp(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""")
            .firstMatch(lines[i]);
        if (match == null) continue;
        final uri = match.group(1)!;

        if (!uri.startsWith('package:appfit_order_agent/')) continue;
        // 형제 파일끼리는 허용. 승격 시 package:appfit_core/ 로 치환된다.
        const sibling = 'package:appfit_order_agent/services/fleet/core/';
        if (uri.startsWith(sibling)) continue;

        violations.add('${file.path}:${i + 1}  $uri');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'core/ 가 앱 코드를 참조하면 appfit_core 승격이 파일 이동이 아니라 '
          '재설계가 된다. 앱 의존이 필요한 로직은 core/ 바깥(order_agent_fleet_*.dart)에 두고 '
          '콜백으로 주입할 것.\n${violations.join('\n')}',
    );
  });

  test('core/ 는 상대 import 를 쓰지 않는다 (always_use_package_imports)', () {
    final violations = <String>[];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = RegExp(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""")
            .firstMatch(lines[i]);
        if (match == null) continue;
        final uri = match.group(1)!;
        if (!uri.startsWith('dart:') && !uri.startsWith('package:')) {
          violations.add('${file.path}:${i + 1}  $uri');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('core/ 는 appfit_core 가 아직 의존하지 않는 패키지를 쓰지 않는다', () {
    final violations = <String>[];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = RegExp(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""")
            .firstMatch(lines[i]);
        if (match == null) continue;
        final uri = match.group(1)!;
        if (!uri.startsWith('package:')) continue;

        final pkg = uri.substring('package:'.length).split('/').first;
        if (pkg == 'appfit_order_agent') continue; // 위 테스트가 담당
        if (allowedPackages.contains(pkg)) continue;

        violations.add('${file.path}:${i + 1}  $pkg');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '승격 시 appfit_core/pubspec.yaml 에 새 의존성이 필요해진다. '
          '3앱 공유 패키지라 버전 충돌 위험이 있으니 별도 판단 후 allowedPackages 에 '
          '추가할 것.\n${violations.join('\n')}',
    );
  });
}
