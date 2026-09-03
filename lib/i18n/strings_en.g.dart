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
class TranslationsEn extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEn({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	late final TranslationsEn _root = this; // ignore: unused_field

	@override 
	TranslationsEn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEn(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$app$en app = _Translations$app$en._(_root);
	@override late final _Translations$common$en common = _Translations$common$en._(_root);
	@override late final _Translations$login$en login = _Translations$login$en._(_root);
	@override late final _Translations$settings$en settings = _Translations$settings$en._(_root);
	@override late final _Translations$home$en home = _Translations$home$en._(_root);
	@override late final _Translations$app_bar$en app_bar = _Translations$app_bar$en._(_root);
	@override late final _Translations$order_status$en order_status = _Translations$order_status$en._(_root);
	@override late final _Translations$order_history$en order_history = _Translations$order_history$en._(_root);
	@override late final _Translations$product_mgmt$en product_mgmt = _Translations$product_mgmt$en._(_root);
	@override late final _Translations$order$en order = _Translations$order$en._(_root);
	@override late final _Translations$order_detail$en order_detail = _Translations$order_detail$en._(_root);
	@override late final _Translations$dialog$en dialog = _Translations$dialog$en._(_root);
	@override late final _Translations$drawer$en drawer = _Translations$drawer$en._(_root);
	@override late final _Translations$membership$en membership = _Translations$membership$en._(_root);
	@override late final _Translations$kds$en kds = _Translations$kds$en._(_root);
	@override late final _Translations$receipt$en receipt = _Translations$receipt$en._(_root);
	@override late final _Translations$label_category_select$en label_category_select = _Translations$label_category_select$en._(_root);
	@override late final _Translations$label_subinfo_select$en label_subinfo_select = _Translations$label_subinfo_select$en._(_root);
}

// Path: app
class _Translations$app$en extends Translations$app$ko {
	_Translations$app$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get name => 'Kokonut Order Agent';
}

// Path: common
class _Translations$common$en extends Translations$common$ko {
	_Translations$common$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
	@override late final _Translations$common$api_error$en api_error = _Translations$common$api_error$en._(_root);
}

// Path: login
class _Translations$login$en extends Translations$login$ko {
	_Translations$login$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
	@override late final _Translations$login$tabs$en tabs = _Translations$login$tabs$en._(_root);
	@override late final _Translations$login$kds_notice$en kds_notice = _Translations$login$kds_notice$en._(_root);
	@override late final _Translations$login$overlay_permission$en overlay_permission = _Translations$login$overlay_permission$en._(_root);
}

// Path: settings
class _Translations$settings$en extends Translations$settings$ko {
	_Translations$settings$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Settings';
	@override String get save => 'Save';
	@override String get save_success => 'Settings saved.';
	@override String save_error({required Object error}) => 'Error saving settings: ${error}';
	@override String get section_mode => 'Mode';
	@override String get section_general => 'General';
	@override String get section_printer => 'Printer';
	@override String get section_sound => 'Notifications';
	@override String get section_kiosk => 'Kiosk';
	@override String get section_pos => 'POS Orders';
	@override String get section_server => 'Server';
	@override String get section_print_count => 'Print';
	@override String get section_update => 'Updates';
	@override late final _Translations$settings$mode_switch$en mode_switch = _Translations$settings$mode_switch$en._(_root);
	@override late final _Translations$settings$auto_start$en auto_start = _Translations$settings$auto_start$en._(_root);
	@override late final _Translations$settings$auto_receipt$en auto_receipt = _Translations$settings$auto_receipt$en._(_root);
	@override late final _Translations$settings$print_order$en print_order = _Translations$settings$print_order$en._(_root);
	@override late final _Translations$settings$builtin_printer$en builtin_printer = _Translations$settings$builtin_printer$en._(_root);
	@override late final _Translations$settings$external_printer$en external_printer = _Translations$settings$external_printer$en._(_root);
	@override late final _Translations$settings$label_printer$en label_printer = _Translations$settings$label_printer$en._(_root);
	@override late final _Translations$settings$label_qr$en label_qr = _Translations$settings$label_qr$en._(_root);
	@override late final _Translations$settings$volume$en volume = _Translations$settings$volume$en._(_root);
	@override late final _Translations$settings$sound$en sound = _Translations$settings$sound$en._(_root);
	@override late final _Translations$settings$alert_count$en alert_count = _Translations$settings$alert_count$en._(_root);
	@override late final _Translations$settings$print_count$en print_count = _Translations$settings$print_count$en._(_root);
	@override late final _Translations$settings$language$en language = _Translations$settings$language$en._(_root);
	@override late final _Translations$settings$theme$en theme = _Translations$settings$theme$en._(_root);
	@override late final _Translations$settings$dual_monitor$en dual_monitor = _Translations$settings$dual_monitor$en._(_root);
	@override late final _Translations$settings$currency$en currency = _Translations$settings$currency$en._(_root);
	@override late final _Translations$settings$display_rotate$en display_rotate = _Translations$settings$display_rotate$en._(_root);
	@override late final _Translations$settings$order_type_badge$en order_type_badge = _Translations$settings$order_type_badge$en._(_root);
	@override late final _Translations$settings$print_show_order_type$en print_show_order_type = _Translations$settings$print_show_order_type$en._(_root);
	@override late final _Translations$settings$order_source_color$en order_source_color = _Translations$settings$order_source_color$en._(_root);
	@override late final _Translations$settings$kds_ignore_status$en kds_ignore_status = _Translations$settings$kds_ignore_status$en._(_root);
	@override late final _Translations$settings$kds_accept_orders$en kds_accept_orders = _Translations$settings$kds_accept_orders$en._(_root);
	@override late final _Translations$settings$label_category_filter$en label_category_filter = _Translations$settings$label_category_filter$en._(_root);
	@override late final _Translations$settings$label_subinfo$en label_subinfo = _Translations$settings$label_subinfo$en._(_root);
	@override late final _Translations$settings$label_paper$en label_paper = _Translations$settings$label_paper$en._(_root);
	@override late final _Translations$settings$developer_options$en developer_options = _Translations$settings$developer_options$en._(_root);
	@override late final _Translations$settings$kiosk$en kiosk = _Translations$settings$kiosk$en._(_root);
	@override late final _Translations$settings$pos$en pos = _Translations$settings$pos$en._(_root);
	@override late final _Translations$settings$local_server$en local_server = _Translations$settings$local_server$en._(_root);
	@override late final _Translations$settings$connection$en connection = _Translations$settings$connection$en._(_root);
	@override late final _Translations$settings$soundgraph$en soundgraph = _Translations$settings$soundgraph$en._(_root);
	@override late final _Translations$settings$app_update$en app_update = _Translations$settings$app_update$en._(_root);
	@override late final _Translations$settings$log_collection$en log_collection = _Translations$settings$log_collection$en._(_root);
}

// Path: home
class _Translations$home$en extends Translations$home$ko {
	_Translations$home$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$home$tabs$en tabs = _Translations$home$tabs$en._(_root);
	@override String get logout_confirm => 'Are you sure you want to logout?';
	@override String get minimize_error => 'An error occurred while minimizing the app.';
	@override String get invalid_tab => 'Invalid tab index.';
}

// Path: app_bar
class _Translations$app_bar$en extends Translations$app_bar$ko {
	_Translations$app_bar$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get time_loading => 'Loading date...';
	@override String get time_error => 'Time load error';
	@override String get morning => 'AM';
	@override String get afternoon => 'PM';
	@override String new_order_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 New Order',
		other: '${n} New Orders',
	);
	@override String get kds_mode => 'Kitchen Display (KDS)';
	@override String get order_toggle => 'Order';
	@override String get order_start_confirm_title => 'Confirm Order Start';
	@override String get order_stop_confirm_title => 'Confirm Order Stop';
	@override String get order_start_confirm_content => 'Change status to Open?';
	@override String get order_stop_confirm_content => 'Change status to Preparing (Closed)?';
	@override String get exit_app => 'Exit App';
	@override String get exit_app_desc => 'Are you sure you want to exit?';
	@override String get exit_app_kds_desc => 'Are you sure you want to exit?';
	@override String get store_closed_notice => 'The store will be set to "Preparing".';
	@override String get burst_test_start => '⚡️ Starting simulation (10 orders)';
}

// Path: order_status
class _Translations$order_status$en extends Translations$order_status$ko {
	_Translations$order_status$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
	@override String get scroll_to_end => 'Go to End';
}

// Path: order_history
class _Translations$order_history$en extends Translations$order_history$ko {
	_Translations$order_history$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _Translations$product_mgmt$en extends Translations$product_mgmt$ko {
	_Translations$product_mgmt$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Products';
	@override String get search_placeholder => 'Search product name';
	@override String get all => 'All';
	@override String get sold_out => 'Sold Out';
	@override String count({required Object n}) => '${n}';
	@override String total_count({required Object n}) => 'Total ${n}';
	@override String error_load({required Object error}) => 'An error occurred while loading products.\n${error}';
	@override String get dialog_hidden_title => 'Set to Hidden';
	@override String dialog_hidden_content({required Object name}) => 'Do you want to set [ ${name} ] to hidden?';
	@override String get btn_hidden => 'Hidden';
	@override String same_product_count({required Object n}) => 'Same name × ${n}';
	@override String get error_status_update => 'Failed to change the status. Please try again.';
	@override String get refresh_products => 'Refresh products';
}

// Path: order
class _Translations$order$en extends Translations$order$ko {
	_Translations$order$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get new_order => 'New';
	@override String get preparing => 'Accepted';
	@override String get ready => 'Pickup';
	@override String get cancelled => 'Cancelled';
	@override String get done => 'Done';
	@override String get no_show => 'Not Picked Up';
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
	@override String ordered_time_short({required Object time}) => 'Ordered at ${time}';
	@override late final _Translations$order$payment_method$en payment_method = _Translations$order$payment_method$en._(_root);
	@override late final _Translations$order$discount_type$en discount_type = _Translations$order$discount_type$en._(_root);
	@override String get payment_breakdown => 'Payment';
	@override String payment_count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} payment',
		other: '${n} payments',
	);
}

