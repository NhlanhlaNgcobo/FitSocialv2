import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';

/// The user's data, as the `exportMyData` function packed it.
class DataExport {
  const DataExport({
    required this.fileName,
    required this.bytes,
    required this.counts,
  });

  /// "fitsocial-data-2026-10-02.json"
  final String fileName;

  /// The JSON file, unzipped and ready to write.
  final Uint8List bytes;

  /// Entries per section — meals, runs, posts and so on.
  final Map<String, int> counts;

  /// Reads the function's response: a gzipped, base64-encoded JSON file.
  static DataExport fromResponse(Map<String, dynamic> data) {
    final zipped = base64Decode((data['gzipBase64'] ?? '').toString());
    final bytes = Uint8List.fromList(const GZipDecoder().decodeBytes(zipped));
    final rawCounts = data['counts'];
    return DataExport(
      fileName: (data['fileName'] as String?) ?? 'fitsocial-data.json',
      bytes: bytes,
      counts: {
        if (rawCounts is Map)
          for (final entry in rawCounts.entries)
            if (entry.value is num)
              entry.key.toString(): (entry.value as num).toInt(),
      },
    );
  }

  /// "412 meals, 38 runs and 120 posts" — the three biggest sections, for the
  /// message shown once the file is ready.
  String get summary {
    final sections = counts.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final parts = [
      for (final entry in sections.take(3)) '${entry.value} ${entry.key}',
    ];
    if (parts.isEmpty) return 'Your account';
    if (parts.length == 1) return parts.single;
    return '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
  }
}

/// Asks the server for everything the signed-in user has in FitSocial.
Future<DataExport> requestDataExport() async {
  final callable = appFunctions.httpsCallable(
    'exportMyData',
    // Generous: a long history is a few thousand documents to read and zip.
    options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
  );
  final result = await callable.call<Map<String, dynamic>>();
  return DataExport.fromResponse(Map<String, dynamic>.from(result.data));
}
