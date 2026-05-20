import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_models.dart';

class MusicIntegrationState {
  const MusicIntegrationState({
    this.spotifyConnected = false,
    this.appleMusicConnected = false,
    this.selectedWorkoutType = WorkoutType.run,
    this.selectedPodcastCategory = PodcastCategory.mindset,
    this.selectedSection = ActivitySection.progress,
    this.primaryService,
    this.createdPlaylists = const <UserCreatedPlaylist>[],
  });

  final bool spotifyConnected;
  final bool appleMusicConnected;
  final WorkoutType selectedWorkoutType;
  final PodcastCategory selectedPodcastCategory;
  final ActivitySection selectedSection;
  final MusicProviderService? primaryService;
  final List<UserCreatedPlaylist> createdPlaylists;

  bool get hasAnyConnection => spotifyConnected || appleMusicConnected;

  bool isConnected(MusicProviderService service) {
    switch (service) {
      case MusicProviderService.spotify:
        return spotifyConnected;
      case MusicProviderService.appleMusic:
        return appleMusicConnected;
    }
  }

  MusicIntegrationState copyWith({
    bool? spotifyConnected,
    bool? appleMusicConnected,
    WorkoutType? selectedWorkoutType,
    PodcastCategory? selectedPodcastCategory,
    ActivitySection? selectedSection,
    MusicProviderService? primaryService,
    List<UserCreatedPlaylist>? createdPlaylists,
    bool clearPrimaryService = false,
  }) {
    return MusicIntegrationState(
      spotifyConnected: spotifyConnected ?? this.spotifyConnected,
      appleMusicConnected: appleMusicConnected ?? this.appleMusicConnected,
      selectedWorkoutType: selectedWorkoutType ?? this.selectedWorkoutType,
      selectedPodcastCategory:
          selectedPodcastCategory ?? this.selectedPodcastCategory,
      selectedSection: selectedSection ?? this.selectedSection,
      primaryService:
          clearPrimaryService ? null : (primaryService ?? this.primaryService),
      createdPlaylists: createdPlaylists ?? this.createdPlaylists,
    );
  }
}

class MusicIntegrationController extends StateNotifier<MusicIntegrationState> {
  MusicIntegrationController() : super(const MusicIntegrationState());

  void selectSection(ActivitySection section) {
    state = state.copyWith(selectedSection: section);
  }

  void selectWorkoutType(WorkoutType workoutType) {
    state = state.copyWith(selectedWorkoutType: workoutType);
  }

  void selectPodcastCategory(PodcastCategory category) {
    state = state.copyWith(selectedPodcastCategory: category);
  }

  void toggleConnection(MusicProviderService service) {
    switch (service) {
      case MusicProviderService.spotify:
        final next = !state.spotifyConnected;
        state = state.copyWith(
          spotifyConnected: next,
          primaryService: next
              ? (state.primaryService ?? MusicProviderService.spotify)
              : state.primaryService,
          clearPrimaryService: !next &&
              state.primaryService == MusicProviderService.spotify &&
              !state.appleMusicConnected,
        );
        break;
      case MusicProviderService.appleMusic:
        final next = !state.appleMusicConnected;
        state = state.copyWith(
          appleMusicConnected: next,
          primaryService: next
              ? (state.primaryService ?? MusicProviderService.appleMusic)
              : state.primaryService,
          clearPrimaryService: !next &&
              state.primaryService == MusicProviderService.appleMusic &&
              !state.spotifyConnected,
        );
        break;
    }

    if (!state.isConnected(state.primaryService ?? MusicProviderService.spotify)) {
      if (state.spotifyConnected) {
        state = state.copyWith(primaryService: MusicProviderService.spotify);
      } else if (state.appleMusicConnected) {
        state = state.copyWith(primaryService: MusicProviderService.appleMusic);
      }
    }
  }

  void setPrimaryService(MusicProviderService service) {
    if (!state.isConnected(service)) return;
    state = state.copyWith(primaryService: service);
  }

  void createPlaylist({
    required String name,
    required WorkoutType workoutType,
    required MusicProviderService provider,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final nextPlaylist = UserCreatedPlaylist(
      name: trimmed,
      workoutType: workoutType,
      provider: provider,
      trackCount: 0,
    );

    state = state.copyWith(
      createdPlaylists: [
        nextPlaylist,
        ...state.createdPlaylists,
      ],
      selectedSection: ActivitySection.music,
    );
  }
}

final musicIntegrationControllerProvider =
    StateNotifierProvider<MusicIntegrationController, MusicIntegrationState>(
  (ref) => MusicIntegrationController(),
);
