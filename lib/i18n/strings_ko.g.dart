///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsKo = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ko,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  );

	/// Metadata for the translations of <ko>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$app$ko app = Translations$app$ko.internal(_root);
	late final Translations$common$ko common = Translations$common$ko.internal(_root);
	late final Translations$login$ko login = Translations$login$ko.internal(_root);
	late final Translations$settings$ko settings = Translations$settings$ko.internal(_root);
	late final Translations$home$ko home = Translations$home$ko.internal(_root);
	late final Translations$app_bar$ko app_bar = Translations$app_bar$ko.internal(_root);
	late final Translations$order_status$ko order_status = Translations$order_status$ko.internal(_root);
	late final Translations$order_history$ko order_history = Translations$order_history$ko.internal(_root);
	late final Translations$product_mgmt$ko product_mgmt = Translations$product_mgmt$ko.internal(_root);
	late final Translations$order$ko order = Translations$order$ko.internal(_root);
	late final Translations$order_detail$ko order_detail = Translations$order_detail$ko.internal(_root);
	late final Translations$dialog$ko dialog = Translations$dialog$ko.internal(_root);
	late final Translations$drawer$ko drawer = Translations$drawer$ko.internal(_root);
	late final Translations$membership$ko membership = Translations$membership$ko.internal(_root);
	late final Translations$kds$ko kds = Translations$kds$ko.internal(_root);
	late final Translations$receipt$ko receipt = Translations$receipt$ko.internal(_root);
}

// Path: app
class Translations$app$ko {
	Translations$app$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '코코넛 주문 에이전트'
	String get name => '코코넛 주문 에이전트';
}

// Path: common
class Translations$common$ko {
	Translations$common$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '확인'
	String get confirm => '확인';

	/// ko: '취소'
	String get cancel => '취소';

	/// ko: '닫기'
	String get close => '닫기';

	/// ko: '새로고침'
	String get refresh => '새로고침';

	/// ko: '오류'
	String get error => '오류';

	/// ko: '작업 실패'
	String get error_title => '작업 실패';

	/// ko: '로딩 중...'
	String get loading => '로딩 중...';

	/// ko: '다음'
	String get next => '다음';

	/// ko: '다시 시도'
	String get retry => '다시 시도';

	/// ko: '예'
	String get yes => '예';

	/// ko: '아니요'
	String get no => '아니요';

	/// ko: '알 수 없음'
	String get unknown => '알 수 없음';

	/// ko: '나중에'
	String get later => '나중에';

	late final Translations$common$api_error$ko api_error = Translations$common$api_error$ko.internal(_root);
	late final Translations$common$sync$ko sync = Translations$common$sync$ko.internal(_root);
}

// Path: login
class Translations$login$ko {
	Translations$login$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '로그인'
	String get title => '로그인';

	/// ko: '아이디'
	String get id_label => '아이디';

	/// ko: '비밀번호'
	String get pw_label => '비밀번호';

	/// ko: '아이디를 입력해주세요'
	String get id_placeholder => '아이디를 입력해주세요';

	/// ko: '비밀번호를 입력해주세요'
	String get pw_placeholder => '비밀번호를 입력해주세요';

	/// ko: '로그인'
	String get button => '로그인';

	/// ko: '아이디 저장'
	String get save_id => '아이디 저장';

	/// ko: '자동 로그인'
	String get auto_login => '자동 로그인';

	/// ko: '로그인 실패'
	String get fail_title => '로그인 실패';

	/// ko: '로그인에 실패했습니다.'
	String get fail_msg => '로그인에 실패했습니다.';

	/// ko: '권한 요청 중 오류가 발생했습니다.'
	String get permission_error => '권한 요청 중 오류가 발생했습니다.';

	/// ko: '인터넷 연결 오류'
	String get internet_error_title => '인터넷 연결 오류';

	/// ko: '인터넷 연결을 확인해주세요.'
	String get internet_error_msg => '인터넷 연결을 확인해주세요.';

	/// ko: '자동 로그인 설정이 비활성화 상태입니다.'
	String get auto_login_disabled => '자동 로그인 설정이 비활성화 상태입니다.';

	/// ko: '저장된 매장 ID가 없어 자동 로그인을 건너뜜.'
	String get auto_login_no_id => '저장된 매장 ID가 없어 자동 로그인을 건너뜜.';

	/// ko: '자동 로그인 실패: 저장된 비밀번호가 없습니다. (최초 1회 수동 로그인 필요)'
	String get auto_login_fail_no_pw => '자동 로그인 실패: 저장된 비밀번호가 없습니다. (최초 1회 수동 로그인 필요)';

	late final Translations$login$tabs$ko tabs = Translations$login$tabs$ko.internal(_root);
	late final Translations$login$overlay_permission$ko overlay_permission = Translations$login$overlay_permission$ko.internal(_root);
}

// Path: settings
class Translations$settings$ko {
	Translations$settings$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '설정'
	String get title => '설정';

	/// ko: '저장'
	String get save => '저장';

	/// ko: '설정이 저장되었습니다.'
	String get save_success => '설정이 저장되었습니다.';

	/// ko: '설정 저장 중 오류가 발생했습니다: {error}'
	String save_error({required Object error}) => '설정 저장 중 오류가 발생했습니다: ${error}';

	/// ko: '모드 설정'
	String get section_mode => '모드 설정';

	/// ko: '일반 설정'
	String get section_general => '일반 설정';

	/// ko: '프린터 설정'
	String get section_printer => '프린터 설정';

	/// ko: '알림 설정'
	String get section_sound => '알림 설정';

	/// ko: '키오스크 설정'
	String get section_kiosk => '키오스크 설정';

	/// ko: '서버 설정'
	String get section_server => '서버 설정';

	/// ko: '출력 설정'
	String get section_print_count => '출력 설정';

	/// ko: '업데이트'
	String get section_update => '업데이트';

	late final Translations$settings$mode_switch$ko mode_switch = Translations$settings$mode_switch$ko.internal(_root);
	late final Translations$settings$auto_start$ko auto_start = Translations$settings$auto_start$ko.internal(_root);
	late final Translations$settings$auto_receipt$ko auto_receipt = Translations$settings$auto_receipt$ko.internal(_root);
	late final Translations$settings$print_order$ko print_order = Translations$settings$print_order$ko.internal(_root);
	late final Translations$settings$builtin_printer$ko builtin_printer = Translations$settings$builtin_printer$ko.internal(_root);
	late final Translations$settings$external_printer$ko external_printer = Translations$settings$external_printer$ko.internal(_root);
	late final Translations$settings$label_printer$ko label_printer = Translations$settings$label_printer$ko.internal(_root);
	late final Translations$settings$label_qr$ko label_qr = Translations$settings$label_qr$ko.internal(_root);
	late final Translations$settings$volume$ko volume = Translations$settings$volume$ko.internal(_root);
	late final Translations$settings$sound$ko sound = Translations$settings$sound$ko.internal(_root);
	late final Translations$settings$alert_count$ko alert_count = Translations$settings$alert_count$ko.internal(_root);
	late final Translations$settings$print_count$ko print_count = Translations$settings$print_count$ko.internal(_root);
	late final Translations$settings$language$ko language = Translations$settings$language$ko.internal(_root);
	late final Translations$settings$theme$ko theme = Translations$settings$theme$ko.internal(_root);
	late final Translations$settings$dual_monitor$ko dual_monitor = Translations$settings$dual_monitor$ko.internal(_root);
	late final Translations$settings$currency$ko currency = Translations$settings$currency$ko.internal(_root);
	late final Translations$settings$display_rotate$ko display_rotate = Translations$settings$display_rotate$ko.internal(_root);
	late final Translations$settings$order_type_badge$ko order_type_badge = Translations$settings$order_type_badge$ko.internal(_root);
	late final Translations$settings$order_source_color$ko order_source_color = Translations$settings$order_source_color$ko.internal(_root);
	late final Translations$settings$kds_ignore_status$ko kds_ignore_status = Translations$settings$kds_ignore_status$ko.internal(_root);
	late final Translations$settings$kds_accept_orders$ko kds_accept_orders = Translations$settings$kds_accept_orders$ko.internal(_root);
	late final Translations$settings$label_filter$ko label_filter = Translations$settings$label_filter$ko.internal(_root);
	late final Translations$settings$label_qr_payload$ko label_qr_payload = Translations$settings$label_qr_payload$ko.internal(_root);
	late final Translations$settings$developer_options$ko developer_options = Translations$settings$developer_options$ko.internal(_root);
	late final Translations$settings$kiosk$ko kiosk = Translations$settings$kiosk$ko.internal(_root);
	late final Translations$settings$local_server$ko local_server = Translations$settings$local_server$ko.internal(_root);
	late final Translations$settings$connection$ko connection = Translations$settings$connection$ko.internal(_root);
	late final Translations$settings$soundgraph$ko soundgraph = Translations$settings$soundgraph$ko.internal(_root);
	late final Translations$settings$app_update$ko app_update = Translations$settings$app_update$ko.internal(_root);
	late final Translations$settings$log_collection$ko log_collection = Translations$settings$log_collection$ko.internal(_root);
}

