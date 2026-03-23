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
	late final TranslationsAppKo app = TranslationsAppKo.internal(_root);
	late final TranslationsCommonKo common = TranslationsCommonKo.internal(_root);
	late final TranslationsLoginKo login = TranslationsLoginKo.internal(_root);
	late final TranslationsSettingsKo settings = TranslationsSettingsKo.internal(_root);
	late final TranslationsHomeKo home = TranslationsHomeKo.internal(_root);
	late final TranslationsAppBarKo app_bar = TranslationsAppBarKo.internal(_root);
	late final TranslationsOrderStatusKo order_status = TranslationsOrderStatusKo.internal(_root);
	late final TranslationsOrderHistoryKo order_history = TranslationsOrderHistoryKo.internal(_root);
	late final TranslationsProductMgmtKo product_mgmt = TranslationsProductMgmtKo.internal(_root);
	late final TranslationsOrderKo order = TranslationsOrderKo.internal(_root);
	late final TranslationsOrderDetailKo order_detail = TranslationsOrderDetailKo.internal(_root);
	late final TranslationsDialogKo dialog = TranslationsDialogKo.internal(_root);
	late final TranslationsDrawerKo drawer = TranslationsDrawerKo.internal(_root);
	late final TranslationsMembershipKo membership = TranslationsMembershipKo.internal(_root);
	late final TranslationsKdsKo kds = TranslationsKdsKo.internal(_root);
}

// Path: app
class TranslationsAppKo {
	TranslationsAppKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '코코넛 주문 에이전트'
	String get name => '코코넛 주문 에이전트';
}

// Path: common
class TranslationsCommonKo {
	TranslationsCommonKo.internal(this._root);

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
}

// Path: login
class TranslationsLoginKo {
	TranslationsLoginKo.internal(this._root);

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

	late final TranslationsLoginTabsKo tabs = TranslationsLoginTabsKo.internal(_root);
	late final TranslationsLoginOverlayPermissionKo overlay_permission = TranslationsLoginOverlayPermissionKo.internal(_root);
}

// Path: settings
class TranslationsSettingsKo {
	TranslationsSettingsKo.internal(this._root);

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

	late final TranslationsSettingsModeSwitchKo mode_switch = TranslationsSettingsModeSwitchKo.internal(_root);
	late final TranslationsSettingsAutoStartKo auto_start = TranslationsSettingsAutoStartKo.internal(_root);
	late final TranslationsSettingsAutoReceiptKo auto_receipt = TranslationsSettingsAutoReceiptKo.internal(_root);
	late final TranslationsSettingsPrintOrderKo print_order = TranslationsSettingsPrintOrderKo.internal(_root);
	late final TranslationsSettingsBuiltinPrinterKo builtin_printer = TranslationsSettingsBuiltinPrinterKo.internal(_root);
	late final TranslationsSettingsExternalPrinterKo external_printer = TranslationsSettingsExternalPrinterKo.internal(_root);
	late final TranslationsSettingsLabelPrinterKo label_printer = TranslationsSettingsLabelPrinterKo.internal(_root);
	late final TranslationsSettingsVolumeKo volume = TranslationsSettingsVolumeKo.internal(_root);
	late final TranslationsSettingsSoundKo sound = TranslationsSettingsSoundKo.internal(_root);
	late final TranslationsSettingsAlertCountKo alert_count = TranslationsSettingsAlertCountKo.internal(_root);
	late final TranslationsSettingsPrintCountKo print_count = TranslationsSettingsPrintCountKo.internal(_root);
	late final TranslationsSettingsLanguageKo language = TranslationsSettingsLanguageKo.internal(_root);
	late final TranslationsSettingsDeveloperOptionsKo developer_options = TranslationsSettingsDeveloperOptionsKo.internal(_root);
	late final TranslationsSettingsLocalServerKo local_server = TranslationsSettingsLocalServerKo.internal(_root);
	late final TranslationsSettingsConnectionKo connection = TranslationsSettingsConnectionKo.internal(_root);
}

// Path: home
class TranslationsHomeKo {
	TranslationsHomeKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsHomeTabsKo tabs = TranslationsHomeTabsKo.internal(_root);

	/// ko: '정말 로그아웃 하시겠습니까?'
	String get logout_confirm => '정말 로그아웃 하시겠습니까?';

