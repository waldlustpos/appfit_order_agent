import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_styles.dart';
import '../../providers/store_provider.dart';
import '../../providers/app_info_provider.dart';
import '../../services/platform_service.dart';
import 'package:kokonut_order_agent/i18n/strings.g.dart';

class DrawerMenu extends ConsumerWidget {
  final int currentIndex;
  final Future<void> Function(int) onItemSelected;

  const DrawerMenu({
    Key? key,
    required this.currentIndex,
    required this.onItemSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final appInfoAsync = ref.watch(appInfoProvider);

    return Drawer(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            height: 80,
            decoration: BoxDecoration(
              color: AppStyles.kMainColor.withValues(alpha: 0.1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      store.value?.name ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: AppStyles.kMainColor),
            title: Text(t.drawer.settings),
            selected: currentIndex == 1,
            onTap: () async {
              await onItemSelected(1);
              logToFile(tag: LogTag.UI_ACTION, message: '설정 선택');
            },
          ),
          const Divider(),
          ListTile(
              leading: const Icon(Icons.logout, color: AppStyles.kMainColor),
              title: Text(t.drawer.logout),
              onTap: () async {
                await onItemSelected(-1);
                logToFile(tag: LogTag.UI_ACTION, message: '로그아웃 선택');
              }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.drawer.customer_center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        softWrap: true,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '070-7781-4531',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                appInfoAsync.when(
                  data: (appInfo) => Text(
                    t.drawer.version(
                        version: appInfo.version, build: appInfo.buildNumber),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  loading: () => Text(
                    t.drawer.version_loading,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  error: (_, __) => Text(
                    t.drawer.version_error,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