// Path: home
class Translations$home$ko {
	Translations$home$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$home$tabs$ko tabs = Translations$home$tabs$ko.internal(_root);

	/// ko: '정말 로그아웃 하시겠습니까?'
	String get logout_confirm => '정말 로그아웃 하시겠습니까?';

	/// ko: '최소화 기능 실행 중 오류가 발생했습니다.'
	String get minimize_error => '최소화 기능 실행 중 오류가 발생했습니다.';

	/// ko: '잘못된 탭 인덱스입니다.'
	String get invalid_tab => '잘못된 탭 인덱스입니다.';
}

// Path: app_bar
class Translations$app_bar$ko {
	Translations$app_bar$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '날짜 로딩 중...'
	String get time_loading => '날짜 로딩 중...';

	/// ko: '시간 로드 오류'
	String get time_error => '시간 로드 오류';

	/// ko: '오전'
	String get morning => '오전';

	/// ko: '오후'
	String get afternoon => '오후';

	/// ko: '(other) {신규 {n} 건}'
	String new_order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '신규 ${n} 건',
	);

	/// ko: '주방모니터(KDS)'
	String get kds_mode => '주방모니터(KDS)';

	/// ko: '오더'
	String get order_toggle => '오더';

	/// ko: '오더 시작 확인'
	String get order_start_confirm_title => '오더 시작 확인';

	/// ko: '오더 중지 확인'
	String get order_stop_confirm_title => '오더 중지 확인';

	/// ko: '오더 영업중으로 변경하시겠습니까?'
	String get order_start_confirm_content => '오더 영업중으로 변경하시겠습니까?';

	/// ko: '오더 준비중으로 변경하시겠습니까?'
	String get order_stop_confirm_content => '오더 준비중으로 변경하시겠습니까?';

	/// ko: '앱 종료'
	String get exit_app => '앱 종료';

	/// ko: '앱을 종료하시겠습니까?'
	String get exit_app_desc => '앱을 종료하시겠습니까?';

	/// ko: '앱을 종료하시겠습니까?'
	String get exit_app_kds_desc => '앱을 종료하시겠습니까?';

	/// ko: '매장이 '오더 준비중'으로 변경됩니다.'
	String get store_closed_notice => '매장이 \'오더 준비중\'으로 변경됩니다.';

	/// ko: '⚡️ 주문 폭주 시뮬레이션 시작 (10건)'
	String get burst_test_start => '⚡️ 주문 폭주 시뮬레이션 시작 (10건)';
}

// Path: order_status
class Translations$order_status$ko {
	Translations$order_status$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '신규주문'
	String get tab_new => '신규주문';

	/// ko: '주문접수'
	String get tab_preparing => '주문접수';

	/// ko: '상품준비 완료'
	String get tab_ready => '상품준비\n완료';

	/// ko: '완료'
	String get tab_done => '완료';

	/// ko: '(other) {{n} 건}'
	String order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '${n} 건',
	);

	/// ko: '픽업 준비 완료'
	String get batch_complete_confirm_title => '픽업 준비 완료';

	/// ko: '{n}건 일괄 완료처리 하시겠습니까?'
	String batch_complete_confirm_content({required Object n}) => '${n}건 일괄 완료처리 하시겠습니까?';

	/// ko: '일괄 완료 처리 결과'
	String get batch_result_title => '일괄 완료 처리 결과';

	/// ko: '처리 완료: {n}건 모두 성공적으로 처리되었습니다.'
	String batch_result_success({required Object n}) => '처리 완료: ${n}건 모두 성공적으로 처리되었습니다.';

	/// ko: '처리 완료: 성공 {success}건, 실패 {fail}건'
	String batch_result_partial({required Object success, required Object fail}) => '처리 완료: 성공 ${success}건, 실패 ${fail}건';

	/// ko: '처리 실패: {error}'
	String batch_result_fail({required Object error}) => '처리 실패: ${error}';

	/// ko: '오류 발생: 처리 중 예외가 발생했습니다.'
	String get batch_result_error => '오류 발생: 처리 중 예외가 발생했습니다.';

	/// ko: '맨 앞으로'
	String get scroll_to_start => '맨 앞으로';

	/// ko: '맨 뒤로'
	String get scroll_to_end => '맨 뒤로';
}

// Path: order_history
class Translations$order_history$ko {
	Translations$order_history$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문내역'
	String get title => '주문내역';

	/// ko: '오늘날짜조회'
	String get search_today => '오늘날짜조회';

	/// ko: '정렬'
	String get sort => '정렬';

	/// ko: '전체주문'
	String get filter_all => '전체주문';

	/// ko: '픽업완료'
	String get filter_completed => '픽업완료';

	/// ko: '주문취소'
	String get filter_cancelled => '주문취소';

	/// ko: '(other) {총 {n}건}'
	String total_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '총 ${n}건',
	);

	/// ko: '(other) {취소 {n}건}'
	String cancel_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '취소 ${n}건',
	);

	/// ko: '로딩중...'
	String get loading => '로딩중...';

	/// ko: '오늘 주문 내역이 없습니다.'
	String get no_data_today => '오늘 주문 내역이 없습니다.';

	/// ko: '오늘 완료된 주문이 없습니다.'
	String get no_completed_today => '오늘 완료된 주문이 없습니다.';

	/// ko: '오늘 취소된 주문이 없습니다.'
	String get no_cancelled_today => '오늘 취소된 주문이 없습니다.';

	/// ko: '해당 날짜에 주문 내역이 없습니다.'
	String get no_data_date => '해당 날짜에 주문 내역이 없습니다.';

	/// ko: '해당 날짜에 완료된 주문이 없습니다.'
	String get no_completed_date => '해당 날짜에 완료된 주문이 없습니다.';

	/// ko: '해당 날짜에 취소된 주문이 없습니다.'
	String get no_cancelled_date => '해당 날짜에 취소된 주문이 없습니다.';

	/// ko: '주문 내역 로딩 실패: {error}. 매장 정보가 로드되었는지 확인하세요.'
	String error_load({required Object error}) => '주문 내역 로딩 실패: ${error}.\n매장 정보가 로드되었는지 확인하세요.';
}

// Path: product_mgmt
class Translations$product_mgmt$ko {
	Translations$product_mgmt$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '상품관리'
	String get title => '상품관리';

	/// ko: '상품명 검색'
	String get search_placeholder => '상품명 검색';

	/// ko: '전체'
	String get all => '전체';

	/// ko: '품절'
	String get sold_out => '품절';

	/// ko: '{n}개'
	String count({required Object n}) => '${n}개';

