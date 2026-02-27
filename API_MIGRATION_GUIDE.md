# API 마이그레이션 가이드

이 문서는 기존 브랜드와 신규 브랜드 간의 API 버전 관리 방법을 설명합니다.

## 📋 개요

프로젝트는 이제 두 가지 API 버전을 지원합니다:
- **Legacy API**: 기존 브랜드들이 사용하는 API
- **AppFit API**: 신규 브랜드들이 사용할 새로운 플랫폼 API

## 🏗️ 아키텍처

### 구조

```
lib/services/
├── api_service_interface.dart    # API 인터페이스 정의
├── legacy_api_service.dart        # 기존 API 구현
├── appfit_api_service.dart        # 신규 API 구현 (스켈레톤)
├── api_service_factory.dart       # API 버전별 서비스 생성
└── api_service.dart               # 기존 호환성 유지 + Provider

lib/config/
└── server_config.dart             # 브랜드별 설정 및 API 버전 관리
```

### 주요 클래스

#### 1. ApiVersion (Enum)
```dart
enum ApiVersion {
  legacy,  // 기존 플랫폼
  v2,      // 신규 플랫폼 (AppFit)
}
```

#### 2. BrandConfig
브랜드별 설정을 담는 클래스입니다.

```dart
class BrandConfig {
  final String checkURL;
  final String checkURL_https;
  final String prefix;
  final String notiUrl;
  final int port;
  final ApiVersion apiVersion;  // API 버전
}
```

#### 3. ApiServiceInterface
모든 API 서비스가 구현해야 하는 인터페이스입니다.

주요 메서드:
- `getOrders()` - 주문 목록 조회
- `updateOrderStatus()` - 주문 상태 업데이트
- `getStoreInfo()` - 매장 정보 조회
- `getProducts()` - 상품 목록 조회
- 기타 멤버십, 리워드 관련 메서드들

#### 4. ApiServiceFactory
API 버전에 따라 적절한 서비스를 생성합니다.

```dart
// API 버전으로 생성
ApiServiceFactory.create(ApiVersion.legacy, ref);

// 브랜드 설정으로 생성
ApiServiceFactory.createFromBrandConfig(brandConfig, ref);

// Store ID로 생성
ApiServiceFactory.createFromStoreId(storeId, ref);
```

## 🚀 신규 브랜드 추가 방법

### 1. server_config.dart에 브랜드 추가

```dart
// 상수 정의
static const String newBrandPRE = "K999";
static const String newBrandCheckURL = "https://new-brand-api.example.com";
static const String newBrandCheckURL_https = "https://new-brand-api.example.com";
static const String newBrandNotiUrl = "https://new-brand-noti.example.com:9999";
static const int newBrandPort = 9999;

// _brandConfigs Map에 추가
static final Map<String, BrandConfig> _brandConfigs = {
  // ... 기존 브랜드들
  newBrandPRE: BrandConfig(
    checkURL: newBrandCheckURL,
    checkURL_https: newBrandCheckURL_https,
    prefix: newBrandPRE,
    notiUrl: newBrandNotiUrl,
    port: newBrandPort,
    apiVersion: ApiVersion.v2,  // 신규 API (AppFit) 사용
  ),
};
```

### 2. AppFit API 구현

`lib/services/appfit_api_service.dart` 파일에서 실제 API 로직을 구현합니다.

```dart
@override
Future<List<OrderModel>> getOrders(
  String storeId, {
  String? startDate,
  String? endDate,
  String? orderStatus,
}) async {
  // TODO: 신규 플랫폼 (AppFit) API 엔드포인트 호출
  // 예: GET /v2/orders?storeId={storeId}&date={startDate}
  
  final response = await _dio.get('/v2/orders', queryParameters: {
    'storeId': storeId,
    'startDate': startDate,
    'endDate': endDate,
  });
  
  // 응답 파싱 및 OrderModel 리스트 반환
  return (response.data as List)
      .map((json) => OrderModel.fromJson(json))
      .toList();
}
```

### 3. 테스트

신규 브랜드로 로그인하면 자동으로 AppFit API가 사용됩니다.

```dart
// 자동으로 적절한 API 서비스가 선택됨
final apiService = ref.read(apiServiceProvider);
final orders = await apiService.getOrders(storeId);
```

## 🔄 기존 브랜드를 신규 API로 마이그레이션

기존 브랜드를 신규 API로 전환하려면 `server_config.dart`에서 해당 브랜드의 `apiVersion`만 변경하면 됩니다.

```dart
mmthPRE: BrandConfig(
  checkURL: mmthCheckURL,
  checkURL_https: mmthCheckURL_https,
  prefix: mmthPRE,
  notiUrl: mmthNotiUrl,
  port: mmthPort,
  apiVersion: ApiVersion.v2,  // legacy → v2(AppFit)로 변경
),
```

## 📝 사용 예시

### Provider에서 사용

```dart
@riverpod
class OrderList extends _$OrderList {
  @override
  Future<List<OrderModel>> build(String storeId) async {
    final apiService = ref.read(apiServiceProvider);
    return apiService.getOrders(storeId);
  }
}
```

### 직접 사용

```dart
// 현재 설정된 API 버전으로 자동 선택
final apiService = ref.read(apiServiceProvider);
final orders = await apiService.getOrders(storeId);

// 또는 특정 버전 명시
final legacyService = LegacyApiService(ref);
final appfitService = AppFitApiService(ref);
```

## ⚠️ 주의사항

1. **하위 호환성**: 기존 코드는 그대로 동작합니다. `ApiService` 클래스는 여전히 사용 가능합니다.

2. **API 인터페이스 준수**: 새로운 API를 구현할 때는 반드시 `ApiServiceInterface`를 구현해야 합니다.

3. **에러 처리**: AppFit API 구현 시 기존과 동일한 예외 처리 패턴을 따라야 합니다:
   - `NetworkException`: 네트워크 오류
   - `ServerException`: 서버 응답 오류
   - `DataParsingException`: 데이터 파싱 오류
   - `BusinessLogicException`: 비즈니스 로직 오류

4. **테스트**: 신규 API 구현 후 반드시 충분한 테스트를 거쳐야 합니다.

## 🔍 디버깅

현재 사용 중인 API 버전 확인:

```dart
final apiVersion = ServerConfig.getApiVersion();
logger.d('Current API Version: $apiVersion');

// 브랜드 설정 확인
final brandConfig = ServerConfig.getBrandConfig(storeId);
logger.d('Brand API Version: ${brandConfig?.apiVersion}');
```

## 📚 다음 단계

1. ✅ API 버전 관리 구조 구축 (완료)
2. ✅ Legacy API 서비스 분리 (완료)
3. ✅ AppFit API 스켈레톤 구현 (완료)
4. ⏳ AppFit API 실제 구현 (진행 예정)
5. ⏳ 신규 브랜드 테스트 (진행 예정)
6. ⏳ 기존 브랜드 점진적 마이그레이션 (진행 예정)

## 💡 팁

- 신규 브랜드 추가 시 먼저 `ApiVersion.legacy`로 시작해서 테스트 후 `v2`(AppFit)로 전환하는 것을 권장합니다.
- AppFit API 구현 시 Legacy API의 로직을 참고하되, 신규 플랫폼의 API 스펙에 맞게 수정하세요.
- 로그를 충분히 남겨서 어떤 API 버전이 사용되는지 추적 가능하도록 하세요.

