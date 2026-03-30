/// Generated file. Do not edit.
///
/// Original: lib/i18n
/// To regenerate, run: `dart run slang`
///
/// Locales: 3
/// Strings: 924 (308 per locale)
///
/// Built on 2026-03-30 at 00:13 UTC

// coverage:ignore-file
// ignore_for_file: type=lint

import 'package:flutter/widgets.dart';
import 'package:slang/builder/model/node.dart';
import 'package:slang_flutter/slang_flutter.dart';
export 'package:slang_flutter/slang_flutter.dart';

const AppLocale _baseLocale = AppLocale.ko;

/// Supported locales, see extension methods below.
///
/// Usage:
/// - LocaleSettings.setLocale(AppLocale.ko) // set locale
/// - Locale locale = AppLocale.ko.flutterLocale // get flutter locale from enum
/// - if (LocaleSettings.currentLocale == AppLocale.ko) // locale check
enum AppLocale with BaseAppLocale<AppLocale, Translations> {
	ko(languageCode: 'ko', build: Translations.build),
	en(languageCode: 'en', build: _StringsEn.build),
	ja(languageCode: 'ja', build: _StringsJa.build);

	const AppLocale({required this.languageCode, this.scriptCode, this.countryCode, required this.build}); // ignore: unused_element

	@override final String languageCode;
	@override final String? scriptCode;
	@override final String? countryCode;
	@override final TranslationBuilder<AppLocale, Translations> build;

	/// Gets current instance managed by [LocaleSettings].
	Translations get translations => LocaleSettings.instance.translationMap[this]!;
}

/// Method A: Simple
///
/// No rebuild after locale change.
/// Translation happens during initialization of the widget (call of t).
/// Configurable via 'translate_var'.
///
/// Usage:
/// String a = t.someKey.anotherKey;
Translations get t => LocaleSettings.instance.currentTranslations;

/// Method B: Advanced
///
/// All widgets using this method will trigger a rebuild when locale changes.
/// Use this if you have e.g. a settings page where the user can select the locale during runtime.
///
/// Step 1:
/// wrap your App with
/// TranslationProvider(
/// 	child: MyApp()
/// );
///
/// Step 2:
/// final t = Translations.of(context); // Get t variable.
/// String a = t.someKey.anotherKey; // Use t variable.
class TranslationProvider extends BaseTranslationProvider<AppLocale, Translations> {
	TranslationProvider({required super.child}) : super(settings: LocaleSettings.instance);

	static InheritedLocaleData<AppLocale, Translations> of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context);
}

/// Method B shorthand via [BuildContext] extension method.
/// Configurable via 'translate_var'.
///
/// Usage (e.g. in a widget's build method):
/// context.t.someKey.anotherKey
extension BuildContextTranslationsExtension on BuildContext {
	Translations get t => TranslationProvider.of(this).translations;
}

/// Manages all translation instances and the current locale
class LocaleSettings extends BaseFlutterLocaleSettings<AppLocale, Translations> {
	LocaleSettings._() : super(utils: AppLocaleUtils.instance);

	static final instance = LocaleSettings._();

	// static aliases (checkout base methods for documentation)
	static AppLocale get currentLocale => instance.currentLocale;
	static Stream<AppLocale> getLocaleStream() => instance.getLocaleStream();
	static AppLocale setLocale(AppLocale locale, {bool? listenToDeviceLocale = false}) => instance.setLocale(locale, listenToDeviceLocale: listenToDeviceLocale);
	static AppLocale setLocaleRaw(String rawLocale, {bool? listenToDeviceLocale = false}) => instance.setLocaleRaw(rawLocale, listenToDeviceLocale: listenToDeviceLocale);
	static AppLocale useDeviceLocale() => instance.useDeviceLocale();
	@Deprecated('Use [AppLocaleUtils.supportedLocales]') static List<Locale> get supportedLocales => instance.supportedLocales;
	@Deprecated('Use [AppLocaleUtils.supportedLocalesRaw]') static List<String> get supportedLocalesRaw => instance.supportedLocalesRaw;
	static void setPluralResolver({String? language, AppLocale? locale, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver}) => instance.setPluralResolver(
		language: language,
		locale: locale,
		cardinalResolver: cardinalResolver,
		ordinalResolver: ordinalResolver,
	);
}

/// Provides utility functions without any side effects.
class AppLocaleUtils extends BaseAppLocaleUtils<AppLocale, Translations> {
	AppLocaleUtils._() : super(baseLocale: _baseLocale, locales: AppLocale.values);

	static final instance = AppLocaleUtils._();

	// static aliases (checkout base methods for documentation)
	static AppLocale parse(String rawLocale) => instance.parse(rawLocale);
	static AppLocale parseLocaleParts({required String languageCode, String? scriptCode, String? countryCode}) => instance.parseLocaleParts(languageCode: languageCode, scriptCode: scriptCode, countryCode: countryCode);
	static AppLocale findDeviceLocale() => instance.findDeviceLocale();
	static List<Locale> get supportedLocales => instance.supportedLocales;
	static List<String> get supportedLocalesRaw => instance.supportedLocalesRaw;
}

// translations

// Path: <root>
class Translations implements BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations.build({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = TranslationMetadata(
		    locale: AppLocale.ko,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  );

	/// Metadata for the translations of <ko>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	late final Translations _root = this; // ignore: unused_field

	// Translations
	late final _StringsAppKo app = _StringsAppKo._(_root);
	late final _StringsCommonKo common = _StringsCommonKo._(_root);
	late final _StringsLoginKo login = _StringsLoginKo._(_root);
	late final _StringsSettingsKo settings = _StringsSettingsKo._(_root);
	late final _StringsHomeKo home = _StringsHomeKo._(_root);
	late final _StringsAppBarKo app_bar = _StringsAppBarKo._(_root);
	late final _StringsOrderStatusKo order_status = _StringsOrderStatusKo._(_root);
	late final _StringsOrderHistoryKo order_history = _StringsOrderHistoryKo._(_root);
	late final _StringsProductMgmtKo product_mgmt = _StringsProductMgmtKo._(_root);
	late final _StringsOrderKo order = _StringsOrderKo._(_root);
	late final _StringsOrderDetailKo order_detail = _StringsOrderDetailKo._(_root);
	late final _StringsDialogKo dialog = _StringsDialogKo._(_root);
	late final _StringsDrawerKo drawer = _StringsDrawerKo._(_root);
	late final _StringsMembershipKo membership = _StringsMembershipKo._(_root);
	late final _StringsKdsKo kds = _StringsKdsKo._(_root);
}

// Path: app
class _StringsAppKo {
	_StringsAppKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get name => '코코넛 주문 에이전트';
}

// Path: common
class _StringsCommonKo {
	_StringsCommonKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get confirm => '확인';
	String get cancel => '취소';
	String get close => '닫기';
	String get refresh => '새로고침';
	String get error => '오류';
	String get error_title => '작업 실패';
	String get loading => '로딩 중...';
	String get next => '다음';
	String get retry => '다시 시도';
	String get yes => '예';
	String get no => '아니요';
	String get unknown => '알 수 없음';
	String get later => '나중에';
}

// Path: login
class _StringsLoginKo {
	_StringsLoginKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '로그인';
	String get id_label => '아이디';
	String get pw_label => '비밀번호';
	String get id_placeholder => '아이디를 입력해주세요';
	String get pw_placeholder => '비밀번호를 입력해주세요';
	String get button => '로그인';
	String get save_id => '아이디 저장';
	String get auto_login => '자동 로그인';
	String get fail_title => '로그인 실패';
	String get fail_msg => '로그인에 실패했습니다.';
	String get permission_error => '권한 요청 중 오류가 발생했습니다.';
	String get internet_error_title => '인터넷 연결 오류';
	String get internet_error_msg => '인터넷 연결을 확인해주세요.';
	String get auto_login_disabled => '자동 로그인 설정이 비활성화 상태입니다.';
	String get auto_login_no_id => '저장된 매장 ID가 없어 자동 로그인을 건너뜜.';
	String get auto_login_fail_no_pw => '자동 로그인 실패: 저장된 비밀번호가 없습니다. (최초 1회 수동 로그인 필요)';
	late final _StringsLoginTabsKo tabs = _StringsLoginTabsKo._(_root);
	late final _StringsLoginOverlayPermissionKo overlay_permission = _StringsLoginOverlayPermissionKo._(_root);
}

// Path: settings
class _StringsSettingsKo {
	_StringsSettingsKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '설정';
	String get save => '저장';
	String get save_success => '설정이 저장되었습니다.';
	String save_error({required Object error}) => '설정 저장 중 오류가 발생했습니다: ${error}';
	late final _StringsSettingsModeSwitchKo mode_switch = _StringsSettingsModeSwitchKo._(_root);
	late final _StringsSettingsAutoStartKo auto_start = _StringsSettingsAutoStartKo._(_root);
	late final _StringsSettingsAutoReceiptKo auto_receipt = _StringsSettingsAutoReceiptKo._(_root);
	late final _StringsSettingsPrintOrderKo print_order = _StringsSettingsPrintOrderKo._(_root);
	late final _StringsSettingsBuiltinPrinterKo builtin_printer = _StringsSettingsBuiltinPrinterKo._(_root);
	late final _StringsSettingsExternalPrinterKo external_printer = _StringsSettingsExternalPrinterKo._(_root);
	late final _StringsSettingsLabelPrinterKo label_printer = _StringsSettingsLabelPrinterKo._(_root);
	late final _StringsSettingsVolumeKo volume = _StringsSettingsVolumeKo._(_root);
	late final _StringsSettingsSoundKo sound = _StringsSettingsSoundKo._(_root);
	late final _StringsSettingsAlertCountKo alert_count = _StringsSettingsAlertCountKo._(_root);
	late final _StringsSettingsPrintCountKo print_count = _StringsSettingsPrintCountKo._(_root);
	late final _StringsSettingsLanguageKo language = _StringsSettingsLanguageKo._(_root);
	late final _StringsSettingsCurrencyKo currency = _StringsSettingsCurrencyKo._(_root);
	late final _StringsSettingsDisplayRotateKo display_rotate = _StringsSettingsDisplayRotateKo._(_root);
	late final _StringsSettingsKdsIgnoreStatusKo kds_ignore_status = _StringsSettingsKdsIgnoreStatusKo._(_root);
	late final _StringsSettingsLabelFilterKo label_filter = _StringsSettingsLabelFilterKo._(_root);
	late final _StringsSettingsDeveloperOptionsKo developer_options = _StringsSettingsDeveloperOptionsKo._(_root);
	late final _StringsSettingsLocalServerKo local_server = _StringsSettingsLocalServerKo._(_root);
	late final _StringsSettingsConnectionKo connection = _StringsSettingsConnectionKo._(_root);
}

// Path: home
class _StringsHomeKo {
	_StringsHomeKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final _StringsHomeTabsKo tabs = _StringsHomeTabsKo._(_root);
	String get logout_confirm => '정말 로그아웃 하시겠습니까?';
	String get minimize_error => '최소화 기능 실행 중 오류가 발생했습니다.';
	String get invalid_tab => '잘못된 탭 인덱스입니다.';
}

// Path: app_bar
class _StringsAppBarKo {
	_StringsAppBarKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get time_loading => '날짜 로딩 중...';
	String get time_error => '시간 로드 오류';
	String get morning => '오전';
	String get afternoon => '오후';
	String new_order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '신규 ${n} 건',
	);
	String get kds_mode => '주방모니터';
	String get order_toggle => '오더';
	String get order_start_confirm_title => '오더 시작 확인';
	String get order_stop_confirm_title => '오더 중지 확인';
	String get order_start_confirm_content => '오더 영업중으로 변경하시겠습니까?';
	String get order_stop_confirm_content => '오더 준비중으로 변경하시겠습니까?';
	String get exit_app => '앱 종료';
	String get exit_app_desc => '앱을 종료하시겠습니까?';
	String get exit_app_kds_desc => '앱을 종료하시겠습니까?';
	String get burst_test_start => '⚡️ 주문 폭주 시뮬레이션 시작 (10건)';
}

