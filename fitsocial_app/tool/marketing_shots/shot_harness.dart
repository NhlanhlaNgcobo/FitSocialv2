// Renders real FitSocial screens to PNG for marketing videos and carousels.
//
// Run a shot file with:
//   flutter test --update-goldens tool/marketing_shots/<file>_test.dart
// PNGs land in tool/marketing_shots/out/.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/shared/widgets/liquid_backdrop.dart';
import 'package:fitsocial_app/shared/widgets/run_route_map.dart';

const _sdkFonts = 'C:/src/flutter/bin/cache/artifacts/material_fonts';

Future<ByteData> _bytes(String path) async {
  final data = await File(path).readAsBytes();
  return ByteData.view(Uint8List.fromList(data).buffer);
}

Future<void> _family(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(_bytes(p));
  }
  await loader.load();
}

bool _fontsLoaded = false;

/// Real glyphs instead of the test font's boxes.
Future<void> loadShotFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final roboto = [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
    'roboto-light.ttf',
    'roboto-italic.ttf',
    'roboto-mediumitalic.ttf',
    'roboto-bolditalic.ttf',
    'roboto-blackitalic.ttf',
  ].map((f) => '$_sdkFonts/$f').toList();
  await _family('Roboto', roboto);
  // A TextStyle with no family falls to the test font; on a phone it is the
  // platform face, which on Android is Roboto.
  for (final alias in ['FlutterTest', 'Ahem', 'sans-serif', 'Roboto Flex']) {
    await _family(alias, roboto);
  }
  await _family('MaterialIcons', ['$_sdkFonts/materialicons-regular.otf']);
  final pubCache = Platform.environment['LOCALAPPDATA'];
  final cupertino =
      '$pubCache/Pub/Cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf';
  await _family('CupertinoIcons', [cupertino]);
  await _family('packages/cupertino_icons/CupertinoIcons', [cupertino]);
  // Stands in for the phone's colour emoji font. Noto's COLRv1 build does not
  // draw in the test renderer; Segoe's COLRv0 does.
  await _family('ShotEmoji', ['C:/Windows/Fonts/seguiemj.ttf']);
  await _family('PulseModern', ['assets/fonts/Montserrat-Variable.ttf']);
  await _family('PulseNeon', ['assets/fonts/Pacifico-Regular.ttf']);
  await _family('PulseTypewriter', ['assets/fonts/CourierPrime-Bold.ttf']);
  await _family('PulseStrong', ['assets/fonts/Anton-Regular.ttf']);
  await _family('PulseElegant', ['assets/fonts/PlayfairDisplay-ItalicVariable.ttf']);
}

/// Phone canvas: 1179x2556 physical at 3x, i.e. 393x852 logical, with a
/// status-bar and home-indicator inset the video draws over.
void phoneView(WidgetTester tester, {double height = 852}) {
  tester.view.physicalSize = Size(1179, height * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(top: 162, bottom: 102);
  tester.view.viewPadding = const FakeViewPadding(top: 162, bottom: 102);
  addTearDown(tester.view.reset);
}

final _boundary = GlobalKey();

/// The app's own dark theme and the liquid ground, the way FitSocialApp
/// builds them, around [home].
/// Replaces the liquid ground with a flat colour for the matte captures.
final _ground = ValueNotifier<Color?>(null);

Widget shotApp(Widget home,
    {List<Override> overrides = const [], bool pushed = false}) {
  return ProviderScope(
    overrides: overrides,
    child: RepaintBoundary(
      key: _boundary,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: GoRouter(
          initialLocation: pushed ? '/shot' : '/',
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, __) => NoTransitionPage(
                child: pushed ? const SizedBox.shrink() : home,
              ),
              routes: [
                GoRoute(
                  path: 'shot',
                  pageBuilder: (_, __) => NoTransitionPage(child: home),
                ),
              ],
            ),
          ],
        ),
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<Color?>(
                valueListenable: _ground,
                builder: (context, ground, _) => ground == null
                    ? const LiquidBackdrop()
                    : ColoredBox(color: ground),
              ),
            ),
            if (child != null) child,
          ],
        ),
      ),
    ),
  );
}

/// Pumps [app], lets streams and images land, and writes out/<name>.png.
Future<void> shoot(WidgetTester tester, String name, Widget app,
    {Future<void> Function(WidgetTester)? before,
    void Function(WidgetTester)? setup,
    double height = 852}) async {
  await tester.runAsync(loadShotFonts);
  phoneView(tester, height: height);
  _fakePlatformViews(tester);
  GoogleMapsFlutterPlatform.instance = _ShotMaps();
  setup?.call(tester);
  await tester.pumpWidget(app);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await _decodeImages(tester);
  if (before != null) await before(tester);
  await _decodeImages(tester);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  _platformFace(tester);
  await tester.pump();
  await _capture(tester, name);
  await _captureMaps(tester, name);
}