	/// ko: '전체 {n}개'
	String total_count({required Object n}) => '전체 ${n}개';

	/// ko: '상품 목록을 불러오는 중 오류가 발생했습니다. {error}'
	String error_load({required Object error}) => '상품 목록을 불러오는 중 오류가 발생했습니다.\n${error}';

	/// ko: '미노출 처리'
	String get dialog_hidden_title => '미노출 처리';

	/// ko: '[ {name} ] 미노출(키삭제) 처리하시겠습니까?'
	String dialog_hidden_content({required Object name}) => '[ ${name} ] 미노출(키삭제) 처리하시겠습니까?';

	/// ko: '미노출(키삭제)'
	String get btn_hidden => '미노출(키삭제)';
}

// Path: order
class Translations$order$ko {
	Translations$order$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '신규'
	String get new_order => '신규';

	/// ko: '접수'
	String get preparing => '접수';

	/// ko: '픽업'
	String get ready => '픽업';

	/// ko: '취소'
	String get cancelled => '취소';

	/// ko: '완료'
	String get done => '완료';

	/// ko: '매장'
	String get type_dine_in => '매장';

	/// ko: '포장'
	String get type_takeout => '포장';

	/// ko: '복합'
	String get type_both => '복합';

	/// ko: '(other) {{n}개}'
	String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '${n}개',
	);

	/// ko: '(other) {총 {n}개}'
	String count_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '총 ${n}개',
	);

	/// ko: '상세 메뉴 정보가 없습니다.'
	String get menu_no_info => '상세 메뉴 정보가 없습니다.';

	/// ko: '{n}개'
	String qty({required Object n}) => '${n}개';

	/// ko: '메모'
	String get memo => '메모';

	/// ko: '주문금액'
	String get amount => '주문금액';

	/// ko: '할인금액'
	String get discount => '할인금액';

	/// ko: '결제금액'
	String get payment => '결제금액';

	/// ko: '{name} 님'
	String customer_honorific({required Object name}) => '${name} 님';

	/// ko: '{time} 주문'
	String ordered_time_short({required Object time}) => '${time} 주문';

	late final Translations$order$payment_method$ko payment_method = Translations$order$payment_method$ko.internal(_root);
	late final Translations$order$discount_type$ko discount_type = Translations$order$discount_type$ko.internal(_root);

	/// ko: '결제수단'
	String get payment_breakdown => '결제수단';

	/// ko: '(other) {{n}건}'
	String payment_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '${n}건',
	);
}

// Path: order_detail
class Translations$order_detail$ko {
	Translations$order_detail$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문 상세 정보를 불러오는 중...'
	String get loading => '주문 상세 정보를 불러오는 중...';

	/// ko: '오류 발생: {error}'
	String error_prefix({required Object error}) => '오류 발생: ${error}';

	/// ko: '주문 상태 변경에 실패했습니다.'
	String get status_update_fail => '주문 상태 변경에 실패했습니다.';

	/// ko: '주문 취소'
	String get dialog_kiosk_cancel_title => '주문 취소';

	/// ko: '키오스크 주문은 키오스크 기기에서 취소해주세요.'
	String get dialog_kiosk_cancel_content => '키오스크 주문은 키오스크 기기에서 취소해주세요.';

	/// ko: '{n}번 주문을 취소하시겠습니까?'
	String dialog_cancel_confirm_content({required Object n}) => '${n}번 주문을 취소하시겠습니까?';

	/// ko: '취소 사유 선택'
	String get dialog_cancel_reason_title => '취소 사유 선택';

	/// ko: '{n}번 주문의 취소 사유를 선택해주세요.'
	String dialog_cancel_reason_content({required Object n}) => '${n}번 주문의 취소 사유를 선택해주세요.';

	/// ko: '매장운영'
	String get cancel_reason_shop_request => '매장운영';

	/// ko: '영업종료'
	String get cancel_reason_shop_closed => '영업종료';

	/// ko: '고객 요청'
	String get cancel_reason_customer_request => '고객 요청';

	/// ko: '품절'
	String get cancel_reason_sold_out => '품절';

	/// ko: '재료 소진'
	String get cancel_reason_ingredient_shortage => '재료 소진';

	/// ko: '시스템 오류'
	String get cancel_reason_system_error => '시스템 오류';

	/// ko: '주문량 폭증'
	String get cancel_reason_order_surge => '주문량 폭증';

	/// ko: '픽업 재요청'
	String get dialog_repickup_confirm_title => '픽업 재요청';

	/// ko: '#{n}번 주문 픽업을 재요청하시겠습니까?'
	String dialog_repickup_confirm_content({required Object n}) => '#${n}번 주문 픽업을 재요청하시겠습니까?';

	/// ko: '미픽업 처리'
	String get dialog_not_picked_up_confirm_title => '미픽업 처리';

	/// ko: '#{n}번 주문을 미픽업 처리하시겠습니까?'
	String dialog_not_picked_up_confirm_content({required Object n}) => '#${n}번 주문을 미픽업 처리하시겠습니까?';

	/// ko: '#{n}번 주문을 완료 처리하시겠습니까?'
	String dialog_complete_confirm_content({required Object n}) => '#${n}번 주문을 완료 처리하시겠습니까?';

	/// ko: '영수증 출력에 실패했습니다: {error}'
	String print_receipt_fail({required Object error}) => '영수증 출력에 실패했습니다: ${error}';

	/// ko: '영수증 재출력'
	String get btn_receipt_reprint => '영수증 재출력';

	/// ko: '라벨 재출력'
	String get btn_label_reprint => '라벨 재출력';

	/// ko: '픽업 요청'
	String get btn_pickup_request => '픽업 요청';

	/// ko: '주문 접수'
	String get btn_order_accept => '주문 접수';

	/// ko: '주문 완료'
	String get btn_order_complete => '주문 완료';

	/// ko: '주문 취소'
	String get btn_order_cancel => '주문 취소';

	/// ko: '조리 시간 선택'
	String get time_select_title => '조리 시간 선택';

	/// ko: '주문 준비에 필요한 시간을 선택해주세요.'
	String get time_select_content => '주문 준비에 필요한 시간을 선택해주세요.';

	/// ko: '{n}분'
	String minutes({required Object n}) => '${n}분';
}

// Path: dialog
class Translations$dialog$ko {
	Translations$dialog$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$dialog$status_change$ko status_change = Translations$dialog$status_change$ko.internal(_root);
	late final Translations$dialog$exit$ko exit = Translations$dialog$exit$ko.internal(_root);
	late final Translations$dialog$update$ko update = Translations$dialog$update$ko.internal(_root);
}

// Path: drawer
class Translations$drawer$ko {
	Translations$drawer$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '상품관리'
	String get product_management => '상품관리';

	/// ko: '설정'
	String get settings => '설정';

	/// ko: '로그아웃'
	String get logout => '로그아웃';

	/// ko: '고객센터'
	String get customer_center => '고객센터';

	/// ko: '버전: {version} ({build})'
	String version({required Object version, required Object build}) => '버전: ${version} (${build})';

	/// ko: '버전: 로딩 중...'
	String get version_loading => '버전: 로딩 중...';

	/// ko: '버전: 오류'
	String get version_error => '버전: 오류';
}

// Path: membership
class Translations$membership$ko {
	Translations$membership$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '멤버십 조회'
	String get title => '멤버십 조회';

	late final Translations$membership$search$ko search = Translations$membership$search$ko.internal(_root);
	late final Translations$membership$customer$ko customer = Translations$membership$customer$ko.internal(_root);
	late final Translations$membership$tabs$ko tabs = Translations$membership$tabs$ko.internal(_root);
	late final Translations$membership$history$ko history = Translations$membership$history$ko.internal(_root);
	late final Translations$membership$dialog$ko dialog = Translations$membership$dialog$ko.internal(_root);
	late final Translations$membership$keypad$ko keypad = Translations$membership$keypad$ko.internal(_root);
}

