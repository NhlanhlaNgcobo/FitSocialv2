import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/quick_toast.dart';
import '../application/content_providers.dart';
import '../domain/shopping_list.dart';

/// Foods ticked off on the shopping list, by name.
///
/// Kept for the app session rather than saved: a list is ticked off during
/// one trip to the shop, and next week's list starts clean.
final shoppingTicksProvider = StateProvider<Set<String>>((ref) => const {});

/// A grocery app the list can be taken to.
///
/// The list is copied first and the shop opened second: none of these shops
/// offers a way for another app to fill a basket, so pasting into their search
/// is as close as the handover gets. Their websites rather than app-specific
/// links, because a phone with the shop's app installed opens the app from its
/// own site, and one without still lands somewhere useful.
enum GroceryShop {
  sixty60('Checkers Sixty60', 'https://www.checkers.co.za/'),
  woolies('Woolies', 'https://www.woolworths.co.za/'),
  pnpAsap('Pick n Pay asap!', 'https://www.pnp.co.za/');

  const GroceryShop(this.label, this.url);

  final String label;
  final String url;
}

class ShoppingListScreen extends ConsumerWidget {
  const ShoppingListScreen({super.key, this.today});

  /// For tests; the real screen uses the clock.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repeats = ref.watch(mealRepeatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Shopping List')),
      body: repeats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Message(
          icon: Icons.cloud_off_rounded,
          text: 'Could not load your repeating meals.',
          action: TextButton(
            onPressed: () => ref.invalidate(mealRepeatsProvider),
            child: const Text('Try again'),
          ),
        ),
        data: (repeats) {
          final list = ShoppingList.fromRepeats(
            repeats,
            today: today ?? DateTime.now(),
          );
          if (list.isEmpty) {
            return const _Message(
              icon: Icons.shopping_basket_outlined,
              text: 'Set a meal to repeat and the foods for the week ahead '
                  'show up here. Use ••• on any meal in your summary.',
            );
          }
          return _ListBody(list: list);
        },
      ),
    );
  }
}

class _ListBody extends ConsumerWidget {
  const _ListBody({required this.list});

  final ShoppingList list;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: list.toText()));
    if (context.mounted) {
      showQuickToast(context, 'List copied.', tone: ToastTone.success);
    }
  }

  Future<void> _openShop(BuildContext context, GroceryShop shop) async {
    await Clipboard.setData(ClipboardData(text: list.toText()));
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(shop.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Nothing to open it with. Same handling as a refusal.
    }
    if (!context.mounted) return;
    showQuickToast(
      context,
      opened
          ? 'List copied. Paste items into ${shop.label} search.'
          : 'List copied, but ${shop.label} could not be opened.',
      tone: opened ? ToastTone.success : ToastTone.neutral,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final ticks = ref.watch(shoppingTicksProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Text(
          '${list.itemCount} foods for the next 7 days, from your repeating '
          'meals. Amounts are what the meals use, not pack sizes.',
          style: TextStyle(color: palette.muted, fontSize: 13, height: 1.35),
        ),
        for (final entry in list.sections.entries) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            entry.key.label,
            style: TextStyle(
              color: palette.text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in entry.value)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: ticks.contains(item.name),
              onChanged: (checked) {
                final next = {...ticks};
                checked == true ? next.add(item.name) : next.remove(item.name);
                ref.read(shoppingTicksProvider.notifier).state = next;
              },
              title: Text(
                item.name,
                style: TextStyle(
                  color: ticks.contains(item.name) ? palette.muted : palette.text,
                  decoration: ticks.contains(item.name)
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              secondary: Text(
                item.amountLabel,
                style: TextStyle(color: palette.muted, fontSize: 13),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy list'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Shop with',
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final shop in GroceryShop.values)
              ActionChip(
                avatar: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(shop.label),
                onPressed: () => _openShop(context, shop),
              ),
          ],
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: palette.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, height: 1.4),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.sm),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