// Path: order_status
class _StringsOrderStatusKo {
	_StringsOrderStatusKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get tab_new => '신규주문';
	String get tab_preparing => '주문접수';
	String get tab_ready => '상품준비\n완료';
	String get tab_done => '완료';
	String order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '${n} 건',
	);
	String get batch_complete_confirm_title => '픽업 준비 완료';
	String batch_complete_confirm_content({required Object n}) => '${n}건 일괄 완료처리 하시겠습니까?';
	String get batch_result_title => '일괄 완료 처리 결과';
	String batch_result_success({required Object n}) => '처리 완료: ${n}건 모두 성공적으로 처리되었습니다.';
	String batch_result_partial({required Object success, required Object fail}) => '처리 완료: 성공 ${success}건, 실패 ${fail}건';
	String batch_result_fail({required Object error}) => '처리 실패: ${error}';
	String get batch_result_error => '오류 발생: 처리 중 예외가 발생했습니다.';
	String get scroll_to_start => '맨 앞으로';
}

// Path: order_history
class _StringsOrderHistoryKo {
	_StringsOrderHistoryKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '주문내역';
	String get search_today => '오늘날짜조회';
	String get sort => '정렬';
	String get filter_all => '전체주문';
	String get filter_completed => '픽업완료';
	String get filter_cancelled => '주문취소';
	String total_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '총 ${n}건',
	);
	String cancel_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '취소 ${n}건',
	);
	String get loading => '로딩중...';
	String get no_data_today => '오늘 주문 내역이 없습니다.';
	String get no_completed_today => '오늘 완료된 주문이 없습니다.';
	String get no_cancelled_today => '오늘 취소된 주문이 없습니다.';
	String get no_data_date => '해당 날짜에 주문 내역이 없습니다.';
	String get no_completed_date => '해당 날짜에 완료된 주문이 없습니다.';
	String get no_cancelled_date => '해당 날짜에 취소된 주문이 없습니다.';
	String error_load({required Object error}) => '주문 내역 로딩 실패: ${error}.\n매장 정보가 로드되었는지 확인하세요.';
}

// Path: product_mgmt
class _StringsProductMgmtKo {
	_StringsProductMgmtKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '상품관리';
	String get search_placeholder => '상품명 검색';
	String get sold_out => '품절';
	String count({required Object n}) => '${n}개';
	String total_count({required Object n}) => '전체 ${n}개';
	String error_load({required Object error}) => '상품 목록을 불러오는 중 오류가 발생했습니다.\n${error}';
	String get dialog_hidden_title => '미노출 처리';
	String dialog_hidden_content({required Object name}) => '[ ${name} ] 미노출(키삭제) 처리하시겠습니까?';
	String get btn_hidden => '미노출(키삭제)';
}

// Path: order
class _StringsOrderKo {
	_StringsOrderKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get new_order => '신규';
	String get preparing => '접수';
	String get ready => '대기';
	String get cancelled => '취소';
	String get done => '완료';
	String get type_dine_in => '매장';
	String get type_takeout => '포장';
	String get type_both => '복합';
	String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '${n}개',
	);
	String count_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '총 ${n}개',
	);
	String get menu_no_info => '상세 메뉴 정보가 없습니다.';
	String qty({required Object n}) => '${n}개';
	String get memo => '메모';
	String get amount => '주문금액';
	String get discount => '할인금액';
	String get payment => '결제금액';
	String customer_honorific({required Object name}) => '${name} 님';
}

// Path: order_detail
class _StringsOrderDetailKo {
	_StringsOrderDetailKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get loading => '주문 상세 정보를 불러오는 중...';
	String error_prefix({required Object error}) => '오류 발생: ${error}';
	String get status_update_fail => '주문 상태 변경에 실패했습니다.';
	String get dialog_kiosk_cancel_title => '주문 취소';
	String get dialog_kiosk_cancel_content => '키오스크 주문은 키오스크 기기에서 취소해주세요.';
	String dialog_cancel_confirm_content({required Object n}) => '#${n}번 주문을 취소하시겠습니까?';
	String get dialog_repickup_confirm_title => '픽업 재요청';
	String dialog_repickup_confirm_content({required Object n}) => '#${n}번 주문 픽업을 재요청하시겠습니까?';
	String get dialog_not_picked_up_confirm_title => '미픽업 처리';
	String dialog_not_picked_up_confirm_content({required Object n}) => '#${n}번 주문을 미픽업 처리하시겠습니까?';
	String dialog_complete_confirm_content({required Object n}) => '#${n}번 주문을 완료 처리하시겠습니까?';
	String print_receipt_fail({required Object error}) => '영수증 출력에 실패했습니다: ${error}';
	String get btn_receipt_reprint => '영수증 재출력';
	String get btn_label_reprint => '라벨 재출력';
	String get btn_pickup_request => '픽업 요청';
	String get btn_order_accept => '주문 접수';
	String get btn_order_complete => '주문 완료';
	String get btn_order_cancel => '주문 취소';
	String get time_select_title => '조리 시간 선택';
	String get time_select_content => '주문 준비에 필요한 시간을 선택해주세요.';
	String minutes({required Object n}) => '${n}분';
}

// Path: dialog
class _StringsDialogKo {
	_StringsDialogKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final _StringsDialogStatusChangeKo status_change = _StringsDialogStatusChangeKo._(_root);
	late final _StringsDialogExitKo exit = _StringsDialogExitKo._(_root);
	late final _StringsDialogUpdateKo update = _StringsDialogUpdateKo._(_root);
}

// Path: drawer
class _StringsDrawerKo {
	_StringsDrawerKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get settings => '설정';
	String get logout => '로그아웃';
	String get customer_center => '고객센터';
	String version({required Object version, required Object build}) => '버전: ${version} (${build})';
	String get version_loading => '버전: 로딩 중...';
	String get version_error => '버전: 오류';
}

// Path: membership
class _StringsMembershipKo {
	_StringsMembershipKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '멤버십 조회';
	late final _StringsMembershipSearchKo search = _StringsMembershipSearchKo._(_root);
	late final _StringsMembershipCustomerKo customer = _StringsMembershipCustomerKo._(_root);
	late final _StringsMembershipTabsKo tabs = _StringsMembershipTabsKo._(_root);
	late final _StringsMembershipHistoryKo history = _StringsMembershipHistoryKo._(_root);
	late final _StringsMembershipDialogKo dialog = _StringsMembershipDialogKo._(_root);
	late final _StringsMembershipKeypadKo keypad = _StringsMembershipKeypadKo._(_root);
}