// Path: kds
class Translations$kds$ko {
	Translations$kds$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$kds$tabs$ko tabs = Translations$kds$tabs$ko.internal(_root);

	/// ko: '일괄 완료'
	String get btn_batch_complete => '일괄 완료';

	/// ko: '주문 완료'
	String get btn_order_complete => '주문 완료';

	late final Translations$kds$sort$ko sort = Translations$kds$sort$ko.internal(_root);

	/// ko: '주문시간 {time}'
	String order_time({required Object time}) => '주문시간 ${time}';

	/// ko: '(other) {총 {n}개}'
	String total_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '총 ${n}개',
	);

	/// ko: '(other) {{n}개}'
	String item_qty({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '${n}개',
	);

	/// ko: '상세 정보 로딩중...'
	String get loading_detail => '상세 정보 로딩중...';

	/// ko: '메뉴 정보 없음'
	String get no_menu_info => '메뉴 정보 없음';

	/// ko: '주문 상세'
	String get btn_detail => '주문 상세';

	/// ko: '픽업 요청'
	String get btn_pickup_request => '픽업 요청';

	/// ko: '{n}번 주문 픽업 요청 하시겠습니까?'
	String msg_pickup_confirm({required Object n}) => '${n}번 주문 픽업 요청 하시겠습니까?';

	/// ko: '주문 정보를 불러오는 중...'
	String get loading_orders => '주문 정보를 불러오는 중...';

	/// ko: '완료할 픽업 주문이 없습니다.'
	String get msg_no_pickup_to_complete => '완료할 픽업 주문이 없습니다.';

	/// ko: '진행 중인 주문이 없습니다.'
	String get empty_progress => '진행 중인 주문이 없습니다.';

	/// ko: '픽업 대기 중인 주문이 없습니다.'
	String get empty_pickup => '픽업 대기 중인 주문이 없습니다.';

	/// ko: '완료된 주문이 없습니다.'
	String get empty_completed => '완료된 주문이 없습니다.';

	/// ko: '취소된 주문이 없습니다.'
	String get empty_cancelled => '취소된 주문이 없습니다.';
}

// Path: receipt
class Translations$receipt$ko {
	Translations$receipt$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '취소영수증'
	String get cancel_receipt => '취소영수증';

	/// ko: '취소주문서'
	String get cancel_order => '취소주문서';

	/// ko: '주문번호'
	String get order_no => '주문번호';

	/// ko: '일시'
	String get datetime => '일시';

	/// ko: '메뉴'
	String get col_menu => '메뉴';

	/// ko: '수량'
	String get col_qty => '수량';

	/// ko: '금액'
	String get col_amount => '금액';

	/// ko: '과세금액'
	String get taxable => '과세금액';

	/// ko: '부가세'
	String get vat => '부가세';

	/// ko: '주문금액'
	String get order_amount => '주문금액';

	/// ko: '할인금액'
	String get discount_amount => '할인금액';

	/// ko: '결제금액'
	String get payment_amount => '결제금액';

	/// ko: '키오스크'
	String get kiosk => '키오스크';

	/// ko: '님'
	String get customer_suffix => '님';

	/// ko: '옵션'
	String get section_option => '옵션';

	/// ko: '상세'
	String get section_detail => '상세';

	/// ko: '포트'
	String get test_port => '포트';

	/// ko: '보드'
	String get test_board => '보드';

	/// ko: '이 영수증이 보이면 정상'
	String get test_ok => '이 영수증이 보이면 정상';
}

// Path: common.api_error
class Translations$common$api_error$ko {
	Translations$common$api_error$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '네트워크 연결 상태를 확인해주세요.'
	String get network => '네트워크 연결 상태를 확인해주세요.';

	/// ko: '서버 응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.'
	String get timeout => '서버 응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.';

	/// ko: '인증이 만료되었습니다. 다시 로그인해주세요.'
	String get auth => '인증이 만료되었습니다. 다시 로그인해주세요.';

	/// ko: '요청한 정보를 찾을 수 없습니다.'
	String get not_found => '요청한 정보를 찾을 수 없습니다.';

	/// ko: '일시적인 서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.'
	String get server => '일시적인 서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';

	/// ko: '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.'
	String get generic => '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.';
}

// Path: common.sync
class Translations$common$sync$ko {
	Translations$common$sync$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '서버 응답 지연 — 주문 동기화가 지연되고 있습니다'
	String get degraded => '서버 응답 지연 — 주문 동기화가 지연되고 있습니다';

	/// ko: '마지막 갱신 {time}'
	String last_updated({required Object time}) => '마지막 갱신 ${time}';

	/// ko: '아직 갱신되지 않음'
	String get never_updated => '아직 갱신되지 않음';

	/// ko: '지금 재시도'
	String get retry_now => '지금 재시도';
}

// Path: login.tabs
class Translations$login$tabs$ko {
	Translations$login$tabs$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문접수'
	String get order => '주문접수';

	/// ko: '주방모니터'
	String get kitchen => '주방모니터';
}

// Path: login.overlay_permission
class Translations$login$overlay_permission$ko {
	Translations$login$overlay_permission$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '권한 필요'
	String get title => '권한 필요';

	/// ko: '최소화 기능을 사용하려면 "다른 앱 위에 표시" 권한이 필요합니다. 지금 설정하시겠습니까?'
	String get content => '최소화 기능을 사용하려면 "다른 앱 위에 표시" 권한이 필요합니다.\n지금 설정하시겠습니까?';

	/// ko: '설정하기'
	String get set => '설정하기';

	/// ko: '나중에'
	String get later => '나중에';
}

// Path: settings.mode_switch
class Translations$settings$mode_switch$ko {
	Translations$settings$mode_switch$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '메인 시스템으로 전환'
	String get to_main => '메인 시스템으로 전환';

	/// ko: '주방모니터(KDS)로 전환'
	String get to_kds => '주방모니터(KDS)로 전환';

	/// ko: '메인 시스템(일반 접수)으로 전환하시겠습니까?'
	String get confirm_to_main => '메인 시스템(일반 접수)으로 전환하시겠습니까?';

	/// ko: '주문 접수가 OFF되어 신규 주문을 직접 수신하지 않습니다. 주방모니터(KDS)모드에서 주문을 직접 받으려면 전환 후 '주문 접수'를 ON 하세요.'
	String get confirm_to_kds => '주문 접수가 OFF되어 신규 주문을 직접 수신하지 않습니다.\n주방모니터(KDS)모드에서 주문을 직접 받으려면 전환 후 \'주문 접수\'를 ON 하세요.';

	/// ko: '전환하기'
	String get btn_switch => '전환하기';

	/// ko: '일반 접수 화면으로 변경합니다.'
	String get desc_to_main => '일반 접수 화면으로 변경합니다.';

	/// ko: '주방모니터(KDS) 화면으로 변경합니다.'
	String get desc_to_kds => '주방모니터(KDS) 화면으로 변경합니다.';
}

// Path: settings.auto_start
class Translations$settings$auto_start$ko {
	Translations$settings$auto_start$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: 'PC시작 시 자동 실행'
	String get title => 'PC시작 시 자동 실행';

	/// ko: 'PC시작시 자동으로 에이전트를 실행합니다.'
	String get desc => 'PC시작시 자동으로 에이전트를 실행합니다.';

	/// ko: 'PC시작시 자동으로 에이전트를 실행합니다. 오더를 영업중으로 설정해야 주문접수가 가능합니다.'
	String get desc_general => 'PC시작시 자동으로 에이전트를 실행합니다.\n오더를 영업중으로 설정해야 주문접수가 가능합니다.';

	/// ko: 'ON'
	String get on => 'ON';

	/// ko: 'OFF'
	String get off => 'OFF';
}

// Path: settings.auto_receipt
class Translations$settings$auto_receipt$ko {
	Translations$settings$auto_receipt$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '픽업 오더 자동 접수'
	String get title => '픽업 오더 자동 접수';

