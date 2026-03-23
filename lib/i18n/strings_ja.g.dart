///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsJa extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsJa({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ja,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

	/// Metadata for the translations of <ja>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	late final TranslationsJa _root = this; // ignore: unused_field

	@override 
	TranslationsJa $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsJa(meta: meta ?? this.$meta);

	// Translations
	@override late final _TranslationsAppJa app = _TranslationsAppJa._(_root);
	@override late final _TranslationsCommonJa common = _TranslationsCommonJa._(_root);
	@override late final _TranslationsLoginJa login = _TranslationsLoginJa._(_root);
	@override late final _TranslationsSettingsJa settings = _TranslationsSettingsJa._(_root);
	@override late final _TranslationsHomeJa home = _TranslationsHomeJa._(_root);
	@override late final _TranslationsAppBarJa app_bar = _TranslationsAppBarJa._(_root);
	@override late final _TranslationsOrderStatusJa order_status = _TranslationsOrderStatusJa._(_root);
	@override late final _TranslationsOrderHistoryJa order_history = _TranslationsOrderHistoryJa._(_root);
	@override late final _TranslationsProductMgmtJa product_mgmt = _TranslationsProductMgmtJa._(_root);
	@override late final _TranslationsOrderJa order = _TranslationsOrderJa._(_root);
	@override late final _TranslationsOrderDetailJa order_detail = _TranslationsOrderDetailJa._(_root);
	@override late final _TranslationsDialogJa dialog = _TranslationsDialogJa._(_root);
	@override late final _TranslationsDrawerJa drawer = _TranslationsDrawerJa._(_root);
	@override late final _TranslationsMembershipJa membership = _TranslationsMembershipJa._(_root);
	@override late final _TranslationsKdsJa kds = _TranslationsKdsJa._(_root);
}

// Path: app
class _TranslationsAppJa extends TranslationsAppKo {
	_TranslationsAppJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get name => 'ココナッツ注文エージェント';
}

