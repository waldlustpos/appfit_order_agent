import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async'; // FutureOr 사용을 위해 추가
import '../models/store_model.dart';
import '../services/platform_service.dart';
import '../services/preference_service.dart';
import 'kds_unified_providers.dart';
import 'providers.dart';
import 'package:appfit_order_agent/utils/logger.dart'; // logger import 추가

part 'store_provider.g.dart';

@Riverpod(keepAlive: true)
class Store extends _$Store {
  // build 메서드는 초기 상태를 정의합니다.
  @override
  FutureOr<StoreModel?> build() async {
    // 초기 로딩 시 매장 ID가 없으므로 null 반환
    // setStoreModel을 통해 실제 데이터 로드
    return null;
  }

  // 매장 정보 설정 (비동기 로드)
  Future<StoreModel?> setStoreModel(String storeId) async {
    state = const AsyncLoading(); // 로딩 상태 설정
    try {
      // AsyncNotifier 내부에서는 ref 사용 가능
      final apiService = ref.read(apiServiceProvider);
      final storeModel = await apiService.getStoreInfo(storeId);
      state = AsyncData(storeModel); // 데이터 로드 성공

      // 매장 정보 로그
      const sep = '[SYSTEM] ─────────────────────────────────────────────';
      logger.i(sep);
      logger.i('[SYSTEM]  매장 정보 로드 완료');
      logger.i('[SYSTEM]  매장 ID  : ${storeModel.storeId}');
      logger.i('[SYSTEM]  매장 이름: ${storeModel.name}');
      logger.i('[SYSTEM]  영업 상태: ${storeModel.isOpen ? "영업 중" : "영업 종료"}');
      logger.i(sep);

      return storeModel;
    } catch (e, stackTrace) {
      logger.e('매장 정보 조회 오류',
          error: e, stackTrace: stackTrace); // logger.e 로 변경
      state = AsyncError(e, stackTrace); // 에러 상태 설정
      return null;
    }
  }

  // 영업 상태 업데이트 (낙관적 업데이트)
  Future<void> setIsOpen(bool value) async {
    // KDS 모드에서는 영업 상태 업데이트를 서버에 전송하지 않음
    final isKdsMode = ref.read(kdsModeProvider);
    if (isKdsMode) {
      logger.i('KDS 모드: updateSaleStatus 호출 생략 (setIsOpen: $value)');
      return;
    }

    // AsyncNotifier 내부에서는 state 사용 가능
    // 현재 상태가 데이터 로드 완료 상태이고, 매장 정보가 있는지 확인
    if (!state.hasValue || state.value == null) {
      logger.w('매장 정보가 없어 영업 상태를 변경할 수 없습니다.'); // logger.w 로 변경
      return;
    }

    final currentModel = state.value!;
    final previousState = state; // 실패 시 복원을 위해 이전 상태 저장

    // 1. UI 즉시 업데이트 (낙관적)
    final optimisticModel = currentModel.copyWith(isOpen: value);
    state = AsyncData(optimisticModel);

    try {
      final apiService = ref.read(apiServiceProvider);
      final preferenceService = PreferenceService();

      // 2. Preference 저장
      await preferenceService.setOrderOn(value);

      // 3. API 호출 (서버 업데이트)
      final success = await apiService.updateShopOperatingStatus(
          currentModel.storeId, value);

      if (!success) {
        // 4a. API 실패 시 롤백
        logger.w('영업 상태 업데이트 실패: 원래 상태로 복원합니다.'); // logger.w 로 변경
        logToFile(tag: LogTag.UI_ACTION, message: '영업 상태 업데이트 실패: 원래 상태로 복원.');
        await preferenceService
            .setOrderOn(currentModel.isOpen); // Preference 롤백
        state = previousState; // 상태 롤백
      } else {
        // 4b. API 성공 시 (이미 UI는 업데이트됨)
        logToFile(
            tag: LogTag.UI_ACTION,
            message: '영업 상태 변경성공 -> ${value ? "영업중" : "영업종료"}');
      }
    } catch (error, stackTrace) {
      // 5. 예외 발생 시 롤백
      logger.e('영업 상태 업데이트 중 오류 발생',
          error: error, stackTrace: stackTrace); // logger.e 로 변경
      logToFile(
          tag: LogTag.UI_ACTION,
          message: '영업 상태 업데이트 중 오류 발생 $error , $stackTrace');
      // PreferenceService 직접 생성 대신 ref.read 사용
      await ref.read(preferenceServiceProvider).setOrderOn(currentModel.isOpen);
      // AsyncValue<StoreModel?> 타입으로 명시적 지정
      state = AsyncValue<StoreModel?>.error(error, stackTrace)
          .copyWithPrevious(previousState);
    }
  }

  void setStoreRewardType(String? rewardType) {
    final currentModel = state.value!;
    final optimisticModel = currentModel.copyWith(rewardType: rewardType);
    state = AsyncData(optimisticModel);
  }
}