// Path: kds
class _StringsKdsKo {
	_StringsKdsKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final _StringsKdsTabsKo tabs = _StringsKdsTabsKo._(_root);
	String get btn_batch_complete => '일괄 완료';
	String get btn_order_complete => '주문 완료';
	late final _StringsKdsSortKo sort = _StringsKdsSortKo._(_root);
	String order_time({required Object time}) => '주문시간 ${time}';
	String total_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '총 ${n}개',
	);
	String item_qty({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(n,
		other: '${n}개',
	);
	String get loading_detail => '상세 정보 로딩중...';
	String get no_menu_info => '메뉴 정보 없음';
	String get btn_detail => '주문 상세';
	String get btn_pickup_request => '픽업 요청';
	String msg_pickup_confirm({required Object n}) => '${n}번 주문 픽업 요청 하시겠습니까?';
	String get loading_orders => '주문 정보를 불러오는 중...';
	String get msg_no_pickup_to_complete => '완료할 픽업 주문이 없습니다.';
	String get empty_progress => '진행 중인 주문이 없습니다.';
	String get empty_pickup => '픽업 대기 중인 주문이 없습니다.';
	String get empty_completed => '완료된 주문이 없습니다.';
	String get empty_cancelled => '취소된 주문이 없습니다.';
}

// Path: login.tabs
class _StringsLoginTabsKo {
	_StringsLoginTabsKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get order => '주문접수';
	String get kitchen => '주방모니터';
}

// Path: login.overlay_permission
class _StringsLoginOverlayPermissionKo {
	_StringsLoginOverlayPermissionKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '권한 필요';
	String get content => '최소화 기능을 사용하려면 "다른 앱 위에 표시" 권한이 필요합니다.\n지금 설정하시겠습니까?';
	String get set => '설정하기';
	String get later => '나중에';
}

// Path: settings.mode_switch
class _StringsSettingsModeSwitchKo {
	_StringsSettingsModeSwitchKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get to_main => '메인 시스템으로 전환';
	String get to_kds => 'KDS 모드로 전환';
	String get confirm_to_main => '메인 시스템(일반 접수)으로 전환하시겠습니까?';
	String get confirm_to_kds => '주방모니터(KDS) 전용 시스템으로 전환하시겠습니까?';
	String get btn_switch => '전환하기';
	String get desc_to_main => '일반 접수 화면으로 변경합니다.';
	String get desc_to_kds => '주방 전용 모니터로 변경합니다.';
}

// Path: settings.auto_start
class _StringsSettingsAutoStartKo {
	_StringsSettingsAutoStartKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => 'PC시작 시 자동 실행';
	String get desc => 'PC시작시 자동으로 에이전트를 실행합니다.';
	String get desc_general => 'PC시작시 자동으로 에이전트를 실행합니다.\n오더를 영업중으로 설정해야 주문접수가 가능합니다.';
	String get on => 'ON';
	String get off => 'OFF';
}

// Path: settings.auto_receipt
class _StringsSettingsAutoReceiptKo {
	_StringsSettingsAutoReceiptKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '픽업 오더 자동 접수';
	String get desc => '주문 수신 시 자동으로 접수됩니다.';
}

// Path: settings.print_order
class _StringsSettingsPrintOrderKo {
	_StringsSettingsPrintOrderKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '주문서 출력';
	String get desc => '주문서를 출력합니다.';
}

// Path: settings.builtin_printer
class _StringsSettingsBuiltinPrinterKo {
	_StringsSettingsBuiltinPrinterKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '기기 내장 프린터 사용';
	String get desc => '기기에 내장된 프린터를 사용합니다.';
}

// Path: settings.external_printer
class _StringsSettingsExternalPrinterKo {
	_StringsSettingsExternalPrinterKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '외부 프린터 사용';
	String get desc => 'USB 연결된 외부 프린터를 사용합니다.\n사용시 주문서는 내장/외부프린터 설정에 따라, 영수증은 외부프린터로만 출력됩니다.';
}

// Path: settings.label_printer
class _StringsSettingsLabelPrinterKo {
	_StringsSettingsLabelPrinterKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '라벨 프린터 사용';
	String get desc => 'USB 연결된 라벨 프린터를 사용합니다. (50mm x 70mm)';
}

// Path: settings.volume
class _StringsSettingsVolumeKo {
	_StringsSettingsVolumeKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '알림음 크기설정';
	String get desc => '알림음의 크기를 조절합니다.';
}

// Path: settings.sound
class _StringsSettingsSoundKo {
	_StringsSettingsSoundKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '알림음 설정';
	String get desc => '알림음을 선택합니다.';
	String get sound1 => '알림음 1';
	String get sound2 => '알림음 2';
}

// Path: settings.alert_count
class _StringsSettingsAlertCountKo {
	_StringsSettingsAlertCountKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '알림횟수 설정';
	String get desc => '알림이 울리는 횟수를 설정합니다.';
	String count({required Object n}) => '${n}회';
	String get unlimited => '무제한';
}

// Path: settings.print_count
class _StringsSettingsPrintCountKo {
	_StringsSettingsPrintCountKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '출력 매수';
	String get desc => '주문 접수 시 출력할 주문서 개수를 설정합니다.';
	String count({required Object n}) => '${n}매';
}

// Path: settings.language
class _StringsSettingsLanguageKo {
	_StringsSettingsLanguageKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '언어 설정';
	String get desc => '앱의 언어를 설정합니다.';
}

// Path: settings.currency
class _StringsSettingsCurrencyKo {
	_StringsSettingsCurrencyKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '화폐단위 설정';
	String get desc => '금액 표시에 사용할 화폐단위를 선택합니다.';
	String get krw => '원 (₩)';
	String get jpy => '엔 (¥)';
}

// Path: settings.display_rotate
class _StringsSettingsDisplayRotateKo {
	_StringsSettingsDisplayRotateKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '화면 상하 반전';
	String get desc => '화면을 180도 회전합니다. OS 회전 설정이 없는 환경에서 사용합니다.';
}

// Path: settings.kds_ignore_status
class _StringsSettingsKdsIgnoreStatusKo {
	_StringsSettingsKdsIgnoreStatusKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '타 기기 진행상태 알림 무시';
	String get desc => '다른 KDS에서 픽업 요청 등 진행상태를 변경해도 내 화면의 주문이 새로고침되지 않습니다. (진행상태 최신화를 수동으로 통제하고 싶을 때 사용)';
}

// Path: settings.label_filter
class _StringsSettingsLabelFilterKo {
	_StringsSettingsLabelFilterKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '라벨 출력 필터';
	String get desc_all => '모든 주문 상품을 라벨 출력합니다.';
	String get desc_waffle_only => '디저트(와플) 상품만 라벨 출력합니다.';
	String get desc_waffle_exclude => '디저트(와플) 상품을 제외하고 라벨 출력합니다.';
	String get btn_all => '모든 주문 출력';
	String get btn_waffle_only => '와플상품만 출력';
	String get btn_waffle_exclude => '와플상품 제외';
}

// Path: settings.developer_options
class _StringsSettingsDeveloperOptionsKo {
	_StringsSettingsDeveloperOptionsKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '개발자 옵션';
	late final _StringsSettingsDeveloperOptionsAppfitTestKo appfit_test = _StringsSettingsDeveloperOptionsAppfitTestKo._(_root);
}

// Path: settings.local_server
class _StringsSettingsLocalServerKo {
	_StringsSettingsLocalServerKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '로컬 서버 활성화';
	String get desc => '키오스크에서 상품 상태를 조회할 수 있는\n로컬 서버를 활성화합니다.';
	String get info => '서버 정보';
	String ip({required Object ip}) => 'IP 주소: ${ip}';
	String port({required Object port}) => '포트: ${port}';
	String get started => '로컬 서버가 시작되었습니다.';
	String get stopped => '로컬 서버가 중지되었습니다.';
	String url({required Object url}) => 'URL: ${url}';
}

// Path: settings.connection
class _StringsSettingsConnectionKo {
	_StringsSettingsConnectionKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get connected => '연결됨';
	String get disconnected => '연결 안 됨';
	String get reconnect => '재연결';
}

// Path: home.tabs
class _StringsHomeTabsKo {
	_StringsHomeTabsKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get order_status => '주문현황';
	String get order_history => '주문내역';
	String get product_management => '상품관리';
	String get membership => '멤버십';
}

// Path: dialog.status_change
class _StringsDialogStatusChangeKo {
	_StringsDialogStatusChangeKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '상태 변경';
	String content({required Object item}) => '[ ${item} ] 상태를 변경하시겠습니까?';
	String get current => '현재 상태: ';
	String get sale => '판매';
	String get sold_out => '품절';
	String get hidden => '미노출';
	String get hidden_delete => '미노출(키삭제)';
}

// Path: dialog.exit
class _StringsDialogExitKo {
	_StringsDialogExitKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '앱 종료';
	String get content => '정말 종료하시겠습니까?';
	String get confirm => '종료';
}

// Path: dialog.update
class _StringsDialogUpdateKo {
	_StringsDialogUpdateKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => '앱 업데이트';
	String get new_update => '새로운 업데이트가 있습니다.';
	String get ask_download => '업데이트를 다운로드하시겠습니까?';
	String get downloading => '업데이트 다운로드 중...';
	String get download_complete => '다운로드가 완료되었습니다!';
	String get installing => '업데이트가 자동으로 설치됩니다.';
	String get fail => '다운로드 실패';
	String get download => '다운로드';
}

// Path: membership.search
class _StringsMembershipSearchKo {
	_StringsMembershipSearchKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get hint => '전화번호 또는 쿠폰번호를 입력해주세요.';
	String get hint_searched => '스탬프 개수를 입력해주세요. (최대 20개까지)';
	String get btn_search => '회원조회';
	String get btn_other_member => '다른 회원 조회';
	String get btn_save_stamp => '스탬프 적립';
	String get btn_use_coupon => '쿠폰사용';
	String get btn_validate_coupon => '쿠폰검증';
	String get btn_scan => '바코드 스캔';
}

// Path: membership.customer
class _StringsMembershipCustomerKo {
	_StringsMembershipCustomerKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get status_none => '회원 정보가 없습니다.';
	String honorific({required Object name}) => '${name}님';
	String summary({required Object stamps, required Object coupons}) => '스탬프 ${stamps} | 쿠폰 ${coupons}';
}

// Path: membership.tabs
class _StringsMembershipTabsKo {
	_StringsMembershipTabsKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get stamps => '스탬프내역';
	String get coupons => '쿠폰사용내역';
	String get available => '보유쿠폰';
}

// Path: membership.history
class _StringsMembershipHistoryKo {
	_StringsMembershipHistoryKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get no_stamps => '스탬프 내역이 없습니다.';
	String get no_coupons => '쿠폰 내역이 없습니다.';
	String get no_available => '보유한 쿠폰이 없습니다.';
	String get col_date => '적립일시';
	String get col_count => '적립개수';
	String get col_remark => '비고';
	String get col_coupon => '쿠폰명';
	String get col_use_date => '사용일';
	String get col_expiry => '유효기간';
	String get btn_cancel_save => '적립취소';
	String get btn_cancel_use => '사용취소';
	String get btn_use => '사용';
	String get status_cancelled => '취소완료';
	String get status_converted => '쿠폰변환완료';
	String get status_issued => '발급완료';
	String get status_expired => '기간만료';
	String get prev_page => '이전 페이지';
	String get next_page => '다음 페이지';
}

// Path: membership.dialog
class _StringsMembershipDialogKo {
	_StringsMembershipDialogKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get invalid_barcode => '지원하지 않는 바코드 형식입니다.';
	String get enter_phone => '전화번호를 입력해주세요.';
	String get cancel_stamp_title => '스탬프 적립 취소';
	String cancel_stamp_content({required Object date, required Object count}) => '${date} 에 적립된 ${count}개의 스탬프 적립을 취소하시겠습니까?';
	String get cancel_coupon_title => '쿠폰 사용 취소';
	String cancel_coupon_content({required Object title}) => '[${title}] 쿠폰 사용을 취소하시겠습니까?';
	String get use_coupon_title => '쿠폰 사용';
	String use_coupon_content({required Object title}) => '${title} 쿠폰을 사용하시겠습니까?';
	String use_coupon_code_content({required Object code}) => '쿠폰 코드 [${code}]를 사용하시겠습니까?';
	String get scanner_not_supported => 'QR 바코드를 지원하지 않는 단말입니다.';
	String get enter_coupon_code => '쿠폰 코드를 입력해주세요.';
	String get store_info_missing => '매장 정보가 없습니다. 다시 로그인해주세요.';
	String get input_error_title => '입력 오류';
	String get stamp_input_error => '스탬프 개수는 1 이상의 숫자로 입력해주세요.';
	String get stamp_limit_error => '스탬프 개수는 20개 이하로 입력해주세요.';
	String get coupon_info_title => '쿠폰 정보';
	String coupon_info_content({required Object name, required Object benefit}) => '쿠폰명: ${name}\n혜택: ${benefit}\n사용 가능합니다.';
	String get processing_complete => '처리 완료';
	String get notification => '알림';
}

// Path: membership.keypad
class _StringsMembershipKeypadKo {
	_StringsMembershipKeypadKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get clear => '초기화';
	String get delete => 'Delete';
}

// Path: kds.tabs
class _StringsKdsTabsKo {
	_StringsKdsTabsKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String all({required Object n}) => '전체 ${n}';
	String progress({required Object n}) => '진행 ${n}';
	String pickup({required Object n}) => '픽업 ${n}';
	String completed({required Object n}) => '완료 ${n}';
	String cancelled({required Object n}) => '취소 ${n}';
}

// Path: kds.sort
class _StringsKdsSortKo {
	_StringsKdsSortKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get oldest => '오래된 주문순';
	String get newest => '최신 주문순';
}

// Path: settings.developer_options.appfit_test
class _StringsSettingsDeveloperOptionsAppfitTestKo {
	_StringsSettingsDeveloperOptionsAppfitTestKo._(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	String get title => 'AppFit API 테스트';
	String get desc => 'Waldlust Platform AppFit API 설정 확인 및 테스트';
	String get btn => '테스트';
}

// Path: <root>
class _StringsEn extends Translations {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	_StringsEn.build({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super.build(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	@override late final _StringsEn _root = this; // ignore: unused_field

	// Translations
	@override late final _StringsAppEn app = _StringsAppEn._(_root);
	@override late final _StringsCommonEn common = _StringsCommonEn._(_root);
	@override late final _StringsLoginEn login = _StringsLoginEn._(_root);
	@override late final _StringsSettingsEn settings = _StringsSettingsEn._(_root);
	@override late final _StringsHomeEn home = _StringsHomeEn._(_root);
	@override late final _StringsAppBarEn app_bar = _StringsAppBarEn._(_root);
	@override late final _StringsOrderStatusEn order_status = _StringsOrderStatusEn._(_root);
	@override late final _StringsOrderHistoryEn order_history = _StringsOrderHistoryEn._(_root);
	@override late final _StringsProductMgmtEn product_mgmt = _StringsProductMgmtEn._(_root);
	@override late final _StringsOrderEn order = _StringsOrderEn._(_root);
	@override late final _StringsOrderDetailEn order_detail = _StringsOrderDetailEn._(_root);
	@override late final _StringsDialogEn dialog = _StringsDialogEn._(_root);
	@override late final _StringsDrawerEn drawer = _StringsDrawerEn._(_root);
	@override late final _StringsMembershipEn membership = _StringsMembershipEn._(_root);
	@override late final _StringsKdsEn kds = _StringsKdsEn._(_root);
}

// Path: app
class _StringsAppEn extends _StringsAppKo {
	_StringsAppEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get name => 'Kokonut Order Agent';
}

// Path: common
class _StringsCommonEn extends _StringsCommonKo {
	_StringsCommonEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get confirm => 'Confirm';
	@override String get cancel => 'Cancel';
	@override String get close => 'Close';
	@override String get refresh => 'Refresh';
	@override String get error => 'Error';
	@override String get error_title => 'Operation Failed';
	@override String get loading => 'Loading...';
	@override String get next => 'Next';
	@override String get retry => 'Retry';
	@override String get yes => 'Yes';
	@override String get no => 'No';
	@override String get unknown => 'Unknown';
	@override String get later => 'Later';
}

// Path: login
class _StringsLoginEn extends _StringsLoginKo {
	_StringsLoginEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Login';
	@override String get id_label => 'ID';
	@override String get pw_label => 'Password';
	@override String get id_placeholder => 'Please enter your ID';
	@override String get pw_placeholder => 'Please enter your password';
	@override String get button => 'Login';
	@override String get save_id => 'Save ID';
	@override String get auto_login => 'Auto Login';
	@override String get fail_title => 'Login Failed';
	@override String get fail_msg => 'Failed to login.';
	@override String get permission_error => 'Error occurred while requesting permissions.';
	@override String get internet_error_title => 'Connection Error';
	@override String get internet_error_msg => 'Please check your internet connection.';
	@override String get auto_login_disabled => 'Auto login is disabled.';
	@override String get auto_login_no_id => 'No saved Store ID, skipping auto login.';
	@override String get auto_login_fail_no_pw => 'Auto login failed: No saved password. (Manual login required once)';
	@override late final _StringsLoginTabsEn tabs = _StringsLoginTabsEn._(_root);
	@override late final _StringsLoginOverlayPermissionEn overlay_permission = _StringsLoginOverlayPermissionEn._(_root);
}

// Path: settings
class _StringsSettingsEn extends _StringsSettingsKo {
	_StringsSettingsEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Settings';
	@override String get save => 'Save';
	@override String get save_success => 'Settings saved.';
	@override String save_error({required Object error}) => 'Error saving settings: ${error}';
	@override late final _StringsSettingsModeSwitchEn mode_switch = _StringsSettingsModeSwitchEn._(_root);
	@override late final _StringsSettingsAutoStartEn auto_start = _StringsSettingsAutoStartEn._(_root);
	@override late final _StringsSettingsAutoReceiptEn auto_receipt = _StringsSettingsAutoReceiptEn._(_root);
	@override late final _StringsSettingsPrintOrderEn print_order = _StringsSettingsPrintOrderEn._(_root);
	@override late final _StringsSettingsBuiltinPrinterEn builtin_printer = _StringsSettingsBuiltinPrinterEn._(_root);
	@override late final _StringsSettingsExternalPrinterEn external_printer = _StringsSettingsExternalPrinterEn._(_root);
	@override late final _StringsSettingsLabelPrinterEn label_printer = _StringsSettingsLabelPrinterEn._(_root);
	@override late final _StringsSettingsVolumeEn volume = _StringsSettingsVolumeEn._(_root);
	@override late final _StringsSettingsSoundEn sound = _StringsSettingsSoundEn._(_root);
	@override late final _StringsSettingsAlertCountEn alert_count = _StringsSettingsAlertCountEn._(_root);
	@override late final _StringsSettingsPrintCountEn print_count = _StringsSettingsPrintCountEn._(_root);
	@override late final _StringsSettingsLanguageEn language = _StringsSettingsLanguageEn._(_root);
	@override late final _StringsSettingsCurrencyEn currency = _StringsSettingsCurrencyEn._(_root);
	@override late final _StringsSettingsDisplayRotateEn display_rotate = _StringsSettingsDisplayRotateEn._(_root);
	@override late final _StringsSettingsKdsIgnoreStatusEn kds_ignore_status = _StringsSettingsKdsIgnoreStatusEn._(_root);
	@override late final _StringsSettingsLabelFilterEn label_filter = _StringsSettingsLabelFilterEn._(_root);
	@override late final _StringsSettingsDeveloperOptionsEn developer_options = _StringsSettingsDeveloperOptionsEn._(_root);
	@override late final _StringsSettingsLocalServerEn local_server = _StringsSettingsLocalServerEn._(_root);
	@override late final _StringsSettingsConnectionEn connection = _StringsSettingsConnectionEn._(_root);
}

// Path: home
class _StringsHomeEn extends _StringsHomeKo {
	_StringsHomeEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override late final _StringsHomeTabsEn tabs = _StringsHomeTabsEn._(_root);
	@override String get logout_confirm => 'Are you sure you want to logout?';
	@override String get minimize_error => 'An error occurred while minimizing the app.';
	@override String get invalid_tab => 'Invalid tab index.';
}

// Path: app_bar
class _StringsAppBarEn extends _StringsAppBarKo {
	_StringsAppBarEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get time_loading => 'Loading date...';
	@override String get time_error => 'Time load error';
	@override String get morning => 'AM';
	@override String get afternoon => 'PM';
	@override String new_order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 New Order',
		other: '${n} New Orders',
	);
	@override String get kds_mode => 'KDS Mode';
	@override String get order_toggle => 'Order';
	@override String get order_start_confirm_title => 'Confirm Order Start';
	@override String get order_stop_confirm_title => 'Confirm Order Stop';
	@override String get order_start_confirm_content => 'Change status to Open?';
	@override String get order_stop_confirm_content => 'Change status to Preparing (Closed)?';
	@override String get exit_app => 'Exit App';
	@override String get exit_app_desc => 'Are you sure you want to exit?';
	@override String get exit_app_kds_desc => 'Are you sure you want to exit?';
	@override String get burst_test_start => '⚡️ Starting simulation (10 orders)';
}

// Path: order_status
class _StringsOrderStatusEn extends _StringsOrderStatusKo {
	_StringsOrderStatusEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get tab_new => 'New';
	@override String get tab_preparing => 'Accepted';
	@override String get tab_ready => 'Ready';
	@override String get tab_done => 'Done';
	@override String order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 Order',
		other: '${n} Orders',
	);
	@override String get batch_complete_confirm_title => 'Ready for Pickup';
	@override String batch_complete_confirm_content({required Object n}) => 'Do you want to complete all ${n} orders?';
	@override String get batch_result_title => 'Result';
	@override String batch_result_success({required Object n}) => 'Completed: All ${n} orders processed successfully.';
	@override String batch_result_partial({required Object success, required Object fail}) => 'Completed: Success ${success}, Fail ${fail}';
	@override String batch_result_fail({required Object error}) => 'Processing failed: ${error}';
	@override String get batch_result_error => 'Error: An exception occurred during processing.';
	@override String get scroll_to_start => 'Go to Start';
}

// Path: order_history
class _StringsOrderHistoryEn extends _StringsOrderHistoryKo {
	_StringsOrderHistoryEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'History';
	@override String get search_today => 'Today\'s Orders';
	@override String get sort => 'Sort';
	@override String get filter_all => 'All';
	@override String get filter_completed => 'Completed';
	@override String get filter_cancelled => 'Cancelled';
	@override String total_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Total 1 Order',
		other: 'Total ${n} Orders',
	);
	@override String cancel_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 Cancelled',
		other: '${n} Cancelled',
	);
	@override String get loading => 'Loading...';
	@override String get no_data_today => 'No history for today.';
	@override String get no_completed_today => 'No completed orders today.';
	@override String get no_cancelled_today => 'No cancelled orders today.';
	@override String get no_data_date => 'No history for this date.';
	@override String get no_completed_date => 'No completed orders for this date.';
	@override String get no_cancelled_date => 'No cancelled orders for this date.';
	@override String error_load({required Object error}) => 'Failed to load history: ${error}.\nPlease check if store information is loaded.';
}

// Path: product_mgmt
class _StringsProductMgmtEn extends _StringsProductMgmtKo {
	_StringsProductMgmtEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Products';
	@override String get search_placeholder => 'Search product name';
	@override String get sold_out => 'Sold Out';
	@override String count({required Object n}) => '${n}';
	@override String total_count({required Object n}) => 'Total ${n}';
	@override String error_load({required Object error}) => 'An error occurred while loading products.\n${error}';
	@override String get dialog_hidden_title => 'Set to Hidden';
	@override String dialog_hidden_content({required Object name}) => 'Do you want to set [ ${name} ] to hidden?';
	@override String get btn_hidden => 'Hidden';
}

// Path: order
class _StringsOrderEn extends _StringsOrderKo {
	_StringsOrderEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get new_order => 'New';
	@override String get preparing => 'Accepted';
	@override String get ready => 'Ready';
	@override String get cancelled => 'Cancelled';
	@override String get done => 'Done';
	@override String get type_dine_in => 'Dine-in';
	@override String get type_takeout => 'Takeout';
	@override String get type_both => 'Both';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 Item',
		other: '${n} Items',
	);
	@override String count_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Total 1 item',
		other: 'Total ${n} items',
	);
	@override String get menu_no_info => 'No menu info available.';
	@override String qty({required Object n}) => '${n} qty';
	@override String get memo => 'Memo';
	@override String get amount => 'Amount';
	@override String get discount => 'Discount';
	@override String get payment => 'Total Payment';
	@override String customer_honorific({required Object name}) => '${name}';
}

