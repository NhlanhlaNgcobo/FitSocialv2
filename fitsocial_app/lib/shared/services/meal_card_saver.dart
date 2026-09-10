import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/quick_toast.dart';
import '../widgets/share_sheet.dart' show shareOriginOf;
import 'meal_card_exporter.dart';
import 'run_card_saver.dart' show RunCardSaveException;

/// Says why the card did not get saved, whatever went wrong.
///
/// Mirrors [reportRunCardFailure] exactly — the gallery write itself is
/// [saveImageToGallery], reused as-is from the run flow, so its failures still
/// come back as [RunCardSaveException] here too.
void reportMealCardFailure(OverlayState? overlay, Object error) {
  if (overlay == null) return;
  final denied = error is RunCardSaveException && error.deniedAccess;
  showQuickToastOn(
    overlay,
    switch (error) {
      RunCardSaveException(:final message) => message,
      MealCardExportException(:final message) => message,
      _ => "Couldn't save the card",
    },
    icon: Icons.error_outline_rounded,
    tone: ToastTone.danger,
    actionLabel: denied ? 'Settings' : null,
    onAction: denied ? openAppSettings : null,
  );
}

/// A name a gallery will show without embarrassing itself, unique per save.
String mealCardFileName() =>
    'fitsocial-meal-${DateTime.now().millisecondsSinceEpoch}';

/// Hands [bytes] to the OS share sheet as a PNG file.
///
/// Identical to [shareImageFile] except for the subject line — duplicated
/// rather than parameterising that one, so a meal share can never be signed
/// with "My run on FitSocial" by a stray default.
Future<void> shareMealCardFile(
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
      subject: 'My meal on FitSocial',
      // Anchors the popover on iPad and macOS. Ignored everywhere else.
      sharePositionOrigin: origin,
    ),
  );
}