	/// ko: '최소화 기능 실행 중 오류가 발생했습니다.'
	String get minimize_error => '최소화 기능 실행 중 오류가 발생했습니다.';

	/// ko: '잘못된 탭 인덱스입니다.'
	String get invalid_tab => '잘못된 탭 인덱스입니다.';
}

// Path: app_bar
class TranslationsAppBarKo {
	TranslationsAppBarKo.internal(this._root);

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

	/// ko: '주방모니터'
	String get kds_mode => '주방모니터';

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

	/// ko: '앱을 종료하시겠습니까? 종료 시 자동으로 영업 상태가 OFF처리 됩니다.'
	String get exit_app_desc => '앱을 종료하시겠습니까? \n종료 시 자동으로 영업 상태가 OFF처리 됩니다.';

	/// ko: '앱을 종료하시겠습니까?'
	String get exit_app_kds_desc => '앱을 종료하시겠습니까?';

	/// ko: '⚡️ 주문 폭주 시뮬레이션 시작 (10건)'
	String get burst_test_start => '⚡️ 주문 폭주 시뮬레이션 시작 (10건)';
}

// Path: order_status
class TranslationsOrderStatusKo {
	TranslationsOrderStatusKo.internal(this._root);

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
}

// Path: order_history
class TranslationsOrderHistoryKo {
	TranslationsOrderHistoryKo.internal(this._root);

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
class TranslationsProductMgmtKo {
	TranslationsProductMgmtKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '상품관리'
	String get title => '상품관리';

	/// ko: '상품명 검색'
	String get search_placeholder => '상품명 검색';

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
class TranslationsOrderKo {
	TranslationsOrderKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '신규'
	String get new_order => '신규';

	/// ko: '접수'
	String get preparing => '접수';

	/// ko: '대기'
	String get ready => '대기';

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
}

// Path: order_detail
class TranslationsOrderDetailKo {
	TranslationsOrderDetailKo.internal(this._root);

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

	/// ko: '#{n}번 주문을 취소하시겠습니까?'
	String dialog_cancel_confirm_content({required Object n}) => '#${n}번 주문을 취소하시겠습니까?';

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
class TranslationsDialogKo {
	TranslationsDialogKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsDialogStatusChangeKo status_change = TranslationsDialogStatusChangeKo.internal(_root);
	late final TranslationsDialogExitKo exit = TranslationsDialogExitKo.internal(_root);
	late final TranslationsDialogUpdateKo update = TranslationsDialogUpdateKo.internal(_root);
}

// Path: drawer
class TranslationsDrawerKo {
	TranslationsDrawerKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

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
class TranslationsMembershipKo {
	TranslationsMembershipKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '멤버십 조회'
	String get title => '멤버십 조회';

	late final TranslationsMembershipSearchKo search = TranslationsMembershipSearchKo.internal(_root);
	late final TranslationsMembershipCustomerKo customer = TranslationsMembershipCustomerKo.internal(_root);
	late final TranslationsMembershipTabsKo tabs = TranslationsMembershipTabsKo.internal(_root);
	late final TranslationsMembershipHistoryKo history = TranslationsMembershipHistoryKo.internal(_root);
	late final TranslationsMembershipDialogKo dialog = TranslationsMembershipDialogKo.internal(_root);
	late final TranslationsMembershipKeypadKo keypad = TranslationsMembershipKeypadKo.internal(_root);
}

// Path: kds
class TranslationsKdsKo {
	TranslationsKdsKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final TranslationsKdsTabsKo tabs = TranslationsKdsTabsKo.internal(_root);

	/// ko: '일괄 완료'
	String get btn_batch_complete => '일괄 완료';

	/// ko: '주문 완료'
	String get btn_order_complete => '주문 완료';

	late final TranslationsKdsSortKo sort = TranslationsKdsSortKo.internal(_root);

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

// Path: login.tabs
class TranslationsLoginTabsKo {
	TranslationsLoginTabsKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문접수'
	String get order => '주문접수';

	/// ko: '주방모니터'
	String get kitchen => '주방모니터';
}

// Path: login.overlay_permission
class TranslationsLoginOverlayPermissionKo {
	TranslationsLoginOverlayPermissionKo.internal(this._root);

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
class TranslationsSettingsModeSwitchKo {
	TranslationsSettingsModeSwitchKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '메인 시스템으로 전환'
	String get to_main => '메인 시스템으로 전환';

