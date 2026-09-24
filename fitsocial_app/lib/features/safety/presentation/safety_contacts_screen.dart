import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider, userSearchResultsProvider;
import '../application/safety_providers.dart';
import '../data/safety_repositories.dart';
import '../domain/safety_models.dart';
import 'safety_widgets.dart';

/// Up to three safety contacts, each a FitSocial user or an email address,
/// and the requests other people have sent this user.
class SafetyContactsScreen extends ConsumerWidget {
  const SafetyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final appContacts =
        (ref.watch(safetyContactsProvider).valueOrNull ?? const [])
            .where((c) =>
                c.status == SafetyContactStatus.pending ||
                c.status == SafetyContactStatus.accepted ||
                c.status == SafetyContactStatus.declined)
            .toList();
    final emailContacts =
        (ref.watch(emailSafetyContactsProvider).valueOrNull ?? const [])
            .where((c) => c.status != EmailContactStatus.removed)
            .toList();
    final incoming =
        (ref.watch(safetyContactOfProvider).valueOrNull ?? const [])
            .where((c) =>
                c.status == SafetyContactStatus.pending ||
                c.status == SafetyContactStatus.accepted)
            .toList();
    final used = ref.watch(usedSafetySlotsProvider);
    final full = used >= maxAcceptedSafetyContacts;

    return Scaffold(
      appBar: AppBar(title: const Text('Safety contacts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          SafetySectionLabel(
            'Your contacts · $used of $maxAcceptedSafetyContacts',
          ),
          SafetyCard(
            children: [
              if (appContacts.isEmpty && emailContacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Nobody yet. Add up to three people you trust.',
                    style: TextStyle(color: palette.muted),
                  ),
                ),
              for (final c in appContacts) _AppContactRow(contact: c),
              for (final c in emailContacts) _EmailContactRow(contact: c),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full ? null : () => _showAddUserSheet(context),
                  icon: const Icon(Icons.person_search_rounded),
                  label: const Text('FitSocial user'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: full ? null : () => _showAddEmailDialog(context),
                  icon: const Icon(Icons.alternate_email_rounded),
                  label: const Text('By email'),
                ),
              ),
            ],
          ),
          SafetyNote(
            full
                ? 'You have three contacts. Remove one to add someone else.'
                : 'FitSocial users get an urgent notification. Anyone else '
                    'gets an email with a link to your live location. Nobody '
                    'is alerted until they agree.',
          ),
          const SafetyNote(
            'Accepted contacts only · Alert delivery is not guaranteed. SMS '
            'and WhatsApp are not available yet.',
          ),
          if (incoming.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SafetySectionLabel('People who chose you'),
            SafetyCard(
              children: [
                for (final c in incoming) _IncomingRow(contact: c),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- Rows -------------------------------------------------------------------

class _AppContactRow extends ConsumerWidget {
  const _AppContactRow({required this.contact});

  final SafetyContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final (status, color) = switch (contact.status) {
      SafetyContactStatus.accepted => ('Ready · FitSocial alert', safetyTeal),
      SafetyContactStatus.pending => (
          'Waiting for them to accept',
          palette.muted
        ),
      _ => ('Declined', palette.danger),
    };
    return _ContactRow(
      leading: Avatar(
        initials: _initials(contact.displayName),
        imageUrl: contact.avatarUrl,
        size: 40,
      ),
      name: contact.displayName.isEmpty
          ? '@${contact.handle}'
          : contact.displayName,
      status: status,
      statusColor: color,
      onRemove: () async {
        if (!await _confirm(context, 'Remove ${contact.displayName}?',
            'They will no longer be alerted.')) {
          return;
        }
        if (!context.mounted) return;
        final uid = ref.read(currentUserIdProvider);
        if (uid == null) return;
        final repo = ref.read(safetyRepositoryProvider);
        await _run(context, () {
          return contact.status == SafetyContactStatus.accepted
              ? repo.revoke(contact.uid)
              : repo.remove(uid, contact.uid);
        });
      },
    );
  }
}

class _EmailContactRow extends ConsumerWidget {
  const _EmailContactRow({required this.contact});

  final EmailSafetyContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final (status, color) = switch (contact.status) {
      EmailContactStatus.confirmed => ('Ready · email alert', safetyTeal),
      EmailContactStatus.pending => (
          'Waiting for them to confirm by email',
          palette.muted
        ),
      _ => ('Declined', palette.danger),
    };
    return _ContactRow(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: palette.surfaceHigh,
        child: Icon(Icons.mail_outline_rounded, color: palette.muted, size: 20),
      ),
      name: contact.name,
      detail: contact.email,
      status: status,
      statusColor: color,
      onRemove: contact.status == EmailContactStatus.declined
          ? null
          : () async {
              if (!await _confirm(context, 'Remove ${contact.name}?',
                  'They will no longer be emailed if you raise an alert.')) {
                return;
              }
              if (!context.mounted) return;
              await _run(
                context,
                () => ref
                    .read(safetyRepositoryProvider)
                    .removeEmailContact(contact.id),
              );
            },
    );
  }
}

class _IncomingRow extends ConsumerWidget {
  const _IncomingRow({required this.contact});