// Path: common
class _TranslationsCommonJa extends TranslationsCommonKo {
	_TranslationsCommonJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsLoginJa extends TranslationsLoginKo {
	_TranslationsLoginJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
	@override late final _TranslationsLoginTabsJa tabs = _TranslationsLoginTabsJa._(_root);
	@override late final _TranslationsLoginOverlayPermissionJa overlay_permission = _TranslationsLoginOverlayPermissionJa._(_root);
}

// Path: settings
class _TranslationsSettingsJa extends TranslationsSettingsKo {
	_TranslationsSettingsJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '設定';
	@override String get save => '保存';
	@override String get save_success => '設定が保存されました。';
	@override String save_error({required Object error}) => '設定の保存中にエラーが発生しました: ${error}';
	@override late final _TranslationsSettingsModeSwitchJa mode_switch = _TranslationsSettingsModeSwitchJa._(_root);
	@override late final _TranslationsSettingsAutoStartJa auto_start = _TranslationsSettingsAutoStartJa._(_root);
	@override late final _TranslationsSettingsAutoReceiptJa auto_receipt = _TranslationsSettingsAutoReceiptJa._(_root);
	@override late final _TranslationsSettingsPrintOrderJa print_order = _TranslationsSettingsPrintOrderJa._(_root);
	@override late final _TranslationsSettingsBuiltinPrinterJa builtin_printer = _TranslationsSettingsBuiltinPrinterJa._(_root);
	@override late final _TranslationsSettingsExternalPrinterJa external_printer = _TranslationsSettingsExternalPrinterJa._(_root);
	@override late final _TranslationsSettingsLabelPrinterJa label_printer = _TranslationsSettingsLabelPrinterJa._(_root);
	@override late final _TranslationsSettingsVolumeJa volume = _TranslationsSettingsVolumeJa._(_root);
	@override late final _TranslationsSettingsSoundJa sound = _TranslationsSettingsSoundJa._(_root);
	@override late final _TranslationsSettingsAlertCountJa alert_count = _TranslationsSettingsAlertCountJa._(_root);
	@override late final _TranslationsSettingsPrintCountJa print_count = _TranslationsSettingsPrintCountJa._(_root);
	@override late final _TranslationsSettingsLanguageJa language = _TranslationsSettingsLanguageJa._(_root);
	@override late final _TranslationsSettingsDeveloperOptionsJa developer_options = _TranslationsSettingsDeveloperOptionsJa._(_root);
	@override late final _TranslationsSettingsLocalServerJa local_server = _TranslationsSettingsLocalServerJa._(_root);
	@override late final _TranslationsSettingsConnectionJa connection = _TranslationsSettingsConnectionJa._(_root);
}

// Path: home
class _TranslationsHomeJa extends TranslationsHomeKo {
	_TranslationsHomeJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override late final _TranslationsHomeTabsJa tabs = _TranslationsHomeTabsJa._(_root);
	@override String get logout_confirm => 'ログアウトしますか？';
	@override String get minimize_error => '最小化中にエラーが発生しました。';
	@override String get invalid_tab => '無効なタブインデックスです。';
}

// Path: app_bar
class _TranslationsAppBarJa extends TranslationsAppBarKo {
	_TranslationsAppBarJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
	@override String get exit_app_desc => 'アプリを終了しますか？ \n終了時に営業状態가自動的にOFFになります。';
	@override String get exit_app_kds_desc => 'アプリを終了しますか？';
	@override String get burst_test_start => '⚡️ 注文ラッシュシミュレーション開始 (10件)';
}

// Path: order_status
class _TranslationsOrderStatusJa extends TranslationsOrderStatusKo {
	_TranslationsOrderStatusJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
	@override String get batch_result_error => 'エラー: 処理中に例外が発生했습니다。';
	@override String get scroll_to_start => '先頭へ';
}

// Path: order_history
class _TranslationsOrderHistoryJa extends TranslationsOrderHistoryKo {
	_TranslationsOrderHistoryJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsProductMgmtJa extends TranslationsProductMgmtKo {
	_TranslationsProductMgmtJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsOrderJa extends TranslationsOrderKo {
	_TranslationsOrderJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsOrderDetailJa extends TranslationsOrderDetailKo {
	_TranslationsOrderDetailJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get loading => '注文詳細情報を読み込んでいます...';
	@override String error_prefix({required Object error}) => 'エラーが発生しました: ${error}';
	@override String get status_update_fail => '注文状態の変更에 失敗했습니다。';
	@override String get dialog_kiosk_cancel_title => '注文取消';
	@override String get dialog_kiosk_cancel_content => 'キオスク注文はキオスク端末で取り消してください。';
	@override String dialog_cancel_confirm_content({required Object n}) => '${n}番의 注文を取り消しますか？';
	@override String get dialog_repickup_confirm_title => 'ピックアップ再要請';
	@override String dialog_repickup_confirm_content({required Object n}) => '${n}番의 注文의 ピックアップを再要請しますか？';
	@override String get dialog_not_picked_up_confirm_title => '未ピックアップ';
	@override String dialog_not_picked_up_confirm_content({required Object n}) => '${n}番의 注文を未ピックアップ処理しますか？';
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
class _TranslationsDialogJa extends TranslationsDialogKo {
	_TranslationsDialogJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override late final _TranslationsDialogStatusChangeJa status_change = _TranslationsDialogStatusChangeJa._(_root);
	@override late final _TranslationsDialogExitJa exit = _TranslationsDialogExitJa._(_root);
	@override late final _TranslationsDialogUpdateJa update = _TranslationsDialogUpdateJa._(_root);
}

// Path: drawer
class _TranslationsDrawerJa extends TranslationsDrawerKo {
	_TranslationsDrawerJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get settings => '設定';
	@override String get logout => 'ログアウト';
	@override String get customer_center => 'カスタマーセンター';
	@override String version({required Object version, required Object build}) => 'バージョン: ${version} (${build})';
	@override String get version_loading => 'バージョン: 読み込み中...';
	@override String get version_error => 'バージョン: エラー';
}

// Path: membership
class _TranslationsMembershipJa extends TranslationsMembershipKo {
	_TranslationsMembershipJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'メンバーシップ照会';
	@override late final _TranslationsMembershipSearchJa search = _TranslationsMembershipSearchJa._(_root);
	@override late final _TranslationsMembershipCustomerJa customer = _TranslationsMembershipCustomerJa._(_root);
	@override late final _TranslationsMembershipTabsJa tabs = _TranslationsMembershipTabsJa._(_root);
	@override late final _TranslationsMembershipHistoryJa history = _TranslationsMembershipHistoryJa._(_root);
	@override late final _TranslationsMembershipDialogJa dialog = _TranslationsMembershipDialogJa._(_root);
	@override late final _TranslationsMembershipKeypadJa keypad = _TranslationsMembershipKeypadJa._(_root);
}

// Path: kds
class _TranslationsKdsJa extends TranslationsKdsKo {
	_TranslationsKdsJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override late final _TranslationsKdsTabsJa tabs = _TranslationsKdsTabsJa._(_root);
	@override String get btn_batch_complete => '一括完了';
	@override String get btn_order_complete => '注文完了';
	@override late final _TranslationsKdsSortJa sort = _TranslationsKdsSortJa._(_root);
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
class _TranslationsLoginTabsJa extends TranslationsLoginTabsKo {
	_TranslationsLoginTabsJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get order => '注文受付';
	@override String get kitchen => 'キッチン(KDS)';
}

// Path: login.overlay_permission
class _TranslationsLoginOverlayPermissionJa extends TranslationsLoginOverlayPermissionKo {
	_TranslationsLoginOverlayPermissionJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '権限が必要';
	@override String get content => '最小化機能を使用するには「다른 앱 위에 표시」権限が必要です。\n今すぐ設定しますか？';
	@override String get set => '設定する';
	@override String get later => '後で';
}

// Path: settings.mode_switch
class _TranslationsSettingsModeSwitchJa extends TranslationsSettingsModeSwitchKo {
	_TranslationsSettingsModeSwitchJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsSettingsAutoStartJa extends TranslationsSettingsAutoStartKo {
	_TranslationsSettingsAutoStartJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'PC起動時に自動実行';
	@override String get desc => 'PC起動時にエージェントを自動的に実行します。';
	@override String get desc_general => 'PC起動時にエージェントを自動的に実行합니다.\n注文を受け付けるには営業中に設定する必要があります。';
	@override String get on => 'ON';
	@override String get off => 'OFF';
}

// Path: settings.auto_receipt
class _TranslationsSettingsAutoReceiptJa extends TranslationsSettingsAutoReceiptKo {
	_TranslationsSettingsAutoReceiptJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ピックアップ注文自動受付';
	@override String get desc => '注文受信時に自動的に受け付けます。';
}

// Path: settings.print_order
class _TranslationsSettingsPrintOrderJa extends TranslationsSettingsPrintOrderKo {
	_TranslationsSettingsPrintOrderJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '注文書出力';
	@override String get desc => '注文書を出力します。';
}

// Path: settings.builtin_printer
class _TranslationsSettingsBuiltinPrinterJa extends TranslationsSettingsBuiltinPrinterKo {
	_TranslationsSettingsBuiltinPrinterJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '内蔵プリンター使用';
	@override String get desc => 'デバイスの内蔵プリンターを使用します。';
}

// Path: settings.external_printer
class _TranslationsSettingsExternalPrinterJa extends TranslationsSettingsExternalPrinterKo {
	_TranslationsSettingsExternalPrinterJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '外部プリンター使用';
	@override String get desc => 'USB接続された外部プリンターを使用します。\n使用時、注文書は設定に従い、レシートは外部プリンターのみで出力されます。';
}

// Path: settings.label_printer
class _TranslationsSettingsLabelPrinterJa extends TranslationsSettingsLabelPrinterKo {
	_TranslationsSettingsLabelPrinterJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ラベルプリンター使用';
	@override String get desc => 'USB接続されたラベルプリンターを使用します。(50mm x 70mm)';
}

// Path: settings.volume
class _TranslationsSettingsVolumeJa extends TranslationsSettingsVolumeKo {
	_TranslationsSettingsVolumeJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知音量設定';
	@override String get desc => '通知音の大きさを調節します。';
}

// Path: settings.sound
class _TranslationsSettingsSoundJa extends TranslationsSettingsSoundKo {
	_TranslationsSettingsSoundJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知音設定';
	@override String get desc => '通知音を選択します。';
	@override String get sound1 => '通知音 1';
	@override String get sound2 => '通知音 2';
}

// Path: settings.alert_count
class _TranslationsSettingsAlertCountJa extends TranslationsSettingsAlertCountKo {
	_TranslationsSettingsAlertCountJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知回数設定';
	@override String get desc => '通知が鳴る回数を設定します。';
	@override String count({required Object n}) => '${n}回';
	@override String get unlimited => '無制限';
}

// Path: settings.print_count
class _TranslationsSettingsPrintCountJa extends TranslationsSettingsPrintCountKo {
	_TranslationsSettingsPrintCountJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '出力枚数';
	@override String get desc => '注文受付時に印刷する伝票枚数を設定します。';
	@override String count({required Object n}) => '${n}枚';
}

// Path: settings.language
class _TranslationsSettingsLanguageJa extends TranslationsSettingsLanguageKo {
	_TranslationsSettingsLanguageJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '言語設定';
	@override String get desc => 'アプリの言語を設定します。';
}

// Path: settings.developer_options
class _TranslationsSettingsDeveloperOptionsJa extends TranslationsSettingsDeveloperOptionsKo {
	_TranslationsSettingsDeveloperOptionsJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '開発者オプション';
	@override late final _TranslationsSettingsDeveloperOptionsAppfitTestJa appfit_test = _TranslationsSettingsDeveloperOptionsAppfitTestJa._(_root);
}

// Path: settings.local_server
class _TranslationsSettingsLocalServerJa extends TranslationsSettingsLocalServerKo {
	_TranslationsSettingsLocalServerJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ローカルサーバー有効化';
	@override String get desc => 'キ오스크で商品状態を照会できる\nローカルサーバーを有効にします。';
	@override String get info => 'サーバー情報';
	@override String ip({required Object ip}) => 'IPアドレス: ${ip}';
	@override String port({required Object port}) => 'ポート: ${port}';
	@override String get started => 'ローカルサーバーが開始されました。';
	@override String get stopped => 'ローカルサーバーが停止しました。';
	@override String url({required Object url}) => 'URL: ${url}';
}

// Path: settings.connection
class _TranslationsSettingsConnectionJa extends TranslationsSettingsConnectionKo {
	_TranslationsSettingsConnectionJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get connected => '接続済み';
	@override String get disconnected => '未接続';
	@override String get reconnect => '再接続';
}

// Path: home.tabs
class _TranslationsHomeTabsJa extends TranslationsHomeTabsKo {
	_TranslationsHomeTabsJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get order_status => '注文状況';
	@override String get order_history => '注文履歴';
	@override String get product_management => '商品管理';
	@override String get membership => 'メンバーシップ';
}

// Path: dialog.status_change
class _TranslationsDialogStatusChangeJa extends TranslationsDialogStatusChangeKo {
	_TranslationsDialogStatusChangeJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsDialogExitJa extends TranslationsDialogExitKo {
	_TranslationsDialogExitJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'アプリ終了';
	@override String get content => '本当に終了しますか？';
	@override String get confirm => '終了';
}

// Path: dialog.update
class _TranslationsDialogUpdateJa extends TranslationsDialogUpdateKo {
	_TranslationsDialogUpdateJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'アプリのアップデート';
	@override String get new_update => '新しいアップデートがあります。';
	@override String get ask_download => 'アップデートをダウンロードしますか？';
	@override String get downloading => 'アップデートをダウンロード中...';
	@override String get download_complete => 'ダウンロードが完了했습니다！';
	@override String get installing => 'アップデート가自動的이インストールされます。';
	@override String get fail => 'ダウンロード失敗';
	@override String get download => 'ダウンロード';
}

// Path: membership.search
class _TranslationsMembershipSearchJa extends TranslationsMembershipSearchKo {
	_TranslationsMembershipSearchJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsMembershipCustomerJa extends TranslationsMembershipCustomerKo {
	_TranslationsMembershipCustomerJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get status_none => '会員情報がありません。';
	@override String honorific({required Object name}) => '${name}様';
	@override String summary({required Object stamps, required Object coupons}) => 'スタンプ ${stamps} | クーポン ${coupons}';
}

// Path: membership.tabs
class _TranslationsMembershipTabsJa extends TranslationsMembershipTabsKo {
	_TranslationsMembershipTabsJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get stamps => 'スタンプ内訳';
	@override String get coupons => 'クーポン使用内訳';
	@override String get available => '保有クーポン';
}

// Path: membership.history
class _TranslationsMembershipHistoryJa extends TranslationsMembershipHistoryKo {
	_TranslationsMembershipHistoryJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _TranslationsMembershipDialogJa extends TranslationsMembershipDialogKo {
	_TranslationsMembershipDialogJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get invalid_barcode => 'サポートされていないバーコード形式です。';
	@override String get enter_phone => '電話番号を入力してください。';
	@override String get cancel_stamp_title => 'スタンプ積立取消';
	@override String cancel_stamp_content({required Object date, required Object count}) => '${date} に積立された ${count}個의 スタンプ積立を取り消しますか？';
	@override String get cancel_coupon_title => 'クーポン使用取消';
	@override String cancel_coupon_content({required Object title}) => '[${title}] クーポンの使用を取り消しますか？';
	@override String get use_coupon_title => 'クーポン使用';
	@override String use_coupon_content({required Object title}) => '${title} クーポンを使用しますか？';
	@override String use_coupon_code_content({required Object code}) => 'クーポンコード [${code}] を使用しますか？';
	@override String get scanner_not_supported => 'QR버코드를 サポートしていない端末입니다.';
	@override String get enter_coupon_code => 'クーポンコードを入力してください。';
	@override String get store_info_missing => '店舗情報가ありません。再度ログインしてください。';
	@override String get input_error_title => '入力エラー';
	@override String get stamp_input_error => 'スタンプ個数は1以上の数字で入力してください。';
	@override String get stamp_limit_error => 'スタンプ個数は20個以下で入力してください。';
	@override String get coupon_info_title => 'クーポン情報';
	@override String coupon_info_content({required Object name, required Object benefit}) => 'クーポン名: ${name}\n特典: ${benefit}\n使用可能です。';
	@override String get processing_complete => '完了';
	@override String get notification => '通知';
}

// Path: membership.keypad
class _TranslationsMembershipKeypadJa extends TranslationsMembershipKeypadKo {
	_TranslationsMembershipKeypadJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get clear => '初期化';
	@override String get delete => '削除';
}

// Path: kds.tabs
class _TranslationsKdsTabsJa extends TranslationsKdsTabsKo {
	_TranslationsKdsTabsJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String all({required Object n}) => '全体 ${n}';
	@override String progress({required Object n}) => '進行 ${n}';
	@override String pickup({required Object n}) => 'ピックアップ ${n}';
	@override String completed({required Object n}) => '完了 ${n}';
	@override String cancelled({required Object n}) => '取消 ${n}';
}

// Path: kds.sort
class _TranslationsKdsSortJa extends TranslationsKdsSortKo {
	_TranslationsKdsSortJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get oldest => '古い順';
	@override String get newest => '新しい順';
}

// Path: settings.developer_options.appfit_test
class _TranslationsSettingsDeveloperOptionsAppfitTestJa extends TranslationsSettingsDeveloperOptionsAppfitTestKo {
	_TranslationsSettingsDeveloperOptionsAppfitTestJa._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'AppFit API テ스트';
	@override String get desc => 'Waldlust Platform AppFit API 設定確認とテスト';
	@override String get btn => 'テスト';
}
