import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/app_session.dart';
import '../../features/main/application/content_providers.dart';
import '../../features/main/data/content_repository.dart';
import '../reactions/fit_reaction.dart';

/// Double-tap anywhere on [child] to give the post a 🧡.
///
/// Only ever adds, never takes away — Instagram's rule, and the one people
/// expect: a second double-tap on something you already like is enthusiasm,
/// not a change of mind. A post already carrying a different reaction keeps
/// it; the burst still plays so the gesture never feels ignored.
class DoubleTapReact extends ConsumerStatefulWidget {
  const DoubleTapReact({
    required this.postId,
    required this.child,
    super.key,
  });

  final String postId;
  final Widget child;

  @override
  ConsumerState<DoubleTapReact> createState() => _DoubleTapReactState();
}

class _DoubleTapReactState extends ConsumerState<DoubleTapReact>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  Future<void> _onDoubleTap() async {
    HapticFeedback.lightImpact();
    _burst.forward(from: 0);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    final current = ref.read(postReactionProvider(widget.postId)).valueOrNull;
    if (current != null) return;

    await ref.read(contentRepositoryProvider).setPostReaction(
          widget.postId,
          userId,
          FitReaction.love,
          profile: ref.read(appSessionProvider).profile,
        );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _onDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _burst,
                  builder: (context, _) {
                    if (!_burst.isAnimating) return const SizedBox.shrink();
                    final t = _burst.value;
                    // Pops past full size, settles, then fades out.
                    final scale = t < 0.3
                        ? Curves.easeOutBack.transform(t / 0.3) * 1.15
                        : 1.15 - 0.15 * ((t - 0.3) / 0.7);
                    final opacity = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale,
                        child: Text(
                          FitReaction.love.emoji,
                          style: const TextStyle(
                            fontSize: 88,
                            shadows: [
                              Shadow(color: Color(0x55000000), blurRadius: 16),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