  final SafetyContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final repo = ref.read(safetyRepositoryProvider);
    final name = contact.displayName.isEmpty
        ? '@${contact.handle}'
        : contact.displayName;

    if (contact.status == SafetyContactStatus.accepted) {
      return _ContactRow(
        leading: Avatar(
          initials: _initials(contact.displayName),
          imageUrl: contact.avatarUrl,
          size: 40,
        ),
        name: name,
        status: "You're their safety contact",
        statusColor: safetyTeal,
        removeLabel: 'Stop',
        onRemove: () async {
          if (!await _confirm(
            context,
            'Stop being $name\'s safety contact?',
            'They will be told, so they can choose someone else.',
          )) {
            return;
          }
          if (!context.mounted) return;
          await _run(context, () => repo.revoke(contact.uid));
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(
                initials: _initials(contact.displayName),
                imageUrl: contact.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '$name asked you to be their safety contact',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Text(
              'If they raise an alert you will get an urgent notification '
              'with their live location.',
              style: TextStyle(color: palette.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Row(
              children: [
                FilledButton(
                  onPressed: () => _run(
                    context,
                    () => repo.respond(ownerId: contact.uid, accept: true),
                  ),
                  child: const Text('Accept'),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () => _run(
                    context,
                    () => repo.respond(ownerId: contact.uid, accept: false),
                  ),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.leading,
    required this.name,
    required this.status,
    required this.statusColor,
    this.detail,
    this.onRemove,
    this.removeLabel = 'Remove',
  });

  final Widget leading;
  final String name;
  final String? detail;
  final String status;
  final Color statusColor;
  final VoidCallback? onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                Text(
                  status,
                  style: TextStyle(
                    color: palette.accent(statusColor),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            TextButton(onPressed: onRemove, child: Text(removeLabel)),
        ],
      ),
    );
  }
}

// --- Adding -----------------------------------------------------------------

Future<void> _showAddUserSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AddUserSheet(),
  );
}

class _AddUserSheet extends ConsumerStatefulWidget {
  const _AddUserSheet();

  @override
  ConsumerState<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends ConsumerState<_AddUserSheet> {
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final me = ref.watch(currentUserIdProvider);
    final results = _query.length < 2
        ? const AsyncValue.data(<Never>[])
        : ref.watch(userSearchResultsProvider(_query));

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search by name or username',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _query = value.trim());
                });
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: results.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                  child: Text(
                    "Couldn't search right now.",
                    style: TextStyle(color: palette.muted),
                  ),
                ),
                data: (users) {
                  final list = users.where((u) => u.id != me).toList();
                  if (_query.length >= 2 && list.isEmpty) {
                    return Center(
                      child: Text(
                        'Nobody found. Not on FitSocial? Add them by email.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.muted),
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final u in list)
                        ListTile(
                          leading: Avatar(
                            initials: u.initials,
                            imageUrl: u.avatarUrl,
                            size: 40,
                          ),
                          title: Text(u.displayName),
                          subtitle: Text('@${u.handle}'),
                          trailing: const Icon(Icons.person_add_alt_1_rounded),
                          onTap: () async {
                            final uid = ref.read(currentUserIdProvider);
                            if (uid == null) return;
                            final navigator = Navigator.of(context);
                            final ok = await _run(
                              context,
                              () => ref
                                  .read(safetyRepositoryProvider)
                                  .invite(uid, u.id),
                              success: 'Invite sent to ${u.displayName}',
                            );
                            if (ok) navigator.pop();
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddEmailDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AddEmailDialog(),
  );
}

class _AddEmailDialog extends ConsumerStatefulWidget {
  const _AddEmailDialog();

  @override
  ConsumerState<_AddEmailDialog> createState() => _AddEmailDialogState();
}

class _AddEmailDialogState extends ConsumerState<_AddEmailDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Add their name and a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final overlay = Overlay.of(context, rootOverlay: true);
    try {
      await ref
          .read(safetyRepositoryProvider)
          .addEmailContact(name: name, email: email);
      if (!mounted) return;
      Navigator.of(context).pop();
      showQuickToastOn(
        overlay,
        'We emailed $name to confirm',
        icon: Icons.mark_email_read_outlined,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: const Text('Add by email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "We'll email them once to ask if they agree. They won't be "
            'alerted until they confirm.',
            style: TextStyle(color: palette.muted, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            // Lifted off the dialog, which shares the theme's field colour.
            decoration: InputDecoration(
              labelText: 'Their name',
              fillColor: palette.surfaceHigh,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Email address',
              fillColor: palette.surfaceHigh,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: TextStyle(color: palette.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Send'),
        ),
      ],
    );
  }
}

// --- Helpers ----------------------------------------------------------------

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

String _messageFor(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'Something went wrong. Try again.';
  }
  return 'Something went wrong. Check your connection and try again.';
}

/// Runs a contact action and reports failure as a toast. Returns whether it
/// worked.
Future<bool> _run(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  try {
    await action();
    if (success != null) {
      showQuickToastOn(overlay, success, icon: Icons.check_rounded);
    }
    return true;
  } catch (e) {
    showQuickToastOn(
      overlay,
      _messageFor(e),
      icon: Icons.error_outline_rounded,
      tone: ToastTone.danger,
    );
    return false;
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  return result ?? false;
}