// Path: order_detail
class _StringsOrderDetailEn extends _StringsOrderDetailKo {
	_StringsOrderDetailEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get loading => 'Loading details...';
	@override String error_prefix({required Object error}) => 'An error occurred: ${error}';
	@override String get status_update_fail => 'Failed to change status.';
	@override String get dialog_kiosk_cancel_title => 'Cancel Order';
	@override String get dialog_kiosk_cancel_content => 'Please cancel kiosk orders at the kiosk device.';
	@override String dialog_cancel_confirm_content({required Object n}) => 'Do you want to cancel order #${n}?';
	@override String get dialog_repickup_confirm_title => 'Pickup Re-request';
	@override String dialog_repickup_confirm_content({required Object n}) => 'Do you want to re-request pickup for order #${n}?';
	@override String get dialog_not_picked_up_confirm_title => 'Not Picked Up';
	@override String dialog_not_picked_up_confirm_content({required Object n}) => 'Process order #${n} as not picked up?';
	@override String print_receipt_fail({required Object error}) => 'Receipt printing failed: ${error}';
	@override String get btn_receipt_reprint => 'Reprint Receipt';
	@override String get btn_label_reprint => 'Reprint Label';
	@override String get btn_pickup_request => 'Request Pickup';
	@override String get btn_order_accept => 'Accept';
	@override String get btn_order_complete => 'Complete';
	@override String get btn_order_cancel => 'Cancel';
	@override String get time_select_title => 'Select Prep Time';
	@override String get time_select_content => 'Please select the time needed for preparation.';
	@override String minutes({required Object n}) => '${n} min';
}

// Path: dialog
class _StringsDialogEn extends _StringsDialogKo {
	_StringsDialogEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override late final _StringsDialogStatusChangeEn status_change = _StringsDialogStatusChangeEn._(_root);
	@override late final _StringsDialogExitEn exit = _StringsDialogExitEn._(_root);
	@override late final _StringsDialogUpdateEn update = _StringsDialogUpdateEn._(_root);
}

// Path: drawer
class _StringsDrawerEn extends _StringsDrawerKo {
	_StringsDrawerEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get settings => 'Settings';
	@override String get logout => 'Logout';
	@override String get customer_center => 'Customer Center';
	@override String version({required Object version, required Object build}) => 'Version: ${version} (${build})';
	@override String get version_loading => 'Version: Loading...';
	@override String get version_error => 'Version: Error';
}

