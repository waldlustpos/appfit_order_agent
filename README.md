# Kokonut Order Agent

Flutter 기반 주문 접수 앱으로, 두 가지 브랜드별 빌드를 지원합니다.

## 빌드 방법

### 1. 코코넛 주문 접수 (kokonut flavor)
```bash
./build_main.sh
```
- **패키지명**: `co.kr.waldlust.order.receive`
- **앱 이름**: 코코넛 주문 접수
- **버전**: 2.0.1 (82)
- **Firebase**: 활성화됨
- **특징**: 완전한 기능을 포함한 메인 앱

### 2. 커먼브랜드 주문 (commonBrand flavor)
```bash
./build_common_brand.sh
```
- **패키지명**: `co.kr.waldlust.order.common`
- **앱 이름**: 커먼브랜드 주문
- **버전**: 1.0.0 (1)
- **Firebase**: 비활성화됨 (Firebase 설정 문제로 인한 임시 조치)
- **특징**: 기본 주문 기능만 포함

## 주요 특징

### Flavor별 차이점
- **패키지명**: 각각 다른 패키지명으로 별도 앱으로 인식
- **앱 이름**: 홈 화면에 표시되는 앱 이름이 다름
- **버전**: 독립적인 버전 관리
- **Firebase**: kokonut flavor만 Firebase 기능 사용

### 공통 기능
- 주문 접수 및 관리
- 실시간 주문 알림
- 프린터 연동
- 백그라운드 서비스

## 개발 환경
- Flutter 3.x
- Android API 24+
- Kotlin/Java

## 주의사항
- commonBrand flavor는 Firebase 설정 문제로 인해 Firebase 기능이 비활성화되어 있습니다.
- 두 앱을 동시에 설치할 수 있으며, 각각 독립적으로 작동합니다.

**현재 주문 처리 로직 흐름**

**1. 주문 수신 방법**
   
  소켓 통신: 실시간으로 새 주문/변경 사항을 수신
  
  폴링: 60초마다 서버에 새 주문이 있는지 확인 (_pollNewOrders 메서드)
  
  수동 새로고침: 사용자가 UI에서 새로고침 요청 시 (refreshOrders 메서드)

**3. 주문 처리 큐 시스템**
 
  주문이 들어오면 _orderProcessingQueue에 추가
  
  50ms마다 _processNextOrdersInBatch 메서드가 실행되어 큐 처리
  
  배치 수집 시간(200ms) 동안 주문을 모은 후 simpleNum 기준으로 정렬
  
  정렬된 순서대로 주문을 처리하여 올바른 출력 순서 보장



**4. 주문 상태별 처리**

  NEW 상태:
  
  자동 접수 설정 확인 (키오스크 주문은 항상 자동 접수)
  
  소리 알림, UI 블링크 효과 활성화
  
  ACCEPTED 상태:
  
  이미 출력된 주문인지 확인 (_printedOrderCache)
  
  출력 조건 확인 후 영수증 인쇄 (processOrderOutput)
  
  
  READY_FOR_PICKUP, COMPLETED, CANCELLED 상태:
  
  UI 상태 업데이트
  
  상태별 후속 처리 (취소 영수증 인쇄 등)



**5. 중복 처리 방지 메커니즘**

  큐 중복 확인: 이미 큐에 있는 주문은 재추가하지 않음
  
  출력 이력 확인: _printedOrderCache로 이미 출력된 주문 추적
  
  상태 유효성 검사: 최신 상태보다 오래된 정보는 무시






**수신(소켓/폴링) → 큐 추가(_queueOrder) → 배치 수집(_startBatchCollection) → 정렬(_sortBatchQueueByOrderNumber) → 처리(_processSingleOrder) → UI 업데이트**
