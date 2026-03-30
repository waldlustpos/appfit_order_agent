import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

part 'rotation_provider.g.dart';

@Riverpod(keepAlive: true)
class RotationNotifier extends _$RotationNotifier {
  @override
  bool build() {
    return PreferenceService().getIsRotated180();
  }

  Future<void> setRotated180(bool value) async {
    state = value;
    await PreferenceService().setIsRotated180(value);
    await PlatformService.setSystemRotation(value);
  }
}
