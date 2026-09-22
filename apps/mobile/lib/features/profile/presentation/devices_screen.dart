import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';

final FutureProvider<List<Map<String, dynamic>>> deviceSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((Ref ref) {
  return ref.watch(authRepositoryProvider).sessions();
});

/// Signed-in devices, with the ability to revoke any of them.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<Map<String, dynamic>>> sessions =
        ref.watch(deviceSessionsProvider);
    final String locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('profileDevices'))),
      body: sessions.when(
        loading: () => const SkeletonList(itemHeight: 64),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorGeneric'),
          onRetry: () => ref.invalidate(deviceSessionsProvider),
        ),
        data: (List<Map<String, dynamic>> list) {
          if (list.isEmpty) {
            return EmptyStateView(title: l10n.t('profileDevices'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> session = list[index];
              final DateTime? lastUsed =
                  DateTime.tryParse('${session['last_used_at']}');
              return ListTile(
                leading: const Icon(Icons.phone_iphone_rounded),
                title: Text('${session['device_name'] ?? 'Unknown device'}'),
                subtitle: Text(
                  <String>[
                    if (session['platform'] != null) '${session['platform']}',
                    if (lastUsed != null)
                      Formatters.dateTime(lastUsed.toLocal(), locale),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: IconButton(
                  onPressed: () => _revoke(context, ref, '${session['id']}'),
                  tooltip: l10n.t('authSignOut'),
                  icon: const Icon(Icons.logout_rounded),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
  ) async {
    try {
      await ref.read(authRepositoryProvider).revokeSession(sessionId);
      ref.invalidate(deviceSessionsProvider);
    } on Object {
      if (context.mounted) {
        AppToast.error(context, context.l10n.t('errorGeneric'));
      }
    }
  }
}
