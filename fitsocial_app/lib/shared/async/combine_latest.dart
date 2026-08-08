import 'dart:async';

/// One stream carrying the union of several list streams.
///
/// Firestore caps how many values an `in` filter may hold, so a query over the
/// people someone follows has to be split into chunks and run in parallel.
/// Each chunk is its own live query with its own stream; this joins them back
/// into the single list the UI thinks it is reading.
///
/// The union is emitted only once every source has reported, so a partial
/// picture never reaches the screen — the chunks are issued together and land
/// within a round trip of each other. After that, any source updating emits
/// the new union.
///
/// Errors are forwarded rather than swallowed: a chunk that fails is a feed
/// missing people, which the caller should be told about. The result closes
/// when every source has closed.
Stream<List<T>> combineLatestLists<T>(List<Stream<List<T>>> sources) {
  if (sources.isEmpty) return Stream.value(const []);
  if (sources.length == 1) return sources.single;

  final subscriptions = <StreamSubscription<List<T>>>[];
  final latest = List<List<T>?>.filled(sources.length, null);
  var openSources = sources.length;

  late final StreamController<List<T>> controller;

  void emit() {
    if (latest.any((chunk) => chunk == null)) return;
    controller.add([for (final chunk in latest) ...chunk!]);
  }

  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        final index = i;
        subscriptions.add(
          sources[index].listen(
            (chunk) {
              latest[index] = chunk;
              emit();
            },
            onError: controller.addError,
            onDone: () {
              openSources--;
              if (openSources == 0) controller.close();
            },
          ),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    },
  );

  return controller.stream;
}
