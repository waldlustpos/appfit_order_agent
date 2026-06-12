import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
import 'package:appfit_order_agent/services/platform_service.dart';

part 'rotation_provider.g.dart';

@Riverpod(keepAlive: true)
class RotationNotifier extends _$RotationNotifier {
  @override
  bool build() {
    return ref.read(preferenceServiceProvider).getIsRotated180();
  }

  Future<void> setRotated180(bool value) async {
    state = value;
    await ref.read(preferenceServiceProvider).setIsRotated180(value);
    await PlatformService.setSystemRotation(value);
  }
}
