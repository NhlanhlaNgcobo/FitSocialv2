import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/quick_toast.dart';
import '../widgets/share_sheet.dart' show shareOriginOf;
import 'run_card_exporter.dart';

/// A save that did not happen, carrying the line to show the user.
class RunCardSaveException implements Exception {
  const RunCardSaveException(this.message, {this.deniedAccess = false});

  /// Written for the toast, not for a log.
  final String message;

  /// The user turned photo access down, so the only thing that will fix this is
  /// Settings — worth an action on the toast rather than a retry.
  final bool deniedAccess;

  @override
  String toString() => 'RunCardSaveException: $message';
}

/// Says why the card did not get saved, whatever went wrong.
///
/// The catch-all matters more than the two named cases: a plugin that failed to
/// register, a platform channel that threw, an OS that refused for a reason it
/// did not name — none of that is actionable, but letting it pass in silence
/// makes the button look dead, which is exactly how a missing build reads too.
void reportRunCardFailure(OverlayState? overlay, Object error) {
  if (overlay == null) return;
  final denied = error is RunCardSaveException && error.deniedAccess;
  showQuickToastOn(
    overlay,
    switch (error) {
      RunCardSaveException(:final message) => message,
      RunCardExportException(:final message) => message,
      _ => "Couldn't save the card",
    },
    icon: Icons.error_outline_rounded,
    tone: ToastTone.danger,
    actionLabel: denied ? 'Settings' : null,
    onAction: denied ? openAppSettings : null,
  );
}

/// A name a gallery will show without embarrassing itself, unique per save.
String runCardFileName() =>
    'fitsocial-run-${DateTime.now().millisecondsSinceEpoch}';

/// Writes [bytes] into the device's photo library.
///
/// Access is left to `gal`, which knows the split this app would otherwise get
/// wrong: from API 29 an Android MediaStore insert needs no permission at all,
/// below it needs WRITE_EXTERNAL_STORAGE, and `permission_handler`'s
/// `Permission.photos` is the *read* grant either way.
Future<void> saveImageToGallery(
  Uint8List bytes, {
  required String name,
}) async {
  try {
    if (!await Gal.hasAccess()) {
      if (!await Gal.requestAccess()) {
        throw const RunCardSaveException(
          'FitSocial needs permission to save photos',
          deniedAccess: true,
        );
      }
    }
    // No album: naming one asks iOS for full read-write access to the library,
    // which turns a one-tap save into the big prompt. Add-only is enough.
    await Gal.putImageBytes(bytes, name: name);
  } on GalException catch (error) {
    throw RunCardSaveException(
      switch (error.type) {
        GalExceptionType.accessDenied => 'FitSocial needs permission to save '
            'photos',
        GalExceptionType.notEnoughSpace => 'No room left on this phone',
        GalExceptionType.notSupportedFormat ||
        GalExceptionType.unexpected =>
          "Couldn't save the card",
      },
      deniedAccess: error.type == GalExceptionType.accessDenied,
    );
  }
}

/// Hands [bytes] to the OS share sheet as a PNG file.
///
/// The file goes to the temporary directory rather than the documents one that
/// holds run drafts: a draft is the only copy of a run and has to survive, this
/// is scratch the OS is welcome to reclaim once the share is done.
Future<void> shareImageFile(
  BuildContext context,
  Uint8List bytes, {
  required String name,
}) async {
  final origin = shareOriginOf(context);
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$name.png');
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png', name: '$name.png')],
      subject: 'My run on FitSocial',
      // Anchors the popover on iPad and macOS. Ignored everywhere else.
      sharePositionOrigin: origin,
    ),
  );
}