// Path: membership
class _StringsMembershipEn extends _StringsMembershipKo {
	_StringsMembershipEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Membership Search';
	@override late final _StringsMembershipSearchEn search = _StringsMembershipSearchEn._(_root);
	@override late final _StringsMembershipCustomerEn customer = _StringsMembershipCustomerEn._(_root);
	@override late final _StringsMembershipTabsEn tabs = _StringsMembershipTabsEn._(_root);
	@override late final _StringsMembershipHistoryEn history = _StringsMembershipHistoryEn._(_root);
	@override late final _StringsMembershipDialogEn dialog = _StringsMembershipDialogEn._(_root);
	@override late final _StringsMembershipKeypadEn keypad = _StringsMembershipKeypadEn._(_root);
}

// Path: kds
class _StringsKdsEn extends _StringsKdsKo {
	_StringsKdsEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override late final _StringsKdsTabsEn tabs = _StringsKdsTabsEn._(_root);
	@override String get btn_batch_complete => 'Batch Complete';
	@override String get btn_order_complete => 'Complete';
	@override late final _StringsKdsSortEn sort = _StringsKdsSortEn._(_root);
	@override String order_time({required Object time}) => 'Ordered At ${time}';
	@override String total_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Total 1 item',
		other: 'Total ${n} items',
	);
	@override String item_qty({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 item',
		other: '${n} items',
	);
	@override String get loading_detail => 'Loading details...';
	@override String get no_menu_info => 'No menu info';
	@override String get btn_detail => 'Details';
	@override String get btn_pickup_request => 'Pickup';
	@override String msg_pickup_confirm({required Object n}) => 'Would you like to request a pickup for Order #${n}?';
	@override String get loading_orders => 'Loading orders...';
	@override String get msg_no_pickup_to_complete => 'No pickup orders to complete.';
	@override String get empty_progress => 'No orders in progress.';
	@override String get empty_pickup => 'No orders awaiting pickup.';
	@override String get empty_completed => 'No completed orders.';
	@override String get empty_cancelled => 'No cancelled orders.';
}

// Path: login.tabs
class _StringsLoginTabsEn extends _StringsLoginTabsKo {
	_StringsLoginTabsEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get order => 'Reception';
	@override String get kitchen => 'KDS';
}

// Path: login.overlay_permission
class _StringsLoginOverlayPermissionEn extends _StringsLoginOverlayPermissionKo {
	_StringsLoginOverlayPermissionEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Permission Required';
	@override String get content => '"Display over other apps" permission is required for minimize feature.\nSettings now?';
	@override String get set => 'Settings';
	@override String get later => 'Later';
}

// Path: settings.mode_switch
class _StringsSettingsModeSwitchEn extends _StringsSettingsModeSwitchKo {
	_StringsSettingsModeSwitchEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get to_main => 'Switch to Main';
	@override String get to_kds => 'Switch to KDS Mode';
	@override String get confirm_to_main => 'Switch to main (order reception) mode?';
	@override String get confirm_to_kds => 'Switch to KDS (kitchen display) mode?';
	@override String get btn_switch => 'Switch';
	@override String get desc_to_main => 'Changes to order reception screen.';
	@override String get desc_to_kds => 'Changes to kitchen display screen.';
}

// Path: settings.auto_start
class _StringsSettingsAutoStartEn extends _StringsSettingsAutoStartKo {
	_StringsSettingsAutoStartEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Auto Start on Boot';
	@override String get desc => 'Automatically launch agent on PC startup.';
	@override String get desc_general => 'Automatically launch agent on PC startup.\nStore must be open to receive orders.';
	@override String get on => 'ON';
	@override String get off => 'OFF';
}

// Path: settings.auto_receipt
class _StringsSettingsAutoReceiptEn extends _StringsSettingsAutoReceiptKo {
	_StringsSettingsAutoReceiptEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Auto Accept Pickup Orders';
	@override String get desc => 'Automatically accept orders upon receipt.';
}

// Path: settings.print_order
class _StringsSettingsPrintOrderEn extends _StringsSettingsPrintOrderKo {
	_StringsSettingsPrintOrderEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Print Tickets';
	@override String get desc => 'Print order tickets.';
}

// Path: settings.builtin_printer
class _StringsSettingsBuiltinPrinterEn extends _StringsSettingsBuiltinPrinterKo {
	_StringsSettingsBuiltinPrinterEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use Built-in Printer';
	@override String get desc => 'Use the device\'s built-in printer.';
}

// Path: settings.external_printer
class _StringsSettingsExternalPrinterEn extends _StringsSettingsExternalPrinterKo {
	_StringsSettingsExternalPrinterEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use External Printer';
	@override String get desc => 'Use USB-connected external printer.\nOrders follow settings, receipts print only on external printer.';
}

// Path: settings.label_printer
class _StringsSettingsLabelPrinterEn extends _StringsSettingsLabelPrinterKo {
	_StringsSettingsLabelPrinterEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use Label Printer';
	@override String get desc => 'Use USB-connected label printer. (50mm x 70mm)';
}

// Path: settings.volume
class _StringsSettingsVolumeEn extends _StringsSettingsVolumeKo {
	_StringsSettingsVolumeEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Volume';
	@override String get desc => 'Adjust notification volume.';
}

// Path: settings.sound
class _StringsSettingsSoundEn extends _StringsSettingsSoundKo {
	_StringsSettingsSoundEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Notification Sound';
	@override String get desc => 'Select notification sound.';
	@override String get sound1 => 'Sound 1';
	@override String get sound2 => 'Sound 2';
}

// Path: settings.alert_count
class _StringsSettingsAlertCountEn extends _StringsSettingsAlertCountKo {
	_StringsSettingsAlertCountEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Alert Count';
	@override String get desc => 'Set number of times alert plays.';
	@override String count({required Object n}) => '${n} times';
	@override String get unlimited => 'Unlimited';
}

// Path: settings.print_count
class _StringsSettingsPrintCountEn extends _StringsSettingsPrintCountKo {
	_StringsSettingsPrintCountEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Print Copies';
	@override String get desc => 'Set the number of order receipts to print on order.';
	@override String count({required Object n}) => '${n} copies';
}

// Path: settings.language
class _StringsSettingsLanguageEn extends _StringsSettingsLanguageKo {
	_StringsSettingsLanguageEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Language';
	@override String get desc => 'Set the application language.';
}

// Path: settings.currency
class _StringsSettingsCurrencyEn extends _StringsSettingsCurrencyKo {
	_StringsSettingsCurrencyEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Currency Unit';
	@override String get desc => 'Select the currency unit for displaying amounts.';
	@override String get krw => 'Won (₩)';
	@override String get jpy => 'Yen (¥)';
}

// Path: settings.display_rotate
class _StringsSettingsDisplayRotateEn extends _StringsSettingsDisplayRotateKo {
	_StringsSettingsDisplayRotateEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Flip Display';
	@override String get desc => 'Rotate the screen 180°. Use this when OS rotation settings are unavailable.';
}

// Path: settings.kds_ignore_status
class _StringsSettingsKdsIgnoreStatusEn extends _StringsSettingsKdsIgnoreStatusKo {
	_StringsSettingsKdsIgnoreStatusEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ignore Other Device Status Updates';
	@override String get desc => 'Orders on this screen will not refresh when other KDS devices update pickup or progress status. (Use when you want to control status updates manually)';
}

// Path: settings.label_filter
class _StringsSettingsLabelFilterEn extends _StringsSettingsLabelFilterKo {
	_StringsSettingsLabelFilterEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Label Print Filter';
	@override String get desc_all => 'Print labels for all order items.';
	@override String get desc_waffle_only => 'Print labels for dessert (waffle) items only.';
	@override String get desc_waffle_exclude => 'Print labels for all items except dessert (waffle).';
	@override String get btn_all => 'All Orders';
	@override String get btn_waffle_only => 'Waffle Only';
	@override String get btn_waffle_exclude => 'Exclude Waffle';
}

// Path: settings.developer_options
class _StringsSettingsDeveloperOptionsEn extends _StringsSettingsDeveloperOptionsKo {
	_StringsSettingsDeveloperOptionsEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Developer Options';
	@override late final _StringsSettingsDeveloperOptionsAppfitTestEn appfit_test = _StringsSettingsDeveloperOptionsAppfitTestEn._(_root);
}

// Path: settings.local_server
class _StringsSettingsLocalServerEn extends _StringsSettingsLocalServerKo {
	_StringsSettingsLocalServerEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Enable Local Server';
	@override String get desc => 'Enable local server for Kiosk status check.';
	@override String get info => 'Server Info';
	@override String ip({required Object ip}) => 'IP Address: ${ip}';
	@override String port({required Object port}) => 'Port: ${port}';
	@override String get started => 'Local server started.';
	@override String get stopped => 'Local server stopped.';
	@override String url({required Object url}) => 'URL: ${url}';
}

// Path: settings.connection
class _StringsSettingsConnectionEn extends _StringsSettingsConnectionKo {
	_StringsSettingsConnectionEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get connected => 'Connected';
	@override String get disconnected => 'Disconnected';
	@override String get reconnect => 'Reconnect';
}

// Path: home.tabs
class _StringsHomeTabsEn extends _StringsHomeTabsKo {
	_StringsHomeTabsEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get order_status => 'Status';
	@override String get order_history => 'History';
	@override String get product_management => 'Products';
	@override String get membership => 'Membership';
}

// Path: dialog.status_change
class _StringsDialogStatusChangeEn extends _StringsDialogStatusChangeKo {
	_StringsDialogStatusChangeEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Change Status';
	@override String content({required Object item}) => 'Do you want to change the status of [ ${item} ]?';
	@override String get current => 'Current status: ';
	@override String get sale => 'On Sale';
	@override String get sold_out => 'Sold Out';
	@override String get hidden => 'Hidden';
	@override String get hidden_delete => 'Hidden';
}

// Path: dialog.exit
class _StringsDialogExitEn extends _StringsDialogExitKo {
	_StringsDialogExitEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Exit App';
	@override String get content => 'Are you sure you want to exit?';
	@override String get confirm => 'Exit';
}

// Path: dialog.update
class _StringsDialogUpdateEn extends _StringsDialogUpdateKo {
	_StringsDialogUpdateEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'App Update';
	@override String get new_update => 'A new update is available.';
	@override String get ask_download => 'Do you want to download the update?';
	@override String get downloading => 'Downloading update...';
	@override String get download_complete => 'Download complete!';
	@override String get installing => 'The update will be installed automatically.';
	@override String get fail => 'Download failed';
	@override String get download => 'Download';
}

// Path: membership.search
class _StringsMembershipSearchEn extends _StringsMembershipSearchKo {
	_StringsMembershipSearchEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get hint => 'Please enter phone number or coupon number.';
	@override String get hint_searched => 'Please enter number of stamps. (Up to 20)';
	@override String get btn_search => 'Search Member';
	@override String get btn_other_member => 'Search Other Member';
	@override String get btn_save_stamp => 'Save Stamp';
	@override String get btn_use_coupon => 'Use Coupon';
	@override String get btn_validate_coupon => 'Validate Coupon';
	@override String get btn_scan => 'Scan Barcode';
}

