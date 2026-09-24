import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/safety_repository_contract.dart';
import '../domain/safety_alerts.dart';
import '../domain/safety_models.dart';

@immutable
class LocationShareState {
  const LocationShareState({
    this.shareId,
    this.expiresAt,
    this.isStarting = false,
    this.errorMessage,
  });

  static const idle = LocationShareState();

  final String? shareId;
  final DateTime? expiresAt;
  final bool isStarting;
  final String? errorMessage;

  /// Drives the persistent in-app indicator. Whenever this is true the owner
  /// must be able to see it and stop it in one tap.
  bool get isSharing => shareId != null;
}

/// Shares the owner's position with chosen safety contacts while the app is
/// in the foreground. See spec A.4.
///
/// Writes are throttled to one per [writeInterval] however often the OS
/// delivers fixes, and each write replaces the single `current` field — no
/// per-tick history, which would multiply the write cost for nothing v1 uses.
/// The share stops itself at its expiry; the server closes it too, for the
/// phone that died before it could.
class LocationShareController extends StateNotifier<LocationShareState> {
  LocationShareController({
    required LocationShareRepository repository,
    required Stream<PanicPosition> Function() positions,
    required Future<int?> Function() battery,
    DateTime Function()? now,
  })  : _repository = repository,
        _positions = positions,
        _battery = battery,
        _now = now ?? DateTime.now,
        super(LocationShareState.idle);

  static const Duration writeInterval = Duration(seconds: 30);

  final LocationShareRepository _repository;
  final Stream<PanicPosition> Function() _positions;
  final Future<int?> Function() _battery;
  final DateTime Function() _now;

  StreamSubscription<PanicPosition>? _sub;
  Timer? _expiry;
  DateTime? _lastWriteAt;
  bool _writing = false;

  Future<void> start({
    required String ownerId,
    required String ownerName,
    required List<String> viewerIds,
    required Duration duration,
  }) async {
    if (state.isSharing || state.isStarting || viewerIds.isEmpty) return;
    state = const LocationShareState(isStarting: true);
    final capped = duration > LocationShare.maxDuration
        ? LocationShare.maxDuration
        : duration;
    try {
      final id = await _repository.start(
        ownerId: ownerId,
        ownerName: ownerName,
        viewerIds: viewerIds,
        duration: capped,
      );
      if (!mounted) return;
      state = LocationShareState(shareId: id, expiresAt: _now().add(capped));
      _lastWriteAt = null;
      _sub = _positions().listen(_onPosition, onError: (_) {});
      _expiry = Timer(capped, () => unawaited(stop()));
    } catch (e) {
      if (!mounted) return;
      state = LocationShareState(errorMessage: 'Could not start sharing: $e');
    }
  }

  Future<void> _onPosition(PanicPosition p) async {
    final id = state.shareId;
    final expiresAt = state.expiresAt;
    if (id == null || _writing) return;
    if (expiresAt != null && !_now().isBefore(expiresAt)) {
      await stop();
      return;
    }
    final last = _lastWriteAt;
    if (last != null && _now().difference(last) < writeInterval) return;

    _writing = true;
    try {
      await _repository.update(
        id,
        SharedPosition(
          lat: p.lat,
          lng: p.lng,
          accuracy: p.accuracy,
          batteryPercent: await _battery(),
        ),
      );
      _lastWriteAt = _now();
    } catch (_) {
      // Left for the next fix. A missed write is a marker a little behind.
    } finally {
      _writing = false;
    }
  }

  /// One tap, from the indicator.
  Future<void> stop() async {
    final id = state.shareId;
    if (id == null) return;
    _teardown();
    state = LocationShareState.idle;
    try {
      await _repository.stop(id);
    } catch (_) {
      // The scheduled expiry closes it regardless.
    }
  }

  void _teardown() {
    _sub?.cancel();
    _expiry?.cancel();
    _sub = null;
    _expiry = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
