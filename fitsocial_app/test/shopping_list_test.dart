import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/main/data/content_repository.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/meal_repeat.dart';
import 'package:fitsocial_app/features/main/domain/shopping_list.dart';
import 'package:fitsocial_app/features/main/presentation/shopping_list_screen.dart';

MealFoodItem _item(String name, int? grams, String category) => MealFoodItem(
      name: name,
      grams: grams,
      calories: 100,
      protein: 5,
      carbs: 10,
      fat: 2,
      category: category,
    );

MealRepeat _repeat(
  String id,
  Set<int> weekdays,
  List<MealFoodItem> items, {
  String? lastLoggedDay,
}) =>
    MealRepeat(
      id: id,
      name: id,
      weekdays: weekdays,
      hour: 8,
      minute: 0,
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      items: items,
      lastLoggedDay: lastLoggedDay,
    );

// 2026-10-05 is a Monday.
final _monday = DateTime(2026, 10, 5, 9);

final _breakfast = _repeat('Oats', {1, 2, 3, 4, 5}, [
  _item('oats', 250, 'starch'),
  _item('banana', 120, 'fruit'),
  _item('water', 300, 'drink'),
]);
final _dinner = _repeat('Chicken', {6, 7}, [
  _item('chicken breast', 200, 'protein'),
  _item('broccoli', 150, 'vegetable'),
  _item('rice', null, 'starch'),
]);

class _StubRepeats extends UnconfiguredContentRepository {
  _StubRepeats(this.repeats);
  final List<MealRepeat> repeats;

  @override
  Future<List<MealRepeat>> getMealRepeats() async => repeats;
}

Future<void> _pump(WidgetTester tester, List<MealRepeat> repeats) async {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(_StubRepeats(repeats)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: ShoppingListScreen(today: _monday),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ShoppingList.fromRepeats', () {
    test('adds each food up across the days it is eaten', () {
      final list = ShoppingList.fromRepeats(
        [_breakfast, _dinner],
        today: _monday,
      );
      final produce = list.sections[ShoppingSection.produce]!;
      final banana = produce.firstWhere((item) => item.name == 'Banana');
      // Five weekday breakfasts.
      expect(banana.grams, 600);
      expect(banana.servings, 5);
      final broccoli = produce.firstWhere((item) => item.name == 'Broccoli');
      // Saturday and Sunday dinners.
      expect(broccoli.grams, 300);
      expect(list.sections[ShoppingSection.protein]!.single.name,
          'Chicken breast');
    });

    test('tap water is not something to buy', () {
      final list = ShoppingList.fromRepeats([_breakfast], today: _monday);
      final names = list.sections.values.expand((items) => items).map(
            (item) => item.name,
          );
      expect(names, isNot(contains('Water')));
    });

    test("today's meal already logged is not bought again", () {
      final logged = _repeat(
        'Oats',
        {1, 2, 3, 4, 5},
        [_item('oats', 250, 'starch')],
        lastLoggedDay: '2026-10-05',
      );
      final list = ShoppingList.fromRepeats([logged], today: _monday);
      // Tuesday to Friday only.
      expect(list.sections[ShoppingSection.starch]!.single.grams, 1000);
    });

    test('amounts read as kg, g, or servings', () {
      const kilo = ShoppingItem(name: 'Oats', grams: 1250, servings: 5);
      const exact = ShoppingItem(name: 'Rice', grams: 2000, servings: 4);
      const grams = ShoppingItem(name: 'Banana', grams: 600, servings: 5);
      const none = ShoppingItem(name: 'Rice', grams: 0, servings: 2);
      expect(kilo.amountLabel, '1.3 kg');
      expect(exact.amountLabel, '2 kg');
      expect(grams.amountLabel, '600 g');
      expect(none.amountLabel, '2 servings');
    });

    test('a food with no weight is listed by servings', () {
      final list = ShoppingList.fromRepeats([_dinner], today: _monday);
      final rice = list.sections[ShoppingSection.starch]!.single;
      expect(rice.amountLabel, '2 servings');
    });

    test('reads as text in shop order', () {
      final text = ShoppingList.fromRepeats(
        [_breakfast, _dinner],
        today: _monday,
      ).toText();
      expect(text, startsWith('FitSocial shopping list, the week from 5 Oct'));
      expect(text, contains('- Banana, 600 g'));
      expect(
        text.indexOf('Fruit, veg & legumes'),
        lessThan(text.indexOf('Bread, grains & starches')),
      );
    });

    test('no repeats, nothing to buy', () {
      expect(ShoppingList.fromRepeats(const [], today: _monday).isEmpty,
          isTrue);
    });
  });

  group('ShoppingListScreen', () {
    testWidgets('lists the week and ticks foods off', (tester) async {
      await _pump(tester, [_breakfast]);

      expect(find.text('Banana'), findsOneWidget);
      expect(find.text('600 g'), findsOneWidget);
      await tester.tap(find.text('Banana'));
      await tester.pumpAndSettle();
      final tile =
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first);
      expect(tile.value, isTrue);
    });

    testWidgets('copies the list as text', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(tester, [_breakfast]);
      await tester.tap(find.text('Copy list'));
      await tester.pump();
      expect(copied, contains('- Oats, 1.3 kg'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('offers the three shops', (tester) async {
      await _pump(tester, [_breakfast]);
      for (final shop in GroceryShop.values) {
        expect(find.text(shop.label), findsOneWidget);
      }
    });

    testWidgets('without repeats, says how to get a list', (tester) async {
      await _pump(tester, const []);
      expect(find.textContaining('Set a meal to repeat'), findsOneWidget);
      expect(find.text('Copy list'), findsNothing);
    });
  });
}
