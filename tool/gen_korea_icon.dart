// 런처 아이콘 자산 생성기 (한국/일본 단일 패키지 공통).
//
// 로그인 화면과 동일한 대각선 그라데이션(BrandTheme.appfitDefault.loginGradient:
// topLeft #fb3e7e -> bottomRight #9843cb)을 아이콘 배경에 적용한다.
//
// 산출물:
//   assets/icons/app_icon_korea_bg.png        - 그라데이션만 (Android adaptive 배경 레이어)
//   assets/icons/app_icon_korea.png           - 그라데이션 + 흰색 로고 합성 (Android 레거시 아이콘)
//   windows/runner/resources/app_icon.ico     - Windows 런처/설치 아이콘 (단일 공통)
//
// 실행: dart run tool/gen_korea_icon.dart
// 이후(Android): flutter pub run flutter_launcher_icons  (pubspec 기본 블록 사용)
// (Windows ico 는 Runner.rc 의 단일 IDI_APP_ICON 이 직접 참조하므로 추가 단계 없음)
//
// image 는 flutter_launcher_icons 의 전이 의존성이라 직접 의존성 선언 없이 사용한다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

int _lerp(int a, int b, double t) =>
    (a + (b - a) * t).round().clamp(0, 255).toInt();

void main() {
  const size = 1024;

  // 로그인 그라데이션 색상 (lib/constants/brand_theme.dart appfitDefault).
  const r0 = 0xfb, g0 = 0x3e, b0 = 0x7e; // #fb3e7e (topLeft)
  const r1 = 0x98, g1 = 0x43, b1 = 0xcb; // #9843cb (bottomRight)

  // 대각선(topLeft -> bottomRight) 그라데이션 생성.
  // 보라(#9843cb)가 차지하는 면적을 줄이려고 t 에 1보다 큰 지수를 적용한다.
  // 값이 클수록 분홍이 더 넓어지고 보라는 우하단 모서리로 밀린다.
  const purpleBias = 1.7;
  final bg = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final linear = ((x / (size - 1)) + (y / (size - 1))) / 2.0;
      final t = math.pow(linear, purpleBias).toDouble();
      bg.setPixelRgba(
        x,
        y,
        _lerp(r0, r1, t),
        _lerp(g0, g1, t),
        _lerp(b0, b1, t),
        255,
      );
    }
  }

  File('assets/icons/app_icon_korea_bg.png')
      .writeAsBytesSync(img.encodePng(bg));

  // 레거시 아이콘: 그라데이션 위에 투명 배경 흰색 로고를 합성.
  final logo = img.decodePng(
    File('assets/icons/app_icon_transparent.png').readAsBytesSync(),
  );
  if (logo == null) {
    stderr.writeln('app_icon_transparent.png 디코딩 실패');
    exit(1);
  }
  final logoSized = (logo.width == size && logo.height == size)
      ? logo
      : img.copyResize(logo, width: size, height: size);
  final composite = bg.clone();
  img.compositeImage(composite, logoSized);
  File('assets/icons/app_icon_korea.png')
      .writeAsBytesSync(img.encodePng(composite));

  // Windows 런처/설치 아이콘(.ico) — 합성본을 256px ICO 로 인코딩.
  // Runner.rc 의 단일 IDI_APP_ICON 이 참조하는 공통 아이콘.
  final ico = img.copyResize(composite, width: 256, height: 256);
  File('windows/runner/resources/app_icon.ico')
      .writeAsBytesSync(img.encodeIco(ico));

  stdout.writeln(
    '생성 완료: assets/icons/app_icon_korea_bg.png, '
    'assets/icons/app_icon_korea.png, '
    'windows/runner/resources/app_icon.ico',
  );
}