// Path: order_detail
class _Translations$order_detail$en extends Translations$order_detail$ko {
	_Translations$order_detail$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get loading => 'Loading details...';
	@override String error_prefix({required Object error}) => 'An error occurred: ${error}';
	@override String get status_update_fail => 'Failed to change status.';
	@override String get repickup_success => 'Pickup re-request notification sent.';
	@override String get repickup_fail => 'Failed to send pickup re-request.';
	@override String get dialog_kiosk_cancel_title => 'Cancel Order';
	@override String get dialog_kiosk_cancel_content => 'Please cancel kiosk orders at the kiosk device.';
	@override String dialog_cancel_confirm_content({required Object n}) => 'Do you want to cancel order #${n}?';
	@override String get dialog_cancel_reason_title => 'Select Cancellation Reason';
	@override String dialog_cancel_reason_content({required Object n}) => 'Please select a reason for cancelling order #${n}.';
	@override String get cancel_reason_shop_request => 'Store Operations';
	@override String get cancel_reason_shop_closed => 'Closed for the Day';
	@override String get cancel_reason_customer_request => 'Customer\'s Request';
	@override String get cancel_reason_sold_out => 'Sold Out';
	@override String get cancel_reason_ingredient_shortage => 'Ingredient Shortage';
	@override String get cancel_reason_system_error => 'System Error';
	@override String get cancel_reason_order_surge => 'High Order Volume';
	@override String get dialog_repickup_confirm_title => 'Pickup Re-request';
	@override String dialog_repickup_confirm_content({required Object n}) => 'Do you want to re-request pickup for order #${n}?';
	@override String get dialog_no_show_confirm_title => 'Mark Not Picked Up';
	@override String dialog_no_show_confirm_content({required Object n}) => 'Process order #${n} as not picked up?';
	@override String dialog_complete_confirm_content({required Object n}) => 'Do you want to complete order #${n}?';
	@override String print_receipt_fail({required Object error}) => 'Receipt printing failed: ${error}';
	@override String get btn_receipt_reprint => 'Reprint Receipt';
	@override String get btn_label_reprint => 'Reprint Label';
	@override String get btn_pickup_request => 'Request Pickup';
	@override String get btn_repickup => 'Re-request Pickup';
	@override String get btn_no_show => 'Mark Not Picked Up';
	@override String get btn_order_accept => 'Accept';
	@override String get btn_order_complete => 'Complete';
	@override String get btn_order_cancel => 'Cancel';
	@override String get time_select_title => 'Select Prep Time';
	@override String get time_select_content => 'Please select the time needed for preparation.';
	@override String minutes({required Object n}) => '${n} min';
}