	/// ko: '주문 수신 시 자동으로 접수됩니다.'
	String get desc => '주문 수신 시 자동으로 접수됩니다.';
}

// Path: settings.print_order
class Translations$settings$print_order$ko {
	Translations$settings$print_order$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문서 출력'
	String get title => '주문서 출력';

	/// ko: '주문서를 출력합니다. OFF시 주문서를 출력하지 않습니다.'
	String get desc => '주문서를 출력합니다. OFF시 주문서를 출력하지 않습니다.';
}

// Path: settings.builtin_printer
class Translations$settings$builtin_printer$ko {
	Translations$settings$builtin_printer$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '기기 내장 프린터 사용'
	String get title => '기기 내장 프린터 사용';

	/// ko: '기기에 내장된 프린터를 사용합니다.'
	String get desc => '기기에 내장된 프린터를 사용합니다.';

	/// ko: '이 기기에서 내장 프린터를 감지했습니다.'
	String get detected => '이 기기에서 내장 프린터를 감지했습니다.';

	/// ko: '이 기기에서 내장 프린터를 감지하지 못했습니다. (Sunmi 단말의 내장 모듈만 지원)'
	String get not_detected => '이 기기에서 내장 프린터를 감지하지 못했습니다. (Sunmi 단말의 내장 모듈만 지원)';
}

// Path: settings.external_printer
class Translations$settings$external_printer$ko {
	Translations$settings$external_printer$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '외부 프린터 사용'
	String get title => '외부 프린터 사용';

	/// ko: 'USB 연결된 외부 프린터를 사용합니다. 사용시 주문서는 내장/외부프린터 설정에 따라, 영수증은 외부프린터로만 출력됩니다.'
	String get desc => 'USB 연결된 외부 프린터를 사용합니다.\n사용시 주문서는 내장/외부프린터 설정에 따라, 영수증은 외부프린터로만 출력됩니다.';
}

// Path: settings.label_printer
class Translations$settings$label_printer$ko {
	Translations$settings$label_printer$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '라벨 프린터 사용'
	String get title => '라벨 프린터 사용';

	/// ko: 'USB 연결된 라벨 프린터를 사용합니다. (50mm x 70mm) 지원 모델: REXOD RXLA-561, BIXOLON XD5-40d'
	String get desc => 'USB 연결된 라벨 프린터를 사용합니다. (50mm x 70mm)\n지원 모델: REXOD RXLA-561, BIXOLON XD5-40d';
}

// Path: settings.label_qr
class Translations$settings$label_qr$ko {
	Translations$settings$label_qr$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: 'QR 코드 출력'
	String get title => 'QR 코드 출력';

	/// ko: '라벨에 주문 식별용 QR 코드를 함께 인쇄합니다.'
	String get desc => '라벨에 주문 식별용 QR 코드를 함께 인쇄합니다.';
}

// Path: settings.volume
class Translations$settings$volume$ko {
	Translations$settings$volume$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '알림음 크기설정'
	String get title => '알림음 크기설정';

	/// ko: '알림음의 크기를 조절합니다.'
	String get desc => '알림음의 크기를 조절합니다.';
}

// Path: settings.sound
class Translations$settings$sound$ko {
	Translations$settings$sound$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '알림음 설정'
	String get title => '알림음 설정';

	/// ko: '알림음을 선택합니다.'
	String get desc => '알림음을 선택합니다.';

	/// ko: '알림음 1'
	String get sound1 => '알림음 1';

	/// ko: '알림음 2'
	String get sound2 => '알림음 2';
}

// Path: settings.alert_count
class Translations$settings$alert_count$ko {
	Translations$settings$alert_count$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '알림횟수 설정'
	String get title => '알림횟수 설정';

	/// ko: '알림이 울리는 횟수를 설정합니다.'
	String get desc => '알림이 울리는 횟수를 설정합니다.';

	/// ko: '{n}회'
	String count({required Object n}) => '${n}회';

	/// ko: '무제한'
	String get unlimited => '무제한';
}

// Path: settings.print_count
class Translations$settings$print_count$ko {
	Translations$settings$print_count$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '출력 매수'
	String get title => '출력 매수';

	/// ko: '주문 접수 시 출력할 주문서 개수를 설정합니다.'
	String get desc => '주문 접수 시 출력할 주문서 개수를 설정합니다.';

	/// ko: '{n}매'
	String count({required Object n}) => '${n}매';
}

// Path: settings.language
class Translations$settings$language$ko {
	Translations$settings$language$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '언어 설정'
	String get title => '언어 설정';

	/// ko: '앱의 언어를 설정합니다.'
	String get desc => '앱의 언어를 설정합니다.';
}

// Path: settings.theme
class Translations$settings$theme$ko {
	Translations$settings$theme$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '테마'
	String get title => '테마';

	/// ko: '앱 전반의 브랜드 컬러와 로고를 변경합니다.'
	String get desc => '앱 전반의 브랜드 컬러와 로고를 변경합니다.';

	/// ko: '재시작 필요'
	String get restart_title => '재시작 필요';

	/// ko: '테마 변경을 적용하려면 앱을 다시 시작해야 합니다. 지금 재시작할까요?'
	String get restart_message => '테마 변경을 적용하려면 앱을 다시 시작해야 합니다. 지금 재시작할까요?';

	/// ko: '지금 재시작'
	String get restart_now => '지금 재시작';

	/// ko: '나중에'
	String get restart_later => '나중에';

	/// ko: '앱을 자동으로 재시작하지 못했습니다. 앱을 종료한 뒤 다시 실행해 주세요.'
	String get restart_failed => '앱을 자동으로 재시작하지 못했습니다. 앱을 종료한 뒤 다시 실행해 주세요.';

	late final Translations$settings$theme$options$ko options = Translations$settings$theme$options$ko.internal(_root);
}

// Path: settings.dual_monitor
class Translations$settings$dual_monitor$ko {
	Translations$settings$dual_monitor$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '전면 모니터 콘텐츠'
	String get title => '전면 모니터 콘텐츠';

	/// ko: '보조 디스플레이에 표시할 브랜드 콘텐츠를 선택합니다.'
	String get desc => '보조 디스플레이에 표시할 브랜드 콘텐츠를 선택합니다.';

	/// ko: '영상'
	String get option_video => '영상';

	/// ko: '이미지'
	String get option_image => '이미지';

	/// ko: '노출 안 함'
	String get option_none => '노출 안 함';
}

// Path: settings.currency
class Translations$settings$currency$ko {
	Translations$settings$currency$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '화폐단위 설정'
	String get title => '화폐단위 설정';

	/// ko: '금액 표시에 사용할 화폐단위를 선택합니다.'
	String get desc => '금액 표시에 사용할 화폐단위를 선택합니다.';

	/// ko: '원 (₩)'
	String get krw => '원 (₩)';

	/// ko: '엔 (¥)'
	String get jpy => '엔 (¥)';
}

// Path: settings.display_rotate
class Translations$settings$display_rotate$ko {
	Translations$settings$display_rotate$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '화면 상하 반전'
	String get title => '화면 상하 반전';

	/// ko: '화면을 180도 회전합니다. OS 회전 설정이 없는 환경에서 사용합니다.'
	String get desc => '화면을 180도 회전합니다. OS 회전 설정이 없는 환경에서 사용합니다.';
}

// Path: settings.order_type_badge
class Translations$settings$order_type_badge$ko {
	Translations$settings$order_type_badge$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '매장/포장 표시'
	String get title => '매장/포장 표시';

	/// ko: '주문 상세 헤더에 매장/포장 구분 배지를 표시합니다.'
	String get desc => '주문 상세 헤더에 매장/포장 구분 배지를 표시합니다.';
}

// Path: settings.order_source_color
class Translations$settings$order_source_color$ko {
	Translations$settings$order_source_color$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문 출처별 색상'
	String get title => '주문 출처별 색상';

