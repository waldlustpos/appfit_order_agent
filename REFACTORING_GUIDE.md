# OrderProvider 리팩토링 가이드

현재 `order_provider.dart`가 3300줄이 넘는 거대한 파일이 되어 있어서 주문 처리 핵심 로직에만 집중하도록 리팩토링이 필요합니다.

## 분리된 관리자 클래스들

### 1. OrderSettingsManager (완료)
**위치**: `lib/providers/order_settings_manager.dart`

**책임**:
- 알람소리 설정 (파일명, 횟수, 볼륨)
- 자동접수 설정
- AudioPlayer 설정

**주요 메서드**:
- `loadSoundSettings()` - 알람소리 설정 로드
- `applyAudioPlayerSettings()` - AudioPlayer 설정 적용
- `updateAutoReceipt()` - 자동접수 설정 업데이트

### 2. OrderStateManager (완료)
**위치**: `lib/providers/order_state_manager.dart`

**책임**:
- 주문 목록 상태 관리
- 활성 주문 수 계산
- UI 상태 업데이트
- Blink 상태 관리

**주요 메서드**:
- `calculateActiveOrderCount()` - 활성 주문 수 계산
- `updateOrderInList()` - 주문 목록에서 특정 주문 업데이트
- `addOrUpdateOrderInState()` - 주문 추가/업데이트
- `performImmediateUIUpdate()` - 즉시 UI 업데이트

### 3. OrderCacheManager (완료)
**위치**: `lib/providers/order_cache_manager.dart`

**책임**:
- 주문 상세 정보 캐시 관리
- 출력 이력 캐시 관리
- 백그라운드 상세 정보 로드
- 캐시 정리

**주요 메서드**:
- `getCachedOrderDetail()` - 캐시에서 주문 상세 조회
- `fetchOrderDetail()` - API 호출 포함 상세 정보 조회
- `hasBeenPrinted()` - 출력 여부 확인
- `markAsPrinted()` - 출력 완료 표시
- `loadOrderDetailsInBackground()` - 백그라운드 로드

### 4. OrderTimerManager (완료)
**위치**: `lib/providers/order_timer_manager.dart`

**책임**:
- 폴링 타이머 관리
- 캐시 정리 타이머 관리
- 자정 새로고침 타이머 관리
- 소켓 구독 관리

**주요 메서드**:
- `setupPollingTimer()` - 폴링 타이머 설정
- `setupCacheCleanupTimer()` - 캐시 정리 타이머 설정
- `scheduleMidnightRefresh()` - 자정 새로고침 예약
- `setOrderNotificationSubscription()` - 주문 알림 구독 설정

## 리팩토링 방법

### 1단계: 관리자 클래스 인스턴스 생성
기존 OrderProvider의 `build()` 메서드에서:

```dart
@override
OrderState build() {
  _apiService = ref.watch(apiServiceProvider);
  _preferenceService = ref.read(preferenceServiceProvider);
  
  // 관리자 클래스들 초기화
  _settingsManager = OrderSettingsManager(ref, _preferenceService);
  _stateManager = OrderStateManager(ref);
  _cacheManager = OrderCacheManager(ref, _orderDetailCache, _printedOrderCache);
  _timerManager = OrderTimerManager(ref, 
    onPollNewOrders: _pollNewOrders,
    onRefreshOrders: () => refreshOrders(),
    onCacheCleanup: () => _cacheManager.cleanupExpiredEntries(),
  );
  
  // ... 나머지 초기화 코드
}
```

### 2단계: 기존 메서드들을 관리자 클래스 호출로 대체

#### 설정 관련 메서드들:
```dart
// 기존:
void _loadSoundSettings() { ... 복잡한 로직 ... }

// 리팩토링 후:
void _loadSoundSettings() {
  _settingsManager.loadSoundSettings();
  _settingsManager.applyAudioPlayerSettings(_audioPlayer);
}
```

#### 상태 관리 메서드들:
```dart
// 기존:
int _calculateActiveOrderCount(List<OrderModel> orders) { ... 복잡한 로직 ... }

// 리팩토링 후:
int _calculateActiveOrderCount(List<OrderModel> orders) {
  return _stateManager.calculateActiveOrderCount(orders);
}
```

#### 캐시 관리 메서드들:
```dart
// 기존:
Future<OrderModel> getOrderDetail(String orderId, String storeId) async { ... 복잡한 로직 ... }

// 리팩토링 후:
Future<OrderModel> getOrderDetail(String orderId, String storeId) async {
  return await _cacheManager.getOrderDetail(orderId, storeId, state.orders);
}
```

### 3단계: 생명주기 메서드들 정리

```dart
void cleanupOnLogout() {
  logger.d('[OrderProvider] 로그아웃 시 정리 시작');
  
  _isLoggedOut = true;
  
  // 각 관리자들의 정리 메서드 호출
  _timerManager.cleanupOnLogout();
  _settingsManager.clearOnLogout();
  _cacheManager.clearOnLogout();
  
  // 기존 정리 로직들...
  
  logger.d('[OrderProvider] 로그아웃 시 정리 완료');
}

void reloadSettings() {
  logger.d('[OrderProvider] 설정 재로드 시작');
  
  _isLoggedOut = false;
  
  // 각 관리자들의 재로드 메서드 호출
  _settingsManager.reloadAfterLogin();
  _timerManager.setupPollingTimer(_isLoggedOut);
  
  // 기존 재로드 로직들...
  
  logger.d('[OrderProvider] 설정 재로드 완료');
}
```

## 예상되는 효과

### 1. 코드 크기 감소
- 현재 3300줄 → 예상 1500-2000줄로 감소
- 각 관리자 클래스는 200-400줄 정도

### 2. 가독성 향상
- 각 책임이 명확하게 분리됨
- 주문 처리 핵심 로직에 집중 가능
- 디버깅과 유지보수가 쉬워짐

### 3. 테스트 용이성
- 각 관리자 클래스를 독립적으로 테스트 가능
- Mock 객체 사용이 쉬워짐

### 4. 재사용성
- 다른 Provider에서도 관리자 클래스들을 재사용 가능

## 주의사항

1. **점진적 리팩토링**: 한 번에 모든 것을 바꾸지 말고 단계적으로 진행
2. **테스트**: 각 단계마다 기능이 정상 작동하는지 확인
3. **의존성**: 관리자 클래스들 간의 의존성을 최소화
4. **상태 공유**: `ref`를 통한 상태 공유는 신중하게 사용

## 다음 단계

1. 기존 OrderProvider에 관리자 클래스 인스턴스 추가
2. 설정 관련 메서드들부터 순차적으로 관리자 클래스 호출로 변경
3. 상태 관리 메서드들 변경
4. 캐시 관리 메서드들 변경
5. 타이머 관리 메서드들 변경
6. 불필요한 코드 제거 및 정리

이렇게 하면 OrderProvider가 주문 처리 핵심 로직에만 집중할 수 있게 되고, 각 책임이 명확하게 분리되어 유지보수가 훨씬 쉬워질 것입니다.
