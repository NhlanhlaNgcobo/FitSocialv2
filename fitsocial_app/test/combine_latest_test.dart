import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/shared/async/combine_latest.dart';

void main() {
  group('combineLatestLists', () {
    test('no sources is an empty result, not a stream that never speaks',
        () async {
      expect(await combineLatestLists<int>(const []).first, isEmpty);
    });

    test('one source passes straight through', () async {
      final merged = combineLatestLists([
        Stream.value([1, 2]),
      ]);

      expect(await merged.first, [1, 2]);
    });

    test('waits for every source before emitting a union', () async {
      final first = StreamController<List<int>>();
      final second = StreamController<List<int>>();
      addTearDown(first.close);
      addTearDown(second.close);

      final seen = <List<int>>[];
      final subscription =
          combineLatestLists([first.stream, second.stream]).listen(seen.add);
      addTearDown(subscription.cancel);

      first.add([1]);
      await pumpEventQueue();
      // One chunk in hand is a partial picture, and a partial tray is worse
      // than a tray a moment late.
      expect(seen, isEmpty);

      second.add([2]);
      await pumpEventQueue();
      expect(seen, [
        [1, 2],
      ]);
    });

    test('re-emits the whole union when one source updates', () async {
      final first = StreamController<List<int>>();
      final second = StreamController<List<int>>();
      addTearDown(first.close);
      addTearDown(second.close);

      final seen = <List<int>>[];
      final subscription =
          combineLatestLists([first.stream, second.stream]).listen(seen.add);
      addTearDown(subscription.cancel);

      first.add([1]);
      second.add([2]);
      await pumpEventQueue();

      first.add([1, 3]);
      await pumpEventQueue();

      expect(seen, [
        [1, 2],
        [1, 3, 2],
      ]);
    });

    test('forwards an error rather than hiding a chunk that failed', () async {
      final first = StreamController<List<int>>();
      final second = StreamController<List<int>>();
      addTearDown(first.close);
      addTearDown(second.close);

      Object? error;
      final subscription = combineLatestLists([first.stream, second.stream])
          .listen((_) {}, onError: (Object e) => error = e);
      addTearDown(subscription.cancel);

      first.addError(StateError('permission denied'));
      await pumpEventQueue();

      expect(error, isA<StateError>());
    });

    test('closes once every source has closed', () async {
      final first = StreamController<List<int>>();
      final second = StreamController<List<int>>();

      var done = false;
      final subscription = combineLatestLists([first.stream, second.stream])
          .listen((_) {}, onDone: () => done = true);
      addTearDown(subscription.cancel);

      await first.close();
      await pumpEventQueue();
      expect(done, isFalse);

      await second.close();
      await pumpEventQueue();
      expect(done, isTrue);
    });

    test('cancelling the union cancels the sources', () async {
      final first = StreamController<List<int>>();
      final second = StreamController<List<int>>();
      addTearDown(first.close);
      addTearDown(second.close);

      final subscription =
          combineLatestLists([first.stream, second.stream]).listen((_) {});
      await pumpEventQueue();
      expect(first.hasListener, isTrue);
      expect(second.hasListener, isTrue);

      await subscription.cancel();
      await pumpEventQueue();

      expect(first.hasListener, isFalse);
      expect(second.hasListener, isFalse);
    });
  });
}