	/// ko: 'KDS 모드로 전환'
	String get to_kds => 'KDS 모드로 전환';

	/// ko: '메인 시스템(일반 접수)으로 전환하시겠습니까?'
	String get confirm_to_main => '메인 시스템(일반 접수)으로 전환하시겠습니까?';

	/// ko: '주방모니터(KDS) 전용 시스템으로 전환하시겠습니까?'
	String get confirm_to_kds => '주방모니터(KDS) 전용 시스템으로 전환하시겠습니까?';

	/// ko: '전환하기'
	String get btn_switch => '전환하기';

	/// ko: '일반 접수 화면으로 변경합니다.'
	String get desc_to_main => '일반 접수 화면으로 변경합니다.';

	/// ko: '주방 전용 모니터로 변경합니다.'
	String get desc_to_kds => '주방 전용 모니터로 변경합니다.';
}

// Path: settings.auto_start
class TranslationsSettingsAutoStartKo {
	TranslationsSettingsAutoStartKo.internal(this._root);

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
class TranslationsSettingsAutoReceiptKo {
	TranslationsSettingsAutoReceiptKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '픽업 오더 자동 접수'
	String get title => '픽업 오더 자동 접수';

	/// ko: '주문 수신 시 자동으로 접수됩니다.'
	String get desc => '주문 수신 시 자동으로 접수됩니다.';
}

// Path: settings.print_order
class TranslationsSettingsPrintOrderKo {
	TranslationsSettingsPrintOrderKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '주문서 출력'
	String get title => '주문서 출력';

	/// ko: '주문서를 출력합니다.'
	String get desc => '주문서를 출력합니다.';
}

// Path: settings.builtin_printer
class TranslationsSettingsBuiltinPrinterKo {
	TranslationsSettingsBuiltinPrinterKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '기기 내장 프린터 사용'
	String get title => '기기 내장 프린터 사용';

	/// ko: '기기에 내장된 프린터를 사용합니다.'
	String get desc => '기기에 내장된 프린터를 사용합니다.';
}

// Path: settings.external_printer
class TranslationsSettingsExternalPrinterKo {
	TranslationsSettingsExternalPrinterKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '외부 프린터 사용'
	String get title => '외부 프린터 사용';

	/// ko: 'USB 연결된 외부 프린터를 사용합니다. 사용시 주문서는 내장/외부프린터 설정에 따라, 영수증은 외부프린터로만 출력됩니다.'
	String get desc => 'USB 연결된 외부 프린터를 사용합니다.\n사용시 주문서는 내장/외부프린터 설정에 따라, 영수증은 외부프린터로만 출력됩니다.';
}

// Path: settings.label_printer
class TranslationsSettingsLabelPrinterKo {
	TranslationsSettingsLabelPrinterKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '라벨 프린터 사용'
	String get title => '라벨 프린터 사용';

	/// ko: 'USB 연결된 라벨 프린터를 사용합니다. (50mm x 70mm)'
	String get desc => 'USB 연결된 라벨 프린터를 사용합니다. (50mm x 70mm)';
}

// Path: settings.volume
class TranslationsSettingsVolumeKo {
	TranslationsSettingsVolumeKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '알림음 크기설정'
	String get title => '알림음 크기설정';

	/// ko: '알림음의 크기를 조절합니다.'
	String get desc => '알림음의 크기를 조절합니다.';
}

// Path: settings.sound
class TranslationsSettingsSoundKo {
	TranslationsSettingsSoundKo.internal(this._root);

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
class TranslationsSettingsAlertCountKo {
	TranslationsSettingsAlertCountKo.internal(this._root);

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
class TranslationsSettingsPrintCountKo {
	TranslationsSettingsPrintCountKo.internal(this._root);

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
class TranslationsSettingsLanguageKo {
	TranslationsSettingsLanguageKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '언어 설정'
	String get title => '언어 설정';

	/// ko: '앱의 언어를 설정합니다.'
	String get desc => '앱의 언어를 설정합니다.';
}

// Path: settings.developer_options
class TranslationsSettingsDeveloperOptionsKo {
	TranslationsSettingsDeveloperOptionsKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '개발자 옵션'
	String get title => '개발자 옵션';

