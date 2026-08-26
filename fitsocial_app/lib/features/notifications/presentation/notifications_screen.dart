import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../../shared/widgets/staggered_fade_in.dart';
import '../application/notification_providers.dart';
import '../domain/notification_models.dart';
import '../../music/presentation/music_island_action.dart';

/// Who followed you, and who liked what you posted.
///
/// Opening the screen is what marks the list read — the badge on the home bell
/// is answered by looking, not by tapping every row. The rows that were unread
/// when it opened stay highlighted for the rest of the visit, so "what's new"
/// survives the flags being cleared underneath it.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  /// Ids that were unread when the list first arrived. Frozen on purpose: the
  /// stream reports them as read a moment later, and the highlight should not
  /// evaporate while the user is still reading.
  Set<String>? _newOnArrival;

  /// Drives the rows in on the first paint. One-shot: the list rebuilds every
  /// time the stream ticks, and re-running it on each of those would make the
  /// screen twitch while the user is reading.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  void _onFirstLoad(List<FitNotification> items) {
    if (_newOnArrival != null) return;

    _newOnArrival = {
      for (final item in items)
        if (!item.isRead) item.id,
    };
    final hasUnread = _newOnArrival!.isNotEmpty;

    // After the frame: this runs from inside build, so neither the animation
    // nor the write may touch anything the current build depends on. The write
    // comes back through the same stream the list is built from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entrance.forward();
      if (hasUnread) ref.read(markNotificationsReadProvider)();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);

    // Read before the tree is built rather than from inside the `data` branch,
    // so the count beside the title is right on the very first paint.
    final loaded = notifications.valueOrNull;
    if (loaded != null) _onFirstLoad(loaded);
    final newCount = _newOnArrival?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Notifications'),
            if (newCount > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              _NewCountPill(count: newCount),
            ],
          ],
        ),
        actions: const [MusicIslandAction()],
      ),
      body: notifications.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: context.palette.brand),
        ),
        error: (_, __) => const _Message(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load notifications",
          message: 'Check your connection and try again.',
        ),
        data: (items) {
          if (items.isEmpty) return const _EmptyState();

          final now = DateTime.now();
          final entries = _buildEntries(items, now);

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final section = entry.section;
              final notification = entry.notification;

              return StaggeredFadeIn(
                controller: _entrance,
                index: index,
                itemCount: 12,
                child: section != null
                    ? _SectionHeader(section: section, isFirst: index == 0)
                    : _NotificationRow(
                        notification: notification!,
                        isNew:
                            _newOnArrival?.contains(notification.id) ?? false,
                        now: now,
                      ),
              );
            },
          );
        },
      ),
    );
  }

  /// Flattens the list into headers and rows.
  ///
  /// Everything unread on arrival leads under "New", whatever its age, and the
  /// rest falls into date buckets. Partitioned rather than walked in order so
  /// each header can only ever be emitted once — an old notification that was
  /// still unread would otherwise open a second "New" halfway down the list.
  List<_Entry> _buildEntries(List<FitNotification> items, DateTime now) {
    final fresh = <FitNotification>[];
    final byAge = <_Section, List<FitNotification>>{};

    for (final item in items) {
      if (_newOnArrival?.contains(item.id) ?? false) {
        fresh.add(item);
        continue;
      }
      byAge.putIfAbsent(_ageSection(item.createdAt, now), () => []).add(item);
    }

    final entries = <_Entry>[];
    void addGroup(_Section section, List<FitNotification> group) {
      if (group.isEmpty) return;
      entries.add(_Entry.header(section));
      entries.addAll(group.map(_Entry.row));
    }

    addGroup(_Section.fresh, fresh);
    for (final section in const [
      _Section.today,
      _Section.week,
      _Section.earlier,
    ]) {
      addGroup(section, byAge[section] ?? const []);
    }
    return entries;
  }
}

/// The bands the list is divided into.
enum _Section {
  /// Unread when the screen opened.
  fresh('New'),
  today('Today'),
  week('This week'),
  earlier('Earlier');

  const _Section(this.label);

  final String label;
}

/// Which date bucket a already-read notification falls in. Calendar-day based
/// rather than "within 24 hours", because "Today" is read as a date and
/// something from last night should not still be filed under it at noon.
_Section _ageSection(DateTime? createdAt, DateTime now) {
  // A missing or future timestamp is the moment before the server clock
  // resolves — that is as "today" as it gets.
  if (createdAt == null || createdAt.isAfter(now)) return _Section.today;

  final startOfToday = DateTime(now.year, now.month, now.day);
  if (!createdAt.isBefore(startOfToday)) return _Section.today;
  if (now.difference(createdAt).inDays < 7) return _Section.week;
  return _Section.earlier;
}

/// One line of the flattened list: a band header, or a notification.
class _Entry {
  const _Entry.header(_Section this.section) : notification = null;

  const _Entry.row(FitNotification this.notification) : section = null;

  final _Section? section;
  final FitNotification? notification;
}

/// The background a row actually sits on — which is also the colour the little
/// type badge cuts itself out of, so the two can't drift apart.
Color _rowFill(AppPalette palette, {required bool isNew}) {
  if (!isNew) return palette.background;
  // Blended rather than layered, so the badge's ring can be given this exact
  // colour instead of a translucent one that would show the avatar through it.
  return Color.alphaBlend(
    palette.brand.withValues(alpha: 0.09),
    palette.background,
  );
}

