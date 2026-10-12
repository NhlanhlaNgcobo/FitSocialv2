import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../tracking/data/atomic_file.dart';
import '../domain/fitness_profile.dart';

/// Where the answers to onboarding Steps 1–2 wait for an account to exist.
abstract interface class OnboardingDraftStore {
  /// The saved draft, or null when there is none or it cannot be read.
  Future<OnboardingDraft?> read();

  Future<void> save(OnboardingDraft draft);

  Future<void> clear();
}

/// One JSON file under the app's documents directory.
///
/// On disk rather than in memory because the user leaves the app mid-flow by
/// design — the Google consent screen is another app — and Android is free to
/// kill this one while they are there. Documents rather than cache for the
/// same reason as `FileRunDraftStore`: cache is what the OS reclaims first.
///
/// Filed per device, not per user, because there is no user yet. It is
/// cleared once the answers reach Firestore.
class FileOnboardingDraftStore implements OnboardingDraftStore {
  FileOnboardingDraftStore(
      {required Future<Directory> Function() rootDirectory})
      : _rootDirectory = rootDirectory;

  /// Injected so tests can hand over a temp directory.
  final Future<Directory> Function() _rootDirectory;

  /// Writes are chained so a save can never land after the clear that was
  /// meant to follow it.
  Future<void> _pending = Future<void>.value();

  Future<File> _file() async {
    final root = await _rootDirectory();
    final directory = Directory('${root.path}/onboarding');
    await directory.create(recursive: true);
    return File('${directory.path}/draft.json');
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<OnboardingDraft?> read() async {
    // Queued behind writes, so a read straight after a save sees it.
    return _serialized(() async {
      try {
        final file = await _file();
        if (!await file.exists()) return null;
        return OnboardingDraft.fromJson(jsonDecode(await file.readAsString()));
      } catch (error) {
        // An unreadable draft costs the user a few taps, never a crash.
        debugPrint('Could not read the onboarding draft: $error');
        return null;
      }
    });
  }

  @override
  Future<void> save(OnboardingDraft draft) {
    return _serialized(() async {
      await writeFileAtomically(
        await _file(),
        utf8.encode(jsonEncode(draft.toJson())),
      );
    });
  }

  @override
  Future<void> clear() {
    return _serialized(() async {
      try {
        final file = await _file();
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('Could not clear the onboarding draft: $error');
      }
    });
  }
}

/// The web build's store: memory only.
///
/// There is no documents directory on web, and leaving the page for a sign-in
/// popup does not unload it, so memory is enough to carry the answers from
/// Step 1 to the flush.
class MemoryOnboardingDraftStore implements OnboardingDraftStore {
  MemoryOnboardingDraftStore();

  OnboardingDraft? _draft;

  @override
  Future<OnboardingDraft?> read() async => _draft;

  @override
  Future<void> save(OnboardingDraft draft) async => _draft = draft;

  @override
  Future<void> clear() async => _draft = null;
}