	/// ko: '앱·키오스크·POS 주문을 카드 배경색으로 구분합니다.'
	String get desc => '앱·키오스크·POS 주문을 카드 배경색으로 구분합니다.';
}

// Path: settings.kds_ignore_status
class Translations$settings$kds_ignore_status$ko {
	Translations$settings$kds_ignore_status$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '타 기기 진행상태 알림 무시'
	String get title => '타 기기 진행상태 알림 무시';

	/// ko: '다른 주방모니터(KDS)에서 픽업 요청 등 진행상태를 변경해도 내 화면의 주문이 새로고침되지 않습니다. (진행상태 최신화를 수동으로 통제하고 싶을 때 사용)'
	String get desc => '다른 주방모니터(KDS)에서 픽업 요청 등 진행상태를 변경해도 내 화면의 주문이 새로고침되지 않습니다. (진행상태 최신화를 수동으로 통제하고 싶을 때 사용)';
}

// Path: settings.kds_accept_orders
class Translations$settings$kds_accept_orders$ko {
	Translations$settings$kds_accept_orders$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문 접수'
	String get title => '주문 접수';

	/// ko: '주방모니터(KDS)에서 주문을 직접 자동접수처리 합니다. 반드시 다른 메인주문 접수 프로그램과 중복 사용 되지 않도록 확인해주세요'
	String get desc => '주방모니터(KDS)에서 주문을 직접 자동접수처리 합니다. 반드시 다른 메인주문 접수 프로그램과 중복 사용 되지 않도록 확인해주세요';

	/// ko: '주문 접수 활성화'
	String get confirm_title => '주문 접수 활성화';

	/// ko: '주방모니터(KDS)에서 직접 주문 자동접수를 수행합니다. 반드시 다른 메인주문 접수 프로그램과 중복 사용 되지 않도록 확인해주세요. 활성화 하시겠습니까?'
	String get confirm_content => '주방모니터(KDS)에서 직접 주문 자동접수를 수행합니다.\n반드시 다른 메인주문 접수 프로그램과 중복 사용 되지 않도록 확인해주세요.\n활성화 하시겠습니까?';
}

// Path: settings.label_filter
class Translations$settings$label_filter$ko {
	Translations$settings$label_filter$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '라벨 출력 필터'
	String get title => '라벨 출력 필터';

	/// ko: '모든 주문 상품을 라벨 출력합니다.'
	String get desc_all => '모든 주문 상품을 라벨 출력합니다.';

	/// ko: '디저트(와플) 상품만 라벨 출력합니다.'
	String get desc_waffle_only => '디저트(와플) 상품만 라벨 출력합니다.';

	/// ko: '디저트(와플) 상품을 제외하고 라벨 출력합니다.'
	String get desc_waffle_exclude => '디저트(와플) 상품을 제외하고 라벨 출력합니다.';

	/// ko: '모든 주문 출력'
	String get btn_all => '모든 주문 출력';

	/// ko: '와플상품만 출력'
	String get btn_waffle_only => '와플상품만 출력';

	/// ko: '와플상품 제외'
	String get btn_waffle_exclude => '와플상품 제외';
}

// Path: settings.label_qr_payload
class Translations$settings$label_qr_payload$ko {
	Translations$settings$label_qr_payload$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '라벨 QR 포맷'
	String get title => '라벨 QR 포맷';

	/// ko: '기존 포맷으로 QR을 생성합니다. (주문번호-상품ID-컵순번)'
	String get desc_legacy => '기존 포맷으로 QR을 생성합니다. (주문번호-상품ID-컵순번)';

	/// ko: '신규(테스트) 포맷으로 QR을 생성합니다. (표시번호-컵순번)'
	String get desc_new => '신규(테스트) 포맷으로 QR을 생성합니다. (표시번호-컵순번)';

	/// ko: '기존'
	String get btn_legacy => '기존';

	/// ko: '신규'
	String get btn_new => '신규';
}

// Path: settings.developer_options
class Translations$settings$developer_options$ko {
	Translations$settings$developer_options$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '개발자 옵션'
	String get title => '개발자 옵션';

	late final Translations$settings$developer_options$appfit_test$ko appfit_test = Translations$settings$developer_options$appfit_test$ko.internal(_root);
}

// Path: settings.kiosk
class Translations$settings$kiosk$ko {
	Translations$settings$kiosk$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '키오스크 주문 노출'
	String get visible_title => '키오스크 주문 노출';

	/// ko: '키오스크 주문을 화면에 표시합니다.'
	String get visible_desc => '키오스크 주문을 화면에 표시합니다.';

	/// ko: '키오스크 주문 주문서 및 알림소리'
	String get sound_title => '키오스크 주문 주문서 및 알림소리';

	/// ko: '키오스크 주문 수신 시 주문서 출력과 알림음을 재생합니다.'
	String get sound_desc => '키오스크 주문 수신 시 주문서 출력과 알림음을 재생합니다.';

	/// ko: '키오스크 주문 자동 접수'
	String get auto_accept_title => '키오스크 주문 자동 접수';

	/// ko: '키오스크 주문은 '픽업 오더 자동 접수' 설정과 무관하게 항상 즉시 접수합니다.'
	String get auto_accept_desc => '키오스크 주문은 \'픽업 오더 자동 접수\' 설정과 무관하게 항상 즉시 접수합니다.';
}

// Path: settings.local_server
class Translations$settings$local_server$ko {
	Translations$settings$local_server$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '로컬 서버 활성화'
	String get title => '로컬 서버 활성화';

	/// ko: '키오스크에서 상품 상태를 조회할 수 있는 로컬 서버를 활성화합니다.'
	String get desc => '키오스크에서 상품 상태를 조회할 수 있는\n로컬 서버를 활성화합니다.';

	/// ko: '서버 정보'
	String get info => '서버 정보';

	/// ko: 'IP 주소: {ip}'
	String ip({required Object ip}) => 'IP 주소: ${ip}';

	/// ko: '포트: {port}'
	String port({required Object port}) => '포트: ${port}';

	/// ko: '로컬 서버가 시작되었습니다.'
	String get started => '로컬 서버가 시작되었습니다.';

	/// ko: '로컬 서버가 중지되었습니다.'
	String get stopped => '로컬 서버가 중지되었습니다.';

	/// ko: 'URL: {url}'
	String url({required Object url}) => 'URL: ${url}';
}

// Path: settings.connection
class Translations$settings$connection$ko {
	Translations$settings$connection$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '연결됨'
	String get connected => '연결됨';

	/// ko: '연결 안 됨'
	String get disconnected => '연결 안 됨';

	/// ko: '재연결'
	String get reconnect => '재연결';
}

// Path: settings.soundgraph
class Translations$settings$soundgraph$ko {
	Translations$settings$soundgraph$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '사운드그래프 주문전송'
	String get title => '사운드그래프 주문전송';

	/// ko: '주문 접수 시 SoundGraph 로 주문 정보를 전송합니다.'
	String get desc => '주문 접수 시 SoundGraph 로 주문 정보를 전송합니다.';

	/// ko: 'MARKET ID 입력'
	String get market_id_placeholder => 'MARKET ID 입력';

	/// ko: 'MARKET ID 입력'
	String get market_id_dialog_title => 'MARKET ID 입력';

	/// ko: '저장'
	String get market_id_dialog_save => '저장';

	/// ko: '취소'
	String get market_id_dialog_cancel => '취소';
}

// Path: settings.app_update
class Translations$settings$app_update$ko {
	Translations$settings$app_update$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '시작 시 앱 업데이트 확인'
	String get auto_check_title => '시작 시 앱 업데이트 확인';

	/// ko: '앱 시작 시 자동으로 최신 버전을 확인합니다.'
	String get auto_check_desc => '앱 시작 시 자동으로 최신 버전을 확인합니다.';

