import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts taps on the Home tab made while Home is already the tab showing.
///
/// The feed listens and answers each one by scrolling back to the top and
/// refreshing — the one gesture every social app shares, so the tab that is
/// already lit still does something. A count rather than a flag, so two taps
/// in a row are two events rather than one value set twice.
final homeTabReselectProvider = StateProvider<int>((ref) => 0);
