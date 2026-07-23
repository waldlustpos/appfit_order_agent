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
	@override late final _Translations$app$ja app = _Translations$app$ja._(_root);
	@override late final _Translations$common$ja common = _Translations$common$ja._(_root);
	@override late final _Translations$login$ja login = _Translations$login$ja._(_root);
	@override late final _Translations$settings$ja settings = _Translations$settings$ja._(_root);
	@override late final _Translations$home$ja home = _Translations$home$ja._(_root);
	@override late final _Translations$app_bar$ja app_bar = _Translations$app_bar$ja._(_root);
	@override late final _Translations$order_status$ja order_status = _Translations$order_status$ja._(_root);
	@override late final _Translations$order_history$ja order_history = _Translations$order_history$ja._(_root);
	@override late final _Translations$product_mgmt$ja product_mgmt = _Translations$product_mgmt$ja._(_root);
	@override late final _Translations$order$ja order = _Translations$order$ja._(_root);
	@override late final _Translations$order_detail$ja order_detail = _Translations$order_detail$ja._(_root);
	@override late final _Translations$dialog$ja dialog = _Translations$dialog$ja._(_root);
	@override late final _Translations$drawer$ja drawer = _Translations$drawer$ja._(_root);
	@override late final _Translations$membership$ja membership = _Translations$membership$ja._(_root);
	@override late final _Translations$kds$ja kds = _Translations$kds$ja._(_root);
	@override late final _Translations$receipt$ja receipt = _Translations$receipt$ja._(_root);
}

// Path: app
class _Translations$app$ja extends Translations$app$ko {
	_Translations$app$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get name => 'ココナッツ注文エージェント';
}

// Path: common
class _Translations$common$ja extends Translations$common$ko {
	_Translations$common$ja._(TranslationsJa root) : this._root = root, super.internal(root);

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
	@override late final _Translations$common$api_error$ja api_error = _Translations$common$api_error$ja._(_root);
}

// Path: login
class _Translations$login$ja extends Translations$login$ko {
	_Translations$login$ja._(TranslationsJa root) : this._root = root, super.internal(root);

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
	@override late final _Translations$login$tabs$ja tabs = _Translations$login$tabs$ja._(_root);
	@override late final _Translations$login$overlay_permission$ja overlay_permission = _Translations$login$overlay_permission$ja._(_root);
}

