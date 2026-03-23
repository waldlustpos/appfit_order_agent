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
	@override late final _TranslationsAppEn app = _TranslationsAppEn._(_root);
	@override late final _TranslationsCommonEn common = _TranslationsCommonEn._(_root);
	@override late final _TranslationsLoginEn login = _TranslationsLoginEn._(_root);
	@override late final _TranslationsSettingsEn settings = _TranslationsSettingsEn._(_root);
	@override late final _TranslationsHomeEn home = _TranslationsHomeEn._(_root);
	@override late final _TranslationsAppBarEn app_bar = _TranslationsAppBarEn._(_root);
	@override late final _TranslationsOrderStatusEn order_status = _TranslationsOrderStatusEn._(_root);
	@override late final _TranslationsOrderHistoryEn order_history = _TranslationsOrderHistoryEn._(_root);
	@override late final _TranslationsProductMgmtEn product_mgmt = _TranslationsProductMgmtEn._(_root);
	@override late final _TranslationsOrderEn order = _TranslationsOrderEn._(_root);
	@override late final _TranslationsOrderDetailEn order_detail = _TranslationsOrderDetailEn._(_root);
	@override late final _TranslationsDialogEn dialog = _TranslationsDialogEn._(_root);
	@override late final _TranslationsDrawerEn drawer = _TranslationsDrawerEn._(_root);
	@override late final _TranslationsMembershipEn membership = _TranslationsMembershipEn._(_root);
	@override late final _TranslationsKdsEn kds = _TranslationsKdsEn._(_root);
}

// Path: app
class _TranslationsAppEn extends TranslationsAppKo {
	_TranslationsAppEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get name => 'Kokonut Order Agent';
}

// Path: common
class _TranslationsCommonEn extends TranslationsCommonKo {
	_TranslationsCommonEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
}

// Path: login
class _TranslationsLoginEn extends TranslationsLoginKo {
	_TranslationsLoginEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
	@override late final _TranslationsLoginTabsEn tabs = _TranslationsLoginTabsEn._(_root);
	@override late final _TranslationsLoginOverlayPermissionEn overlay_permission = _TranslationsLoginOverlayPermissionEn._(_root);
}

// Path: settings
class _TranslationsSettingsEn extends TranslationsSettingsKo {
	_TranslationsSettingsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Settings';
	@override String get save => 'Save';
	@override String get save_success => 'Settings saved.';
	@override String save_error({required Object error}) => 'Error saving settings: ${error}';
	@override late final _TranslationsSettingsModeSwitchEn mode_switch = _TranslationsSettingsModeSwitchEn._(_root);
	@override late final _TranslationsSettingsAutoStartEn auto_start = _TranslationsSettingsAutoStartEn._(_root);
	@override late final _TranslationsSettingsAutoReceiptEn auto_receipt = _TranslationsSettingsAutoReceiptEn._(_root);
	@override late final _TranslationsSettingsPrintOrderEn print_order = _TranslationsSettingsPrintOrderEn._(_root);
	@override late final _TranslationsSettingsBuiltinPrinterEn builtin_printer = _TranslationsSettingsBuiltinPrinterEn._(_root);
	@override late final _TranslationsSettingsExternalPrinterEn external_printer = _TranslationsSettingsExternalPrinterEn._(_root);
	@override late final _TranslationsSettingsLabelPrinterEn label_printer = _TranslationsSettingsLabelPrinterEn._(_root);
	@override late final _TranslationsSettingsVolumeEn volume = _TranslationsSettingsVolumeEn._(_root);
	@override late final _TranslationsSettingsSoundEn sound = _TranslationsSettingsSoundEn._(_root);
	@override late final _TranslationsSettingsAlertCountEn alert_count = _TranslationsSettingsAlertCountEn._(_root);
	@override late final _TranslationsSettingsPrintCountEn print_count = _TranslationsSettingsPrintCountEn._(_root);
	@override late final _TranslationsSettingsLanguageEn language = _TranslationsSettingsLanguageEn._(_root);
	@override late final _TranslationsSettingsDeveloperOptionsEn developer_options = _TranslationsSettingsDeveloperOptionsEn._(_root);
	@override late final _TranslationsSettingsLocalServerEn local_server = _TranslationsSettingsLocalServerEn._(_root);
	@override late final _TranslationsSettingsConnectionEn connection = _TranslationsSettingsConnectionEn._(_root);
}

