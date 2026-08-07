import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_models.dart';

/// Which tab the Activity screen is showing.
///
/// Which music services are linked is *not* here — that lives in
/// `musicConnectionsProvider`, backed by real OAuth sessions. Keeping the two
/// apart stops the UI from ever showing a service as connected when no token
/// exists for it.
class MusicIntegrationState {
  const MusicIntegrationState({
    this.selectedSection = ActivitySection.progress,
  });

  final ActivitySection selectedSection;

  MusicIntegrationState copyWith({ActivitySection? selectedSection}) {
    return MusicIntegrationState(
      selectedSection: selectedSection ?? this.selectedSection,
    );
  }
}

class MusicIntegrationController extends StateNotifier<MusicIntegrationState> {
  MusicIntegrationController() : super(const MusicIntegrationState());

  void selectSection(ActivitySection section) {
    state = state.copyWith(selectedSection: section);
  }
}

final musicIntegrationControllerProvider =
    StateNotifierProvider<MusicIntegrationController, MusicIntegrationState>(
  (ref) => MusicIntegrationController(),
);