// Path: settings
class _Translations$settings$ja extends Translations$settings$ko {
	_Translations$settings$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '設定';
	@override String get save => '保存';
	@override String get save_success => '設定が保存されました。';
	@override String save_error({required Object error}) => '設定の保存中にエラーが発生しました: ${error}';
	@override String get section_mode => 'モード設定';
	@override String get section_general => '一般設定';
	@override String get section_printer => 'プリンター設定';
	@override String get section_sound => '通知設定';
	@override String get section_kiosk => 'キオスク設定';
	@override String get section_server => 'サーバー設定';
	@override String get section_print_count => '印刷設定';
	@override String get section_update => 'アップデート';
	@override late final _Translations$settings$mode_switch$ja mode_switch = _Translations$settings$mode_switch$ja._(_root);
	@override late final _Translations$settings$auto_start$ja auto_start = _Translations$settings$auto_start$ja._(_root);
	@override late final _Translations$settings$auto_receipt$ja auto_receipt = _Translations$settings$auto_receipt$ja._(_root);
	@override late final _Translations$settings$print_order$ja print_order = _Translations$settings$print_order$ja._(_root);
	@override late final _Translations$settings$builtin_printer$ja builtin_printer = _Translations$settings$builtin_printer$ja._(_root);
	@override late final _Translations$settings$external_printer$ja external_printer = _Translations$settings$external_printer$ja._(_root);
	@override late final _Translations$settings$label_printer$ja label_printer = _Translations$settings$label_printer$ja._(_root);
	@override late final _Translations$settings$label_qr$ja label_qr = _Translations$settings$label_qr$ja._(_root);
	@override late final _Translations$settings$volume$ja volume = _Translations$settings$volume$ja._(_root);
	@override late final _Translations$settings$sound$ja sound = _Translations$settings$sound$ja._(_root);
	@override late final _Translations$settings$alert_count$ja alert_count = _Translations$settings$alert_count$ja._(_root);
	@override late final _Translations$settings$print_count$ja print_count = _Translations$settings$print_count$ja._(_root);
	@override late final _Translations$settings$language$ja language = _Translations$settings$language$ja._(_root);
	@override late final _Translations$settings$theme$ja theme = _Translations$settings$theme$ja._(_root);
	@override late final _Translations$settings$dual_monitor$ja dual_monitor = _Translations$settings$dual_monitor$ja._(_root);
	@override late final _Translations$settings$currency$ja currency = _Translations$settings$currency$ja._(_root);
	@override late final _Translations$settings$display_rotate$ja display_rotate = _Translations$settings$display_rotate$ja._(_root);
	@override late final _Translations$settings$order_type_badge$ja order_type_badge = _Translations$settings$order_type_badge$ja._(_root);
	@override late final _Translations$settings$order_source_color$ja order_source_color = _Translations$settings$order_source_color$ja._(_root);
	@override late final _Translations$settings$kds_ignore_status$ja kds_ignore_status = _Translations$settings$kds_ignore_status$ja._(_root);
	@override late final _Translations$settings$kds_accept_orders$ja kds_accept_orders = _Translations$settings$kds_accept_orders$ja._(_root);
	@override late final _Translations$settings$label_filter$ja label_filter = _Translations$settings$label_filter$ja._(_root);
	@override late final _Translations$settings$label_layout$ja label_layout = _Translations$settings$label_layout$ja._(_root);
	@override late final _Translations$settings$label_qr_payload$ja label_qr_payload = _Translations$settings$label_qr_payload$ja._(_root);
	@override late final _Translations$settings$developer_options$ja developer_options = _Translations$settings$developer_options$ja._(_root);
	@override late final _Translations$settings$kiosk$ja kiosk = _Translations$settings$kiosk$ja._(_root);
	@override late final _Translations$settings$local_server$ja local_server = _Translations$settings$local_server$ja._(_root);
	@override late final _Translations$settings$connection$ja connection = _Translations$settings$connection$ja._(_root);
	@override late final _Translations$settings$soundgraph$ja soundgraph = _Translations$settings$soundgraph$ja._(_root);
	@override late final _Translations$settings$app_update$ja app_update = _Translations$settings$app_update$ja._(_root);
	@override late final _Translations$settings$log_collection$ja log_collection = _Translations$settings$log_collection$ja._(_root);
}

// Path: home
class _Translations$home$ja extends Translations$home$ko {
	_Translations$home$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override late final _Translations$home$tabs$ja tabs = _Translations$home$tabs$ja._(_root);
	@override String get logout_confirm => 'ログアウトしますか？';
	@override String get minimize_error => '最小化中にエラーが発生しました。';
	@override String get invalid_tab => '無効なタブインデックスです。';
}

// Path: app_bar
class _Translations$app_bar$ja extends Translations$app_bar$ko {
	_Translations$app_bar$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get time_loading => '日付読み込み中...';
	@override String get time_error => '時刻読み込みエラー';
	@override String get morning => '午前';
	@override String get afternoon => '午後';
	@override String new_order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(n,
		other: '新規 ${n} 件',
	);
	@override String get kds_mode => 'キッチンモニター(KDS)';
	@override String get order_toggle => 'オーダー';
	@override String get order_start_confirm_title => 'オーダー開始確認';
	@override String get order_stop_confirm_title => 'オーダー停止確認';
	@override String get order_start_confirm_content => '営業中に変更しますか？';
	@override String get order_stop_confirm_content => '準備中に変更しますか？';
	@override String get exit_app => 'アプリ終了';
	@override String get exit_app_desc => 'アプリを終了しますか？';
	@override String get exit_app_kds_desc => 'アプリを終了しますか？';
	@override String get store_closed_notice => '店舗が「準備中」に変更されます。';
	@override String get burst_test_start => '⚡️ 注文ラッシュシミュレーション開始 (10件)';
}