// Path: home
class _TranslationsHomeEn extends TranslationsHomeKo {
	_TranslationsHomeEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _TranslationsHomeTabsEn tabs = _TranslationsHomeTabsEn._(_root);
	@override String get logout_confirm => 'Are you sure you want to logout?';
	@override String get minimize_error => 'An error occurred while minimizing the app.';
	@override String get invalid_tab => 'Invalid tab index.';
}

// Path: app_bar
class _TranslationsAppBarEn extends TranslationsAppBarKo {
	_TranslationsAppBarEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
	@override String get kds_mode => 'KDS Mode';
	@override String get order_toggle => 'Order';
	@override String get order_start_confirm_title => 'Confirm Order Start';
	@override String get order_stop_confirm_title => 'Confirm Order Stop';
	@override String get order_start_confirm_content => 'Change status to Open?';
	@override String get order_stop_confirm_content => 'Change status to Preparing (Closed)?';
	@override String get exit_app => 'Exit App';
	@override String get exit_app_desc => 'Are you sure you want to exit? \nOperating status will be set to OFF automatically.';
	@override String get exit_app_kds_desc => 'Are you sure you want to exit?';
	@override String get burst_test_start => '⚡️ Starting simulation (10 orders)';
}

// Path: order_status
class _TranslationsOrderStatusEn extends TranslationsOrderStatusKo {
	_TranslationsOrderStatusEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
}