// Path: dialog
class _Translations$dialog$en extends Translations$dialog$ko {
	_Translations$dialog$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$dialog$status_change$en status_change = _Translations$dialog$status_change$en._(_root);
	@override late final _Translations$dialog$exit$en exit = _Translations$dialog$exit$en._(_root);
	@override late final _Translations$dialog$update$en update = _Translations$dialog$update$en._(_root);
}

// Path: drawer
class _Translations$drawer$en extends Translations$drawer$ko {
	_Translations$drawer$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get product_management => 'Product Management';
	@override String get settings => 'Settings';
	@override String get logout => 'Logout';
	@override String get customer_center => 'Customer Center';
	@override String version({required Object version, required Object build}) => 'Version: ${version} (${build})';
	@override String get version_loading => 'Version: Loading...';
	@override String get version_error => 'Version: Error';
}

// Path: membership
class _Translations$membership$en extends Translations$membership$ko {
	_Translations$membership$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Membership Search';
	@override late final _Translations$membership$search$en search = _Translations$membership$search$en._(_root);
	@override late final _Translations$membership$customer$en customer = _Translations$membership$customer$en._(_root);
	@override late final _Translations$membership$tabs$en tabs = _Translations$membership$tabs$en._(_root);
	@override late final _Translations$membership$history$en history = _Translations$membership$history$en._(_root);
	@override late final _Translations$membership$dialog$en dialog = _Translations$membership$dialog$en._(_root);
	@override late final _Translations$membership$keypad$en keypad = _Translations$membership$keypad$en._(_root);
}

