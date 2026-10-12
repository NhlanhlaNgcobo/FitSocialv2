import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitsocial_app/features/settings/data/data_export.dart';

/// A response shaped like exportMyData's.
Map<String, dynamic> response(String json, Map<String, int> counts) => {
      'fileName': 'fitsocial-data-2026-10-02.json',
      'gzipBase64':
          base64Encode(const GZipEncoder().encodeBytes(utf8.encode(json))),
      'counts': counts,
    };

void main() {
  test('unzips the file the server sent', () {
    const json = '{"format":"fitsocial-export","meals":[{"id":"m1"}]}';
    final export = DataExport.fromResponse(response(json, {'meals': 1}));

    expect(export.fileName, 'fitsocial-data-2026-10-02.json');
    expect(utf8.decode(export.bytes), json);
    expect(export.counts, {'meals': 1});
  });

  test('sums up the three biggest sections', () {
    final export = DataExport.fromResponse(response('{}', {
      'meals': 412,
      'runs': 38,
      'posts': 120,
      'comments': 9,
      'workouts': 0,
    }));
    expect(export.summary, '412 meals, 120 posts and 38 runs');
  });

  test('an empty account still gets a sensible summary', () {
    expect(DataExport.fromResponse(response('{}', {'meals': 0})).summary,
        'Your account');
    expect(DataExport.fromResponse(response('{}', {'runs': 2})).summary,
        '2 runs');
  });
}