// Path: membership.customer
class _StringsMembershipCustomerEn extends _StringsMembershipCustomerKo {
	_StringsMembershipCustomerEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get status_none => 'No member info found.';
	@override String honorific({required Object name}) => '${name}';
	@override String summary({required Object stamps, required Object coupons}) => 'Stamp ${stamps} | Coupon ${coupons}';
}

// Path: membership.tabs
class _StringsMembershipTabsEn extends _StringsMembershipTabsKo {
	_StringsMembershipTabsEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get stamps => 'Stamps';
	@override String get coupons => 'Usage';
	@override String get available => 'Coupons';
}

// Path: membership.history
class _StringsMembershipHistoryEn extends _StringsMembershipHistoryKo {
	_StringsMembershipHistoryEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get no_stamps => 'No stamp history.';
	@override String get no_coupons => 'No coupon history.';
	@override String get no_available => 'No coupons available.';
	@override String get col_date => 'Date/Time';
	@override String get col_count => 'Count';
	@override String get col_remark => 'Remark';
	@override String get col_coupon => 'Coupon Name';
	@override String get col_use_date => 'Use Date';
	@override String get col_expiry => 'Expiry Date';
	@override String get btn_cancel_save => 'Cancel Save';
	@override String get btn_cancel_use => 'Cancel Use';
	@override String get btn_use => 'Use';
	@override String get status_cancelled => 'Cancelled';
	@override String get status_converted => 'Converted';
	@override String get status_issued => 'Issued';
	@override String get status_expired => 'Expired';
	@override String get prev_page => 'Prev';
	@override String get next_page => 'Next';
}

// Path: membership.dialog
class _StringsMembershipDialogEn extends _StringsMembershipDialogKo {
	_StringsMembershipDialogEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get invalid_barcode => 'Unsupported format.';
	@override String get enter_phone => 'Please enter phone number.';
	@override String get cancel_stamp_title => 'Cancel Stamp Save';
	@override String cancel_stamp_content({required Object count, required Object date}) => 'Cancel ${count} stamps saved on ${date}?';
	@override String get cancel_coupon_title => 'Cancel Coupon Usage';
	@override String cancel_coupon_content({required Object title}) => 'Cancel usage of [${title}]?';
	@override String get use_coupon_title => 'Use Coupon';
	@override String use_coupon_content({required Object title}) => 'Use ${title} coupon?';
	@override String use_coupon_code_content({required Object code}) => 'Use coupon code [${code}]?';
	@override String get scanner_not_supported => 'QR scanning not supported.';
	@override String get enter_coupon_code => 'Please enter coupon code.';
	@override String get store_info_missing => 'Store info missing. Please login again.';
	@override String get input_error_title => 'Input Error';
	@override String get stamp_input_error => 'Please enter 1 or more stamps.';
	@override String get stamp_limit_error => '20 stamps or less.';
	@override String get coupon_info_title => 'Coupon Info';
	@override String coupon_info_content({required Object name, required Object benefit}) => 'Name: ${name}\nBenefit: ${benefit}\nAvailable.';
	@override String get processing_complete => 'Complete';
	@override String get notification => 'Notification';
}

// Path: membership.keypad
class _StringsMembershipKeypadEn extends _StringsMembershipKeypadKo {
	_StringsMembershipKeypadEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get clear => 'Clear';
	@override String get delete => 'Delete';
}

// Path: kds.tabs
class _StringsKdsTabsEn extends _StringsKdsTabsKo {
	_StringsKdsTabsEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String all({required Object n}) => 'All ${n}';
	@override String progress({required Object n}) => 'Progress ${n}';
	@override String pickup({required Object n}) => 'Pickup ${n}';
	@override String completed({required Object n}) => 'Done ${n}';
	@override String cancelled({required Object n}) => 'Cancelled ${n}';
}

// Path: kds.sort
class _StringsKdsSortEn extends _StringsKdsSortKo {
	_StringsKdsSortEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get oldest => 'Oldest';
	@override String get newest => 'Newest';
}

// Path: settings.developer_options.appfit_test
class _StringsSettingsDeveloperOptionsAppfitTestEn extends _StringsSettingsDeveloperOptionsAppfitTestKo {
	_StringsSettingsDeveloperOptionsAppfitTestEn._(_StringsEn root) : this._root = root, super._(root);

	@override final _StringsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'AppFit API Test';
	@override String get desc => 'Test Waldlust Platform AppFit API settings';
	@override String get btn => 'Test';
}

// Path: <root>
class _StringsJa extends Translations {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	_StringsJa.build({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = TranslationMetadata(
		    locale: AppLocale.ja,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super.build(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

	/// Metadata for the translations of <ja>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	@override late final _StringsJa _root = this; // ignore: unused_field

	// Translations
	@override late final _StringsAppJa app = _StringsAppJa._(_root);
	@override late final _StringsCommonJa common = _StringsCommonJa._(_root);
	@override late final _StringsLoginJa login = _StringsLoginJa._(_root);
	@override late final _StringsSettingsJa settings = _StringsSettingsJa._(_root);
	@override late final _StringsHomeJa home = _StringsHomeJa._(_root);
	@override late final _StringsAppBarJa app_bar = _StringsAppBarJa._(_root);
	@override late final _StringsOrderStatusJa order_status = _StringsOrderStatusJa._(_root);
	@override late final _StringsOrderHistoryJa order_history = _StringsOrderHistoryJa._(_root);
	@override late final _StringsProductMgmtJa product_mgmt = _StringsProductMgmtJa._(_root);
	@override late final _StringsOrderJa order = _StringsOrderJa._(_root);
	@override late final _StringsOrderDetailJa order_detail = _StringsOrderDetailJa._(_root);
	@override late final _StringsDialogJa dialog = _StringsDialogJa._(_root);
	@override late final _StringsDrawerJa drawer = _StringsDrawerJa._(_root);
	@override late final _StringsMembershipJa membership = _StringsMembershipJa._(_root);
	@override late final _StringsKdsJa kds = _StringsKdsJa._(_root);
}

// Path: app
class _StringsAppJa extends _StringsAppKo {
	_StringsAppJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get name => 'ココナッツ注文エージェント';
}

// Path: common
class _StringsCommonJa extends _StringsCommonKo {
	_StringsCommonJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get confirm => '確認';
	@override String get cancel => 'キャンセル';
	@override String get close => '閉じる';
	@override String get refresh => '更新';
	@override String get error => 'エラー';
	@override String get error_title => 'エラーが発生しました';
	@override String get loading => 'ロード中...';
	@override String get next => '次へ';
	@override String get retry => '再試行';
	@override String get yes => 'はい';
	@override String get no => 'いいえ';
	@override String get unknown => '不明';
	@override String get later => '後で';
}

// Path: login
class _StringsLoginJa extends _StringsLoginKo {
	_StringsLoginJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ログイン';
	@override String get id_label => 'ID';
	@override String get pw_label => 'パスワード';
	@override String get id_placeholder => 'IDを入力してください';
	@override String get pw_placeholder => 'パスワードを入力してください';
	@override String get button => 'ログイン';
	@override String get save_id => 'ID保存';
	@override String get auto_login => '自動ログイン';
	@override String get fail_title => 'ログイン失敗';
	@override String get fail_msg => 'ログインに失敗しました。';
	@override String get permission_error => '権限リクエスト中にエラーが発生しました。';
	@override String get internet_error_title => '接続エラー';
	@override String get internet_error_msg => 'インターネット接続を確認してください。';
	@override String get auto_login_disabled => '自動ログイン設定が無効です。';
	@override String get auto_login_no_id => '保存された店舗IDがないため、自動ログインをスキップします。';
	@override String get auto_login_fail_no_pw => '自動ログイン失敗：保存されたパスワードがないか空です。(初回は手動ログインが必要です)';
	@override late final _StringsLoginTabsJa tabs = _StringsLoginTabsJa._(_root);
	@override late final _StringsLoginOverlayPermissionJa overlay_permission = _StringsLoginOverlayPermissionJa._(_root);
}

// Path: settings
class _StringsSettingsJa extends _StringsSettingsKo {
	_StringsSettingsJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '設定';
	@override String get save => '保存';
	@override String get save_success => '設定が保存されました。';
	@override String save_error({required Object error}) => '設定の保存中にエラーが発生しました: ${error}';
	@override late final _StringsSettingsModeSwitchJa mode_switch = _StringsSettingsModeSwitchJa._(_root);
	@override late final _StringsSettingsAutoStartJa auto_start = _StringsSettingsAutoStartJa._(_root);
	@override late final _StringsSettingsAutoReceiptJa auto_receipt = _StringsSettingsAutoReceiptJa._(_root);
	@override late final _StringsSettingsPrintOrderJa print_order = _StringsSettingsPrintOrderJa._(_root);
	@override late final _StringsSettingsBuiltinPrinterJa builtin_printer = _StringsSettingsBuiltinPrinterJa._(_root);
	@override late final _StringsSettingsExternalPrinterJa external_printer = _StringsSettingsExternalPrinterJa._(_root);
	@override late final _StringsSettingsLabelPrinterJa label_printer = _StringsSettingsLabelPrinterJa._(_root);
	@override late final _StringsSettingsVolumeJa volume = _StringsSettingsVolumeJa._(_root);
	@override late final _StringsSettingsSoundJa sound = _StringsSettingsSoundJa._(_root);
	@override late final _StringsSettingsAlertCountJa alert_count = _StringsSettingsAlertCountJa._(_root);
	@override late final _StringsSettingsPrintCountJa print_count = _StringsSettingsPrintCountJa._(_root);
	@override late final _StringsSettingsLanguageJa language = _StringsSettingsLanguageJa._(_root);
	@override late final _StringsSettingsCurrencyJa currency = _StringsSettingsCurrencyJa._(_root);
	@override late final _StringsSettingsDisplayRotateJa display_rotate = _StringsSettingsDisplayRotateJa._(_root);
	@override late final _StringsSettingsKdsIgnoreStatusJa kds_ignore_status = _StringsSettingsKdsIgnoreStatusJa._(_root);
	@override late final _StringsSettingsLabelFilterJa label_filter = _StringsSettingsLabelFilterJa._(_root);
	@override late final _StringsSettingsDeveloperOptionsJa developer_options = _StringsSettingsDeveloperOptionsJa._(_root);
	@override late final _StringsSettingsLocalServerJa local_server = _StringsSettingsLocalServerJa._(_root);
	@override late final _StringsSettingsConnectionJa connection = _StringsSettingsConnectionJa._(_root);
}

// Path: home
class _StringsHomeJa extends _StringsHomeKo {
	_StringsHomeJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override late final _StringsHomeTabsJa tabs = _StringsHomeTabsJa._(_root);
	@override String get logout_confirm => 'ログアウトしますか？';
	@override String get minimize_error => '最小化中にエラーが発生しました。';
	@override String get invalid_tab => '無効なタブインデックスです。';
}

// Path: app_bar
class _StringsAppBarJa extends _StringsAppBarKo {
	_StringsAppBarJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get time_loading => '日付読み込み中...';
	@override String get time_error => '時刻読み込みエラー';
	@override String get morning => '午前';
	@override String get afternoon => '午後';
	@override String new_order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '新規 ${n} 件',
	);
	@override String get kds_mode => '厨房モニター';
	@override String get order_toggle => 'オーダー';
	@override String get order_start_confirm_title => 'オーダー開始確認';
	@override String get order_stop_confirm_title => 'オーダー停止確認';
	@override String get order_start_confirm_content => '営業中に変更しますか？';
	@override String get order_stop_confirm_content => '準備中に変更しますか？';
	@override String get exit_app => 'アプリ終了';
	@override String get exit_app_desc => 'アプリを終了しますか？';
	@override String get exit_app_kds_desc => 'アプリを終了しますか？';
	@override String get burst_test_start => '⚡️ 注文ラッシュシミュレーション開始 (10件)';
}

// Path: order_status
class _StringsOrderStatusJa extends _StringsOrderStatusKo {
	_StringsOrderStatusJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get tab_new => '新規注文';
	@override String get tab_preparing => '注文受付';
	@override String get tab_ready => '商品準備\n完了';
	@override String get tab_done => '完了';
	@override String order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '${n} 件',
	);
	@override String get batch_complete_confirm_title => 'ピックアップ準備完了';
	@override String batch_complete_confirm_content({required Object n}) => '${n}件一括完了処理しますか？';
	@override String get batch_result_title => '一括完了処理結果';
	@override String batch_result_success({required Object n}) => '処理完了: ${n}件すべて正常に処理されました。';
	@override String batch_result_partial({required Object success, required Object fail}) => '処理完了: 成功 ${success}件, 失敗 ${fail}件';
	@override String batch_result_fail({required Object error}) => '処理失敗: ${error}';
	@override String get batch_result_error => 'エラー: 処理中に例外が発生しました。';
	@override String get scroll_to_start => '先頭へ';
}

// Path: order_history
class _StringsOrderHistoryJa extends _StringsOrderHistoryKo {
	_StringsOrderHistoryJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '注文履歴';
	@override String get search_today => '今日の注文照会';
	@override String get sort => '整列';
	@override String get filter_all => '全注文';
	@override String get filter_completed => 'ピックアップ完了';
	@override String get filter_cancelled => '注文取消';
	@override String total_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '合計 ${n}件',
	);
	@override String cancel_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '取消 ${n}件',
	);
	@override String get loading => '読み込み中...';
	@override String get no_data_today => '今日の注文履歴がありません。';
	@override String get no_completed_today => '今日完了した注文がありません。';
	@override String get no_cancelled_today => '今日取り消された注文がありません。';
	@override String get no_data_date => '該当日付に注文履歴がありません。';
	@override String get no_completed_date => '該当日付に完了した注文がありません。';
	@override String get no_cancelled_date => '該当日付に取り消された注文がありません。';
	@override String error_load({required Object error}) => '注文履歴の読み込みに失敗しました: ${error}。\n店舗情報が読み込まれているか確認してください。';
}

