# V2 API 설정 가이드 (Waldlust Platform)

## ✅ Phase 1 완료 항목

### 생성된 파일

1. **암호화 유틸리티**
   - `lib/services/v2/crypto_utils.dart`
   - AES-256-GCM 암호화/복호화
   - HMAC-SHA512 서명 생성

2. **토큰 관리**
   - `lib/services/v2/token_manager.dart`
   - JWT 토큰 발급 및 자동 갱신
   - SharedPreferences를 통한 토큰 저장

3. **V2 설정**
   - `lib/services/v2/v2_config.dart`
   - 환경별 URL 관리 (dev/staging/live)
   - Project 정보 관리

4. **Dio Provider**
   - `lib/services/v2/v2_dio_provider.dart`
   - JWT 인증 자동 처리
   - 토큰 자동 갱신 (401 에러 시)
   - 로깅 인터셉터

5. **브랜드 설정**
   - `lib/config/server_config.dart`에 appfit 브랜드 추가
   - ApiVersion.v2로 설정

---

## 🔧 필수 설정 항목

### 1. V2Config 설정 (`lib/services/v2/v2_config.dart`)

다음 값들을 Waldlust에서 받은 실제 값으로 교체해야 합니다:

```dart
// TODO: 실제 값으로 교체
static const String projectId = 'YOUR_PROJECT_ID';
static const String projectApiKey = 'YOUR_PROJECT_API_KEY';
static const String aesKey = 'YOUR_AES_KEY_32_BYTES_STRING';
```

### 2. 환경 설정

현재 환경을 선택하세요:

```dart
// dev, staging, live 중 선택
static const V2Environment environment = V2Environment.dev;
```

### 3. 브랜드 Prefix 설정 (`lib/config/server_config.dart`)

```dart
// TODO: 실제 prefix로 변경
static const String appfitPRE = "WALD"; // 예: "WALD", "APFT" 등
```

---

## 📋 사용 방법

### 토큰 발급 테스트

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kokonut_order_agent/services/v2/v2_dio_provider.dart';

// Provider에서 사용
final tokenManager = ref.read(v2TokenManagerProvider);

// 토큰 발급
final token = await tokenManager.getValidToken('WALD00001'); // shopCode

// API Key 검증
final isValid = await tokenManager.validateApiKey();
```

### V2 Dio 사용

```dart
// V2 Dio Provider 사용
final dio = ref.read(v2DioProvider);

// API 호출 (자동으로 토큰 추가됨)
final response = await dio.get('/v0/some-endpoint');
```

### 암호화/복호화

```dart
import 'package:kokonut_order_agent/services/v2/crypto_utils.dart';

// AES-256-GCM 암호화
final encrypted = CryptoUtils.encryptAesGcm(
  'plaintext',
  'your-aes-key-32-bytes',
);

// 복호화
final decrypted = CryptoUtils.decryptAesGcm(
  encrypted,
  'your-aes-key-32-bytes',
);

// HMAC-SHA512 서명
final signature = CryptoUtils.generateHmacSha512Signature(
  'project-api-key',
  '{"key":"value"}',
);
```

---

## 🔍 체크리스트

### 설정 완료 확인

- [ ] `V2Config.projectId` 설정
- [ ] `V2Config.projectApiKey` 설정
- [ ] `V2Config.aesKey` 설정 (32바이트)
- [ ] `ServerConfig.appfitPRE` 설정
- [ ] 환경 선택 (dev/staging/live)

### 테스트 항목

- [ ] 토큰 발급 테스트
- [ ] API Key 검증 테스트
- [ ] 암호화/복호화 테스트
- [ ] V2 Dio Provider 동작 확인

---

## 📝 다음 단계 (Phase 2)

1. **V2ApiService 구현**
   - `lib/services/v2_api_service.dart` 업데이트
   - 주요 API 엔드포인트 구현
     - getOrders
     - updateOrderStatus
     - getOrderDetail
     - getStoreInfo
     - getProducts

2. **WebSocket 통합**
   - 실시간 주문 알림
   - WebSocket 인증 (암호화된 API Key)

3. **에러 처리**
   - 표준 에러 응답 파싱
   - 재시도 로직

---

## 🐛 트러블슈팅

### 토큰 발급 실패

**증상**: `INVALID_SIGNATURE` 에러

**해결방법**:
1. `projectApiKey`가 올바른지 확인
2. Payload가 공백 없는 compact JSON인지 확인
3. 시스템 시간이 서버와 동기화되어 있는지 확인 (±5분)

### 401 Unauthorized

**증상**: API 호출 시 401 에러

**해결방법**:
1. 토큰이 만료되지 않았는지 확인
2. Authorization 헤더 형식 확인 (`Bearer {token}`)
3. 토큰을 다시 발급받기

### 암호화 오류

**증상**: AES 암호화/복호화 실패

**해결방법**:
1. `aesKey`가 정확히 32바이트인지 확인
2. IV가 12바이트인지 확인
3. AuthTag가 16바이트인지 확인

---

## 📚 참고 문서

- `0. 외부 API 토큰 발급 가이드.md`
- `1. Waldlust 외부 통신용 암호화 가이드.md`
- `2. API 시그니처 생성 가이드.md`
- `3. Noti 서버 WebSocket 연결 가이드.md`
- `API_MIGRATION_GUIDE.md`

---

## ⚙️ 환경 변수 (권장)

보안을 위해 민감한 정보는 환경 변수로 관리하는 것을 권장합니다:

```dart
// .env 파일 (Git에 커밋하지 말 것!)
V2_PROJECT_ID=your-project-id
V2_API_KEY=your-api-key
V2_AES_KEY=your-aes-key
```

```dart
// flutter_dotenv 패키지 사용
import 'package:flutter_dotenv/flutter_dotenv.dart';

static String get projectId => dotenv.env['V2_PROJECT_ID'] ?? '';
static String get projectApiKey => dotenv.env['V2_API_KEY'] ?? '';
static String get aesKey => dotenv.env['V2_AES_KEY'] ?? '';
```