// Path: kds
class _Translations$kds$en extends Translations$kds$ko {
	_Translations$kds$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _Translations$kds$tabs$en tabs = _Translations$kds$tabs$en._(_root);
	@override String get btn_batch_complete => 'Batch Complete';
	@override String get btn_order_complete => 'Complete';
	@override late final _Translations$kds$sort$en sort = _Translations$kds$sort$en._(_root);
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

// Path: receipt
class _Translations$receipt$en extends Translations$receipt$ko {
	_Translations$receipt$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get cancel_receipt => 'Cancellation Receipt';
	@override String get cancel_order => 'Cancellation Order';
	@override String get order_no => 'Order No.';
	@override String get datetime => 'Date';
	@override String get col_menu => 'Menu';
	@override String get col_qty => 'Qty';
	@override String get col_amount => 'Amount';
	@override String get taxable => 'Taxable';
	@override String get vat => 'VAT';
	@override String get order_amount => 'Subtotal';
	@override String get discount_amount => 'Discount';
	@override String get payment_amount => 'Total';
	@override String get kiosk => 'Kiosk';
	@override String get customer_suffix => '';
	@override String get section_option => 'Option';
	@override String get section_detail => 'Detail';
	@override String get test_port => 'Port';
	@override String get test_board => 'Baud';
	@override String get test_ok => 'Printer is working';
}

// Path: label_category_select
class _Translations$label_category_select$en extends Translations$label_category_select$ko {
	_Translations$label_category_select$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Label print categories';
	@override String get guide => 'Only items in the selected categories are printed as labels. Reprinting from the order detail always prints the whole order, regardless of this setting.';
	@override String summary({required Object count, required Object total}) => '${count} of ${total} selected';
	@override String get empty_means_all => 'No category is selected, so every category is printed. To stop printing labels entirely, turn off \'Use label printer\' in settings.';
	@override String get select_all => 'Select all';
	@override String get clear_all => 'Clear all';
	@override String get empty_catalog => 'Could not load product categories. Every category is printed in this state.';
	@override String get save_failed => 'Could not save — store information is unavailable.';
}

// Path: label_subinfo_select
class _Translations$label_subinfo_select$en extends Translations$label_subinfo_select$ko {
	_Translations$label_subinfo_select$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Label sub-info';
	@override String guide({required Object max}) => 'Pick up to ${max} option groups to show prominently at the top of the label. They print left to right in the order you pick, and are removed from the option list at the bottom of the label.';
	@override String max_notice({required Object max}) => 'You can pick up to ${max}.';
	@override String get preview => 'Preview';
	@override String get none => 'Not set';
	@override String get clear_all => 'Clear all';
	@override String get empty_catalog => 'Could not load option groups.';
	@override String get save_failed => 'Could not save — store information is unavailable.';
}

// Path: common.api_error
class _Translations$common$api_error$en extends Translations$common$api_error$ko {
	_Translations$common$api_error$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get network => 'Please check your network connection.';
	@override String get timeout => 'The server is taking too long to respond. Please try again later.';
	@override String get auth => 'Your session has expired. Please sign in again.';
	@override String get not_found => 'The requested information could not be found.';
	@override String get server => 'A temporary server error occurred. Please try again later.';
	@override String get generic => 'We couldn\'t process your request. Please try again later.';
}

// Path: login.tabs
class _Translations$login$tabs$en extends Translations$login$tabs$ko {
	_Translations$login$tabs$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get order => 'Reception';
	@override String get kitchen => 'KDS';
}

// Path: login.kds_notice
class _Translations$login$kds_notice$en extends Translations$login$kds_notice$ko {
	_Translations$login$kds_notice$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'KDS Standalone Operation';
	@override String get content => 'By default, the KDS only displays orders and does not receive new orders directly.\nIt is typically used in setups with two or more devices.\nTo run the store with the KDS alone (without a separate reception device), turn on \'Accept Orders\' in Settings > Mode Settings after logging in.\nMake sure it is not used together with another order reception program.';
}

// Path: login.overlay_permission
class _Translations$login$overlay_permission$en extends Translations$login$overlay_permission$ko {
	_Translations$login$overlay_permission$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Permission Required';
	@override String get content => '"Display over other apps" permission is required for minimize feature.\nSettings now?';
	@override String get set => 'Settings';
	@override String get later => 'Later';
}

// Path: settings.mode_switch
class _Translations$settings$mode_switch$en extends Translations$settings$mode_switch$ko {
	_Translations$settings$mode_switch$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get to_main => 'Switch to Main';
	@override String get to_kds => 'Switch to Kitchen Display (KDS)';
	@override String get confirm_to_main => 'Switch to main (order reception) mode?';
	@override String get confirm_to_kds => 'Order Reception is OFF, so new orders are not received directly.\nTo receive orders directly in Kitchen Monitor (KDS) mode, switch over and turn \'Order Reception\' ON.';
	@override String get btn_switch => 'Switch';
	@override String get desc_to_main => 'Changes to order reception screen.';
	@override String get desc_to_kds => 'Changes to the Kitchen Display (KDS) screen.';
}

// Path: settings.auto_start
class _Translations$settings$auto_start$en extends Translations$settings$auto_start$ko {
	_Translations$settings$auto_start$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Auto Start on Boot';
	@override String get desc => 'Automatically launch agent on PC startup.';
	@override String get desc_general => 'Automatically launch agent on PC startup.\nStore must be open to receive orders.';
	@override String get on => 'ON';
	@override String get off => 'OFF';
}

// Path: settings.auto_receipt
class _Translations$settings$auto_receipt$en extends Translations$settings$auto_receipt$ko {
	_Translations$settings$auto_receipt$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Auto Accept Pickup Orders';
	@override String get desc => 'Automatically accept orders upon receipt.';
}

// Path: settings.print_order
class _Translations$settings$print_order$en extends Translations$settings$print_order$ko {
	_Translations$settings$print_order$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Print Tickets';
	@override String get desc => 'Print order tickets. When OFF, no order ticket is printed.';
}

// Path: settings.builtin_printer
class _Translations$settings$builtin_printer$en extends Translations$settings$builtin_printer$ko {
	_Translations$settings$builtin_printer$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use Built-in Printer';
	@override String get desc => 'Use the device\'s built-in printer.';
	@override String get detected => 'A built-in printer was detected on this device.';
	@override String get not_detected => 'No built-in printer was detected on this device. (Only Sunmi device built-in modules are supported)';
}

// Path: settings.external_printer
class _Translations$settings$external_printer$en extends Translations$settings$external_printer$ko {
	_Translations$settings$external_printer$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use External Printer';
	@override String get desc => 'Use USB-connected external printer.\nOrders follow settings, receipts print only on external printer.';
}

// Path: settings.label_printer
class _Translations$settings$label_printer$en extends Translations$settings$label_printer$ko {
	_Translations$settings$label_printer$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use Label Printer';
	@override String get desc => 'Use USB-connected label printer.\nSupported models: REXOD RXLA-561 (50mm x 70mm), BIXOLON G30 (40/58mm continuous)';
}

// Path: settings.label_qr
class _Translations$settings$label_qr$en extends Translations$settings$label_qr$ko {
	_Translations$settings$label_qr$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Print QR Code';
	@override String get desc => 'Print an order-identification QR code on each label. Used when adopting AI pickup tables.';
}

// Path: settings.volume
class _Translations$settings$volume$en extends Translations$settings$volume$ko {
	_Translations$settings$volume$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Volume';
	@override String get desc => 'Adjust notification volume.';
}

// Path: settings.sound
class _Translations$settings$sound$en extends Translations$settings$sound$ko {
	_Translations$settings$sound$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Notification Sound';
	@override String get desc => 'Select notification sound.';
	@override String get sound1 => 'Sound 1';
	@override String get sound2 => 'Sound 2';
}

// Path: settings.alert_count
class _Translations$settings$alert_count$en extends Translations$settings$alert_count$ko {
	_Translations$settings$alert_count$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Alert Count';
	@override String get desc => 'Set number of times alert plays.';
	@override String count({required Object n}) => '${n} times';
	@override String get unlimited => 'Unlimited';
}

// Path: settings.print_count
class _Translations$settings$print_count$en extends Translations$settings$print_count$ko {
	_Translations$settings$print_count$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Print Copies';
	@override String get desc => 'Set the number of order receipts to print on order.';
	@override String count({required Object n}) => '${n} copies';
}

// Path: settings.language
class _Translations$settings$language$en extends Translations$settings$language$ko {
	_Translations$settings$language$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Language';
	@override String get desc => 'Set the application language.';
}

// Path: settings.theme
class _Translations$settings$theme$en extends Translations$settings$theme$ko {
	_Translations$settings$theme$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Theme';
	@override String get desc => 'Change the app-wide brand color and logo.';
	@override String get restart_title => 'Restart required';
	@override String get restart_message => 'The theme change will apply after restarting the app. Restart now?';
	@override String get restart_now => 'Restart now';
	@override String get restart_later => 'Later';
	@override String get restart_failed => 'Couldn\'t restart the app automatically. Please close and reopen it manually.';
	@override late final _Translations$settings$theme$options$en options = _Translations$settings$theme$options$en._(_root);
}

// Path: settings.dual_monitor
class _Translations$settings$dual_monitor$en extends Translations$settings$dual_monitor$ko {
	_Translations$settings$dual_monitor$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Front Display Content';
	@override String get desc => 'Choose the brand content shown on the secondary display.';
	@override String get option_video => 'Video';
	@override String get option_image => 'Image';
	@override String get option_none => 'Hide';
}

// Path: settings.currency
class _Translations$settings$currency$en extends Translations$settings$currency$ko {
	_Translations$settings$currency$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Currency Unit';
	@override String get desc => 'Select the currency unit for displaying amounts.';
	@override String get krw => 'Won (₩)';
	@override String get jpy => 'Yen (¥)';
}

// Path: settings.display_rotate
class _Translations$settings$display_rotate$en extends Translations$settings$display_rotate$ko {
	_Translations$settings$display_rotate$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Flip Display';
	@override String get desc => 'Rotate the screen 180°. Use this when OS rotation settings are unavailable.';
}

// Path: settings.order_type_badge
class _Translations$settings$order_type_badge$en extends Translations$settings$order_type_badge$ko {
	_Translations$settings$order_type_badge$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Show Dine-in / Takeout Badge';
	@override String get desc => 'Display a dine-in or takeout badge on the order detail header.';
}

// Path: settings.print_show_order_type
class _Translations$settings$print_show_order_type$en extends Translations$settings$print_show_order_type$ko {
	_Translations$settings$print_show_order_type$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Show Dine-in / Takeout on Print';
	@override String get desc => 'Prints the dine-in/takeout label on receipts and order slips.';
}

// Path: settings.order_source_color
class _Translations$settings$order_source_color$en extends Translations$settings$order_source_color$ko {
	_Translations$settings$order_source_color$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Color by Order Source';
	@override String get desc => 'Distinguish app, kiosk, and POS orders by card background color.';
}

// Path: settings.kds_ignore_status
class _Translations$settings$kds_ignore_status$en extends Translations$settings$kds_ignore_status$ko {
	_Translations$settings$kds_ignore_status$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ignore Other Device Status Updates';
	@override String get desc => 'Orders on this screen will not refresh when other Kitchen Display (KDS) devices update pickup or progress status. (Use when you want to control status updates manually)';
}

// Path: settings.kds_accept_orders
class _Translations$settings$kds_accept_orders$en extends Translations$settings$kds_accept_orders$ko {
	_Translations$settings$kds_accept_orders$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Accept Orders';
	@override String get desc => 'Automatically accept incoming orders directly in Kitchen Display (KDS) mode. Be sure NOT to run another main order-receiving program in parallel.';
	@override String get confirm_title => 'Enable Order Acceptance';
	@override String get confirm_content => 'Kitchen Display (KDS) will automatically accept incoming orders directly.\nBe sure NOT to run another main order-receiving program in parallel.\nEnable this option?';
}

// Path: settings.label_category_filter
class _Translations$settings$label_category_filter$en extends Translations$settings$label_category_filter$ko {
	_Translations$settings$label_category_filter$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Label print categories';
	@override String get desc_off => 'Prints labels for every category. Turn on to print only selected categories.';
	@override String get desc_none => 'No category selected — every category is printed.';
	@override String desc_selected({required Object count, required Object total, required Object names}) => 'Printing ${count} of ${total} categories — ${names}';
	@override String get btn_configure => 'Select categories';
}

// Path: settings.label_subinfo
class _Translations$settings$label_subinfo$en extends Translations$settings$label_subinfo$ko {
	_Translations$settings$label_subinfo$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Label sub-info';
	@override String get desc_none => 'Leaves the sub-info area on the label empty. Pick option groups to highlight things like temperature or size.';
	@override String desc_selected({required Object names}) => 'Shown in the order you picked — ${names}';
	@override String get btn_configure => 'Select option groups';
}

// Path: settings.label_paper
class _Translations$settings$label_paper$en extends Translations$settings$label_paper$ko {
	_Translations$settings$label_paper$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Label Paper Size';
	@override String get desc_40 => 'Prints with the 40mm paper layout.';
	@override String get desc_58 => 'Prints with the 58mm paper layout.';
	@override String get btn_40 => '40mm';
	@override String get btn_58 => '58mm';
}

// Path: settings.developer_options
class _Translations$settings$developer_options$en extends Translations$settings$developer_options$ko {
	_Translations$settings$developer_options$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Developer Options';
	@override late final _Translations$settings$developer_options$appfit_test$en appfit_test = _Translations$settings$developer_options$appfit_test$en._(_root);
}

// Path: settings.kiosk
class _Translations$settings$kiosk$en extends Translations$settings$kiosk$ko {
	_Translations$settings$kiosk$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get visible_title => 'Show Kiosk Orders';
	@override String get visible_desc => 'Display kiosk orders on screen.';
	@override String get sound_title => 'Kiosk Order Ticket & Sound';
	@override String get sound_desc => 'Print ticket and play notification sound when a kiosk order is received. Works independently of the display setting.';
	@override String get auto_accept_title => 'Auto-Accept Kiosk Orders';
	@override String get auto_accept_desc => 'Kiosk orders are always accepted immediately, regardless of the \'Auto-Accept Pickup Orders\' setting.';
}

// Path: settings.pos
class _Translations$settings$pos$en extends Translations$settings$pos$ko {
	_Translations$settings$pos$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get visible_title => 'Show POS Orders';
	@override String get visible_desc => 'Display POS orders on screen.';
	@override String get sound_title => 'POS Order Ticket & Sound';
	@override String get sound_desc => 'Print ticket and play notification sound when a POS order is received. Works independently of the display setting.';
}

// Path: settings.local_server
class _Translations$settings$local_server$en extends Translations$settings$local_server$ko {
	_Translations$settings$local_server$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _Translations$settings$connection$en extends Translations$settings$connection$ko {
	_Translations$settings$connection$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get connected => 'Connected';
	@override String get disconnected => 'Disconnected';
	@override String get reconnect => 'Reconnect';
}

// Path: settings.soundgraph
class _Translations$settings$soundgraph$en extends Translations$settings$soundgraph$ko {
	_Translations$settings$soundgraph$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'SoundGraph Order Push';
	@override String get desc => 'Sends order info to SoundGraph when an order is accepted.';
	@override String get market_id_placeholder => 'Enter MARKET ID';
	@override String get market_id_dialog_title => 'Enter MARKET ID';
	@override String get market_id_dialog_save => 'Save';
	@override String get market_id_dialog_cancel => 'Cancel';
}

// Path: settings.app_update
class _Translations$settings$app_update$en extends Translations$settings$app_update$ko {
	_Translations$settings$app_update$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get auto_check_title => 'Check for updates on startup';
	@override String get auto_check_desc => 'Automatically check for the latest version on app launch.';
	@override String get manual_title => 'App Update';
	@override String version_info({required Object currentVersion, required Object latestVersion}) => 'Current: v${currentVersion} / Latest: v${latestVersion}';
	@override String get up_to_date => 'You are up to date.';
	@override String get checking => 'Checking version...';
	@override String get check_failed => 'Version check failed';
	@override String get update_btn => 'Update';
	@override String get check_btn => 'Check Version';
}

// Path: settings.log_collection
class _Translations$settings$log_collection$en extends Translations$settings$log_collection$ko {
	_Translations$settings$log_collection$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get section_title => 'Send Logs';
	@override String get section_desc => 'Compress logs for the selected period and send them to Slack.';
	@override String get store_label => 'Store';
	@override String get brand_label => 'Brand';
	@override String get store_name_label => 'Store name';
	@override String get store_code_label => 'Store code';
	@override String get device_label => 'Device';
	@override String get range_today => 'Today';
	@override String get range_7days => 'Last 7 days';
	@override String get range_30days => 'Last 30 days';
	@override String get send_btn => 'Send logs';
	@override String get stage_flushing => 'Flushing logs...';
	@override String get stage_collecting => 'Collecting logs...';
	@override String get stage_zipping => 'Compressing...';
	@override String get stage_uploading => 'Uploading...';
	@override String success({required Object count, required Object size}) => 'Sent (${count} files, ${size})';
	@override String failed({required Object error}) => 'Send failed: ${error}';
	@override String get not_configured => 'Slack upload is not configured. Check the build settings.';
}

// Path: home.tabs
class _Translations$home$tabs$en extends Translations$home$tabs$ko {
	_Translations$home$tabs$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get order_status => 'Status';
	@override String get order_history => 'History';
	@override String get product_management => 'Products';
	@override String get membership => 'Membership';
}

// Path: order.payment_method
class _Translations$order$payment_method$en extends Translations$order$payment_method$ko {
	_Translations$order$payment_method$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get credit_card => 'Credit Card';
	@override String get prepaid_card => 'Prepaid Card';
	@override String get naver_pay => 'Naver Pay';
	@override String get kakao_pay => 'Kakao Pay';
	@override String get toss_pay => 'Toss Pay';
	@override String get apple_pay => 'Apple Pay';
	@override String get payco => 'PAYCO';
	@override String get easy_card => 'Easy Card';
	@override String get mobile_payment => 'Mobile Payment';
	@override String get qr_payment => 'QR Payment';
	@override String get felica_transportation => 'Felica Transit';
	@override String get felica_id => 'Felica iD';
	@override String get felica_quicpay => 'Felica QUICPay';
	@override String get cash => 'Cash';
	@override String get service => 'Service';
	@override String get free => 'Free';
	@override String get toss_pay_direct => 'Toss Pay Direct';
	@override String get kb_pay => 'KB Pay';
	@override String get hana_pay => 'Hana Pay';
	@override String get woori_pay => 'Woori Pay';
	@override String get gift => 'Gift';
	@override String get app_card => 'App Card';
	@override String get zero_pay => 'Zero Pay';
	@override String get karrot_pay => 'Karrot Pay';
	@override String get bank_transfer => 'Bank Transfer';
	@override String get local_currency => 'Local Currency';
	@override String get easy_payment => 'Easy Payment';
	@override String get multi => 'Split Payment';
	@override String get other => 'Other';
}

// Path: order.discount_type
class _Translations$order$discount_type$en extends Translations$order$discount_type$ko {
	_Translations$order$discount_type$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get coupon => 'Coupon';
	@override String get point => 'Point';
	@override String get gift => 'Gift';
	@override String get partner => 'Partner';
	@override String get membership => 'Membership';
	@override String get employee => 'Employee';
	@override String get pre_payment => 'Prepayment';
	@override String get shop => 'Shop Discount';
}

// Path: dialog.status_change
class _Translations$dialog$status_change$en extends Translations$dialog$status_change$ko {
	_Translations$dialog$status_change$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Change Status';
	@override String content({required Object item}) => 'Do you want to change the status of [ ${item} ]?';
	@override String get current => 'Current status: ';
	@override String get sale => 'On Sale';
	@override String get sold_out => 'Sold Out';
	@override String get hidden => 'Hidden';
	@override String get hidden_delete => 'Hidden';
	@override String get bulk_title => 'Change Status (All)';
	@override String bulk_content({required Object n, required Object item}) => 'Change the status of all ${n} products named [ ${item} ].';
	@override String bulk_prices({required Object n}) => '${n} prices (all of them will be changed)';
	@override String bulk_categories({required Object names}) => 'This product is also listed in ${names}; all of them will be updated.';
	@override String get bulk_sale => 'All On Sale';
	@override String get bulk_sold_out => 'All Sold Out';
}

// Path: dialog.exit
class _Translations$dialog$exit$en extends Translations$dialog$exit$ko {
	_Translations$dialog$exit$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Exit App';
	@override String get content => 'Are you sure you want to exit?';
	@override String get confirm => 'Exit';
}

// Path: dialog.update
class _Translations$dialog$update$en extends Translations$dialog$update$ko {
	_Translations$dialog$update$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _Translations$membership$search$en extends Translations$membership$search$ko {
	_Translations$membership$search$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get hint => 'Please enter phone number or coupon number.';
	@override String get hint_searched => 'Please enter number of stamps. (Up to 20)';
	@override String get hint_unregistered => 'Enter a stamp count or coupon number.';
	@override String get btn_search => 'Search Member';
	@override String get btn_other_member => 'Reset Search';
	@override String get btn_save_stamp => 'Save Stamp';
	@override String get btn_use_coupon => 'Use Coupon';
	@override String get btn_scan => 'Scan Barcode';
}

// Path: membership.customer
class _Translations$membership$customer$en extends Translations$membership$customer$ko {
	_Translations$membership$customer$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get status_none => 'No member info found.';
	@override String get status_unregistered => 'Not registered';
	@override String status_unregistered_with_id({required Object id}) => 'Not registered (${id})';
	@override String honorific({required Object name}) => '${name}';
	@override String summary({required Object stamps, required Object coupons}) => 'Stamp ${stamps} | Coupon ${coupons}';
}

// Path: membership.tabs
class _Translations$membership$tabs$en extends Translations$membership$tabs$ko {
	_Translations$membership$tabs$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get stamps => 'Stamps';
	@override String get coupons => 'History';
	@override String get available => 'Coupons';
}

// Path: membership.history
class _Translations$membership$history$en extends Translations$membership$history$ko {
	_Translations$membership$history$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
	@override String get status_used => 'Used';
	@override String get stamp_status_issued => 'Earned';
	@override String get stamp_status_canceled => 'Canceled';
	@override String get stamp_status_expired => 'Expired';
	@override String get stamp_status_used => 'Converted to Coupon';
	@override String get prev_page => 'Prev';
	@override String get next_page => 'Next';
}

// Path: membership.dialog
class _Translations$membership$dialog$en extends Translations$membership$dialog$ko {
	_Translations$membership$dialog$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
	@override String get coupon_code_looks_like_phone => 'This looks like a phone number. Tap [Search] to look up a member, or enter a coupon code to use a coupon.';
	@override String get store_info_missing => 'Store info missing. Please login again.';
	@override String get input_error_title => 'Input Error';
	@override String get stamp_input_error => 'Please enter 1 or more stamps.';
	@override String get stamp_limit_error => '20 stamps or less.';
	@override String get processing_complete => 'Complete';
	@override String get notification => 'Notification';
}

// Path: membership.keypad
class _Translations$membership$keypad$en extends Translations$membership$keypad$ko {
	_Translations$membership$keypad$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get clear => 'Clear';
	@override String get delete => 'Delete';
}

// Path: kds.tabs
class _Translations$kds$tabs$en extends Translations$kds$tabs$ko {
	_Translations$kds$tabs$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String all({required Object n}) => 'All ${n}';
	@override String progress({required Object n}) => 'Progress ${n}';
	@override String pickup({required Object n}) => 'Pickup ${n}';
	@override String completed({required Object n}) => 'Done ${n}';
	@override String cancelled({required Object n}) => 'Cancelled ${n}';
}

// Path: kds.sort
class _Translations$kds$sort$en extends Translations$kds$sort$ko {
	_Translations$kds$sort$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get oldest => 'Oldest';
	@override String get newest => 'Newest';
}

// Path: settings.theme.options
class _Translations$settings$theme$options$en extends Translations$settings$theme$options$ko {
	_Translations$settings$theme$options$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get appfit_default => 'Default';
	@override String get mammoth_coffee => '매머드커피';
	@override String get mata => '마하테이스트';
	@override String get paik => '빽다방재팬';
	@override String get tljp => '더리터재팬';
}

// Path: settings.developer_options.appfit_test
class _Translations$settings$developer_options$appfit_test$en extends Translations$settings$developer_options$appfit_test$ko {
	_Translations$settings$developer_options$appfit_test$en._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'AppFit API Test';
	@override String get desc => 'Test Waldlust Platform AppFit API settings';
	@override String get btn => 'Test';
}
