# AppFit API 설정 완료 가이드 ✅

## 🎉 Phase 1 완료!

보안 권장사항을 준수한 AppFit API 설정이 완료되었습니다.

---

## 📁 생성된 파일

### 핵심 파일
1. **`lib/services/appfit/crypto_utils.dart`** - AES-256-GCM 암호화 & HMAC-SHA512
2. **`lib/services/appfit/token_manager.dart`** - JWT 토큰 관리
3. **`lib/services/appfit/appfit_config.dart`** - AppFit 설정 (환경 변수 기반) ⭐
4. **`lib/services/appfit/appfit_dio_provider.dart`** - Dio Provider (자동 인증)
5. **`lib/screens/appfit_test_screen.dart`** - 테스트 화면 ⭐

### 설정 파일
6. **`.env.example`** - 환경 변수 템플릿
7. **`.env`** - 실제 환경 변수 (Git 무시됨) 🔒

---

## 🔐 보안 강화 사항

### ✅ 완료된 보안 조치

1. **환경 변수 사용**
   - `flutter_dotenv` 패키지로 민감 정보 분리
   - `.env` 파일에서 API Key, Project ID, AES Key 로드
2. **Git 보안**
   - `.env` 파일 자동 무시
   - `.env.example`로 템플릿 제공
3. **민감 정보 마스킹**
   - 로그에서 API Key, Token 자동 마스킹
   - 테스트 화면에서도 마스킹 처리
4. **에러 처리**
   - 환경 변수 누락 시 명확한 에러 메시지
   - 설정 검증 기능 제공

---

## 🚀 설정 방법

### 1단계: 환경 변수 설정

프로젝트 루트의 `.env` 파일을 열어서 Waldlust에서 받은 실제 값으로 변경하세요:

```bash
# .env 파일 편집
APPFIT_PROJECT_ID=실제_프로젝트_ID
APPFIT_API_KEY=실제_API_키
APPFIT_AES_KEY=실제_32바이트_AES_키
APPFIT_ENVIRONMENT=dev
```

⚠️ **주의**: `.env` 파일은 절대 Git에 커밋하지 마세요!

### 2단계: 환경 선택

```bash
# 개발 환경
APPFIT_ENVIRONMENT=dev

# 스테이징 환경
APPFIT_ENVIRONMENT=staging

# 운영 환경
APPFIT_ENVIRONMENT=live
```

### 3단계: 앱 실행

```bash
flutter run
```

---

## 🧪 테스트 방법

### 앱에서 테스트

1. 앱 실행
2. 설정 화면으로 이동
3. 맨 아래 "개발자 옵션" 섹션 확인
4. "AppFit API 테스트" 버튼 클릭
5. 순서대로 테스트 진행:
   - ✅ 환경 설정 확인
   - ✅ 1. 암호화 테스트
   - ✅ 2. API Key 검증
   - ✅ 3. 토큰 발급 테스트

### 테스트 화면 기능

- **환경 설정 확인**: 환경 변수가 올바르게 로드되었는지 확인
- **암호화 테스트**: AES-256-GCM 암호화/복호화 동작 확인
- **API Key 검증**: Project API Key가 유효한지 서버에 확인
- **토큰 발급 테스트**: JWT 토큰 발급 및 저장 확인

---

## 📊 환경별 URL

| 환경 | Core API | WebSocket |
|------|----------|-----------|
| **Dev** | `https://core-devapi.waldplatform.com` | `wss://notifier-devapi.waldplatform.com` |
| **Staging** | `https://core-stgapi.waldplatform.com` | `wss://notifier-stgapi.waldplatform.com` |
| **Live** | `https://core-api.waldplatform.com` | `wss://notifier-api.waldplatform.com` |

---

## 🔍 문제 해결

### 문제 1: "환경 변수 로드 완료" 로그가 안 보임

**원인**: `.env` 파일이 없거나 경로가 잘못됨

**해결**:
```bash
# 프로젝트 루트에 .env 파일이 있는지 확인
ls -la .env

# 없으면 생성
cp .env .env
```

### 문제 2: "APPFIT_PROJECT_ID가 설정되지 않았습니다"

**원인**: `.env` 파일에 실제 값이 입력되지 않음

**해결**:
```bash
# .env 파일 편집
nano .env

# 또는
open .env
```

### 문제 3: 토큰 발급 실패 (INVALID_SIGNATURE)

**원인**: API Key가 잘못되었거나 시스템 시간이 동기화되지 않음

**해결**:
1. `.env` 파일의 `APPFIT_API_KEY` 확인
2. 시스템 시간 동기화:
   ```bash
   # macOS
   sudo sntp -sS time.apple.com
   ```

### 문제 4: 암호화 테스트 실패

**원인**: AES 키가 올바르지 않음

**해결**:
1. `.env` 파일의 `APPFIT_AES_KEY` 확인
2. 키가 정확히 32바이트인지 확인

