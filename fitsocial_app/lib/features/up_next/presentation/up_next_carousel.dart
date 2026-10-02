import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/liquid_glass.dart';
import '../application/up_next_providers.dart';
import '../domain/up_next.dart';

/// Up Next on the home feed: one to three suggestions for today, side by
/// side, each dismissible and each a way into the thing it suggests.
///
/// Draws nothing at all -- not even its spacing -- while Up Next is off or
/// there is nothing to suggest.
class UpNextCarousel extends ConsumerStatefulWidget {
  const UpNextCarousel({super.key});

  @override
  ConsumerState<UpNextCarousel> createState() => _UpNextCarouselState();
}

class _UpNextCarouselState extends ConsumerState<UpNextCarousel>
    with WidgetsBindingObserver {
  static const double _height = 118;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(upNextActionsProvider).maybeRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(upNextActionsProvider).maybeRefresh();
    }
  }

  /// Tab roots are switched to; everything else is pushed on top of home.
  void _open(String route) {
    const tabs = {'/home', '/explore', '/create', '/activity', '/profile'};
    if (tabs.contains(route)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Flags arrive after the first frame on a cold start; ask then, too.
    ref.listen<bool>(upNextEnabledProvider, (_, enabled) {
      if (enabled) ref.read(upNextActionsProvider).maybeRefresh();
    });
    ref.listen<AsyncValue<List<UpNextSuggestion>>>(upNextProvider, (_, next) {
      final actions = ref.read(upNextActionsProvider);
      for (final suggestion in next.valueOrNull ?? const []) {
        actions.shown(suggestion);
      }
    });

    if (!ref.watch(upNextEnabledProvider)) return const SizedBox.shrink();
    final suggestions = ref.watch(upNextProvider).valueOrNull ?? const [];
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'UP NEXT',
              style: TextStyle(
                color: palette.brandText,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          SizedBox(
            height: _height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // One suggestion takes the full width; more peek in from the
                // right so it reads as something to swipe.
                final width = suggestions.length == 1
                    ? constraints.maxWidth
                    : constraints.maxWidth * 0.82;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) => SizedBox(
                    width: width,
                    child: _SuggestionCard(
                      suggestion: suggestions[i],
                      onTap: () {
                        ref.read(upNextActionsProvider).tapped(suggestions[i]);
                        _open(suggestions[i].route);
                      },
                      onDismiss: () => ref
                          .read(upNextActionsProvider)
                          .dismiss(suggestions[i])
                          .catchError((_) {}),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.onTap,
    required this.onDismiss,
  });

  final UpNextSuggestion suggestion;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  IconData get _icon => switch (suggestion.kind) {
        'streak' => Icons.local_fire_department_rounded,
        'goal' => Icons.track_changes_rounded,
        'meal' => Icons.restaurant_rounded,
        _ => Icons.directions_run_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LiquidGlass(
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.stroke),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(_icon, color: palette.brand, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        suggestion.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Not today',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: palette.muted),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
