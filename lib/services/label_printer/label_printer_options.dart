// 라벨 프린터 SDK 호출 시 적용되는 사용자 옵션.
//
// 양 플랫폼 (Android Caysn SDK / Windows autoreplyprint.dll) 공통.
// PreferenceService 에서 읽어서 backend 로 전달.

class LabelPrinterOptions {
  const LabelPrinterOptions({
    required this.autoReplyMode,
    required this.useFeedToTear,
    required this.useBackToPrint,
    required this.useCalibrate,
  });

  final int autoReplyMode;
  final bool useFeedToTear;
  final bool useBackToPrint;
  final bool useCalibrate;
}
