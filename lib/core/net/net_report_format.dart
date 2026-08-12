/// 원격 관제(Sentry·Slack) 문구 전용 최소 포맷터.
///
/// `intl` 을 끌어오지 않는다 — 이 문구들은 매장 직원이 아니라 개발·운영팀이
/// 읽으므로 로캘 분기가 필요 없고, 패키지 하나를 더 얹을 이유도 없다
/// (`SyncStatusBanner._hhmm` 과 같은 판단).
library;

String _two(int v) => v.toString().padLeft(2, '0');

/// 시:분만 — `21:07`.
String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// 날짜를 **반드시 포함하는** 짧은 시각 표기 — `08-11 21:07`.
///
/// 왜 날짜를 넣는가: 매장 네트워크 장애로 생긴 Sentry 이벤트는 그 장애가 끝나고
/// 앱이 재시작돼야 서버에 도착한다. 2026-08-11 PAIK00002 장애는 21:09 에
/// 발생했는데 슬랙 알림은 다음 날 07:00 에 왔다(9시간 41분 지연). 제목에 시각이
/// 없으면 "오늘 아침 장애"로 오독하게 된다 — 실제로 그렇게 읽혔다.
///
/// 연도는 뺀다. 지연은 길어야 하루 단위라 월-일이면 충분하고, 제목은 슬랙에서
/// 한 줄로 보여야 한다.
String formatStamp(DateTime t) =>
    '${_two(t.month)}-${_two(t.day)} ${formatClock(t)}';

/// 구간 표기 — `08-11 21:09~21:19`.
///
/// 같은 날이면 끝 시각의 날짜를 생략한다(`08-11 21:09~08-11 21:19` 는 읽는 데
/// 방해만 된다). 자정을 넘긴 구간은 날짜를 붙여 `08-11 23:55~08-12 00:07`.
String formatRange(DateTime from, DateTime to) {
  final sameDay =
      from.year == to.year && from.month == to.month && from.day == to.day;
  return '${formatStamp(from)}~${sameDay ? formatClock(to) : formatStamp(to)}';
}

/// 사람이 읽는 지속 시간 — `41초` / `9분 41초` / `1시간 3분`.
///
/// 1시간을 넘으면 초를 버린다. 그 규모에서는 초가 판단을 바꾸지 않고 제목만
/// 길어진다. 음수(시계 역행 등)는 `0초` 로 흡수한다 — 관제 문구에서 `-3초` 는
/// 읽는 사람을 멈춰 세울 뿐 알려주는 게 없다.
String formatDuration(Duration d) {
  if (d.isNegative) return '0초';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '$h시간 $m분';
  if (m > 0) return '$m분 $s초';
  return '$s초';
}