	late final TranslationsSettingsDeveloperOptionsAppfitTestKo appfit_test = TranslationsSettingsDeveloperOptionsAppfitTestKo.internal(_root);
}

// Path: settings.local_server
class TranslationsSettingsLocalServerKo {
	TranslationsSettingsLocalServerKo.internal(this._root);

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
class TranslationsSettingsConnectionKo {
	TranslationsSettingsConnectionKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '연결됨'
	String get connected => '연결됨';

	/// ko: '연결 안 됨'
	String get disconnected => '연결 안 됨';

	/// ko: '재연결'
	String get reconnect => '재연결';
}

// Path: home.tabs
class TranslationsHomeTabsKo {
	TranslationsHomeTabsKo.internal(this._root);

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

// Path: dialog.status_change
class TranslationsDialogStatusChangeKo {
	TranslationsDialogStatusChangeKo.internal(this._root);

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
class TranslationsDialogExitKo {
	TranslationsDialogExitKo.internal(this._root);

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
class TranslationsDialogUpdateKo {
	TranslationsDialogUpdateKo.internal(this._root);

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
class TranslationsMembershipSearchKo {
	TranslationsMembershipSearchKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '전화번호 또는 쿠폰번호를 입력해주세요.'
	String get hint => '전화번호 또는 쿠폰번호를 입력해주세요.';

	/// ko: '스탬프 개수를 입력해주세요. (최대 20개까지)'
	String get hint_searched => '스탬프 개수를 입력해주세요. (최대 20개까지)';

	/// ko: '회원조회'
	String get btn_search => '회원조회';

	/// ko: '다른 회원 조회'
	String get btn_other_member => '다른 회원 조회';

	/// ko: '스탬프 적립'
	String get btn_save_stamp => '스탬프 적립';

	/// ko: '쿠폰사용'
	String get btn_use_coupon => '쿠폰사용';

	/// ko: '쿠폰검증'
	String get btn_validate_coupon => '쿠폰검증';

	/// ko: '바코드 스캔'
	String get btn_scan => '바코드 스캔';
}

// Path: membership.customer
class TranslationsMembershipCustomerKo {
	TranslationsMembershipCustomerKo.internal(this._root);

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
class TranslationsMembershipTabsKo {
	TranslationsMembershipTabsKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '스탬프내역'
	String get stamps => '스탬프내역';

	/// ko: '쿠폰사용내역'
	String get coupons => '쿠폰사용내역';

	/// ko: '보유쿠폰'
	String get available => '보유쿠폰';
}

// Path: membership.history
class TranslationsMembershipHistoryKo {
	TranslationsMembershipHistoryKo.internal(this._root);

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

	/// ko: '이전 페이지'
	String get prev_page => '이전 페이지';

	/// ko: '다음 페이지'
	String get next_page => '다음 페이지';
}

// Path: membership.dialog
class TranslationsMembershipDialogKo {
	TranslationsMembershipDialogKo.internal(this._root);

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

	/// ko: '쿠폰 정보'
	String get coupon_info_title => '쿠폰 정보';

	/// ko: '쿠폰명: {name} 혜택: {benefit} 사용 가능합니다.'
	String coupon_info_content({required Object name, required Object benefit}) => '쿠폰명: ${name}\n혜택: ${benefit}\n사용 가능합니다.';

	/// ko: '처리 완료'
	String get processing_complete => '처리 완료';

	/// ko: '알림'
	String get notification => '알림';
}

// Path: membership.keypad
class TranslationsMembershipKeypadKo {
	TranslationsMembershipKeypadKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '초기화'
	String get clear => '초기화';

	/// ko: 'Delete'
	String get delete => 'Delete';
}

// Path: kds.tabs
class TranslationsKdsTabsKo {
	TranslationsKdsTabsKo.internal(this._root);

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
class TranslationsKdsSortKo {
	TranslationsKdsSortKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: '오래된 주문순'
	String get oldest => '오래된 주문순';

	/// ko: '최신 주문순'
	String get newest => '최신 주문순';
}

// Path: settings.developer_options.appfit_test
class TranslationsSettingsDeveloperOptionsAppfitTestKo {
	TranslationsSettingsDeveloperOptionsAppfitTestKo.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// ko: 'AppFit API 테스트'
	String get title => 'AppFit API 테스트';

	/// ko: 'Waldlust Platform AppFit API 설정 확인 및 테스트'
	String get desc => 'Waldlust Platform AppFit API 설정 확인 및 테스트';

	/// ko: '테스트'
	String get btn => '테스트';
}
