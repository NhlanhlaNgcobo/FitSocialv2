import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The look of every run map, chosen by the runner.
///
/// The choice is how *this* person sees maps — their own runs, the feed, a
/// friend's live share — and it is what a map they share gets captured in, so
/// a runner who likes satellite posts satellite.
enum RunMapStyle {
  /// Follows the app: [midnight] on the dark theme, [paper] on the light one.
  auto('Auto', 'Follows the app theme'),
  midnight('Midnight', 'Black streets, nothing else'),
  ember('Ember', 'Warm, dark, glowing'),
  paper('Paper', 'Clean and light'),
  satellite('Satellite', 'Real photos from above'),
  terrain('Terrain', 'Hills and parks');

  const RunMapStyle(this.label, this.blurb);

  final String label;
  final String blurb;

  /// [auto] settled against the app theme. Every other style is itself.
  RunMapStyle resolve({required bool appIsDark}) =>
      this == auto ? (appIsDark ? midnight : paper) : this;

  MapType get mapType => switch (this) {
        satellite => MapType.hybrid,
        terrain => MapType.terrain,
        _ => MapType.normal,
      };

  /// Whether the map underneath is dark, which decides how the route stands
  /// off it: a glow on dark ground, a white casing on light.
  bool get isDarkGround => switch (this) {
        midnight || ember || satellite => true,
        paper || terrain => false,
        auto => throw StateError('Resolve auto before asking for its ground'),
      };

  /// The JSON style for the base map, or null for Google's own look.
  String? get json => switch (this) {
        midnight => _midnight,
        ember => _ember,
        paper => _paper,
        satellite => null,
        terrain => _terrain,
        auto => throw StateError('Resolve auto before asking for its JSON'),
      };
}

/// Everything the runner can change about run maps.
@immutable
class RunMapPrefs {
  const RunMapPrefs({
    this.style = RunMapStyle.auto,
    this.paceColours = true,
    this.tilt3d = true,
  });

  final RunMapStyle style;

  /// Colour the route by speed — yellow where fast, red where slow — instead
  /// of one solid orange. Only routes that recorded times can show it.
  final bool paceColours;

  /// Tilt the camera and turn it to the runner's heading during a live run,
  /// with 3D buildings showing.
  final bool tilt3d;

  RunMapPrefs copyWith({RunMapStyle? style, bool? paceColours, bool? tilt3d}) =>
      RunMapPrefs(
        style: style ?? this.style,
        paceColours: paceColours ?? this.paceColours,
        tilt3d: tilt3d ?? this.tilt3d,
      );

  String encode() => '${style.name};${paceColours ? 1 : 0};${tilt3d ? 1 : 0}';

  static RunMapPrefs decode(String? raw) {
    if (raw == null) return const RunMapPrefs();
    final parts = raw.split(';');
    return RunMapPrefs(
      style: RunMapStyle.values.firstWhere(
        (style) => style.name == parts.first,
        orElse: () => RunMapStyle.auto,
      ),
      paceColours: parts.length < 2 || parts[1] != '0',
      tilt3d: parts.length < 3 || parts[2] != '0',
    );
  }

  /// The live choice. A plain notifier rather than a provider because maps are
  /// drawn in places with no [ProviderScope] above them — the share exporter's
  /// offscreen card, widget tests — and a map should never fail to draw for
  /// want of one.
  static final ValueNotifier<RunMapPrefs> current =
      ValueNotifier(const RunMapPrefs());

  static const _storage = FlutterSecureStorage();
  static const _key = 'run_map_prefs';

  /// Reads the saved choice into [current]. Called before the first frame so a
  /// map never opens in one style and flips to another. Never throws: a
  /// keystore that has gone bad falls back to the defaults.
  static Future<void> load() async {
    try {
      current.value = decode(await _storage.read(key: _key));
    } catch (_) {}
  }

  /// Applies [prefs] at once and saves them in the background.
  static Future<void> save(RunMapPrefs prefs) async {
    current.value = prefs;
    try {
      await _storage.write(key: _key, value: prefs.encode());
    } catch (_) {
      // Holds for this session; it just won't survive a relaunch.
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RunMapPrefs &&
      other.style == style &&
      other.paceColours == paceColours &&
      other.tilt3d == tilt3d;

  @override
  int get hashCode => Object.hash(style, paceColours, tilt3d);
}

// Pure-black map style to match the FitSocial surface (#000000). POIs and
// transit are hidden so the route is the only thing that draws the eye — except
// parks and water, kept as faint tints so the map still reads as a place, and
// buildings, a shade off the ground so the 3D camera has something to show.
// Small-street names and road shields go: at a run's zoom they are clutter.
const _midnight = '''
[
  {"elementType":"geometry","stylers":[{"color":"#000000"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5c5c5c"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#000000"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#0a0a0a"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#141414"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#0d1a10"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1c1c1c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#6b6b6b"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2b2b2b"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0a1820"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#2c4450"}]}
]
''';

// Midnight warmed through: the ground and the streets lean toward the brand
// orange, so the route reads as the hottest line in a city already glowing.
const _ember = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0f0805"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a6248"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0f0805"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#140b07"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#21130b"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#1a1a0b"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#3a2012"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#a3734f"}]},
  {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#2a170d"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#5a2e14"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#07090d"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3a4250"}]}
]
''';

// The light counterpart of midnight: the app's cream page as the landmass,
// roads a shade off it, parks and water kept as soft tints.
const _paper = '''
[
  {"elementType":"geometry","stylers":[{"color":"#F5F1EA"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8A857C"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#F5F1EA"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.neighborhood","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#EFEAE1"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#E6DFD3"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#E2E8D5"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#FFFFFF"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8A857C"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#E7E0D4"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#CFDFE4"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#7C969E"}]}
]
''';

// Google's terrain shading left as it is — the hills are the point — with only
// the shop and transit pins taken off.
const _terrain = '''
[
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]
''';