// Path: order_status
class _Translations$order_status$ja extends Translations$order_status$ko {
	_Translations$order_status$ja._(TranslationsJa root) : this._root = root, super.internal(root);

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
	@override String get batch_result_error => 'エラー: 処理中に例外が発生しました。';
	@override String get scroll_to_start => '先頭へ';
	@override String get scroll_to_end => '最後へ';
}

// Path: order_history
class _Translations$order_history$ja extends Translations$order_history$ko {
	_Translations$order_history$ja._(TranslationsJa root) : this._root = root, super.internal(root);

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
class _Translations$product_mgmt$ja extends Translations$product_mgmt$ko {
	_Translations$product_mgmt$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '商品管理';
	@override String get search_placeholder => '商品名検索';
	@override String get all => '全体';
	@override String get sold_out => '品切れ';
	@override String count({required Object n}) => '${n}個';
	@override String total_count({required Object n}) => '全体 ${n}個';
	@override String error_load({required Object error}) => '商品リストの読み込み中にエラーが発生しました。\n${error}';
	@override String get dialog_hidden_title => '非表示処理';
	@override String dialog_hidden_content({required Object name}) => '[ ${name} ] を非表示(キー削除)にしますか？';
	@override String get btn_hidden => '非表示(キー削除)';
}

// Path: order
class _Translations$order$ja extends Translations$order$ko {
	_Translations$order$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get new_order => '新規';
	@override String get preparing => '受付';
	@override String get ready => 'ピックアップ';
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
	@override String ordered_time_short({required Object time}) => '${time} 注文';
	@override late final _Translations$order$payment_method$ja payment_method = _Translations$order$payment_method$ja._(_root);
	@override late final _Translations$order$discount_type$ja discount_type = _Translations$order$discount_type$ja._(_root);
}

// Path: order_detail
class _Translations$order_detail$ja extends Translations$order_detail$ko {
	_Translations$order_detail$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
	@override String dialog_complete_confirm_content({required Object n}) => '${n}番の注文を完了処理しますか？';
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
class _Translations$dialog$ja extends Translations$dialog$ko {
	_Translations$dialog$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override late final _Translations$dialog$status_change$ja status_change = _Translations$dialog$status_change$ja._(_root);
	@override late final _Translations$dialog$exit$ja exit = _Translations$dialog$exit$ja._(_root);
	@override late final _Translations$dialog$update$ja update = _Translations$dialog$update$ja._(_root);
}

// Path: drawer
class _Translations$drawer$ja extends Translations$drawer$ko {
	_Translations$drawer$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get product_management => '商品管理';
	@override String get settings => '設定';
	@override String get logout => 'ログアウト';
	@override String get customer_center => 'カスタマーセンター';
	@override String version({required Object version, required Object build}) => 'バージョン: ${version} (${build})';
	@override String get version_loading => 'バージョン: 読み込み中...';
	@override String get version_error => 'バージョン: エラー';
}

// Path: membership
class _Translations$membership$ja extends Translations$membership$ko {
	_Translations$membership$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'メンバーシップ照会';
	@override late final _Translations$membership$search$ja search = _Translations$membership$search$ja._(_root);
	@override late final _Translations$membership$customer$ja customer = _Translations$membership$customer$ja._(_root);
	@override late final _Translations$membership$tabs$ja tabs = _Translations$membership$tabs$ja._(_root);
	@override late final _Translations$membership$history$ja history = _Translations$membership$history$ja._(_root);
	@override late final _Translations$membership$dialog$ja dialog = _Translations$membership$dialog$ja._(_root);
	@override late final _Translations$membership$keypad$ja keypad = _Translations$membership$keypad$ja._(_root);
}

// Path: kds
class _Translations$kds$ja extends Translations$kds$ko {
	_Translations$kds$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override late final _Translations$kds$tabs$ja tabs = _Translations$kds$tabs$ja._(_root);
	@override String get btn_batch_complete => '一括完了';
	@override String get btn_order_complete => '注文完了';
	@override late final _Translations$kds$sort$ja sort = _Translations$kds$sort$ja._(_root);
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

// Path: receipt
class _Translations$receipt$ja extends Translations$receipt$ko {
	_Translations$receipt$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get cancel_receipt => '取消領収書';
	@override String get cancel_order => '取消注文書';
	@override String get order_no => '注文番号';
	@override String get datetime => '日時';
	@override String get col_menu => 'メニュー';
	@override String get col_qty => '数量';
	@override String get col_amount => '金額';
	@override String get taxable => '課税額';
	@override String get vat => '消費税';
	@override String get order_amount => '注文金額';
	@override String get discount_amount => '割引額';
	@override String get payment_amount => '支払金額';
	@override String get kiosk => 'キオスク';
	@override String get customer_suffix => '様';
	@override String get section_option => 'オプション';
	@override String get section_detail => '詳細';
	@override String get test_port => 'ポート';
	@override String get test_board => 'ボーレート';
	@override String get test_ok => '印刷正常';
}

// Path: common.api_error
class _Translations$common$api_error$ja extends Translations$common$api_error$ko {
	_Translations$common$api_error$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get network => 'ネットワーク接続を確認してください。';
	@override String get timeout => 'サーバーの応答が遅れています。しばらくしてからもう一度お試しください。';
	@override String get auth => '認証の有効期限が切れました。再度ログインしてください。';
	@override String get not_found => 'リクエストされた情報が見つかりませんでした。';
	@override String get server => '一時的なサーバーエラーが発生しました。しばらくしてからもう一度お試しください。';
	@override String get generic => 'リクエストを処理できませんでした。しばらくしてからもう一度お試しください。';
}

// Path: login.tabs
class _Translations$login$tabs$ja extends Translations$login$tabs$ko {
	_Translations$login$tabs$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get order => '注文受付';
	@override String get kitchen => 'キッチン(KDS)';
}

// Path: login.overlay_permission
class _Translations$login$overlay_permission$ja extends Translations$login$overlay_permission$ko {
	_Translations$login$overlay_permission$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '権限が必要';
	@override String get content => '最小化機能を使用するには「他のアプリの上に表示」権限が必要です。\n今すぐ設定しますか？';
	@override String get set => '設定する';
	@override String get later => '後で';
}

// Path: settings.mode_switch
class _Translations$settings$mode_switch$ja extends Translations$settings$mode_switch$ko {
	_Translations$settings$mode_switch$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get to_main => 'メインに切替';
	@override String get to_kds => 'キッチンモニター(KDS)に切替';
	@override String get confirm_to_main => 'メイン（注文受付）に切り替えますか？';
	@override String get confirm_to_kds => '状態別カードで表示するキッチン専用画面です。\n「注文受付」がOFFのため処理されません。\n受け付けるには「注文受付」をONにします。';
	@override String get btn_switch => '切替';
	@override String get desc_to_main => '注文受付画面に変更します。';
	@override String get desc_to_kds => 'キッチンモニター(KDS)画面に変更します。';
}

// Path: settings.auto_start
class _Translations$settings$auto_start$ja extends Translations$settings$auto_start$ko {
	_Translations$settings$auto_start$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'PC起動時に自動実行';
	@override String get desc => 'PC起動時にエージェントを自動的に実行します。';
	@override String get desc_general => 'PC起動時にエージェントを自動的に実行します。\n注文を受け付けるには営業中に設定する必要があります。';
	@override String get on => 'ON';
	@override String get off => 'OFF';
}

// Path: settings.auto_receipt
class _Translations$settings$auto_receipt$ja extends Translations$settings$auto_receipt$ko {
	_Translations$settings$auto_receipt$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ピックアップ注文自動受付';
	@override String get desc => '注文受信時に自動的に受け付けます。';
}

// Path: settings.print_order
class _Translations$settings$print_order$ja extends Translations$settings$print_order$ko {
	_Translations$settings$print_order$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '注文書出力';
	@override String get desc => '注文書を出力します。';
}

// Path: settings.builtin_printer
class _Translations$settings$builtin_printer$ja extends Translations$settings$builtin_printer$ko {
	_Translations$settings$builtin_printer$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '内蔵プリンター使用';
	@override String get desc => 'デバイスの内蔵プリンターを使用します。';
	@override String get detected => 'このデバイスで内蔵プリンターを検出しました。';
	@override String get not_detected => 'このデバイスで内蔵プリンターを検出できませんでした。(Sunmi端末の内蔵モジュールのみ対応)';
}

// Path: settings.external_printer
class _Translations$settings$external_printer$ja extends Translations$settings$external_printer$ko {
	_Translations$settings$external_printer$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '外部プリンター使用';
	@override String get desc => 'USB接続された外部プリンターを使用します。\n使用時、注文書は設定に従い、レシートは外部プリンターのみで出力されます。';
}

// Path: settings.label_printer
class _Translations$settings$label_printer$ja extends Translations$settings$label_printer$ko {
	_Translations$settings$label_printer$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ラベルプリンター使用';
	@override String get desc => 'USB接続されたラベルプリンターを使用します。(50mm x 70mm)\n対応モデル: REXOD RXLA-561、BIXOLON XD5-40d';
}

// Path: settings.label_qr
class _Translations$settings$label_qr$ja extends Translations$settings$label_qr$ko {
	_Translations$settings$label_qr$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'QRコード出力';
	@override String get desc => 'ラベルに注文識別用のQRコードを印刷します。';
}

// Path: settings.volume
class _Translations$settings$volume$ja extends Translations$settings$volume$ko {
	_Translations$settings$volume$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知音量設定';
	@override String get desc => '通知音の大きさを調節します。';
}

// Path: settings.sound
class _Translations$settings$sound$ja extends Translations$settings$sound$ko {
	_Translations$settings$sound$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知音設定';
	@override String get desc => '通知音を選択します。';
	@override String get sound1 => '通知音 1';
	@override String get sound2 => '通知音 2';
}

// Path: settings.alert_count
class _Translations$settings$alert_count$ja extends Translations$settings$alert_count$ko {
	_Translations$settings$alert_count$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通知回数設定';
	@override String get desc => '通知が鳴る回数を設定します。';
	@override String count({required Object n}) => '${n}回';
	@override String get unlimited => '無制限';
}

// Path: settings.print_count
class _Translations$settings$print_count$ja extends Translations$settings$print_count$ko {
	_Translations$settings$print_count$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '出力枚数';
	@override String get desc => '注文受付時に印刷する伝票枚数を設定します。';
	@override String count({required Object n}) => '${n}枚';
}

// Path: settings.language
class _Translations$settings$language$ja extends Translations$settings$language$ko {
	_Translations$settings$language$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '言語設定';
	@override String get desc => 'アプリの言語を設定します。';
}

// Path: settings.theme
class _Translations$settings$theme$ja extends Translations$settings$theme$ko {
	_Translations$settings$theme$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'テーマ';
	@override String get desc => 'アプリ全体のブランドカラーとロゴを変更します。';
	@override String get restart_title => '再起動が必要';
	@override String get restart_message => 'テーマ変更を適用するにはアプリを再起動する必要があります。今すぐ再起動しますか？';
	@override String get restart_now => '今すぐ再起動';
	@override String get restart_later => '後で';
	@override late final _Translations$settings$theme$options$ja options = _Translations$settings$theme$options$ja._(_root);
}

// Path: settings.dual_monitor
class _Translations$settings$dual_monitor$ja extends Translations$settings$dual_monitor$ko {
	_Translations$settings$dual_monitor$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'フロントモニター表示';
	@override String get desc => 'サブディスプレイに表示するブランドコンテンツを選択します。';
	@override String get option_video => '動画';
	@override String get option_image => '画像';
	@override String get option_none => '非表示';
}

// Path: settings.currency
class _Translations$settings$currency$ja extends Translations$settings$currency$ko {
	_Translations$settings$currency$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '通貨単位設定';
	@override String get desc => '金額表示に使用する通貨単位を選択します。';
	@override String get krw => 'ウォン (₩)';
	@override String get jpy => '円 (¥)';
}

// Path: settings.display_rotate
class _Translations$settings$display_rotate$ja extends Translations$settings$display_rotate$ko {
	_Translations$settings$display_rotate$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '画面上下反転';
	@override String get desc => '画面を180度回転します。OS側に回転設定がない環境で使用します。';
}

// Path: settings.order_type_badge
class _Translations$settings$order_type_badge$ja extends Translations$settings$order_type_badge$ko {
	_Translations$settings$order_type_badge$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '店内/持ち帰り表示';
	@override String get desc => '注文詳細ヘッダーに店内/持ち帰りバッジを表示します。';
}

// Path: settings.order_source_color
class _Translations$settings$order_source_color$ja extends Translations$settings$order_source_color$ko {
	_Translations$settings$order_source_color$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '注文元別の色分け';
	@override String get desc => 'アプリ注文とキオスク注文をカード背景色で区別します。';
}

// Path: settings.kds_ignore_status
class _Translations$settings$kds_ignore_status$ja extends Translations$settings$kds_ignore_status$ko {
	_Translations$settings$kds_ignore_status$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '他端末の進行状態通知を無視';
	@override String get desc => '他のキッチンモニター(KDS)でピックアップ要請などの進行状態を変更しても、この画面の注文は更新されません。(進行状態の更新を手動で管理したい場合に使用)';
}

// Path: settings.kds_accept_orders
class _Translations$settings$kds_accept_orders$ja extends Translations$settings$kds_accept_orders$ko {
	_Translations$settings$kds_accept_orders$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '注文受付';
	@override String get desc => 'キッチンモニター(KDS)で注文を直接自動受付処理します。他のメイン注文受付プログラムと併用しないよう必ずご確認ください。';
	@override String get confirm_title => '注文受付を有効化';
	@override String get confirm_content => 'キッチンモニター(KDS)で注文の自動受付を直接実行します。\n他のメイン注文受付プログラムと併用しないよう必ずご確認ください。\n有効にしますか?';
}

// Path: settings.label_filter
class _Translations$settings$label_filter$ja extends Translations$settings$label_filter$ko {
	_Translations$settings$label_filter$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ラベル印刷フィルター';
	@override String get desc_all => '全注文商品のラベルを印刷します。';
	@override String get desc_waffle_only => 'デザート(ワッフル)商品のみラベルを印刷します。';
	@override String get desc_waffle_exclude => 'デザート(ワッフル)商品を除いてラベルを印刷します。';
	@override String get btn_all => '全注文印刷';
	@override String get btn_waffle_only => 'ワッフルのみ';
	@override String get btn_waffle_exclude => 'ワッフル除外';
}

// Path: settings.label_layout
class _Translations$settings$label_layout$ja extends Translations$settings$label_layout$ko {
	_Translations$settings$label_layout$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ラベルレイアウト';
	@override String get desc_v1 => '従来のレイアウトでラベルを印刷します。';
	@override String get desc_v2 => '新しいレイアウト(QR右上・商品名下部)でラベルを印刷します。';
	@override String get btn_v1 => '標準 (V1)';
	@override String get btn_v2 => '新規 (V2)';
}

// Path: settings.label_qr_payload
class _Translations$settings$label_qr_payload$ja extends Translations$settings$label_qr_payload$ko {
	_Translations$settings$label_qr_payload$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'ラベルQRフォーマット';
	@override String get desc_legacy => '従来のフォーマットでQRを生成します。(注文番号-商品ID-カップ順番)';
	@override String get desc_new => '新規(テスト)フォーマットでQRを生成します。(表示番号-カップ順番)';
	@override String get btn_legacy => '従来';
	@override String get btn_new => '新規';
}

// Path: settings.developer_options
class _Translations$settings$developer_options$ja extends Translations$settings$developer_options$ko {
	_Translations$settings$developer_options$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => '開発者オプション';
	@override late final _Translations$settings$developer_options$appfit_test$ja appfit_test = _Translations$settings$developer_options$appfit_test$ja._(_root);
}

// Path: settings.kiosk
class _Translations$settings$kiosk$ja extends Translations$settings$kiosk$ko {
	_Translations$settings$kiosk$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get visible_title => 'キオスク注文の表示';
	@override String get visible_desc => 'キオスク注文を画面に表示します。';
	@override String get sound_title => 'キオスク注文の注文票と通知音';
	@override String get sound_desc => 'キオスク注文受信時に注文票を出力し、通知音を再生します。';
}

// Path: settings.local_server
class _Translations$settings$local_server$ja extends Translations$settings$local_server$ko {
	_Translations$settings$local_server$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _Translations$settings$connection$ja extends Translations$settings$connection$ko {
	_Translations$settings$connection$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get connected => '接続済み';
	@override String get disconnected => '未接続';
	@override String get reconnect => '再接続';
}

// Path: settings.soundgraph
class _Translations$settings$soundgraph$ja extends Translations$settings$soundgraph$ko {
	_Translations$settings$soundgraph$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'SoundGraph 注文送信';
	@override String get desc => '注文受付時にSoundGraphへ注文情報を送信します。';
	@override String get market_id_placeholder => 'MARKET IDを入力';
	@override String get market_id_dialog_title => 'MARKET IDを入力';
	@override String get market_id_dialog_save => '保存';
	@override String get market_id_dialog_cancel => 'キャンセル';
}

// Path: settings.app_update
class _Translations$settings$app_update$ja extends Translations$settings$app_update$ko {
	_Translations$settings$app_update$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get auto_check_title => '起動時にアプリ更新を確認';
	@override String get auto_check_desc => 'アプリ起動時に自動的に最新バージョンを確認します。';
	@override String get manual_title => 'アプリ更新';
	@override String version_info({required Object currentVersion, required Object latestVersion}) => '現在: v${currentVersion} / 最新: v${latestVersion}';
	@override String get up_to_date => '最新バージョンです。';
	@override String get checking => 'バージョン確認中...';
	@override String get check_failed => 'バージョン確認に失敗しました';
	@override String get update_btn => '更新';
	@override String get check_btn => 'バージョン確認';
}

// Path: settings.log_collection
class _Translations$settings$log_collection$ja extends Translations$settings$log_collection$ko {
	_Translations$settings$log_collection$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get section_title => 'ログ送信';
	@override String get section_desc => '選択した期間のログを圧縮して Slack に送信します。';
	@override String get store_label => '店舗';
	@override String get brand_label => 'ブランド';
	@override String get store_name_label => '店舗名';
	@override String get store_code_label => '店舗コード';
	@override String get device_label => '端末';
	@override String get range_today => '今日';
	@override String get range_7days => '直近7日';
	@override String get range_30days => '直近30日';
	@override String get send_btn => 'ログ送信';
	@override String get stage_flushing => 'ログ整理中...';
	@override String get stage_collecting => 'ログ収集中...';
	@override String get stage_zipping => '圧縮中...';
	@override String get stage_uploading => 'アップロード中...';
	@override String success({required Object count, required Object size}) => '送信完了 (${count}件, ${size})';
	@override String failed({required Object error}) => '送信失敗: ${error}';
	@override String get not_configured => 'Slack 送信設定がありません。ビルド設定を確認してください。';
}

// Path: home.tabs
class _Translations$home$tabs$ja extends Translations$home$tabs$ko {
	_Translations$home$tabs$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get order_status => '注文状況';
	@override String get order_history => '注文履歴';
	@override String get product_management => '商品管理';
	@override String get membership => 'メンバーシップ';
}

// Path: order.payment_method
class _Translations$order$payment_method$ja extends Translations$order$payment_method$ko {
	_Translations$order$payment_method$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get credit_card => 'クレジットカード';
	@override String get prepaid_card => 'プリペイドカード';
	@override String get naver_pay => 'Naver Pay';
	@override String get kakao_pay => 'Kakao Pay';
	@override String get toss_pay => 'Toss Pay';
	@override String get apple_pay => 'Apple Pay';
	@override String get payco => 'PAYCO';
	@override String get easy_card => '電子マネー';
	@override String get mobile_payment => 'モバイル決済';
	@override String get qr_payment => 'QR決済';
	@override String get felica_transportation => 'Felica交通系';
	@override String get felica_id => 'Felica iD';
	@override String get felica_quicpay => 'Felica QUICPay';
	@override String get cash => '現金';
	@override String get service => 'サービス';
}

// Path: order.discount_type
class _Translations$order$discount_type$ja extends Translations$order$discount_type$ko {
	_Translations$order$discount_type$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get coupon => 'クーポン';
	@override String get point => 'ポイント';
	@override String get gift => 'ギフト';
	@override String get partner => '提携';
	@override String get membership => 'メンバーシップ';
}

// Path: dialog.status_change
class _Translations$dialog$status_change$ja extends Translations$dialog$status_change$ko {
	_Translations$dialog$status_change$ja._(TranslationsJa root) : this._root = root, super.internal(root);

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
class _Translations$dialog$exit$ja extends Translations$dialog$exit$ko {
	_Translations$dialog$exit$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'アプリ終了';
	@override String get content => '本当に終了しますか？';
	@override String get confirm => '終了';
}

// Path: dialog.update
class _Translations$dialog$update$ja extends Translations$dialog$update$ko {
	_Translations$dialog$update$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
class _Translations$membership$search$ja extends Translations$membership$search$ko {
	_Translations$membership$search$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get hint => '電話番号またはクーポン番号を入力してください。';
	@override String get hint_searched => 'スタンプの個数を入力してください。(最大20個まで)';
	@override String get btn_search => '会員照会';
	@override String get btn_other_member => '検索リセット';
	@override String get btn_save_stamp => 'スタンプ積立';
	@override String get btn_use_coupon => 'クーポン使用';
	@override String get btn_scan => 'バーコードスキャン';
}

// Path: membership.customer
class _Translations$membership$customer$ja extends Translations$membership$customer$ko {
	_Translations$membership$customer$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get status_none => '会員情報がありません。';
	@override String honorific({required Object name}) => '${name}様';
	@override String summary({required Object stamps, required Object coupons}) => 'スタンプ ${stamps} | クーポン ${coupons}';
}

// Path: membership.tabs
class _Translations$membership$tabs$ja extends Translations$membership$tabs$ko {
	_Translations$membership$tabs$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get stamps => 'スタンプ内訳';
	@override String get coupons => 'クーポン履歴';
	@override String get available => '保有クーポン';
}

// Path: membership.history
class _Translations$membership$history$ja extends Translations$membership$history$ko {
	_Translations$membership$history$ja._(TranslationsJa root) : this._root = root, super.internal(root);

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
	@override String get status_used => '使用完了';
	@override String get stamp_status_issued => '積立';
	@override String get stamp_status_canceled => 'キャンセル';
	@override String get stamp_status_expired => '期限切れ';
	@override String get stamp_status_used => 'クーポン変換';
	@override String get prev_page => '前のページ';
	@override String get next_page => '次のページ';
}

// Path: membership.dialog
class _Translations$membership$dialog$ja extends Translations$membership$dialog$ko {
	_Translations$membership$dialog$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

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
	@override String get processing_complete => '完了';
	@override String get notification => '通知';
}

// Path: membership.keypad
class _Translations$membership$keypad$ja extends Translations$membership$keypad$ko {
	_Translations$membership$keypad$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get clear => '初期化';
	@override String get delete => '削除';
}

// Path: kds.tabs
class _Translations$kds$tabs$ja extends Translations$kds$tabs$ko {
	_Translations$kds$tabs$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String all({required Object n}) => '全体 ${n}';
	@override String progress({required Object n}) => '進行 ${n}';
	@override String pickup({required Object n}) => 'ピックアップ ${n}';
	@override String completed({required Object n}) => '完了 ${n}';
	@override String cancelled({required Object n}) => '取消 ${n}';
}

// Path: kds.sort
class _Translations$kds$sort$ja extends Translations$kds$sort$ko {
	_Translations$kds$sort$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get oldest => '古い順';
	@override String get newest => '新しい順';
}

// Path: settings.theme.options
class _Translations$settings$theme$options$ja extends Translations$settings$theme$options$ko {
	_Translations$settings$theme$options$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get appfit_default => 'デフォルト';
	@override String get mammoth_coffee => '매머드커피';
	@override String get mata => '마하테이스트';
	@override String get paik => '빽다방재팬';
}

// Path: settings.developer_options.appfit_test
class _Translations$settings$developer_options$appfit_test$ja extends Translations$settings$developer_options$appfit_test$ko {
	_Translations$settings$developer_options$appfit_test$ja._(TranslationsJa root) : this._root = root, super.internal(root);

	final TranslationsJa _root; // ignore: unused_field

	// Translations
	@override String get title => 'AppFit API テスト';
	@override String get desc => 'Waldlust Platform AppFit API 設定確認とテスト';
	@override String get btn => 'テスト';
}