// Path: product_mgmt
class _StringsProductMgmtJa extends _StringsProductMgmtKo {
	_StringsProductMgmtJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '商品管理';
	@override String get search_placeholder => '商品名検索';
	@override String get sold_out => '品切れ';
	@override String count({required Object n}) => '${n}個';
	@override String total_count({required Object n}) => '全体 ${n}個';
	@override String error_load({required Object error}) => '商品リストの読み込み中にエラーが発生しました。\n${error}';
	@override String get dialog_hidden_title => '非表示処理';
	@override String dialog_hidden_content({required Object name}) => '[ ${name} ] を非表示(キー削除)にしますか？';
	@override String get btn_hidden => '非表示(キー削除)';
}

// Path: order
class _StringsOrderJa extends _StringsOrderKo {
	_StringsOrderJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get new_order => '新規';
	@override String get preparing => '受付';
	@override String get ready => '待機';
	@override String get cancelled => '取消';
	@override String get done => '完了';
	@override String get type_dine_in => '店内';
	@override String get type_takeout => '持ち帰り';
	@override String get type_both => '複合';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '${n} 個',
	);
	@override String count_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '注文メニュー合計 ${n}個',
	);
	@override String get menu_no_info => 'メニュー情報がありません。';
	@override String qty({required Object n}) => '${n}個';
	@override String get memo => 'メモ';
	@override String get amount => '注文金額';
	@override String get discount => '割引金額';
	@override String get payment => '決済金額';
	@override String customer_honorific({required Object name}) => '${name}様';
}

// Path: order_detail
class _StringsOrderDetailJa extends _StringsOrderDetailKo {
	_StringsOrderDetailJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get loading => '注文詳細情報を読み込んでいます...';
	@override String error_prefix({required Object error}) => 'エラーが発生しました: ${error}';
	@override String get status_update_fail => '注文状態の変更に失敗しました。';
	@override String get dialog_kiosk_cancel_title => '注文取消';
	@override String get dialog_kiosk_cancel_content => 'キオスク注文はキオスク端末で取り消してください。';
	@override String dialog_cancel_confirm_content({required Object n}) => '${n}番の注文を取り消しますか？';
	@override String get dialog_repickup_confirm_title => 'ピックアップ再要請';
	@override String dialog_repickup_confirm_content({required Object n}) => '${n}番の注文のピックアップを再要請しますか？';
	@override String get dialog_not_picked_up_confirm_title => '未ピックアップ';
	@override String dialog_not_picked_up_confirm_content({required Object n}) => '${n}番の注文を未ピックアップ処理しますか？';
	@override String print_receipt_fail({required Object error}) => '領収書印刷失敗: ${error}';
	@override String get btn_receipt_reprint => '領収書再印刷';
	@override String get btn_label_reprint => 'ラベル再印刷';
	@override String get btn_pickup_request => 'ピックアップ要請';
	@override String get btn_order_accept => '注文受付';
	@override String get btn_order_complete => '注文完了';
	@override String get btn_order_cancel => '注文取消';
	@override String get time_select_title => '準備時間選択';
	@override String get time_select_content => '注文準備に必要な時間を選択してください。';
	@override String minutes({required Object n}) => '${n}分';
}

// Path: dialog
class _StringsDialogJa extends _StringsDialogKo {
	_StringsDialogJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override late final _StringsDialogStatusChangeJa status_change = _StringsDialogStatusChangeJa._(_root);
	@override late final _StringsDialogExitJa exit = _StringsDialogExitJa._(_root);
	@override late final _StringsDialogUpdateJa update = _StringsDialogUpdateJa._(_root);
}

// Path: drawer
class _StringsDrawerJa extends _StringsDrawerKo {
	_StringsDrawerJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get settings => '設定';
	@override String get logout => 'ログアウト';
	@override String get customer_center => 'カスタマーセンター';
	@override String version({required Object version, required Object build}) => 'バージョン: ${version} (${build})';
	@override String get version_loading => 'バージョン: 読み込み中...';
	@override String get version_error => 'バージョン: エラー';
}

// Path: membership
class _StringsMembershipJa extends _StringsMembershipKo {
	_StringsMembershipJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'メンバーシップ照会';
	@override late final _StringsMembershipSearchJa search = _StringsMembershipSearchJa._(_root);
	@override late final _StringsMembershipCustomerJa customer = _StringsMembershipCustomerJa._(_root);
	@override late final _StringsMembershipTabsJa tabs = _StringsMembershipTabsJa._(_root);
	@override late final _StringsMembershipHistoryJa history = _StringsMembershipHistoryJa._(_root);
	@override late final _StringsMembershipDialogJa dialog = _StringsMembershipDialogJa._(_root);
	@override late final _StringsMembershipKeypadJa keypad = _StringsMembershipKeypadJa._(_root);
}