/// Opens [page] as a pushed route, so it has the back arrow it has in the app.
class _PushedOver extends StatefulWidget {
  const _PushedOver(this.page);
  final Widget page;
  @override
  State<_PushedOver> createState() => _PushedOverState();
}

class _PushedOverState extends State<_PushedOver> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => widget.page,
      ));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// For every map on screen: a sidecar describing exactly what the map would
/// draw, and the screen captured over flat black and flat white so the map
/// image can be matted in under whatever the app lays over it.
Future<void> _captureMaps(WidgetTester tester, String name) async {
  final maps = find.byType(GoogleMap).evaluate().toList();
  if (maps.isEmpty) return;
  final entries = <Map<String, Object?>>[];
  for (final element in maps) {
    final map = element.widget as GoogleMap;
    final box = element.renderObject! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    final route = element.findAncestorWidgetOfExactType<RunRouteMap>();
    final padding = map.padding;
    entries.add({
      'rect': [topLeft.dx, topLeft.dy, box.size.width, box.size.height],
      'radius': route?.borderRadius.topLeft.x ?? 0,
      'mode': route?.mode.name ?? 'live',
      'framePadding': route?.framePadding ?? 32,
      'padding': [padding.left, padding.top, padding.right, padding.bottom],
      'target': [
        map.initialCameraPosition.target.latitude,
        map.initialCameraPosition.target.longitude,
      ],
      'zoom': map.initialCameraPosition.zoom,
      'style': map.style,
      'polylines': [
        for (final line in map.polylines)
          {
            'color': line.color.toARGB32().toRadixString(16),
            'width': line.width,
            'points': [
              for (final p in line.points) [p.latitude, p.longitude]
            ],
          }
      ],
      'markers': [
        for (final marker in map.markers)
          {
            'id': marker.markerId.value,
            'position': [marker.position.latitude, marker.position.longitude],
            'icon': marker.icon.toJson(),
          }
      ],
    });
  }
  await tester.runAsync(() => File('tool/marketing_shots/out/$name.maps.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(entries)));
  // In the app the map is opaque and hides whatever the screen paints behind
  // it (the run screen's ambient glow). Blank those full-screen grounds for
  // the matte, or they would read as overlays on the map.
  final mapBoxes = [for (final e in maps) e.renderObject!];
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final hidden = <RenderDecoratedBox, Decoration>{};
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderDecoratedBox || !ro.hasSize) continue;
    if (ro.size.width < screen.width * 0.9 ||
        ro.size.height < screen.height * 0.6) {
      continue;
    }
    final isAncestor = mapBoxes.any((m) {
      RenderObject? node = m.parent;
      while (node != null) {
        if (identical(node, ro)) return true;
        node = node.parent;
      }
      return false;
    });
    if (isAncestor) continue;
    hidden[ro] = ro.decoration;
    ro.decoration = const BoxDecoration();
  }
  // The map's own containers paint fills and shadows underneath it too; keep
  // only their borders. A Scaffold's ground is a Material, which paints as a
  // physical model.
  final grounds = <RenderObject, Color>{};
  for (final m in mapBoxes) {
    RenderObject? node = m.parent;
    while (node != null) {
      if (node is RenderPhysicalModel && !grounds.containsKey(node)) {
        grounds[node] = node.color;
        node.color = const Color(0x00000000);
      } else if (node is RenderPhysicalShape && !grounds.containsKey(node)) {
        grounds[node] = node.color;
        node.color = const Color(0x00000000);
      }
      if (node is RenderDecoratedBox &&
          node.position == DecorationPosition.background &&
          node.decoration is BoxDecoration &&
          !hidden.containsKey(node)) {
        final d = node.decoration as BoxDecoration;
        hidden[node] = d;
        node.decoration = BoxDecoration(
          border: d.border,
          borderRadius: d.borderRadius,
          shape: d.shape,
        );
      }
      node = node.parent;
    }
  }
  for (final (suffix, color) in [
    ('k', const Color(0xFF000000)),
    ('w', const Color(0xFFFFFFFF)),
  ]) {
    _ground.value = color;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _capture(tester, '${name}_$suffix');
  }
  _ground.value = null;
  hidden.forEach((ro, decoration) => ro.decoration = decoration);
  grounds.forEach((ro, color) {
    if (ro is RenderPhysicalModel) ro.color = color;
    if (ro is RenderPhysicalShape) ro.color = color;
  });
}

/// A TextStyle that names no family gets the platform face on a phone
/// (Roboto on Android) but the test engine's block glyphs here. Give every
/// laid-out paragraph without a family Roboto, right before the capture.
const _fallback = ['Roboto', 'ShotEmoji'];

void _platformFace(WidgetTester tester) {
  InlineSpan fix(InlineSpan span) {
    if (span is! TextSpan) return span;
    final style = span.style;
    return TextSpan(
      text: span.text,
      style: (style == null || style.fontFamily == null)
          ? (style ?? const TextStyle())
              .copyWith(fontFamily: 'Roboto', fontFamilyFallback: _fallback)
          : style.copyWith(fontFamilyFallback: _fallback),
      children: span.children?.map(fix).toList(),
      recognizer: span.recognizer,
      semanticsLabel: span.semanticsLabel,
    );
  }

  for (final ro in tester.allRenderObjects) {
    if (ro is RenderParagraph) {
      ro.text = fix(ro.text);
    } else if (ro is RenderEditable) {
      final text = ro.text;
      if (text != null) ro.text = fix(text) as TextSpan;
    }
  }
}

