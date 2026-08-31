import 'package:appfit_order_agent/exceptions/api_exceptions.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 미가입 번호(서버 404 `NOT_FOUND_USER`)도 정상 회원과 같은 API 를 태우는
/// 동작을 고정한다.
///
/// 핵심은 "미가입은 실패가 아니다" 와 "미가입만 그렇고 통신 오류는 아니다"
/// 두 가지다. 후자가 무너지면 네트워크 장애 때 조회조차 안 된 번호에 스탬프를
/// 적립하게 된다.

class _FakeApiService implements ApiService {
  _FakeApiService();

  /// getUserProfile 이 던질 예외. null 이면 [profile] 을 정상 반환한다.
  Object? profileError;

  /// getUserProfile 정상 응답의 `data` 본문.
  Map<String, dynamic>? profile;

  /// 내역 조회 2종이 던질 예외. null 이면 빈 목록.
  Object? historyError;

  final List<String> profileRequests = [];
  final List<String> stampHistoryRequests = [];
  final List<String> couponHistoryRequests = [];

  /// earnStamp 호출 기록: (userSearchNo, storeId, stampCount)
  final List<({String userId, String storeId, int count})> earnCalls = [];

  @override
  Future<Map<String, dynamic>> getUserProfile(
      String storeId, String userSearchNo) async {
    profileRequests.add(userSearchNo);
    final err = profileError;
    if (err != null) throw err;
    return {'data': profile};
  }

  @override
  Future<List<StampInfo>> getStampHistory(
      String userSearchNo, String storeId) async {
    stampHistoryRequests.add(userSearchNo);
    final err = historyError;
    if (err != null) throw err;
    return <StampInfo>[];
  }

  @override
  Future<List<CouponHistoryInfo>> getCouponHistory(
      String storeId, String userSearchNo) async {
    couponHistoryRequests.add(userSearchNo);
    final err = historyError;
    if (err != null) throw err;
    return <CouponHistoryInfo>[];
  }