/// The accent that identifies what happened, on the badge and nowhere else.
/// A reaction brings its own colour so 🔥 and 🏆 don't both land on orange.
Color _accentFor(FitNotification notification, AppPalette palette) {
  switch (notification.type) {
    case FitNotificationType.follow:
      return palette.brand;
    case FitNotificationType.like:
      return palette.accent(
        notification.reaction?.accent ?? const Color(0xFFE23D5A),
      );
    case FitNotificationType.mention:
    case FitNotificationType.tag:
      return palette.accent(const Color(0xFF3AA9C9));
    // The three challenge kinds share the brand orange, which is what the
    // challenge screens are already painted in — a fourth accent would be a
    // colour that means nothing anywhere else in the app.
    case FitNotificationType.challengeInvite:
    case FitNotificationType.challengeAccepted:
    case FitNotificationType.challengeCompleted:
      return palette.brand;
  }
}

class _NewCountPill extends StatelessWidget {
  const _NewCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: context.palette.brand,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count new',
        style: const TextStyle(
          color: AppColors.onBrand,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.isFirst});

  final _Section section;

  /// The top of the list already has the app bar above it, so the first header
  /// doesn't need the full gap the later ones use to separate two bands.
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isFresh = section == _Section.fresh;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md + 4,
        isFirst ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (isFresh) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.palette.brand,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            section.label.toUpperCase(),
            style: TextStyle(
              color: isFresh ? palette.brandText : palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.isNew,
    required this.now,
  });

  final FitNotification notification;

  /// Unread when the screen opened, which earns the row a tinted card.
  final bool isNew;

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final route = notification.route;
    // A row in a list, not a pane on the page: the tighter of the two radii,
    // so a highlighted row reads as nested inside the list rather than as a
    // card that happens to be the width of one.
    final radius = BorderRadius.circular(AppRadius.nested);
    final fill = _rowFill(palette, isNew: isNew);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: 2,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isNew ? fill : Colors.transparent,
          borderRadius: radius,
          border: isNew ? Border.all(color: palette.brandSoftStroke) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: route == null ? null : () => context.push(route),
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              child: Row(
                children: [
                  // The avatar goes to the person even when the row goes to a
                  // post — on a like, those are two different destinations.
                  GestureDetector(
                    onTap: () => context.push('/user/${notification.actorId}'),
                    child: _ActorAvatar(
                      notification: notification,
                      ringColor: fill,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: notification.actorName,
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: ' ${notification.message}',
                            style: TextStyle(color: palette.text),
                          ),
                          TextSpan(
                            text:
                                '  ·  ${notificationAgeLabel(notification.createdAt, now)}',
                            style: TextStyle(
                              color: palette.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, height: 1.35),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  _Trailing(notification: notification),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The actor's photo with a small glyph on the corner saying what they did, so
/// a follow and a like are told apart before the sentence is read.
class _ActorAvatar extends StatelessWidget {
  const _ActorAvatar({required this.notification, required this.ringColor});

  final FitNotification notification;

  /// What the badge cuts itself out of: the row's own fill, so the ring reads
  /// as a gap rather than as a grey outline on a tinted card.
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(notification, context.palette);

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        children: [
          Avatar(
            initials: notificationInitials(notification.actorName),
            size: 48,
            imageUrl: notification.actorAvatarUrl,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                // Cuts the glyph out of the avatar rather than letting it
                // blend into whatever photo is behind it.
                border: Border.all(color: ringColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              // The glyph stays a heart even when a reaction was given: the
              // emoji is already in the sentence beside it, and the disc's
              // colour is what carries which reaction it was.
              child: Icon(
                _glyph(notification.type),
                size: 11,
                color: AppColors.onBrand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The badge that says what happened, before the sentence is read. A mention
  /// and a tag get the same '@' — both mean "your name is on this" — and are
  /// told apart by the words beside them.
  static IconData _glyph(FitNotificationType type) {
    switch (type) {
      case FitNotificationType.follow:
        return Icons.person_add_alt_1_rounded;
      case FitNotificationType.like:
        return Icons.favorite_rounded;
      case FitNotificationType.mention:
      case FitNotificationType.tag:
        return Icons.alternate_email_rounded;
      case FitNotificationType.challengeInvite:
        return Icons.emoji_events_outlined;
      case FitNotificationType.challengeAccepted:
        return Icons.group_add_rounded;
      case FitNotificationType.challengeCompleted:
        return Icons.emoji_events_rounded;
    }
  }
}

/// A follow-back button on a follow; a thumbnail of the post on everything
/// else, which is what those all hang off.
class _Trailing extends StatelessWidget {
  const _Trailing({required this.notification});

  final FitNotification notification;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    if (notification.type == FitNotificationType.follow) {
      return FollowButton(
        targetUserId: notification.actorId,
        shape: FollowButtonShape.compact,
      );
    }

    final imageUrl = notification.postImageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      // Nothing to show: a text post has no thumbnail, and a grey square
      // standing in for one would only ask to be tapped.
      return const SizedBox.shrink();
    }

    final palette = context.palette;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        // A failed load takes the whole thumbnail with it, for the same reason
        // a text post never gets one. While it is still coming, though, the
        // slot is held open so the row doesn't jump when the picture lands.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                width: _size,
                height: _size,
                color: palette.surfaceHigh,
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const _Message(
      icon: Icons.notifications_none_rounded,
      title: 'Nothing here yet',
      message: 'When someone follows you, likes what you post or mentions '
          'you, it shows up here.',
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A glow that fades into the page, with the disc floating in the
            // middle of it — a flat circle on its own reads as a placeholder
            // that failed to load.
            Container(
              width: 132,
              height: 132,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.brand.withValues(alpha: 0.16),
                    palette.brand.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surface,
                  border: Border.all(color: palette.stroke),
                ),
                child: Icon(icon, size: 38, color: palette.brand),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.muted,
                height: 1.5,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