/// Image decoding is real async work the fake clock never waits for, so asset
/// and file images would otherwise capture blank.
Future<void> _decodeImages(WidgetTester tester) async {
  final elements = find.byType(Image).evaluate().toList();
  await tester.runAsync(() async {
    for (final element in elements) {
      final image = (element.widget as Image).image;
      await precacheImage(image, element, onError: (_, __) {});
    }
  });
  await tester.pump(const Duration(milliseconds: 50));
}

/// Writes the boundary at the phone's full 3x resolution. matchesGoldenFile
/// captures at 1x, which is too soft for a 1080-wide video.
Future<void> _capture(WidgetTester tester, String name,
    {double pixelRatio = 3}) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('tool/marketing_shots/out/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

/// Platform views (the Google map) have no host in a test. Accept their
/// creation so the rest of the screen builds; the map image is laid in later.
void _fakePlatformViews(WidgetTester tester) {
  var nextTexture = 1;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform_views,
    (call) async {
      switch (call.method) {
        case 'create':
          return nextTexture++;
        case 'resize':
          final args = call.arguments as Map;
          return {'width': args['width'], 'height': args['height']};
        default:
          return null;
      }
    },
  );
  // Location permission granted while in use (LocationPermission.whileInUse).
  for (final name in [
    'flutter.baseflow.com/geolocator',
    'flutter.baseflow.com/geolocator_android',
    'flutter.baseflow.com/geolocator_apple',
  ]) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => switch (call.method) {
        'checkPermission' || 'requestPermission' => 2,
        'isLocationServiceEnabled' => true,
        _ => null,
      },
    );
  }
  // The map's own per-instance channel: answer everything, draw nothing.
  for (var id = 0; id < 32; id++) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('plugins.flutter.io/google_maps_$id'),
      (call) async => null,
    );
  }
}

/// A frame sequence for a clip: out/<name>/f0001.png ... at 30 fps, each frame
/// set up by [step] (scroll a list, advance an animation, hold a button).
/// Encoded to video by frames_to_mp4.py.
Future<void> shootFrames(
  WidgetTester tester,
  String name,
  Widget app, {
  required int count,
  required Future<void> Function(WidgetTester tester, int i, double t) step,
  Future<void> Function(WidgetTester)? before,
  void Function(WidgetTester)? setup,
  double pixelRatio = 2,
}) async {
  await tester.runAsync(loadShotFonts);
  phoneView(tester);
  _fakePlatformViews(tester);
  GoogleMapsFlutterPlatform.instance = _ShotMaps();
  setup?.call(tester);
  await tester.pumpWidget(app);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await _decodeImages(tester);
  if (before != null) await before(tester);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.runAsync(() async {
    final dir = Directory('tool/marketing_shots/out/$name');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  });
  for (var i = 0; i < count; i++) {
    await step(tester, i, count == 1 ? 1 : i / (count - 1));
    _platformFace(tester);
    await tester.pump();
    await _capture(tester, '$name/f${(i + 1).toString().padLeft(4, '0')}',
        pixelRatio: pixelRatio);
  }
}

/// The screen's main vertical list: the tallest vertical Scrollable.
ScrollPosition mainScroll(WidgetTester tester) {
  ScrollableState? best;
  var bestHeight = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.axis != Axis.vertical) continue;
    final height = state.position.viewportDimension;
    if (height > bestHeight) {
      best = state;
      bestHeight = height;
    }
  }
  return best!.position;
}

/// A step that eases the main list from [from] to [to] over the clip.
Future<void> Function(WidgetTester, int, double) scrollStep(
    double from, double to,
    {Curve curve = Curves.easeInOutCubic}) {
  return (tester, i, t) async {
    final position = mainScroll(tester);
    final target = from + (to - from) * curve.transform(t);
    position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    await tester.pump();
  };
}

/// A step that lets the app's own animations run in real time.
Future<void> tickStep(WidgetTester tester, int i, double t) =>
    tester.pump(const Duration(microseconds: 33333));

/// The map draws nothing here (mapcomp.py lays the streets in afterwards) and
/// every call it makes into the platform simply succeeds.
// This harness is test code; the mixin is how a test swaps in a platform.
// ignore: invalid_use_of_visible_for_testing_member
class _ShotMaps with MockPlatformInterfaceMixin implements GoogleMapsFlutterPlatform {
  final _created = <int>{};

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    if (_created.add(creationId)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => onPlatformViewCreated(creationId));
    }
    return const SizedBox.expand();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('"on')) return const Stream<Never>.empty();
    return Future<void>.value();
  }
}