	/// ko: '앱 업데이트'
	String get manual_title => '앱 업데이트';

	/// ko: '현재 버전: v{currentVersion} / 최신 버전: v{latestVersion}'
	String version_info({required Object currentVersion, required Object latestVersion}) => '현재 버전: v${currentVersion} / 최신 버전: v${latestVersion}';

	/// ko: '최신 버전입니다.'
	String get up_to_date => '최신 버전입니다.';

	/// ko: '버전 확인 중...'
	String get checking => '버전 확인 중...';

	/// ko: '버전 확인 실패'
	String get check_failed => '버전 확인 실패';

	/// ko: '업데이트'
	String get update_btn => '업데이트';

	/// ko: '버전 확인'
	String get check_btn => '버전 확인';
}

// Path: settings.log_collection
class Translations$settings$log_collection$ko {
	Translations$settings$log_collection$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '로그 전송'
	String get section_title => '로그 전송';

	/// ko: '선택한 기간의 로그를 압축해 Slack으로 전송합니다.'
	String get section_desc => '선택한 기간의 로그를 압축해 Slack으로 전송합니다.';

	/// ko: '매장'
	String get store_label => '매장';

	/// ko: '브랜드'
	String get brand_label => '브랜드';

	/// ko: '매장명'
	String get store_name_label => '매장명';

	/// ko: '매장코드'
	String get store_code_label => '매장코드';

	/// ko: '기기'
	String get device_label => '기기';

	/// ko: '오늘'
	String get range_today => '오늘';

	/// ko: '최근 7일'
	String get range_7days => '최근 7일';

	/// ko: '최근 30일'
	String get range_30days => '최근 30일';

	/// ko: '로그 전송'
	String get send_btn => '로그 전송';

	/// ko: '로그 정리 중...'
	String get stage_flushing => '로그 정리 중...';

	/// ko: '로그 수집 중...'
	String get stage_collecting => '로그 수집 중...';

	/// ko: '압축 중...'
	String get stage_zipping => '압축 중...';

	/// ko: '업로드 중...'
	String get stage_uploading => '업로드 중...';

	/// ko: '전송 완료 ({count}개 파일, {size})'
	String success({required Object count, required Object size}) => '전송 완료 (${count}개 파일, ${size})';

	/// ko: '전송 실패: {error}'
	String failed({required Object error}) => '전송 실패: ${error}';

	/// ko: 'Slack 전송 설정이 없습니다. 빌드 설정을 확인하세요.'
	String get not_configured => 'Slack 전송 설정이 없습니다. 빌드 설정을 확인하세요.';
}

// Path: home.tabs
class Translations$home$tabs$ko {
	Translations$home$tabs$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문현황'
	String get order_status => '주문현황';

	/// ko: '주문내역'
	String get order_history => '주문내역';

	/// ko: '상품관리'
	String get product_management => '상품관리';

	/// ko: '멤버십'
	String get membership => '멤버십';
}

// Path: order.payment_method
class Translations$order$payment_method$ko {
	Translations$order$payment_method$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '신용카드'
	String get credit_card => '신용카드';

	/// ko: '선불카드'
	String get prepaid_card => '선불카드';

	/// ko: '네이버페이'
	String get naver_pay => '네이버페이';

	/// ko: '카카오페이'
	String get kakao_pay => '카카오페이';

	/// ko: '토스페이'
	String get toss_pay => '토스페이';

	/// ko: '애플페이'
	String get apple_pay => '애플페이';

	/// ko: '페이코'
	String get payco => '페이코';

	/// ko: '간편카드'
	String get easy_card => '간편카드';

	/// ko: '모바일 결제'
	String get mobile_payment => '모바일 결제';

	/// ko: 'QR 결제'
	String get qr_payment => 'QR 결제';

	/// ko: 'Felica 교통'
	String get felica_transportation => 'Felica 교통';

	/// ko: 'Felica iD'
	String get felica_id => 'Felica iD';

	/// ko: 'Felica QUICPay'
	String get felica_quicpay => 'Felica QUICPay';

	/// ko: '현금'
	String get cash => '현금';

	/// ko: '서비스'
	String get service => '서비스';

	/// ko: '무료'
	String get free => '무료';

	/// ko: '토스페이 다이렉트'
	String get toss_pay_direct => '토스페이 다이렉트';

	/// ko: 'KB페이'
	String get kb_pay => 'KB페이';

	/// ko: '하나페이'
	String get hana_pay => '하나페이';

	/// ko: '우리페이'
	String get woori_pay => '우리페이';

	/// ko: '선물하기'
	String get gift => '선물하기';

	/// ko: '앱카드'
	String get app_card => '앱카드';

	/// ko: '제로페이'
	String get zero_pay => '제로페이';

	/// ko: '당근페이'
	String get karrot_pay => '당근페이';

	/// ko: '계좌이체'
	String get bank_transfer => '계좌이체';

	/// ko: '지역화폐'
	String get local_currency => '지역화폐';

	/// ko: '간편결제'
	String get easy_payment => '간편결제';

	/// ko: '복합결제'
	String get multi => '복합결제';

	/// ko: '기타'
	String get other => '기타';
}

// Path: order.discount_type
class Translations$order$discount_type$ko {
	Translations$order$discount_type$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '쿠폰'
	String get coupon => '쿠폰';

	/// ko: '포인트'
	String get point => '포인트';

	/// ko: '기프트'
	String get gift => '기프트';

	/// ko: '제휴'
	String get partner => '제휴';

	/// ko: '멤버십'
	String get membership => '멤버십';

	/// ko: '임직원'
	String get employee => '임직원';

	/// ko: '선결제'
	String get pre_payment => '선결제';

	/// ko: '매장할인'
	String get shop => '매장할인';
}

// Path: dialog.status_change
class Translations$dialog$status_change$ko {
	Translations$dialog$status_change$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '상태 변경'
	String get title => '상태 변경';

	/// ko: '[ {item} ] 상태를 변경하시겠습니까?'
	String content({required Object item}) => '[ ${item} ] 상태를 변경하시겠습니까?';

	/// ko: '현재 상태: '
	String get current => '현재 상태: ';

	/// ko: '판매'
	String get sale => '판매';

	/// ko: '품절'
	String get sold_out => '품절';

	/// ko: '미노출'
	String get hidden => '미노출';

	/// ko: '미노출(키삭제)'
	String get hidden_delete => '미노출(키삭제)';
}

// Path: dialog.exit
class Translations$dialog$exit$ko {
	Translations$dialog$exit$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '앱 종료'
	String get title => '앱 종료';

	/// ko: '정말 종료하시겠습니까?'
	String get content => '정말 종료하시겠습니까?';

	/// ko: '종료'
	String get confirm => '종료';
}

// Path: dialog.update
class Translations$dialog$update$ko {
	Translations$dialog$update$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '앱 업데이트'
	String get title => '앱 업데이트';

	/// ko: '새로운 업데이트가 있습니다.'
	String get new_update => '새로운 업데이트가 있습니다.';

	/// ko: '업데이트를 다운로드하시겠습니까?'
	String get ask_download => '업데이트를 다운로드하시겠습니까?';

	/// ko: '업데이트 다운로드 중...'
	String get downloading => '업데이트 다운로드 중...';

	/// ko: '다운로드가 완료되었습니다!'
	String get download_complete => '다운로드가 완료되었습니다!';

	/// ko: '업데이트가 자동으로 설치됩니다.'
	String get installing => '업데이트가 자동으로 설치됩니다.';

	/// ko: '다운로드 실패'
	String get fail => '다운로드 실패';

	/// ko: '다운로드'
	String get download => '다운로드';
}

// Path: membership.search
class Translations$membership$search$ko {
	Translations$membership$search$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '전화번호 또는 쿠폰번호를 입력해주세요.'
	String get hint => '전화번호 또는 쿠폰번호를 입력해주세요.';

