import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../features/main/domain/shared_post.dart';
import '../links/share_links.dart';
import '../services/meal_card_exporter.dart';
import '../services/meal_card_saver.dart';
import '../services/run_card_exporter.dart';
import '../services/run_card_saver.dart';
import 'quick_toast.dart';
import 'liquid_glass.dart';

/// The ways a post leaves the screen it is on.
enum _ShareChoice {
  /// Onto the sharer's own Pulse, as a card that opens the post.
  pulse,

  /// Out of FitSocial entirely, through the OS share sheet.
  external,

  /// The link on its own, for pasting somewhere the share sheet doesn't reach.
  copyLink,

  /// The run or meal card itself, drawn to a file and put in the camera roll.
  /// Only offered on a post that has a card to draw.
  saveImage,
}

/// Opens the share options for [post].
///
/// Two destinations, which is the split Instagram uses: *inside* the app, where
/// a share means putting the post on your own Pulse, and *outside* it, where a
/// share means handing someone a link. Of the post's own content only its run
/// or meal card leaves, and only when the reader asks for it by name — never
/// the caption, never the photo on its own. Someone who receives a link and
/// has FitSocial opens the post; someone who doesn't gets the page that offers
/// the app. See [FitSocialLinks].
///
/// [runCard] and [mealCard] both decide whether the save row appears and say
/// what it should draw, because [SharedPostRef] carries neither the route nor
/// the macros the cards read their numbers out of. A post is never both, so at
/// most one is ever non-null.
Future<void> showPostShareSheet(
  BuildContext context,
  SharedPostRef post, {
  RunCardExport? runCard,
  MealCardExport? mealCard,
}) async {
  final palette = context.palette;
  final canSaveImage = (runCard != null || mealCard != null) && !kIsWeb;

  final choice = await showModalBottomSheet<_ShareChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    // The sheet may be opened from inside another sheet (Explore's post peek),
    // so it goes on the root navigator or it would be trapped under that one.
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => LiquidGlass(
      // Over the screen it was opened from, so there is real content to bend.
      lens: true,
      // A sheet always has a page behind it, which makes it the one surface in
      // the app guaranteed something worth bending.
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _ShareOption(
              icon: Icons.bolt_rounded,
              label: 'Add to your Pulse',
              detail: 'Share it as a card for 24 hours',
              onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.pulse),
            ),
            _ShareOption(
              icon: Icons.ios_share_rounded,
              label: 'Share to…',
              detail: 'Send a link through another app',
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ShareChoice.external),
            ),
            _ShareOption(
              icon: Icons.link_rounded,
              label: 'Copy link',
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ShareChoice.copyLink),
            ),
            // Last, and the only row here that hands over a file rather than a
            // link — the three above it are one set.
            if (canSaveImage)
              _ShareOption(
                icon: Icons.download_rounded,
                label: 'Save image',
                detail: 'Put this card in your photos',
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ShareChoice.saveImage),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    ),
  );

  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _ShareChoice.pulse:
      // The post rides as `extra` — the composer is drawing the snapshot the
      // user just tapped, not re-fetching it.
      context.push('/share-to-pulse', extra: post);
    case _ShareChoice.external:
      await sharePostLink(context, post);
    case _ShareChoice.copyLink:
      await copyPostLink(context, post);
    case _ShareChoice.saveImage:
      if (runCard != null) {
        await saveRunCardImage(context, runCard);
      } else if (mealCard != null) {
        await saveMealCardImage(context, mealCard);
      }
  }
}

/// Draws [card] into the camera roll, saying either way what happened.
///
/// Lives here rather than in the row that shares its logic because this one is
/// reached from a sheet that has already closed: there is no button left to put
/// a spinner on, so the toast is the whole of the feedback.
Future<void> saveRunCardImage(BuildContext context, RunCardExport card) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  try {
    final bytes = await renderRunCardPng(context, card);
    await saveImageToGallery(bytes, name: runCardFileName());
    if (overlay == null) return;
    showQuickToastOn(overlay, 'Saved to your photos', tone: ToastTone.success);
  } catch (error) {
    reportRunCardFailure(overlay, error);
  }
}

/// [saveRunCardImage]'s meal-flavoured twin.
Future<void> saveMealCardImage(BuildContext context, MealCardExport card) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  try {
    final bytes = await renderMealCardPng(context, card);
    await saveImageToGallery(bytes, name: mealCardFileName());
    if (overlay == null) return;
    showQuickToastOn(overlay, 'Saved to your photos', tone: ToastTone.success);
  } catch (error) {
    reportMealCardFailure(overlay, error);
  }
}

/// Hands the post's link to the OS share sheet.
///
/// A [Uri] rather than text: iOS fetches the page behind it and shows its title
/// and icon in the sheet, which is what makes a shared post look like a shared
/// post instead of a bare string. [ShareParams.subject] is the fallback for
/// destinations that want a title — email, mostly.
Future<void> sharePostLink(BuildContext context, SharedPostRef post) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  try {
    await SharePlus.instance.share(
      ShareParams(
        uri: FitSocialLinks.post(post.postId),
        subject: '${post.authorName} on FitSocial',
        title: '${post.authorName} on FitSocial',
        // Anchors the popover on iPad and macOS, where a share sheet has to
        // come from somewhere. Ignored everywhere else.
        sharePositionOrigin: shareOriginOf(context),
      ),
    );
  } catch (_) {
    // No share sheet on this device, or the platform refused. Falling back to
    // the clipboard means the link is still in the user's hands.
    await Clipboard.setData(
      ClipboardData(text: FitSocialLinks.post(post.postId).toString()),
    );
    if (overlay == null) return;
    showQuickToastOn(
      overlay,
      'Link copied instead',
      icon: Icons.link_rounded,
    );
  }
}

/// Puts the post's link on the clipboard.
Future<void> copyPostLink(BuildContext context, SharedPostRef post) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  await Clipboard.setData(
    ClipboardData(text: FitSocialLinks.post(post.postId).toString()),
  );
  if (overlay == null) return;
  showQuickToastOn(overlay, 'Link copied', icon: Icons.link_rounded);
}

/// Where the tapped control is on screen, for platforms that pop the share
/// sheet out of it. Null when the widget has already gone.
///
/// Public because saving the run card shares a file from the same sheets and
/// wants the same anchor.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;

  /// The second line, for the two options whose consequence isn't obvious from
  /// their name. "Copy link" needs no explanation and gets none.
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      leading: Icon(icon, color: palette.text),
      title: Text(
        label,
        style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
      ),
      subtitle: detail == null
          ? null
          : Text(
              detail!,
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
      onTap: onTap,
    );
  }
}
