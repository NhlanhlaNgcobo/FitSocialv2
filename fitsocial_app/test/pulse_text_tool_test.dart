import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/pulse/domain/pulse_text_style.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_composer_screen.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_text.dart';
import 'package:fitsocial_app/features/pulse/presentation/pulse_text_tool.dart';

Future<void> pumpComposer(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: PulseComposerScreen()),
    ),
  );
  await tester.pump();
}

/// Lands on a blank text card, the way a person does: through the mode
/// switch, pressed where a thumb lands.
Future<void> openTextCard(WidgetTester tester) async {
  await pumpComposer(tester);
  final segment = tester.getRect(find.byTooltip('Text'));
  await tester.tapAt(Offset(segment.center.dx, segment.bottom - 4));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Opens the text tool from the card and writes [message] into it.
Future<void> write(WidgetTester tester, String message) async {
  await tester.tap(find.text('Say something'));
  await tester.pump();
  await tester.pump();
  await tester.enterText(find.byType(TextField), message);
  await tester.pump();
}

/// The style the words on screen are drawn in, wherever they are.
TextStyle styleOf(WidgetTester tester, String text) {
  final editing = find.byType(TextField);
  if (editing.evaluate().isNotEmpty) {
    return tester.widget<TextField>(editing).style!;
  }
  return tester.widget<Text>(find.text(text)).style!;
}

void main() {
  group('storing how the words are drawn', () {
    test('round-trips through a map', () {
      const style = PulseTextStyle(
        font: PulseFont.neon,
        color: Color(0xFFFF2D55),
        alignment: PulseTextAlignment.left,
        backdrop: PulseTextBackdrop.solid,
        scale: 1.4,
        x: 0.3,
        y: 0.7,
        rotation: 0.2,
      );

      expect(PulseTextStyle.fromMap(style.toMap()), style);
    });

    // A Pulse written before the tool existed carries no style at all, and
    // that absence is meaningful: the viewer draws it the old way.
    test('reads nothing as nothing', () {
      expect(PulseTextStyle.fromMap(null), isNull);
      expect(PulseTextStyle.fromMap('classic'), isNull);
    });

    // A newer build may ship a face or a plate this one does not know. The
    // words still matter more than the dressing.
    test('falls back on anything it does not recognise', () {
      final style = PulseTextStyle.fromMap(const {
        'font': 'graffiti',
        'align': 'justify',
        'backdrop': 'glitter',
        'color': 'red',
        'scale': 'big',
        'x': double.nan,
      })!;

      expect(style.font, PulseFont.classic);
      expect(style.alignment, PulseTextAlignment.center);
      expect(style.backdrop, PulseTextBackdrop.none);
      expect(style.color, PulseTextColors.white);
      expect(style.scale, 1);
      expect(style.x, 0.5);
    });

    // A document claiming the text sits three screens to the right, or at a
    // hundred times size, is clamped rather than trusted.
    test('keeps placement and size inside the frame', () {
      final style = PulseTextStyle.fromMap(const {
        'scale': 40,
        'x': 3,
        'y': -1,
      })!;

      expect(style.scale, PulseTextStyle.maxScale);
      expect(style.x, 1);
      expect(style.y, 0);
    });

    test('every face and plate survives the round trip', () {
      for (final font in PulseFont.values) {
        expect(PulseFont.fromKey(font.key), font);
      }
      for (final backdrop in PulseTextBackdrop.values) {
        expect(PulseTextBackdrop.fromKey(backdrop.key), backdrop);
      }
      for (final alignment in PulseTextAlignment.values) {
        expect(PulseTextAlignment.fromKey(alignment.key), alignment);
      }
    });
  });

  group('what the letters are painted in', () {
    test('bare and smoked plates keep the chosen colour', () {
      const pink = Color(0xFFFF2D55);
      const bare = PulseTextStyle(color: pink);
      const smoked = PulseTextStyle(
        color: pink,
        backdrop: PulseTextBackdrop.translucent,
      );

      expect(bare.foreground, pink);
      expect(bare.plate, isNull);
      expect(smoked.foreground, pink);
      expect(smoked.plate, isNotNull);
    });

    // On a solid plate the plate takes the colour, and white letters on a
    // white plate would vanish.
    test('a solid plate flips the letters to contrast with it', () {
      const onWhite = PulseTextStyle(
        color: PulseTextColors.white,
        backdrop: PulseTextBackdrop.solid,
      );
      const onBlack = PulseTextStyle(
        color: PulseTextColors.black,
        backdrop: PulseTextBackdrop.solid,
      );

      expect(onWhite.plate, PulseTextColors.white);
      expect(onWhite.foreground, PulseTextColors.black);
      expect(onBlack.plate, PulseTextColors.black);
      expect(onBlack.foreground, PulseTextColors.white);
    });

    test('each face brings its own family', () {
      expect(PulseFont.classic.baseStyle.fontFamily, isNull);
      expect(PulseFont.neon.baseStyle.fontFamily, 'PulseNeon');
      expect(PulseFont.strong.baseStyle.fontFamily, 'PulseStrong');
      expect(
        const PulseTextStyle(font: PulseFont.typewriter).resolve(30).fontFamily,
        'PulseTypewriter',
      );
    });

    test('the size slider and the length rule multiply', () {
      const doubled = PulseTextStyle(scale: 2);
      expect(doubled.resolve(30).fontSize, 60);
    });
  });

  group('writing on a text card', () {
    testWidgets('a tap on the card opens the tool', (tester) async {
      await openTextCard(tester);
      expect(find.byType(PulseTextEditor), findsNothing);

      await tester.tap(find.text('Say something'));
      await tester.pump();

      expect(find.byType(PulseTextEditor), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      // The faces, each named, and the way out.
      for (final font in PulseFont.values) {
        expect(find.text(font.label), findsOneWidget);
      }
    });

    testWidgets('the words land on the card as a sticker after Done',
        (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');

      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(find.byType(PulseTextEditor), findsNothing);
      expect(find.byType(PulseTextSticker), findsOneWidget);
      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Say something'), findsNothing);
      // Share wakes up now that there is something to share.
      expect(find.text('Share Pulse'), findsOneWidget);
    });

    testWidgets('a tap on the sticker reopens the tool', (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');
      await tester.tap(find.text('Done'));
      await tester.pump();

      await tester.tap(find.byType(PulseTextSticker));
      await tester.pump();

      expect(find.byType(PulseTextEditor), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Leg day');
    });

    testWidgets('picking a face changes the words as they are typed',
        (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');
      expect(styleOf(tester, 'Leg day').fontFamily, isNull);

      await tester.tap(find.text('Strong'));
      await tester.pump();

      expect(styleOf(tester, 'Leg day').fontFamily, 'PulseStrong');

      // And the sticker keeps the face once the tool closes.
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(styleOf(tester, 'Leg day').fontFamily, 'PulseStrong');
    });

    testWidgets('picking a colour paints the words', (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');

      // The third swatch is the app's own orange.
      final swatches = find.bySemanticsLabel('Text colour');
      await tester.tap(swatches.at(2));
      await tester.pump();

      expect(styleOf(tester, 'Leg day').color, PulseTextColors.all[2]);
    });

    testWidgets('the plate button cycles through the backdrops',
        (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');
      final plate = find.byTooltip('Text background');

      // none → solid: white plate, black letters.
      await tester.tap(plate);
      await tester.pump();
      expect(styleOf(tester, 'Leg day').color, PulseTextColors.black);

      // solid → translucent: letters back in their colour.
      await tester.tap(plate);
      await tester.pump();
      expect(styleOf(tester, 'Leg day').color, PulseTextColors.white);

      // translucent → none.
      await tester.tap(plate);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration,
        isNotNull,
      );
    });

    testWidgets('the align button cycles the alignment', (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');

      await tester.tap(find.byTooltip('Align'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).textAlign,
        TextAlign.left,
      );

      await tester.tap(find.byTooltip('Align'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).textAlign,
        TextAlign.right,
      );
    });

    // Whitespace is not a message. Done on a blank field leaves the card as
    // it was, with nothing to share.
    testWidgets('Done with nothing written leaves the card blank',
        (tester) async {
      await openTextCard(tester);
      await write(tester, '   ');

      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(find.byType(PulseTextSticker), findsNothing);
      expect(find.text('Say something'), findsOneWidget);
    });

    testWidgets('dragging the sticker moves the words', (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');
      await tester.tap(find.text('Done'));
      await tester.pump();

      final before = tester.getCenter(find.text('Leg day'));
      await tester.drag(find.byType(PulseTextSticker), const Offset(0, -120));
      await tester.pump();
      final after = tester.getCenter(find.text('Leg day'));

      // A little under the full drag: the first 18px are the touch slop the
      // recogniser spends deciding this is a drag at all.
      expect(after.dy, lessThan(before.dy - 90));
      expect(after.dx, closeTo(before.dx, 1));
    });

    testWidgets('press and hold picks the words up and moves them',
        (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');
      await tester.tap(find.text('Done'));
      await tester.pump();

      final before = tester.getCenter(find.text('Leg day'));
      final gesture = await tester.startGesture(before);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(80, -150));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final after = tester.getCenter(find.text('Leg day'));

      expect(after.dx, closeTo(before.dx + 80, 1));
      expect(after.dy, closeTo(before.dy - 150, 1));
    });

    // Switching kinds throws the writing away with the media: words placed
    // over a photo were placed for that photo.
    testWidgets('leaving text mode clears the words', (tester) async {
      await openTextCard(tester);
      await write(tester, 'Leg day');
      await tester.tap(find.text('Done'));
      await tester.pump();

      final photo = tester.getRect(find.byTooltip('Photo'));
      await tester.tapAt(Offset(photo.center.dx, photo.bottom - 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final text = tester.getRect(find.byTooltip('Text'));
      await tester.tapAt(Offset(text.center.dx, text.bottom - 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Leg day'), findsNothing);
      expect(find.text('Say something'), findsOneWidget);
    });
  });

  group('drawing the words on a frame', () {
    testWidgets('sits the block where the style says', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 400,
            height: 800,
            child: PulseTextLayer(
              text: 'Hi',
              style: PulseTextStyle(x: 0.25, y: 0.75),
            ),
          ),
        ),
      );
      await tester.pump();

      final frame = tester.getRect(find.byType(PulseTextLayer));
      final block = tester.getCenter(find.text('Hi'));
      expect(block.dx, closeTo(frame.left + frame.width * 0.25, 1));
      expect(block.dy, closeTo(frame.top + frame.height * 0.75, 1));
    });

    testWidgets('a plate wraps the words when the style asks for one',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: PulseTextBlock(
              text: 'Hi',
              style: PulseTextStyle(
                color: Color(0xFFFF6B1A),
                backdrop: PulseTextBackdrop.solid,
              ),
            ),
          ),
        ),
      );

      final plate = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
      expect(
          (plate.decoration as BoxDecoration).color, const Color(0xFFFF6B1A));
    });
  });
}
