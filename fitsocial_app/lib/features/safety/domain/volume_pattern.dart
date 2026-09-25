/// A volume button press, as far as the pattern cares.
enum VolumeKey { up, down }

/// Recognises the silent-alert volume pattern: up, down, up, down — or the
/// same starting with down — inside [window].
///
/// Four alternating presses rather than two. A single up-then-down is what
/// anyone does when nudging the volume, and would send alerts by accident;
/// four quick alternating presses is something nobody does without meaning it.
///
/// Android only, and only while FitSocial is on screen: no app on either
/// platform may watch the volume buttons from the background, and iOS does not
/// report them to apps at all.
class VolumePattern {
  VolumePattern({this.window = const Duration(seconds: 2)});

  /// How long the four presses may take, first to last.
  final Duration window;

  static const int presses = 4;

  final List<(VolumeKey, DateTime)> _recent = [];

  /// Records one press. Returns true when it completes the pattern, and
  /// starts over so the same presses cannot fire twice.
  bool press(VolumeKey key, DateTime at) {
    // A press that repeats the previous direction breaks the alternation;
    // it becomes the first press of a possible new pattern.
    if (_recent.isNotEmpty && _recent.last.$1 == key) _recent.clear();
    _recent.add((key, at));
    while (_recent.length > presses) {
      _recent.removeAt(0);
    }
    _recent.removeWhere((p) => at.difference(p.$2) > window);
    if (_recent.length == presses) {
      _recent.clear();
      return true;
    }
    return false;
  }
}
