import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/data/firestore_mappers.dart';
import 'package:fitsocial_app/features/main/data/firestore_models.dart';
import 'package:fitsocial_app/shared/widgets/profile_bio.dart';

/// What a profile says about itself. Every field here reached the screen only
/// after being carried through three layers, so the mapping is tested next to
/// the rendering — a field dropped in either place looks identical to the user.
void main() {
  testWidgets('shows the bio, the meta line and the link', (tester) async {
    await _pump(
      tester,
      const ProfileBio(
        bio: 'Chasing a sub-4 marathon.',
        pronouns: 'they/them',
        location: 'Cape Town',
        links: 'https://bear.run/',
      ),
    );

    expect(find.text('Chasing a sub-4 marathon.'), findsOneWidget);
    expect(find.text('they/them  ·  Cape Town'), findsOneWidget);
    // Shown the way a browser shows one: no scheme, no trailing slash.
    expect(find.text('bear.run'), findsOneWidget);
  });

  testWidgets('renders a link even with nothing else filled in', (tester) async {
    await _pump(tester, const ProfileBio(links: 'bear.run'));

    expect(find.text('bear.run'), findsOneWidget);
  });

  testWidgets('drops the separator when only one meta field is set',
      (tester) async {
    await _pump(tester, const ProfileBio(bio: 'Lifting.', location: 'Durban'));

    expect(find.text('Durban'), findsOneWidget);
  });

  testWidgets('collapses when the profile has nothing to say', (tester) async {
    const bio = ProfileBio();
    expect(bio.isEmpty, isTrue);

    await _pump(tester, bio);
    expect(tester.getSize(find.byType(ProfileBio)), Size.zero);
  });

  testWidgets('copies the link with a scheme the user never typed',
      (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, const ProfileBio(links: 'bear.run'));
    await tester.tap(find.text('bear.run'));
    await tester.pump();

    expect(copied, ['https://bear.run']);
  });

  test('the written part of a profile survives the Firestore mapping', () {
    final result = FirestoreMapper.toUserSearchResult(
      FirestoreUserRecord.fromMap('uid-1', const {
        'displayName': 'Bear',
        'handle': 'bear',
        'bio': 'Chasing a sub-4 marathon.',
        'location': 'Cape Town',
        'pronouns': 'they/them',
        'links': 'bear.run',
      }),
    );

    expect(result.bio, 'Chasing a sub-4 marathon.');
    expect(result.location, 'Cape Town');
    expect(result.pronouns, 'they/them');
    expect(result.links, 'bear.run');
  });
}

Future<void> _pump(WidgetTester tester, ProfileBio bio) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: Center(child: bio)),
    ),
  );
}