  @override
  Future<bool> earnStamp(
      String userId, String storeId, String orderId, int stampCount) async {
    earnCalls.add((userId: userId, storeId: storeId, count: stampCount));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStore extends Store {
  _FakeStore(this._initial);
  final StoreModel? _initial;

  @override
  Future<StoreModel?> build() async => _initial;
}

/// 가입 회원 프로필 응답 본문(`data`).
Map<String, dynamic> _memberProfile({String nickname = '홍길동'}) => {
      'id': 'uuid-1234',
      'barcode': 'BAR-0001',
      'nickname': nickname,
      'phoneNumber': '01012345678',
      'stampCount': 5,
      'couponCount': 2,
      'points': 100,
      'activeCoupons': <dynamic>[],
      'recentOrders': <dynamic>[],
    };

Future<({ProviderContainer container, _FakeApiService api})> _build() async {
  final api = _FakeApiService();
  final container = ProviderContainer(overrides: [
    apiServiceProvider.overrideWithValue(api),
    storeProvider.overrideWith(
      () => _FakeStore(
          StoreModel(storeId: 'TPCP00001', name: '테스트매장', isOpen: true)),
    ),
  ]);
  addTearDown(container.dispose);
  // Membership.build() 가 storeProvider 를 동기로 읽으므로 먼저 settle 시킨다.
  await container.read(storeProvider.future);
  return (container: container, api: api);
}

void main() {
  test('404 NOT_FOUND_USER 는 에러가 아니라 미가입 상태로 들어간다', () async {
    final b = await _build();
    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');

    final ok = await b.container.read(membershipProvider.notifier).search(
          '01099998888',
        );

    final s = b.container.read(membershipProvider);
    expect(ok, isTrue, reason: '조회 절차 자체는 정상 완료다');
    expect(s.isUnregistered, isTrue);
    expect(s.customerPhone, '01099998888', reason: '적립/쿠폰이 쓸 번호가 남아야 한다');
    expect(s.customerName, isEmpty);
    expect(s.errorMessage, isNull, reason: '에러 다이얼로그를 띄우지 않기로 했다');
    expect(s.hasSearchedMember, isTrue, reason: '조회 후 조작 화면으로 전환돼야 한다');
  });

  test('통신 오류는 미가입으로 오분류하지 않고 기존 에러 경로를 유지한다', () async {
    final b = await _build();
    b.api.profileError = ApiException('서버가 응답하지 않습니다.');

    final ok = await b.container
        .read(membershipProvider.notifier)
        .search('01099998888');

    final s = b.container.read(membershipProvider);
    expect(ok, isFalse);
    expect(s.isUnregistered, isFalse);
    expect(s.errorMessage, '서버가 응답하지 않습니다.');
    expect(s.customerPhone, isEmpty, reason: '조회 실패에 번호를 남기면 엉뚱한 적립이 된다');
    expect(s.hasSearchedMember, isFalse);
  });

  test('미가입 상태의 스탬프 적립은 조회에 쓴 번호로 나간다', () async {
    final b = await _build();
    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');
    await b.container.read(membershipProvider.notifier).search('01099998888');

    final ok =
        await b.container.read(membershipProvider.notifier).saveStamp('3');

    expect(ok, isTrue);
    expect(b.api.earnCalls, hasLength(1));
    expect(b.api.earnCalls.single.userId, '01099998888');
    expect(b.api.earnCalls.single.count, 3);
  });

  test('미가입이면 스탬프/쿠폰 내역 API 를 호출하지 않는다', () async {
    // 실기기 로그로 확인: 내역 2종도 프로필과 똑같이 404 NOT_FOUND_USER 를
    // 준다. 유저 단위 판정이라 성공할 수 없는 호출이므로, 태우면 조회 1건당
    // 왕복 2회와 404 2건이 그대로 낭비된다.
    final b = await _build();
    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');

    await b.container.read(membershipProvider.notifier).search('01099998888');

    expect(b.api.stampHistoryRequests, isEmpty);
    expect(b.api.couponHistoryRequests, isEmpty);

    final s = b.container.read(membershipProvider);
    expect(s.stampHistory, isEmpty);
    expect(s.couponHistory, isEmpty);
    expect(s.isLoadingRewardHistory, isFalse, reason: '스피너가 영구히 남으면 안 된다');
    expect(s.errorMessage, isNull);
  });

  test('정상 회원은 기존대로 내역 2종을 조회한다 (건너뛰기가 새지 않는다)', () async {
    final b = await _build();
    b.api.profile = _memberProfile();

    await b.container.read(membershipProvider.notifier).search('01012345678');

    expect(b.api.stampHistoryRequests, ['01012345678']);
    expect(b.api.couponHistoryRequests, ['01012345678']);
  });

  test('정상 회원 조회 뒤 다른 번호가 미가입이면 이전 회원 정보가 남지 않는다', () async {
    final b = await _build();

    // 1) 가입 회원 조회 성공
    b.api.profile = _memberProfile();
    await b.container.read(membershipProvider.notifier).search('01012345678');
    var s = b.container.read(membershipProvider);
    expect(s.customerName, '홍길동');
    expect(s.membershipInfo, isNotNull);
    expect(s.isUnregistered, isFalse);

    // 2) 다른 번호가 미가입
    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');
    await b.container.read(membershipProvider.notifier).search('01099998888');

    s = b.container.read(membershipProvider);
    expect(s.isUnregistered, isTrue);
    expect(s.membershipInfo, isNull, reason: '이전 회원의 보유쿠폰이 남으면 안 된다');
    expect(s.customerName, isEmpty);
    expect(s.stampCount, 0);
    expect(s.couponCount, 0);
    expect(s.customerPhone, '01099998888');
  });

  test('미가입 뒤 조회가 통신오류로 실패하면 미가입 판정이 되돌려진다', () async {
    // 되돌리지 않으면: 화면은 '미가입'+[스탬프 적립] 인 채로 customerPhone 만
    // 앞 번호로 남아, 점주가 개수를 넣는 순간 **앞 사람에게** 적립된다.
    // '미가입' 라벨은 번호가 달라도 글자가 같아 알아챌 단서가 없다.
    final b = await _build();
    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');
    await b.container.read(membershipProvider.notifier).search('01011112222');
    expect(b.container.read(membershipProvider).isUnregistered, isTrue);

    b.api.profileError = ApiException('서버가 응답하지 않습니다.');
    await b.container.read(membershipProvider.notifier).search('01033334444');

    final s = b.container.read(membershipProvider);
    expect(s.isUnregistered, isFalse);
    expect(s.hasSearchedMember, isFalse,
        reason: '조회 전 화면으로 돌아가 [스탬프 적립] 버튼이 사라져야 한다');
    expect(s.errorMessage, '서버가 응답하지 않습니다.');
  });

  test('빈 식별자로는 조회하지 않는다 (유령 미가입 방지)', () async {
    // cancelCoupon 은 userId.isEmpty 가드 없이 search('') 를 부른다. 서버가
    // 빈 값에도 404 NOT_FOUND_USER 를 주면 customerPhone='' 인 미가입 상태가
    // 만들어져 [스탬프 적립]이 눌리는 화면이 된다.
    final b = await _build();
    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');

    final ok = await b.container.read(membershipProvider.notifier).search('  ');

    expect(ok, isFalse);
    expect(b.api.profileRequests, isEmpty, reason: '요청 자체가 나가면 안 된다');
    expect(b.container.read(membershipProvider).isUnregistered, isFalse);
  });

  test('조회가 끝나면 어느 경로든 isLoading 이 내려간다 (스피너 고착 방지)', () async {
    // search() 진입부에서 isLoading:true 를 세우게 됐으므로, 세 종료 경로가
    // 모두 내려놓는지 고정한다. 하나라도 빠지면 우측 카드 스피너가 영구히 돌고
    // 버튼이 잠긴 채 화면이 멈춘다.
    final b = await _build();

    b.api.profile = _memberProfile();
    await b.container.read(membershipProvider.notifier).search('01012345678');
    expect(b.container.read(membershipProvider).isLoading, isFalse,
        reason: '정상 회원');

    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');
    await b.container.read(membershipProvider.notifier).search('01099998888');
    expect(b.container.read(membershipProvider).isLoading, isFalse,
        reason: '미가입');

    b.api.profileError = ApiException('서버가 응답하지 않습니다.');
    await b.container.read(membershipProvider.notifier).search('01099998888');
    expect(b.container.read(membershipProvider).isLoading, isFalse,
        reason: '통신 오류');
  });

  test('미가입 뒤 가입 회원을 조회하면 미가입 플래그가 풀린다', () async {
    final b = await _build();
    b.api.profileError = MemberNotFoundException('존재하지 않는 유저입니다.');
    await b.container.read(membershipProvider.notifier).search('01099998888');
    expect(b.container.read(membershipProvider).isUnregistered, isTrue);

    b.api.profileError = null;
    b.api.profile = _memberProfile();
    await b.container.read(membershipProvider.notifier).search('01012345678');

    final s = b.container.read(membershipProvider);
    expect(s.isUnregistered, isFalse);
    expect(s.customerName, '홍길동');
    expect(s.membershipInfo, isNotNull);
  });
}
