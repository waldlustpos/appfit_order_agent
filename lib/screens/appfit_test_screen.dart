import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed
import '../config/app_env.dart'; // AppEnv 추가 // import 추가
import 'package:appfit_core/appfit_core.dart';
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/services/api_service.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:intl/intl.dart';
import 'package:appfit_order_agent/utils/print/label_painter.dart';

/// AppFit API 설정 및 테스트 화면
///
/// - 환경 변수 설정 확인
/// - 토큰 발급 테스트
/// - API Key 검증 테스트
/// - 암호화/복호화 테스트
class AppFitTestScreen extends ConsumerStatefulWidget {
  const AppFitTestScreen({super.key});

  @override
  ConsumerState<AppFitTestScreen> createState() => _AppFitTestScreenState();
}

class _AppFitTestScreenState extends ConsumerState<AppFitTestScreen> {
  String _result = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  /// 환경 변수 설정 확인
  void _checkConfig() {
    try {
      final summary = AppFitConfig.getConfigSummary();
      final aesKey = AppEnv.aesKey;
      setState(() {
        _result = summary;
      });
    } catch (e, s) {
      setState(() {
        _result = '❌ 설정 오류: $e\n\n.env 파일을 확인하세요!';
      });
    }
  }

  /// API Key 검증 테스트
  Future<void> _testApiKeyValidation() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = 'API Key 검증 중...';
    });

    try {
      final tokenManager = ref.read(appFitTokenManagerProvider);
      final isValid = await tokenManager.validateApiKey();

      setState(() {
        _result = '''
${isValid ? '✅' : '❌'} API Key 검증 ${isValid ? '성공' : '실패'}

결과: ${isValid ? 'API Key가 유효합니다' : 'API Key가 유효하지 않습니다'}

${isValid ? '다음 단계:\n- 실제 API 호출을 시도하세요' : '해결 방법:\n1. .env 파일의 APPFIT_API_KEY 확인\n2. Waldlust에서 받은 키가 맞는지 확인'}
''';
      });

      logger.i('[AppFit 테스트] API Key 검증: $isValid');
    } catch (e, s) {
      logger.e('[AppFit 테스트] API Key 검증 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ API Key 검증 실패

에러: $e

해결 방법:
1. .env 파일의 APPFIT_API_KEY 확인
2. 서버 URL 확인
3. 네트워크 연결 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 암호화/복호화 테스트
  Future<void> _testEncryption() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '암호화/복호화 테스트 중...';
    });

    try {
      const testText = 'Hello, Waldlust Platform!';

      // 암호화
      final encrypted = CryptoUtils.encryptAesGcm(testText, AppEnv.aesKey);
      logger.d('[AppFit 테스트] 암호화 완료: ${encrypted.substring(0, 20)}...');

      // 복호화
      final decrypted = CryptoUtils.decryptAesGcm(encrypted, AppEnv.aesKey);

      final success = decrypted == testText;

      setState(() {
        _result = '''
${success ? '✅' : '❌'} 암호화/복호화 테스트 ${success ? '성공' : '실패'}

원본 텍스트:
$testText

암호화 결과 (Base64):
${encrypted.substring(0, 50)}...
(총 ${encrypted.length} 글자)

복호화 결과:
$decrypted

${success ? '✅ AES 키가 올바르게 설정되었습니다!' : '❌ AES 키 설정을 확인하세요.'}
''';
      });

      logger.i('[AppFit 테스트] 암호화/복호화 테스트: $success');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 암호화 테스트 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 암호화/복호화 테스트 실패

에러: $e

해결 방법:
1. .env 파일의 APPFIT_AES_KEY 확인
2. AES 키가 정확히 32바이트인지 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 매장 정보 조회 테스트
  Future<void> _testStoreInfo() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '매장 정보 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. API 호출
      final apiService = ref.read(apiServiceProvider);
      final store = await apiService.getStoreInfo(testShopCode);

      setState(() {
        _result = '''
✅ 매장 정보 조회 성공!

매장명: ${store.name}
매장코드: ${store.storeId}
영업상태: ${store.isOpen ? '영업 중 (OPEN)' : '영업 아님 (CLOSED/BREAK)'}

상세 응답 데이터는 로그를 확인하세요.
''';
      });

      logger.i('[AppFit 테스트] 매장 정보 조회 성공');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 매장 정보 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 매장 정보 조회 실패

에러: $e

해결 방법:
1. 토큰 발급이 먼저 성공했는지 확인
2. 해당 매장코드(${"TPCP00002"})가 존재하는지 확인
3. 서버 URL 및 네트워크 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 상품 목록 조회 테스트
  Future<void> _testProducts() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '상품 목록 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. API 호출
      final apiService = ref.read(apiServiceProvider);
      final products = await apiService.getShopCategories(testShopCode);

      setState(() {
        _result = '''
✅ 상품 목록 조회 성공!

총 상품 수: ${products.length}개

상품 목록 (상위 5개):
${products.take(5).map((p) => '- [${p.categoryName}] ${p.productName} (${p.menuPrice}원)').join('\n')}
${products.length > 5 ? '...외 ${products.length - 5}개 더 있음' : ''}

상세 데이터는 로그를 확인하세요.
''';
      });

      logger.i('[AppFit 테스트] 상품 목록 조회 성공: ${products.length}개');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 상품 목록 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 상품 목록 조회 실패

에러: $e

해결 방법:
1. 토큰 발급이 먼저 성공했는지 확인
2. 매장코드(${"TPCP00002"})에 카테고리와 상품이 등록되어 있는지 확인
3. 서버 URL 및 네트워크 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 주문 목록 조회 테스트
  Future<void> _testOrders() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '주문 목록 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. API 호출
      final apiService = ref.read(apiServiceProvider);
      // 오늘 날짜 구하기 (yyyy-MM-dd)
      final today = DateTime.now().toString().split(' ')[0];

      final orders = await apiService.getOrders(
        testShopCode,
        startDate: today,
        endDate: today,
      );

      setState(() {
        _result = '''
✅ 주문 목록 조회 성공!

기간: $today ~ $today
총 주문 수: ${orders.length}개

주문 목록 (상위 5개):
${orders.take(5).map((o) => '- [#${o.displayNum}] ${o.ordererName} (${o.totalAmount.toInt()}원) [${o.status.name}]').join('\n')}
${orders.length > 5 ? '...외 ${orders.length - 5}개 더 있음' : ''}

상세 데이터는 로그를 확인하세요.
''';
      });

      logger.i('[AppFit 테스트] 주문 목록 조회 성공: ${orders.length}개');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 주문 목록 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 주문 목록 조회 실패

에러: $e

해결 방법:
1. 토큰 발급 여부 확인
2. 매장코드(${"TPCP00002"}) 확인
3. 서버 URL 및 네트워크 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 주문 상세 조회 테스트
  Future<void> _testOrderDetail() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '주문 상세 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. 오늘 첫 번째 주문 조회
      final apiService = ref.read(apiServiceProvider);
      final today = DateTime.now().toString().split(' ')[0];
      final orders = await apiService.getOrders(testShopCode,
          startDate: today, endDate: today);

      if (orders.isEmpty) {
        setState(() {
          _result = '테스트 가능한 오늘의 주문이 없습니다.';
        });
        return;
      }

      // 3. 첫 번째 주문의 상세 정보 조회
      final firstOrderId = orders.first.orderNo;
      final detailOrder = await apiService.getOrder(firstOrderId);

      // 4. 결과 출력
      setState(() {
        final buffer = StringBuffer();
        buffer.writeln('✅ 주문 상세 조회 성공!');
        buffer.writeln('주문번호: ${detailOrder.displayNum}');
        buffer.writeln('주문금액: ${detailOrder.totalAmount.toInt()}원');
        buffer.writeln('주문메뉴:');
        for (var menu in detailOrder.menus) {
          buffer.writeln(
              '- ${menu.itemName} x ${menu.qty} (${menu.totalAmount.toInt()}원)');
          for (var opt in menu.options) {
            buffer.writeln(
                '  └ 옵션: ${opt.optionName} x ${opt.qty} (${opt.optionPrice.toInt()}원)');
          }
        }
        _result = buffer.toString();
      });

      logger.i('[AppFit 테스트] 주문 상세 조회 성공: ${detailOrder.displayNum}');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 주문 상세 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 주문 상세 조회 실패

에러: $e
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 쿠폰 유효성 검증 테스트
  Future<void> _testCouponValidation() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '쿠폰 유효성 검증 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. 상품 목록 조회 및 TKP0005 상품 찾기
      final apiService = ref.read(apiServiceProvider);
      final products = await apiService.getShopCategories(testShopCode);

      final targetProduct = products.firstWhere(
        (p) => p.productId == 'TKP0005',
        orElse: () => throw Exception('상품 목록에서 TKP0005 상품을 찾을 수 없습니다.'),
      );

      // 3. 테스트 데이터 구성
      const testCouponNo = '5001868426241491';
      final List<Map<String, dynamic>> testItems = [
        {
          'posId': targetProduct.productId,
          'price': targetProduct.menuPrice,
          'quantity': 1,
          'couponUseCount': 0,
        }
      ];

      // 4. API 호출
      final couponData = await apiService.validateCoupon(
        testCouponNo,
        testShopCode,
        items: testItems,
      );

      // 5. 결과 출력
      setState(() {
        _result = '''
✅ 쿠폰 검증 성공!

쿠폰명: ${couponData['couponTitle']}
할인대상: ${couponData['discountTarget']}
할인방식: ${couponData['discountMethod']}
할인금액: ${couponData['discountAmount']}원
대상아이템: ${couponData['targetItemId']}

상세 응답 데이터는 로그를 확인하세요.
''';
      });

      logger.i('[AppFit 테스트] 쿠폰 검증 성공: ${couponData['couponTitle']}');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 쿠폰 검증 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 쿠폰 검증 실패

에러: $e

해결 방법:
1. 쿠폰 번호(${"WELCOME2024"})가 유효한지 확인
2. 해당 매장에서 사용 가능한 쿠폰인지 확인
3. 서버 URL 및 네트워크 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 쿠폰 사용 테스트
  Future<void> _testCouponUse() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '쿠폰 사용 처리 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. 상품 목록 조회 및 TKP0005 상품 찾기
      final apiService = ref.read(apiServiceProvider);
      final products = await apiService.getShopCategories(testShopCode);

      final targetProduct = products.firstWhere(
        (p) => p.productId == 'TKP0005',
        orElse: () => throw Exception('상품 목록에서 TKP0005 상품을 찾을 수 없습니다.'),
      );

      // 2. 테스트 데이터 구성
      const testCouponNo = '5001868426241491';
      final List<Map<String, dynamic>> testItems = [
        {
          'posId': targetProduct.productId,
          'price': targetProduct.menuPrice,
          'quantity': 1,
          'couponUseCount': 0,
        }
      ];

      // 3. API 호출
      final couponData = await apiService.useCoupon(
        testCouponNo,
        testShopCode,
        items: testItems,
      );

      // 4. 결과 출력
      setState(() {
        _result = '''
✅ 쿠폰 사용 성공!

쿠폰명: ${couponData['couponTitle']}
할인금액: ${couponData['discountAmount']}원
상태: 사용됨

상세 응답 데이터는 로그를 확인하세요.
''';
      });

      logger.i('[AppFit 테스트] 쿠폰 사용 성공: ${couponData['couponTitle']}');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 쿠폰 사용 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 쿠폰 사용 실패

에러: $e

해결 방법:
1. 쿠폰 번호가 이미 사용되었거나 유효하지 않은지 확인
2. 해당 매장에서 사용 가능한 쿠폰인지 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 쿠폰 사용 취소 테스트
  Future<void> _testCouponUseCancel() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '쿠폰 사용 취소 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. 테스트 데이터 구성
      const testCouponNo = '5001868426241491';

      // 2. API 호출
      final apiService = ref.read(apiServiceProvider);
      await apiService.cancelCouponUse(testCouponNo, testShopCode);

      // 3. 결과 출력
      setState(() {
        _result = '''
✅ 쿠폰 사용 취소 성공!

쿠폰번호: $testCouponNo
상태: 취소 완료
''';
      });

      logger.i('[AppFit 테스트] 쿠폰 사용 취소 성공: $testCouponNo');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 쿠폰 사용 취소 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 쿠폰 사용 취소 실패

에러: $e

해결 방법:
1. 쿠폰 번호가 사용된 상태인지 확인
2. 이미 취소되었거나 유효하지 않은지 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 쿠폰 내역 조회 테스트
  Future<void> _testCouponHistory() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '쿠폰 내역 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';

      // 1. 테스트 데이터 구성
      const testUserSearchNo = '1621725316154595'; // 테스트용 번호

      // 2. API 호출
      final apiService = ref.read(apiServiceProvider);
      final history =
          await apiService.getCouponHistory(testShopCode, testUserSearchNo);

      final List<dynamic> content = history['content'] ?? [];

      // 3. 결과 출력
      setState(() {
        final buffer = StringBuffer();
        buffer.writeln('✅ 쿠폰 내역 조회 성공!');
        buffer.writeln('검색번호: $testUserSearchNo');
        buffer.writeln('조회 결과: ${content.length}건');
        buffer.writeln('');
        for (var item in content) {
          buffer.writeln('- [${item['status']}] ${item['title']}');
          buffer.writeln('  번호: ${item['couponNo']}');
          if (item['usedAt'] != null) {
            buffer.writeln('  사용일: ${item['usedAt']}');
          }
          buffer.writeln('');
        }
        _result = buffer.toString();
      });

      logger.i('[AppFit 테스트] 쿠폰 내역 조회 성공: ${content.length}건');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 쿠폰 내역 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 쿠폰 내역 조회 실패

에러: $e
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 회원 프로필 조회 테스트
  Future<void> _testUserProfile() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '회원 프로필 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';
      var testUserSearchNo =
          CryptoUtils.encryptAesGcm('01062947151', AppEnv.aesKey); // 테스트용 번호

      // 1. API 호출
      final apiService = ref.read(apiServiceProvider);
      final response =
          await apiService.getUserProfile(testShopCode, testUserSearchNo);

      final data = response['data'] as Map<String, dynamic>?;

      if (data == null) {
        setState(() {
          _result = '회원 정보를 찾을 수 없습니다.';
        });
        return;
      }

      // 2. 모델 매핑 및 결과 출력
      final membership = MembershipInfo.fromAppFitJson(data);

      setState(() {
        final buffer = StringBuffer();
        buffer.writeln('✅ 회원 프로필 조회 성공!');
        buffer.writeln('ID: ${membership.id}');
        buffer.writeln('바코드: ${membership.barcode}');
        buffer.writeln('닉네임: ${membership.userName}');
        buffer.writeln('전화번호: ${membership.phoneNumber}');
        buffer.writeln('포인트: ${membership.totalPoint}');
        buffer.writeln('쿠폰 수: ${membership.couponCount}');
        buffer.writeln('스탬프 수: ${membership.stampCount}');
        buffer.writeln('');
        buffer.writeln('최근 주문:');
        if (membership.recentOrders.isNotEmpty) {
          for (var order in membership.recentOrders) {
            final formattedDate =
                DateFormat('yyyy-MM-dd HH:mm').format(order.createdAt);
            buffer.writeln(
                '- ${order.orderName} [${order.orderStatus}] ($formattedDate)');
          }
        } else {
          buffer.writeln('최근 주문 내역이 없습니다.');
        }
        _result = buffer.toString();
      });

      logger.i('[AppFit 테스트] 회원 프로필 조회 성공: ${membership.userName}');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 회원 프로필 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 회원 프로필 조회 실패

에러: $e
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 일괄 주문 완료 테스트
  Future<void> _testBulkCompleteOrders() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '일괄 주문 완료 처리 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. API 호출
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.bulkCompleteOrders(
        testShopCode,
        from: today,
        to: today,
      );

      final data = response['data'] as Map<String, dynamic>;

      // 2. 결과 출력
      setState(() {
        _result = '''
✅ 일괄 주문 완료 성공!

대상 주문 수: ${data['targetOrderCount']}
성공 수: ${data['updateSuccessCount']}
실패 수: ${data['updateFailCount']}
''';
      });

      logger.i('[AppFit 테스트] 일괄 주문 완료 성공: $data');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 일괄 주문 완료 실패', error: e, stackTrace: s);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 스탬프 적립 테스트
  Future<void> _testStampSave() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '스탬프 적립 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';
      final testUserSearchNo = '1621725316154595';

      final apiService = ref.read(apiServiceProvider);
      final success = await apiService.earnStamp(
        testUserSearchNo,
        testShopCode,
        'TEST_ORDER_ID',
        3,
      );

      setState(() {
        _result = success ? '✅ 스탬프 적립 성공!' : '❌ 스탬프 적립 실패!';
      });

      logger.i('[AppFit 테스트] 스탬프 적립 테스트: $success');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 스탬프 적립 실패', error: e, stackTrace: s);
      setState(() {
        _result = '❌ 스탬프 적립 실패\n\n에러: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 스탬프 내역 조회 테스트
  Future<void> _testStampHistory() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '스탬프 내역 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';
      final testUserPhone = '01062947151';

      final apiService = ref.read(apiServiceProvider);
      final history =
          await apiService.getStampHistory(testUserPhone, testShopCode);
      final List<dynamic> stamps = history['content'] ?? [];

      setState(() {
        final buffer = StringBuffer();
        buffer.writeln('✅ 스탬프 내역 조회 성공!');
        buffer.writeln('조회 결과: ${stamps.length}건');
        buffer.writeln('');
        for (var item in stamps) {
          final stamp = StampInfo.fromAppFitJson(item as Map<String, dynamic>);
          buffer.writeln('- [${stamp.status}] ${stamp.stampCount}개');
          buffer.writeln(
              '  날짜: ${DateFormat('yyyy-MM-dd HH:mm').format(stamp.logDate)}');
          buffer.writeln('  ID: ${stamp.rewardId}, Seq: ${stamp.seq}');
          buffer.writeln('');
        }
        _result = buffer.toString();
      });

      logger.i('[AppFit 테스트] 스탬프 내역 조회 성공: ${stamps.length}건');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 스탬프 내역 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '❌ 스탬프 내역 조회 실패\n\n에러: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 스탬프 적립 취소 테스트
  Future<void> _testStampCancel() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '스탬프 적립 취소 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';
      final testUserPhone = '01062947151';

      final apiService = ref.read(apiServiceProvider);

      // 1. 먼저 내역조회해서 최근 적립건 찾기
      final history =
          await apiService.getStampHistory(testUserPhone, testShopCode);
      final List<dynamic> stamps = history['content'] ?? [];

      if (stamps.isEmpty) {
        setState(() {
          _result = '취소할 스탬프 내역이 없습니다.';
        });
        return;
      }

      final latestStamp =
          StampInfo.fromAppFitJson(stamps.first as Map<String, dynamic>);

      // 2. 취소 호출
      final success = await apiService.cancelStamp(latestStamp.rewardId);

      setState(() {
        _result = success
            ? '✅ 스탬프 적립 취소 성공!\n로그 ID: ${latestStamp.rewardId}'
            : '❌ 스탬프 적립 취소 실패!';
      });

      logger.i('[AppFit 테스트] 스탬프 적립 취소 테스트: $success');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 스탬프 적립 취소 실패', error: e, stackTrace: s);
      setState(() {
        _result = '❌ 스탬프 적립 취소 실패\n\n에러: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 라벨 프린터 출력 테스트
  Future<void> _testLabelPrint() async {
    setState(() {
      _isLoading = true;
      _result = '라벨 프린터 테스트 중...';
    });

    try {
      final printService = ref.read(printServiceProvider);

      // 테스트 데이터 (일본어 케이스)
      final dummyMenuName = 'アイスアメリカーノ';
      final dummyOptions = [
        'ショット追加 (+500)',
        'シロップ追加',
        '氷多め',
        'カップホルダー O',
        'デカフェ変更',
        'ホイップ多め'
      ];
      final dummyOrderNo = '1234';
      final dummyTime = DateFormat('MM/dd\nHH:mm:ss').format(DateTime.now());
      const dummyBeanType = 'Standard';
      const dummyTemp = 'Ice';
      const dummySize = 'Large';
      const dummyQrData = 'QR_TEST_1234'; // QR 데이터 테스트

      // 이미지 생성
      final imageBytes = await LabelPainter.generateLabelImage(
        menuName: dummyMenuName,
        options: dummyOptions,
        shopOrderNo: dummyOrderNo,
        orderTime: dummyTime,
        beanType: dummyBeanType,
        temperature: dummyTemp,
        sizeOption: dummySize,
        qrData: dummyQrData,
        orderIndex: 1,
        orderTotal: 3,
      );

      // 출력 요청
      await printService.printLabel(imageBytes);

      setState(() {
        _result = '''
✅ 라벨 프린터 테스트 완료!

[테스트 데이터]
메뉴: $dummyMenuName
정보: $dummyBeanType / $dummyTemp / $dummySize
주문번호: #$dummyOrderNo
옵션: ${dummyOptions.length}개
시간: $dummyTime

실제 출력물을 확인하세요.
''';
      });

      logger.i('[AppFit 테스트] 라벨 프린터 테스트 완료');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 라벨 프린터 테스트 실패', error: e, stackTrace: s);
      setState(() {
        _result = '❌ 라벨 프린터 테스트 실패\n\n에러: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 옵션 마이그레이션 조회 테스트
  Future<void> _testMigrationOptions() async {
    if (!AppFitConfig.isConfigured()) {
      _showError('환경 변수가 올바르게 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _result = '옵션 마이그레이션 정보 조회 중...';
    });

    try {
      final pref = ref.read(preferenceServiceProvider);
      final testShopCode = pref.getId() ?? 'TPCP00002';
      final apiService = ref.read(apiServiceProvider);

      final data = await apiService.getMigrationOptions(
        type: 'SHOP',
        shopCode: testShopCode,
      );

      setState(() {
        final buffer = StringBuffer();
        buffer.writeln('✅ 옵션 마이그레이션 조회 성공!');
        buffer.writeln('총 옵션 수: ${data.length}개');
        buffer.writeln('\n옵션 목록 (상위 10개):');

        for (var item in data.take(10)) {
          buffer.writeln(
              '- [${item['posCategoryId'] ?? 'N/A'}] ${item['name']} (${item['salePrice']?.toInt() ?? 0}원) [${item['status']}]');
        }
        if (data.length > 10) {
          buffer.writeln('...외 ${data.length - 10}개 더 있음');
        }

        buffer.writeln('\n상세 데이터는 로그를 확인하세요.');
        _result = buffer.toString();
      });

      logger.i('[AppFit 테스트] 옵션 마이그레이션 조회 성공: ${data.length}개');
    } catch (e, s) {
      logger.e('[AppFit 테스트] 옵션 마이그레이션 조회 실패', error: e, stackTrace: s);
      setState(() {
        _result = '''
❌ 옵션 마이그레이션 조회 실패

에러: $e

해결 방법:
1. 토큰 발급 여부 확인
2. 매장코드(${"TPCP00002"}) 확인
3. 서버 URL 및 네트워크 확인
''';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// 테스트 버튼 빌더
  Widget _buildTestButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color backgroundColor = Colors.blue,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AppFit API 테스트'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 결과 표시
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.psychology, color: Colors.blue),
                              const SizedBox(width: 8),
                              const Text(
                                '테스트 결과',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              if (_isLoading)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                            ],
                          ),
                          const Divider(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: SelectableText(
                              _result,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 테스트 버튼들 (컴팩트 그리드 레이아웃)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildTestButton(
                    icon: Icons.settings,
                    label: '환경 설정',
                    onPressed: _isLoading ? null : _checkConfig,
                    backgroundColor: Colors.blueGrey,
                  ),
                  _buildTestButton(
                    icon: Icons.lock_open,
                    label: '암호화',
                    onPressed: _isLoading ? null : _testEncryption,
                  ),
                  _buildTestButton(
                    icon: Icons.vpn_key,
                    label: 'API Key 검증',
                    onPressed: _isLoading ? null : _testApiKeyValidation,
                  ),
                  _buildTestButton(
                    icon: Icons.storefront,
                    label: '매장 정보',
                    onPressed: _isLoading ? null : _testStoreInfo,
                  ),
                  _buildTestButton(
                    icon: Icons.inventory,
                    label: '상품 목록',
                    onPressed: _isLoading ? null : _testProducts,
                  ),
                  _buildTestButton(
                    icon: Icons.list_alt,
                    label: '주문 목록',
                    onPressed: _isLoading ? null : _testOrders,
                  ),
                  _buildTestButton(
                    icon: Icons.receipt_long,
                    label: '주문 상세',
                    onPressed: _isLoading ? null : _testOrderDetail,
                  ),
                  _buildTestButton(
                    icon: Icons.swap_calls,
                    label: '옵션 마이그레이션',
                    onPressed: _isLoading ? null : _testMigrationOptions,
                    backgroundColor: Colors.indigo,
                  ),
                  _buildTestButton(
                    icon: Icons.confirmation_number,
                    label: '쿠폰 검증',
                    onPressed: _isLoading ? null : _testCouponValidation,
                  ),
                  _buildTestButton(
                    icon: Icons.check_circle,
                    label: '쿠폰 사용',
                    onPressed: _isLoading ? null : _testCouponUse,
                  ),
                  _buildTestButton(
                    icon: Icons.history,
                    label: '쿠폰 내역',
                    onPressed: _isLoading ? null : _testCouponHistory,
                  ),
                  _buildTestButton(
                    icon: Icons.playlist_add_check,
                    label: '일괄 완료',
                    onPressed: _isLoading ? null : _testBulkCompleteOrders,
                    backgroundColor: Colors.green,
                  ),
                  _buildTestButton(
                    icon: Icons.person_search,
                    label: '회원 프로필',
                    onPressed: _isLoading ? null : _testUserProfile,
                    backgroundColor: Colors.teal,
                  ),
                  _buildTestButton(
                    icon: Icons.cancel,
                    label: '쿠폰 취소',
                    onPressed: _isLoading ? null : _testCouponUseCancel,
                    backgroundColor: Colors.red[400]!,
                  ),
                  _buildTestButton(
                    icon: Icons.add_circle_outline,
                    label: '스탬프 적립',
                    onPressed: _isLoading ? null : _testStampSave,
                    backgroundColor: Colors.orange,
                  ),
                  _buildTestButton(
                    icon: Icons.history_edu,
                    label: '스탬프 내역',
                    onPressed: _isLoading ? null : _testStampHistory,
                    backgroundColor: Colors.orange,
                  ),
                  _buildTestButton(
                    icon: Icons.remove_circle_outline,
                    label: '스탬프 취소',
                    onPressed: _isLoading ? null : _testStampCancel,
                    backgroundColor: Colors.orange,
                  ),
                  _buildTestButton(
                    icon: Icons.print,
                    label: '라벨 출력',
                    onPressed: _isLoading ? null : _testLabelPrint,
                    backgroundColor: Colors.purple,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
