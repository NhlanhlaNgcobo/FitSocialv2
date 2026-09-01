import 'dart:io';

/// Writes [bytes] to [file] via a sibling `.tmp` that is renamed over it.
///
/// A rename is atomic within a filesystem, so a process killed mid-write
/// leaves either the previous file or the complete new one — never half of
/// either. Both things this app keeps on disk need that: a run draft is the
/// only copy of a run that has not been uploaded, and the live-run checkpoint
/// is rewritten every twenty seconds, which is to say while the app is at its
/// most killable.
Future<void> writeFileAtomically(File file, List<int> bytes) async {
  final temp = File('${file.path}.tmp');
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(file.path);
}
