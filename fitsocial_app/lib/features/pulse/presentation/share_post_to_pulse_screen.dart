import 'package:flutter/material.dart';

import '../../../shared/widgets/shared_post_card.dart';
import '../../main/domain/shared_post.dart';
import '../domain/pulse_models.dart';
import 'pulse_share_scaffold.dart';

/// "Add this post to your Pulse" — Instagram's share-to-story, in FitSocial's
/// terms.
///
/// The same canvas the Pulse composer uses, with one thing already on it: the
/// post, as a card mounted on a gradient you pick. There is no camera and no
/// gallery here, because there is nothing to capture — the picture has already
/// been taken by somebody else, and this screen is about how you frame it.
///
/// Nothing is uploaded. The card is drawn from a snapshot written onto the
/// Pulse document, so publishing is a single write and the result opens the
/// original post when tapped.
class SharePostToPulseScreen extends StatelessWidget {
  const SharePostToPulseScreen({required this.post, super.key});

  final SharedPostRef post;

  @override
  Widget build(BuildContext context) {
    return PulseShareScaffold(
      canvas: SharedPostCard(post: post),
      buildDraft: (caption, gradientKey) => PulseDraft(
        type: PulseMediaType.post,
        text: caption,
        gradientKey: gradientKey,
        sharedPost: post,
      ),
    );
  }
}