---

## 📝 체크리스트

### 설정 완료

- [ ] `.env` 파일 생성
- [ ] `APPFIT_PROJECT_ID` 실제 값 입력
- [ ] `APPFIT_API_KEY` 실제 값 입력
- [ ] `APPFIT_AES_KEY` 실제 값 입력 (32바이트)
- [ ] `APPFIT_ENVIRONMENT` 선택 (dev/staging/live)
- [ ] `.env` 파일이 `.gitignore`에 포함되어 있는지 확인

### 테스트 완료

- [ ] 환경 설정 확인 통과
- [ ] 암호화 테스트 통과
- [ ] API Key 검증 통과
- [ ] 토큰 발급 테스트 통과

---

## 📚 코드 예시

### AppFitConfig 사용

```dart
import 'package:kokonut_order_agent/services/appfit/appfit_config.dart';

// 환경 정보 확인
print('현재 환경: ${AppFitConfig.environment.name}');
print('Base URL: ${AppFitConfig.baseUrl}');

// 설정 검증
if (AppFitConfig.isConfigured()) {
  print('✅ AppFit 설정 완료');
} else {
  print('❌ AppFit 설정 필요');
}

// 설정 요약 (마스킹됨)
print(AppFitConfig.getConfigSummary());
```

### 토큰 발급

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kokonut_order_agent/services/appfit/appfit_dio_provider.dart';

// Provider에서 사용
final tokenManager = ref.read(appFitTokenManagerProvider);

// 토큰 발급 (자동 캐싱 및 갱신)
final token = await tokenManager.getValidToken('WALD00001');
print('토큰: $token');
```

### AppFit API 호출

```dart
// AppFit Dio 사용 (자동 인증)
final dio = ref.read(appFitDioProvider);

// API 호출 - Authorization 헤더 자동 추가됨
final response = await dio.get('/v0/orders');
```

---

## 🎯 다음 단계

### Phase 2: AppFit API 구현

이제 실제 API 엔드포인트를 구현할 준비가 되었습니다:

1. **주문 API**
   - `getOrders()` - 주문 목록 조회
   - `updateOrderStatus()` - 주문 상태 업데이트
   - `getOrderDetail()` - 주문 상세 조회

2. **매장 API**
   - `getStoreInfo()` - 매장 정보 조회
   - `updateSaleStatus()` - 판매 상태 변경

3. **상품 API**
   - `getProducts()` - 상품 목록 조회
   - `updateProductStatus()` - 상품 상태 업데이트

### Phase 3: WebSocket 통합

- 실시간 주문 알림
- WebSocket 인증 (암호화된 API Key)
- 재연결 로직

---

## 🔗 관련 문서

- `APPFIT_API_SETUP_GUIDE.md` - 전체 설정 가이드
- `API_MIGRATION_GUIDE.md` - API 마이그레이션 가이드
- `0. 외부 API 토큰 발급 가이드.md` - 토큰 발급 상세 가이드
- `1. Waldlust 외부 통신용 암호화 가이드.md` - 암호화 가이드
- `2. API 시그니처 생성 가이드.md` - 시그니처 가이드
- `3. Noti 서버 WebSocket 연결 가이드.md` - WebSocket 가이드

---

## ⚠️ 중요 보안 주의사항

### 절대 하지 말아야 할 것

❌ `.env` 파일을 Git에 커밋  
❌ API Key를 코드에 하드코딩  
❌ 민감한 정보를 로그에 출력  
❌ 운영 키를 개발 환경에서 사용  

### 반드시 해야 할 것

✅ `.env` 파일 Git 무시 확인  
✅ 환경별로 다른 키 사용  
✅ 정기적인 키 갱신  
✅ 팀원과 안전한 채널로 키 공유  

---

## 💡 팁

### 빠른 환경 전환

```bash
# 개발 환경
echo "APPFIT_ENVIRONMENT=dev" > .env
cat .env | grep -v APPFIT_ENVIRONMENT >> .env

# 운영 환경
echo "APPFIT_ENVIRONMENT=live" > .env
cat .env | grep -v APPFIT_ENVIRONMENT >> .env
```

### 설정 검증 스크립트

```bash
# .env 파일 검증
if grep -q "your-project-id-here" .env; then
    echo "❌ .env 파일에 실제 값을 입력하세요!"
else
    echo "✅ .env 파일 설정 완료"
fi
```

---

## 📞 지원

문제가 발생하거나 도움이 필요한 경우:

1. 테스트 화면에서 "환경 설정 확인" 실행
2. 에러 메시지 확인
3. 이 문서의 "문제 해결" 섹션 참고
4. 개발팀에 문의

---

**축하합니다! 🎊**

보안이 강화된 AppFit API 기반 구축이 완료되었습니다.
이제 실제 API를 구현하거나 테스트를 진행하세요!

