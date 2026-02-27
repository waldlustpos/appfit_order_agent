import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appfit_order_agent/providers/providers.dart';

class BlinkService {
  final Ref ref;
  BlinkService(this.ref);

  void updateActiveCount(int count) {
    ref.read(blinkStateProvider.notifier).updateActiveOrderCount(count);
  }

  void start() {
    ref.read(blinkStateProvider.notifier).startBlinking();
  }

  void stopIfZero(int count) {
    if (count == 0) {
      ref.read(blinkStateProvider.notifier).stopBlinking();
    }
  }
}

final blinkAppServiceProvider = Provider<BlinkService>((ref) {
  return BlinkService(ref);
});