// Path: order_history
class _TranslationsOrderHistoryEn extends TranslationsOrderHistoryKo {
	_TranslationsOrderHistoryEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
class _TranslationsProductMgmtEn extends TranslationsProductMgmtKo {
	_TranslationsProductMgmtEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _TranslationsOrderEn extends TranslationsOrderKo {
	_TranslationsOrderEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _TranslationsOrderDetailEn extends TranslationsOrderDetailKo {
	_TranslationsOrderDetailEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _TranslationsDialogEn extends TranslationsDialogKo {
	_TranslationsDialogEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _TranslationsDialogStatusChangeEn status_change = _TranslationsDialogStatusChangeEn._(_root);
	@override late final _TranslationsDialogExitEn exit = _TranslationsDialogExitEn._(_root);
	@override late final _TranslationsDialogUpdateEn update = _TranslationsDialogUpdateEn._(_root);
}

// Path: drawer
class _TranslationsDrawerEn extends TranslationsDrawerKo {
	_TranslationsDrawerEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get settings => 'Settings';
	@override String get logout => 'Logout';
	@override String get customer_center => 'Customer Center';
	@override String version({required Object version, required Object build}) => 'Version: ${version} (${build})';
	@override String get version_loading => 'Version: Loading...';
	@override String get version_error => 'Version: Error';
}

// Path: membership
class _TranslationsMembershipEn extends TranslationsMembershipKo {
	_TranslationsMembershipEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Membership Search';
	@override late final _TranslationsMembershipSearchEn search = _TranslationsMembershipSearchEn._(_root);
	@override late final _TranslationsMembershipCustomerEn customer = _TranslationsMembershipCustomerEn._(_root);
	@override late final _TranslationsMembershipTabsEn tabs = _TranslationsMembershipTabsEn._(_root);
	@override late final _TranslationsMembershipHistoryEn history = _TranslationsMembershipHistoryEn._(_root);
	@override late final _TranslationsMembershipDialogEn dialog = _TranslationsMembershipDialogEn._(_root);
	@override late final _TranslationsMembershipKeypadEn keypad = _TranslationsMembershipKeypadEn._(_root);
}

// Path: kds
class _TranslationsKdsEn extends TranslationsKdsKo {
	_TranslationsKdsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override late final _TranslationsKdsTabsEn tabs = _TranslationsKdsTabsEn._(_root);
	@override String get btn_batch_complete => 'Batch Complete';
	@override String get btn_order_complete => 'Complete';
	@override late final _TranslationsKdsSortEn sort = _TranslationsKdsSortEn._(_root);
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
class _TranslationsLoginTabsEn extends TranslationsLoginTabsKo {
	_TranslationsLoginTabsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get order => 'Reception';
	@override String get kitchen => 'KDS';
}

// Path: login.overlay_permission
class _TranslationsLoginOverlayPermissionEn extends TranslationsLoginOverlayPermissionKo {
	_TranslationsLoginOverlayPermissionEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Permission Required';
	@override String get content => '"Display over other apps" permission is required for minimize feature.\nSettings now?';
	@override String get set => 'Settings';
	@override String get later => 'Later';
}

// Path: settings.mode_switch
class _TranslationsSettingsModeSwitchEn extends TranslationsSettingsModeSwitchKo {
	_TranslationsSettingsModeSwitchEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _TranslationsSettingsAutoStartEn extends TranslationsSettingsAutoStartKo {
	_TranslationsSettingsAutoStartEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Auto Start on Boot';
	@override String get desc => 'Automatically launch agent on PC startup.';
	@override String get desc_general => 'Automatically launch agent on PC startup.\nStore must be open to receive orders.';
	@override String get on => 'ON';
	@override String get off => 'OFF';
}

// Path: settings.auto_receipt
class _TranslationsSettingsAutoReceiptEn extends TranslationsSettingsAutoReceiptKo {
	_TranslationsSettingsAutoReceiptEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Auto Accept Pickup Orders';
	@override String get desc => 'Automatically accept orders upon receipt.';
}

// Path: settings.print_order
class _TranslationsSettingsPrintOrderEn extends TranslationsSettingsPrintOrderKo {
	_TranslationsSettingsPrintOrderEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Print Tickets';
	@override String get desc => 'Print order tickets.';
}

// Path: settings.builtin_printer
class _TranslationsSettingsBuiltinPrinterEn extends TranslationsSettingsBuiltinPrinterKo {
	_TranslationsSettingsBuiltinPrinterEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use Built-in Printer';
	@override String get desc => 'Use the device\'s built-in printer.';
}

// Path: settings.external_printer
class _TranslationsSettingsExternalPrinterEn extends TranslationsSettingsExternalPrinterKo {
	_TranslationsSettingsExternalPrinterEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use External Printer';
	@override String get desc => 'Use USB-connected external printer.\nOrders follow settings, receipts print only on external printer.';
}

// Path: settings.label_printer
class _TranslationsSettingsLabelPrinterEn extends TranslationsSettingsLabelPrinterKo {
	_TranslationsSettingsLabelPrinterEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Use Label Printer';
	@override String get desc => 'Use USB-connected label printer. (50mm x 70mm)';
}

// Path: settings.volume
class _TranslationsSettingsVolumeEn extends TranslationsSettingsVolumeKo {
	_TranslationsSettingsVolumeEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Volume';
	@override String get desc => 'Adjust notification volume.';
}

// Path: settings.sound
class _TranslationsSettingsSoundEn extends TranslationsSettingsSoundKo {
	_TranslationsSettingsSoundEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Notification Sound';
	@override String get desc => 'Select notification sound.';
	@override String get sound1 => 'Sound 1';
	@override String get sound2 => 'Sound 2';
}

// Path: settings.alert_count
class _TranslationsSettingsAlertCountEn extends TranslationsSettingsAlertCountKo {
	_TranslationsSettingsAlertCountEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Alert Count';
	@override String get desc => 'Set number of times alert plays.';
	@override String count({required Object n}) => '${n} times';
	@override String get unlimited => 'Unlimited';
}

// Path: settings.print_count
class _TranslationsSettingsPrintCountEn extends TranslationsSettingsPrintCountKo {
	_TranslationsSettingsPrintCountEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Print Copies';
	@override String get desc => 'Set the number of order receipts to print on order.';
	@override String count({required Object n}) => '${n} copies';
}

// Path: settings.language
class _TranslationsSettingsLanguageEn extends TranslationsSettingsLanguageKo {
	_TranslationsSettingsLanguageEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Language';
	@override String get desc => 'Set the application language.';
}

// Path: settings.developer_options
class _TranslationsSettingsDeveloperOptionsEn extends TranslationsSettingsDeveloperOptionsKo {
	_TranslationsSettingsDeveloperOptionsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Developer Options';
	@override late final _TranslationsSettingsDeveloperOptionsAppfitTestEn appfit_test = _TranslationsSettingsDeveloperOptionsAppfitTestEn._(_root);
}

// Path: settings.local_server
class _TranslationsSettingsLocalServerEn extends TranslationsSettingsLocalServerKo {
	_TranslationsSettingsLocalServerEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
class _TranslationsSettingsConnectionEn extends TranslationsSettingsConnectionKo {
	_TranslationsSettingsConnectionEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get connected => 'Connected';
	@override String get disconnected => 'Disconnected';
	@override String get reconnect => 'Reconnect';
}

// Path: home.tabs
class _TranslationsHomeTabsEn extends TranslationsHomeTabsKo {
	_TranslationsHomeTabsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get order_status => 'Status';
	@override String get order_history => 'History';
	@override String get product_management => 'Products';
	@override String get membership => 'Membership';
}

// Path: dialog.status_change
class _TranslationsDialogStatusChangeEn extends TranslationsDialogStatusChangeKo {
	_TranslationsDialogStatusChangeEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _TranslationsDialogExitEn extends TranslationsDialogExitKo {
	_TranslationsDialogExitEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Exit App';
	@override String get content => 'Are you sure you want to exit?';
	@override String get confirm => 'Exit';
}

// Path: dialog.update
class _TranslationsDialogUpdateEn extends TranslationsDialogUpdateKo {
	_TranslationsDialogUpdateEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
class _TranslationsMembershipSearchEn extends TranslationsMembershipSearchKo {
	_TranslationsMembershipSearchEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

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
class _TranslationsMembershipCustomerEn extends TranslationsMembershipCustomerKo {
	_TranslationsMembershipCustomerEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get status_none => 'No member info found.';
	@override String honorific({required Object name}) => '${name}';
	@override String summary({required Object stamps, required Object coupons}) => 'Stamp ${stamps} | Coupon ${coupons}';
}

// Path: membership.tabs
class _TranslationsMembershipTabsEn extends TranslationsMembershipTabsKo {
	_TranslationsMembershipTabsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get stamps => 'Stamps';
	@override String get coupons => 'Usage';
	@override String get available => 'Coupons';
}

// Path: membership.history
class _TranslationsMembershipHistoryEn extends TranslationsMembershipHistoryKo {
	_TranslationsMembershipHistoryEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
	@override String get prev_page => 'Prev';
	@override String get next_page => 'Next';
}

// Path: membership.dialog
class _TranslationsMembershipDialogEn extends TranslationsMembershipDialogKo {
	_TranslationsMembershipDialogEn._(TranslationsEn root) : this._root = root, super.internal(root);

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
class _TranslationsMembershipKeypadEn extends TranslationsMembershipKeypadKo {
	_TranslationsMembershipKeypadEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get clear => 'Clear';
	@override String get delete => 'Delete';
}

// Path: kds.tabs
class _TranslationsKdsTabsEn extends TranslationsKdsTabsKo {
	_TranslationsKdsTabsEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String all({required Object n}) => 'All ${n}';
	@override String progress({required Object n}) => 'Progress ${n}';
	@override String pickup({required Object n}) => 'Pickup ${n}';
	@override String completed({required Object n}) => 'Done ${n}';
	@override String cancelled({required Object n}) => 'Cancelled ${n}';
}

// Path: kds.sort
class _TranslationsKdsSortEn extends TranslationsKdsSortKo {
	_TranslationsKdsSortEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get oldest => 'Oldest';
	@override String get newest => 'Newest';
}

// Path: settings.developer_options.appfit_test
class _TranslationsSettingsDeveloperOptionsAppfitTestEn extends TranslationsSettingsDeveloperOptionsAppfitTestKo {
	_TranslationsSettingsDeveloperOptionsAppfitTestEn._(TranslationsEn root) : this._root = root, super.internal(root);

	final TranslationsEn _root; // ignore: unused_field

	// Translations
	@override String get title => 'AppFit API Test';
	@override String get desc => 'Test Waldlust Platform AppFit API settings';
	@override String get btn => 'Test';
}
