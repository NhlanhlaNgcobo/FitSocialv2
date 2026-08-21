import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../auth/domain/username.dart';
import '../application/content_providers.dart';
import '../domain/app_models.dart';
import '../domain/mentions.dart';
import '../../../shared/widgets/liquid_glass.dart';

/// "Tag people" — pick the accounts to attach to a post.
///
/// Returns the chosen list, or null when the sheet was dismissed without
/// confirming. The caller keeps the selection: a composer that loses its tags
/// because the sheet was reopened would be worse than one without tagging.
Future<List<TaggedUser>?> showTagPeopleSheet(
  BuildContext context, {
  required List<TaggedUser> selected,
}) {
  return showModalBottomSheet<List<TaggedUser>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useRootNavigator: true,
    builder: (_) => _TagPeopleSheet(initial: selected),
  );
}

class _TagPeopleSheet extends ConsumerStatefulWidget {
  const _TagPeopleSheet({required this.initial});

  final List<TaggedUser> initial;

  @override
  ConsumerState<_TagPeopleSheet> createState() => _TagPeopleSheetState();
}

class _TagPeopleSheetState extends ConsumerState<_TagPeopleSheet> {
  static const _debounce = Duration(milliseconds: 220);

  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  /// The term actually queried, which trails what has been typed.
  String _query = '';

  /// Ordered so the chips keep the order they were picked in, which is the
  /// order they will read in on the post.
  late final List<TaggedUser> _selected = List.of(widget.initial);

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  bool _isSelected(String id) => _selected.any((tagged) => tagged.id == id);

  void _toggle(UserSearchResult user) {
    setState(() {
      if (_isSelected(user.id)) {
        _selected.removeWhere((tagged) => tagged.id == user.id);
        return;
      }
      // The same ceiling mentions use. Tagging twenty people is a broadcast,
      // not a post about the two of you.
      if (_selected.length >= maxMentionsPerItem) return;
      _selected.add(
        TaggedUser(
          id: user.id,
          displayName: user.displayName,
          handle: normalizeUsername(user.handle),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = MediaQuery.of(context);
    final atLimit = _selected.length >= maxMentionsPerItem;

    return Padding(
      // The sheet floats over its own barrier, so nothing else lifts it clear
      // of the keyboard the search field raises.
      padding: EdgeInsets.only(
        bottom: math.max(media.viewInsets.bottom, media.viewPadding.bottom),
      ),
      child: LiquidGlass(
        // A sheet always has a page behind it, which makes it the
        // one surface guaranteed something worth bending.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(
                      'Tag people',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: palette.text,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.brandText,
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              _SearchField(
                controller: _searchController,
                onChanged: _onSearchChanged,
              ),
              if (_selected.isNotEmpty) _selectedChips(palette),
              Flexible(child: _results(palette, atLimit: atLimit)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedChips(AppPalette palette) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          0,
        ),
        child: Row(
          children: [
            for (final tagged in _selected) ...[
              _SelectedChip(
                tagged: tagged,
                onRemove: () => setState(
                  () => _selected.removeWhere((it) => it.id == tagged.id),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _results(AppPalette palette, {required bool atLimit}) {
    if (_query.isEmpty) {
      return _Hint(
        message: _selected.isEmpty
            ? 'Search for someone to tag in this post.'
            : 'Search again to tag someone else.',
      );
    }

    final resultsAsync = ref.watch(userSearchResultsProvider(_query));
    return resultsAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: context.palette.brand,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      error: (_, __) => const _Hint(message: "Couldn't search right now."),
      data: (results) {
        if (results.isEmpty) {
          return _Hint(message: 'Nobody found for "$_query".');
        }
        return ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final user = results[index];
            final selected = _isSelected(user.id);
            return _ResultTile(
              user: user,
              selected: selected,
              // A full list stays tappable for the people already on it, so
              // the way to undo a mistake is never greyed out.
              enabled: selected || !atLimit,
              onTap: () => _toggle(user),
            );
          },
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: LiquidGlass(
        // Painted by the lens rather than by a fill of its own: a pane
        // over the app backdrop, like every other card.
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.stroke),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            autofocus: true,
            style: TextStyle(color: palette.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search people',
              hintStyle: TextStyle(color: palette.muted),
              prefixIcon: Icon(Icons.search_rounded, color: palette.muted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.tagged, required this.onRemove});

  final TaggedUser tagged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label =
        tagged.handle.isEmpty ? tagged.displayName : '@${tagged.handle}';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: palette.brandSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.brandSoftStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.brandText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: palette.brandText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.user,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final UserSearchResult user;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final username = normalizeUsername(user.handle);

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 8,
          ),
          child: Row(
            children: [
              Avatar(
                initials: user.initials,
                size: 40,
                imageUrl: user.avatarUrl,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? palette.brand : palette.stroke,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