	/// ko: '스탬프 개수를 입력해주세요. (최대 20개까지)'
	String get hint_searched => '스탬프 개수를 입력해주세요. (최대 20개까지)';

	/// ko: '회원조회'
	String get btn_search => '회원조회';

	/// ko: '검색 초기화'
	String get btn_other_member => '검색 초기화';

	/// ko: '스탬프 적립'
	String get btn_save_stamp => '스탬프 적립';

	/// ko: '쿠폰사용'
	String get btn_use_coupon => '쿠폰사용';

	/// ko: '바코드 스캔'
	String get btn_scan => '바코드 스캔';
}

// Path: membership.customer
class Translations$membership$customer$ko {
	Translations$membership$customer$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '회원 정보가 없습니다.'
	String get status_none => '회원 정보가 없습니다.';

	/// ko: '{name}님'
	String honorific({required Object name}) => '${name}님';

	/// ko: '스탬프 {stamps} | 쿠폰 {coupons}'
	String summary({required Object stamps, required Object coupons}) => '스탬프 ${stamps} | 쿠폰 ${coupons}';
}

// Path: membership.tabs
class Translations$membership$tabs$ko {
	Translations$membership$tabs$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '스탬프내역'
	String get stamps => '스탬프내역';

	/// ko: '쿠폰내역'
	String get coupons => '쿠폰내역';

	/// ko: '보유쿠폰'
	String get available => '보유쿠폰';
}

// Path: membership.history
class Translations$membership$history$ko {
	Translations$membership$history$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '스탬프 내역이 없습니다.'
	String get no_stamps => '스탬프 내역이 없습니다.';

	/// ko: '쿠폰 내역이 없습니다.'
	String get no_coupons => '쿠폰 내역이 없습니다.';

	/// ko: '보유한 쿠폰이 없습니다.'
	String get no_available => '보유한 쿠폰이 없습니다.';

	/// ko: '적립일시'
	String get col_date => '적립일시';

	/// ko: '적립개수'
	String get col_count => '적립개수';

	/// ko: '비고'
	String get col_remark => '비고';

	/// ko: '쿠폰명'
	String get col_coupon => '쿠폰명';

	/// ko: '사용일'
	String get col_use_date => '사용일';

	/// ko: '유효기간'
	String get col_expiry => '유효기간';

	/// ko: '적립취소'
	String get btn_cancel_save => '적립취소';

	/// ko: '사용취소'
	String get btn_cancel_use => '사용취소';

	/// ko: '사용'
	String get btn_use => '사용';

	/// ko: '취소완료'
	String get status_cancelled => '취소완료';

	/// ko: '쿠폰변환완료'
	String get status_converted => '쿠폰변환완료';

	/// ko: '발급완료'
	String get status_issued => '발급완료';

	/// ko: '기간만료'
	String get status_expired => '기간만료';

	/// ko: '사용완료'
	String get status_used => '사용완료';

	/// ko: '적립'
	String get stamp_status_issued => '적립';

	/// ko: '취소'
	String get stamp_status_canceled => '취소';

	/// ko: '만료'
	String get stamp_status_expired => '만료';

	/// ko: '쿠폰 변환'
	String get stamp_status_used => '쿠폰 변환';

	/// ko: '이전 페이지'
	String get prev_page => '이전 페이지';

	/// ko: '다음 페이지'
	String get next_page => '다음 페이지';
}

// Path: membership.dialog
class Translations$membership$dialog$ko {
	Translations$membership$dialog$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '지원하지 않는 바코드 형식입니다.'
	String get invalid_barcode => '지원하지 않는 바코드 형식입니다.';

	/// ko: '전화번호를 입력해주세요.'
	String get enter_phone => '전화번호를 입력해주세요.';

	/// ko: '스탬프 적립 취소'
	String get cancel_stamp_title => '스탬프 적립 취소';

	/// ko: '{date} 에 적립된 {count}개의 스탬프 적립을 취소하시겠습니까?'
	String cancel_stamp_content({required Object date, required Object count}) => '${date} 에 적립된 ${count}개의 스탬프 적립을 취소하시겠습니까?';

	/// ko: '쿠폰 사용 취소'
	String get cancel_coupon_title => '쿠폰 사용 취소';

	/// ko: '[{title}] 쿠폰 사용을 취소하시겠습니까?'
	String cancel_coupon_content({required Object title}) => '[${title}] 쿠폰 사용을 취소하시겠습니까?';

	/// ko: '쿠폰 사용'
	String get use_coupon_title => '쿠폰 사용';

	/// ko: '{title} 쿠폰을 사용하시겠습니까?'
	String use_coupon_content({required Object title}) => '${title} 쿠폰을 사용하시겠습니까?';

	/// ko: '쿠폰 코드 [{code}]를 사용하시겠습니까?'
	String use_coupon_code_content({required Object code}) => '쿠폰 코드 [${code}]를 사용하시겠습니까?';

	/// ko: 'QR 바코드를 지원하지 않는 단말입니다.'
	String get scanner_not_supported => 'QR 바코드를 지원하지 않는 단말입니다.';

	/// ko: '쿠폰 코드를 입력해주세요.'
	String get enter_coupon_code => '쿠폰 코드를 입력해주세요.';

	/// ko: '매장 정보가 없습니다. 다시 로그인해주세요.'
	String get store_info_missing => '매장 정보가 없습니다. 다시 로그인해주세요.';

	/// ko: '입력 오류'
	String get input_error_title => '입력 오류';

	/// ko: '스탬프 개수는 1 이상의 숫자로 입력해주세요.'
	String get stamp_input_error => '스탬프 개수는 1 이상의 숫자로 입력해주세요.';

	/// ko: '스탬프 개수는 20개 이하로 입력해주세요.'
	String get stamp_limit_error => '스탬프 개수는 20개 이하로 입력해주세요.';

	/// ko: '처리 완료'
	String get processing_complete => '처리 완료';

	/// ko: '알림'
	String get notification => '알림';
}

// Path: membership.keypad
class Translations$membership$keypad$ko {
	Translations$membership$keypad$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '초기화'
	String get clear => '초기화';

	/// ko: 'Delete'
	String get delete => 'Delete';
}

// Path: kds.tabs
class Translations$kds$tabs$ko {
	Translations$kds$tabs$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '전체 {n}'
	String all({required Object n}) => '전체 ${n}';

	/// ko: '진행 {n}'
	String progress({required Object n}) => '진행 ${n}';

	/// ko: '픽업 {n}'
	String pickup({required Object n}) => '픽업 ${n}';

	/// ko: '완료 {n}'
	String completed({required Object n}) => '완료 ${n}';

	/// ko: '취소 {n}'
	String cancelled({required Object n}) => '취소 ${n}';
}

// Path: kds.sort
class Translations$kds$sort$ko {
	Translations$kds$sort$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '오래된 주문순'
	String get oldest => '오래된 주문순';

	/// ko: '최신 주문순'
	String get newest => '최신 주문순';
}

// Path: settings.theme.options
class Translations$settings$theme$options$ko {
	Translations$settings$theme$options$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '기본'
	String get appfit_default => '기본';

	/// ko: '매머드커피'
	String get mammoth_coffee => '매머드커피';

	/// ko: '마하테이스트'
	String get mata => '마하테이스트';

	/// ko: '빽다방재팬'
	String get paik => '빽다방재팬';

	/// ko: '더리터재팬'
	String get tljp => '더리터재팬';
}

// Path: settings.developer_options.appfit_test
class Translations$settings$developer_options$appfit_test$ko {
	Translations$settings$developer_options$appfit_test$ko.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: 'AppFit API 테스트'
	String get title => 'AppFit API 테스트';

	/// ko: 'Waldlust Platform AppFit API 설정 확인 및 테스트'
	String get desc => 'Waldlust Platform AppFit API 설정 확인 및 테스트';

	/// ko: '테스트'
	String get btn => '테스트';
}