// Path: kds
class _StringsKdsJa extends _StringsKdsKo {
	_StringsKdsJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override late final _StringsKdsTabsJa tabs = _StringsKdsTabsJa._(_root);
	@override String get btn_batch_complete => '一括完了';
	@override String get btn_order_complete => '注文完了';
	@override late final _StringsKdsSortJa sort = _StringsKdsSortJa._(_root);
	@override String order_time({required Object time}) => '注文時間 ${time}';
	@override String total_items({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '合計 ${n}個',
	);
	@override String item_qty({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '${n}個',
	);
	@override String get loading_detail => '詳細情報読み込み中...';
	@override String get no_menu_info => 'メニュー情報なし';
	@override String get btn_detail => '詳細';
	@override String get btn_pickup_request => '呼出';
	@override String msg_pickup_confirm({required Object n}) => '${n}番の注文のピックアップを要請しますか？';
	@override String get loading_orders => '注文情報を読み込んでいます...';
	@override String get msg_no_pickup_to_complete => '完了するピックアップ注文がありません。';
	@override String get empty_progress => '進行中の注文がありません。';
	@override String get empty_pickup => 'ピックアップ待ちの注文がありません。';
	@override String get empty_completed => '完了した注文がありません。';
	@override String get empty_cancelled => '取消した注文がありません。';
}

// Path: login.tabs
class _StringsLoginTabsJa extends _StringsLoginTabsKo {
	_StringsLoginTabsJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get order => '注文受付';
	@override String get kitchen => 'キッチン(KDS)';
}

// Path: login.overlay_permission
class _StringsLoginOverlayPermissionJa extends _StringsLoginOverlayPermissionKo {
	_StringsLoginOverlayPermissionJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '権限が必要';
	@override String get content => '最小化機能を使用するには「他のアプリの上に表示」権限が必要です。\n今すぐ設定しますか？';
	@override String get set => '設定する';
	@override String get later => '後で';
}

// Path: settings.mode_switch
class _StringsSettingsModeSwitchJa extends _StringsSettingsModeSwitchKo {
	_StringsSettingsModeSwitchJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get to_main => 'メインに切替';
	@override String get to_kds => 'KDSモードに切替';
	@override String get confirm_to_main => 'メイン（注文受付）に切り替えますか？';
	@override String get confirm_to_kds => 'KDS（キッチンモニター）に切り替えますか？';
	@override String get btn_switch => '切替';
	@override String get desc_to_main => '注文受付画面に変更します。';
	@override String get desc_to_kds => 'キッチン専用モニターに変更します。';
}

// Path: settings.auto_start
class _StringsSettingsAutoStartJa extends _StringsSettingsAutoStartKo {
	_StringsSettingsAutoStartJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'PC起動時に自動実行';
	@override String get desc => 'PC起動時にエージェントを自動的に実行します。';
	@override String get desc_general => 'PC起動時にエージェントを自動的に実行します。\n注文を受け付けるには営業中に設定する必要があります。';
	@override String get on => 'ON';
	@override String get off => 'OFF';
}

// Path: settings.auto_receipt
class _StringsSettingsAutoReceiptJa extends _StringsSettingsAutoReceiptKo {
	_StringsSettingsAutoReceiptJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ピックアップ注文自動受付';
	@override String get desc => '注文受信時に自動的に受け付けます。';
}

// Path: settings.print_order
class _StringsSettingsPrintOrderJa extends _StringsSettingsPrintOrderKo {
	_StringsSettingsPrintOrderJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '注文書出力';
	@override String get desc => '注文書を出力します。';
}

// Path: settings.builtin_printer
class _StringsSettingsBuiltinPrinterJa extends _StringsSettingsBuiltinPrinterKo {
	_StringsSettingsBuiltinPrinterJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '内蔵プリンター使用';
	@override String get desc => 'デバイスの内蔵プリンターを使用します。';
}

// Path: settings.external_printer
class _StringsSettingsExternalPrinterJa extends _StringsSettingsExternalPrinterKo {
	_StringsSettingsExternalPrinterJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '外部プリンター使用';
	@override String get desc => 'USB接続された外部プリンターを使用します。\n使用時、注文書は設定に従い、レシートは外部プリンターのみで出力されます。';
}

// Path: settings.label_printer
class _StringsSettingsLabelPrinterJa extends _StringsSettingsLabelPrinterKo {
	_StringsSettingsLabelPrinterJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ラベルプリンター使用';
	@override String get desc => 'USB接続されたラベルプリンターを使用します。(50mm x 70mm)';
}

// Path: settings.volume
class _StringsSettingsVolumeJa extends _StringsSettingsVolumeKo {
	_StringsSettingsVolumeJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知音量設定';
	@override String get desc => '通知音の大きさを調節します。';
}

// Path: settings.sound
class _StringsSettingsSoundJa extends _StringsSettingsSoundKo {
	_StringsSettingsSoundJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知音設定';
	@override String get desc => '通知音を選択します。';
	@override String get sound1 => '通知音 1';
	@override String get sound2 => '通知音 2';
}

// Path: settings.alert_count
class _StringsSettingsAlertCountJa extends _StringsSettingsAlertCountKo {
	_StringsSettingsAlertCountJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知回数設定';
	@override String get desc => '通知が鳴る回数を設定します。';
	@override String count({required Object n}) => '${n}回';
	@override String get unlimited => '無制限';
}

// Path: settings.print_count
class _StringsSettingsPrintCountJa extends _StringsSettingsPrintCountKo {
	_StringsSettingsPrintCountJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '出力枚数';
	@override String get desc => '注文受付時に印刷する伝票枚数を設定します。';
	@override String count({required Object n}) => '${n}枚';
}

// Path: settings.language
class _StringsSettingsLanguageJa extends _StringsSettingsLanguageKo {
	_StringsSettingsLanguageJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '言語設定';
	@override String get desc => 'アプリの言語を設定します。';
}

// Path: settings.currency
class _StringsSettingsCurrencyJa extends _StringsSettingsCurrencyKo {
	_StringsSettingsCurrencyJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通貨単位設定';
	@override String get desc => '金額表示に使用する通貨単位を選択します。';
	@override String get krw => 'ウォン (₩)';
	@override String get jpy => '円 (¥)';
}

// Path: settings.display_rotate
class _StringsSettingsDisplayRotateJa extends _StringsSettingsDisplayRotateKo {
	_StringsSettingsDisplayRotateJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '画面上下反転';
	@override String get desc => '画面を180度回転します。OS側に回転設定がない環境で使用します。';
}

// Path: settings.kds_ignore_status
class _StringsSettingsKdsIgnoreStatusJa extends _StringsSettingsKdsIgnoreStatusKo {
	_StringsSettingsKdsIgnoreStatusJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '他端末の進行状態通知を無視';
	@override String get desc => '他のKDSでピックアップ要請などの進行状態を変更しても、この画面の注文は更新されません。(進行状態の更新を手動で管理したい場合に使用)';
}

// Path: settings.label_filter
class _StringsSettingsLabelFilterJa extends _StringsSettingsLabelFilterKo {
	_StringsSettingsLabelFilterJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ラベル印刷フィルター';
	@override String get desc_all => '全注文商品のラベルを印刷します。';
	@override String get desc_waffle_only => 'デザート(ワッフル)商品のみラベルを印刷します。';
	@override String get desc_waffle_exclude => 'デザート(ワッフル)商品を除いてラベルを印刷します。';
	@override String get btn_all => '全注文印刷';
	@override String get btn_waffle_only => 'ワッフルのみ';
	@override String get btn_waffle_exclude => 'ワッフル除外';
}

// Path: settings.developer_options
class _StringsSettingsDeveloperOptionsJa extends _StringsSettingsDeveloperOptionsKo {
	_StringsSettingsDeveloperOptionsJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '開発者オプション';
	@override late final _StringsSettingsDeveloperOptionsAppfitTestJa appfit_test = _StringsSettingsDeveloperOptionsAppfitTestJa._(_root);
}

// Path: settings.local_server
class _StringsSettingsLocalServerJa extends _StringsSettingsLocalServerKo {
	_StringsSettingsLocalServerJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ローカルサーバー有効化';
	@override String get desc => 'キオスクで商品状態を照会できる\nローカルサーバーを有効にします。';
	@override String get info => 'サーバー情報';
	@override String ip({required Object ip}) => 'IPアドレス: ${ip}';
	@override String port({required Object port}) => 'ポート: ${port}';
	@override String get started => 'ローカルサーバーが開始されました。';
	@override String get stopped => 'ローカルサーバーが停止しました。';
	@override String url({required Object url}) => 'URL: ${url}';
}

// Path: settings.connection
class _StringsSettingsConnectionJa extends _StringsSettingsConnectionKo {
	_StringsSettingsConnectionJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get connected => '接続済み';
	@override String get disconnected => '未接続';
	@override String get reconnect => '再接続';
}

// Path: home.tabs
class _StringsHomeTabsJa extends _StringsHomeTabsKo {
	_StringsHomeTabsJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get order_status => '注文状況';
	@override String get order_history => '注文履歴';
	@override String get product_management => '商品管理';
	@override String get membership => 'メンバーシップ';
}

// Path: dialog.status_change
class _StringsDialogStatusChangeJa extends _StringsDialogStatusChangeKo {
	_StringsDialogStatusChangeJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '状態変更';
	@override String content({required Object item}) => '[ ${item} ] の状態を変更しますか？';
	@override String get current => '現在の状態: ';
	@override String get sale => '販売';
	@override String get sold_out => '品切れ';
	@override String get hidden => '非表示';
	@override String get hidden_delete => '非表示(キー削除)';
}

// Path: dialog.exit
class _StringsDialogExitJa extends _StringsDialogExitKo {
	_StringsDialogExitJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'アプリ終了';
	@override String get content => '本当に終了しますか？';
	@override String get confirm => '終了';
}

// Path: dialog.update
class _StringsDialogUpdateJa extends _StringsDialogUpdateKo {
	_StringsDialogUpdateJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'アプリのアップデート';
	@override String get new_update => '新しいアップデートがあります。';
	@override String get ask_download => 'アップデートをダウンロードしますか？';
	@override String get downloading => 'アップデートをダウンロード中...';
	@override String get download_complete => 'ダウンロードが完了しました！';
	@override String get installing => 'アップデートが自動的にインストールされます。';
	@override String get fail => 'ダウンロード失敗';
	@override String get download => 'ダウンロード';
}

// Path: membership.search
class _StringsMembershipSearchJa extends _StringsMembershipSearchKo {
	_StringsMembershipSearchJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get hint => '電話番号またはクーポン番号を入力してください。';
	@override String get hint_searched => 'スタンプの個数を入力してください。(最大20個まで)';
	@override String get btn_search => '会員照会';
	@override String get btn_other_member => '他の会員を照会';
	@override String get btn_save_stamp => 'スタンプ積立';
	@override String get btn_use_coupon => 'クーポン使用';
	@override String get btn_validate_coupon => 'クーポン検証';
	@override String get btn_scan => 'バーコードスキャン';
}

// Path: membership.customer
class _StringsMembershipCustomerJa extends _StringsMembershipCustomerKo {
	_StringsMembershipCustomerJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get status_none => '会員情報がありません。';
	@override String honorific({required Object name}) => '${name}様';
	@override String summary({required Object stamps, required Object coupons}) => 'スタンプ ${stamps} | クーポン ${coupons}';
}

// Path: membership.tabs
class _StringsMembershipTabsJa extends _StringsMembershipTabsKo {
	_StringsMembershipTabsJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get stamps => 'スタンプ内訳';
	@override String get coupons => 'クーポン使用内訳';
	@override String get available => '保有クーポン';
}

// Path: membership.history
class _StringsMembershipHistoryJa extends _StringsMembershipHistoryKo {
	_StringsMembershipHistoryJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get no_stamps => 'スタンプ内訳がありません。';
	@override String get no_coupons => 'クーポン内訳がありません。';
	@override String get no_available => '保有しているクーポンがありません。';
	@override String get col_date => '積立日時';
	@override String get col_count => '積立個数';
	@override String get col_remark => '備考';
	@override String get col_coupon => 'クーポン名';
	@override String get col_use_date => '使用日';
	@override String get col_expiry => '有効期限';
	@override String get btn_cancel_save => '積立取消';
	@override String get btn_cancel_use => '使用取消';
	@override String get btn_use => '使用';
	@override String get status_cancelled => '取消完了';
	@override String get status_converted => 'クーポン変換完了';
	@override String get status_issued => '発行完了';
	@override String get status_expired => '期間満了';
	@override String get prev_page => '前のページ';
	@override String get next_page => '次のページ';
}

// Path: membership.dialog
class _StringsMembershipDialogJa extends _StringsMembershipDialogKo {
	_StringsMembershipDialogJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get invalid_barcode => 'サポートされていないバーコード形式です。';
	@override String get enter_phone => '電話番号を入力してください。';
	@override String get cancel_stamp_title => 'スタンプ積立取消';
	@override String cancel_stamp_content({required Object date, required Object count}) => '${date} に積立された ${count}個のスタンプ積立を取り消しますか？';
	@override String get cancel_coupon_title => 'クーポン使用取消';
	@override String cancel_coupon_content({required Object title}) => '[${title}] クーポンの使用を取り消しますか？';
	@override String get use_coupon_title => 'クーポン使用';
	@override String use_coupon_content({required Object title}) => '${title} クーポンを使用しますか？';
	@override String use_coupon_code_content({required Object code}) => 'クーポンコード [${code}] を使用しますか？';
	@override String get scanner_not_supported => 'QRバーコードをサポートしていない端末です。';
	@override String get enter_coupon_code => 'クーポンコードを入力してください。';
	@override String get store_info_missing => '店舗情報がありません。再度ログインしてください。';
	@override String get input_error_title => '入力エラー';
	@override String get stamp_input_error => 'スタンプ個数は1以上の数字で入力してください。';
	@override String get stamp_limit_error => 'スタンプ個数は20個以下で入力してください。';
	@override String get coupon_info_title => 'クーポン情報';
	@override String coupon_info_content({required Object name, required Object benefit}) => 'クーポン名: ${name}\n特典: ${benefit}\n使用可能です。';
	@override String get processing_complete => '完了';
	@override String get notification => '通知';
}

// Path: membership.keypad
class _StringsMembershipKeypadJa extends _StringsMembershipKeypadKo {
	_StringsMembershipKeypadJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get clear => '初期化';
	@override String get delete => '削除';
}

// Path: kds.tabs
class _StringsKdsTabsJa extends _StringsKdsTabsKo {
	_StringsKdsTabsJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String all({required Object n}) => '全体 ${n}';
	@override String progress({required Object n}) => '進行 ${n}';
	@override String pickup({required Object n}) => 'ピックアップ ${n}';
	@override String completed({required Object n}) => '完了 ${n}';
	@override String cancelled({required Object n}) => '取消 ${n}';
}

// Path: kds.sort
class _StringsKdsSortJa extends _StringsKdsSortKo {
	_StringsKdsSortJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get oldest => '古い順';
	@override String get newest => '新しい順';
}

// Path: settings.developer_options.appfit_test
class _StringsSettingsDeveloperOptionsAppfitTestJa extends _StringsSettingsDeveloperOptionsAppfitTestKo {
	_StringsSettingsDeveloperOptionsAppfitTestJa._(_StringsJa root) : this._root = root, super._(root);

	@override final _StringsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'AppFit API テスト';
	@override String get desc => 'Waldlust Platform AppFit API 設定確認とテスト';
	@override String get btn => 'テスト';
}
