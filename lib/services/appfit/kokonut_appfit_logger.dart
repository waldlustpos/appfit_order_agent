import 'package:appfit_core/appfit_core.dart';
import '../../utils/logger.dart';

class KokonutAppFitLogger implements AppFitLogger {
  @override
  Future<void> log(String message) async {
    // [API] 태그를 추가하여 CustomLogOutput에서 필터링 가능하게 함
    logger.i('[API] [AppFitCore] $message');
  }

  @override
  Future<void> error(String message, dynamic error) async {
    // [API] ERROR 형식을 갖추어 파일에 기록되도록 함
    logger.e('[API] ERROR [AppFitCore] $message', error: error);
  }
}
