import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/follow_button.dart';
import '../application/notification_providers.dart';
import '../domain/notification_models.dart';

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

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Ids that were unread when the list first arrived. Frozen on purpose: the
  /// stream reports them as read a moment later, and the highlight should not
  /// evaporate while the user is still reading.
  Set<String>? _newOnArrival;

  void _onFirstLoad(List<FitNotification> items) {
    if (_newOnArrival != null) return;

    _newOnArrival = {
      for (final item in items)
        if (!item.isRead) item.id,
    };
    if (_newOnArrival!.isEmpty) return;

    // After the frame: this runs from inside build, and the write comes back
    // through the same stream the list is built from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(markNotificationsReadProvider)();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notifications.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orangeBright),
        ),
        error: (_, __) => const _Message(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load notifications",
          message: 'Check your connection and try again.',
        ),
        data: (items) {
          _onFirstLoad(items);
          if (items.isEmpty) return const _EmptyState();

          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (context, index) {
              final item = items[index];
              return _NotificationRow(
                notification: item,
                isNew: _newOnArrival?.contains(item.id) ?? false,
                now: now,
              );
            },
          );
        },
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

  /// Unread when the screen opened, which earns the row a tinted backing.
  final bool isNew;

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final route = notification.route;

    return Material(
      color: isNew
          ? AppColors.orangeBright.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: route == null ? null : () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
          child: Row(
            children: [
              // The avatar goes to the person even when the row goes to a
              // post — on a like, those are two different destinations.
              GestureDetector(
                onTap: () => context.push('/user/${notification.actorId}'),
                child: _ActorAvatar(notification: notification),
              ),
              const SizedBox(width: AppSpacing.md),
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
                            '  ${notificationAgeLabel(notification.createdAt, now)}',
                        style: TextStyle(color: palette.muted),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14.5, height: 1.35),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _Trailing(notification: notification),
            ],
          ),
        ),
      ),
    );
  }
}

/// The actor's photo with a small glyph on the corner saying what they did, so
/// a follow and a like are told apart before the sentence is read.
class _ActorAvatar extends StatelessWidget {
  const _ActorAvatar({required this.notification});

  final FitNotification notification;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          Avatar(
            initials: notificationInitials(notification.actorName),
            size: 46,
            imageUrl: notification.actorAvatarUrl,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.orangeBright,
                // Cuts the glyph out of the avatar rather than letting it
                // blend into whatever photo is behind it.
                border: Border.all(color: palette.background, width: 2),
              ),
              child: Icon(
                _glyph(notification.type),
                size: 10,
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
    }
  }
}

/// A follow-back button on a follow; a thumbnail of the post on everything
/// else, which is what those all hang off.
class _Trailing extends StatelessWidget {
  const _Trailing({required this.notification});

  final FitNotification notification;

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const SizedBox(width: 46, height: 46),
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surfaceHigh,
              ),
              child: Icon(icon, size: 40, color: AppColors.orangeBright),
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
              style: TextStyle(color: palette.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
