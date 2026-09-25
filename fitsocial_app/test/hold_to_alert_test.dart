import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitsocial_app/app/theme/app_theme.dart';
import 'package:fitsocial_app/features/safety/application/panic_controller.dart';
import 'package:fitsocial_app/features/safety/application/safety_providers.dart';
import 'package:fitsocial_app/features/safety/data/panic_device.dart';
import 'package:fitsocial_app/features/safety/data/panic_locator.dart';
import 'package:fitsocial_app/features/safety/data/panic_repository_contract.dart';
import 'package:fitsocial_app/features/safety/domain/safety_alerts.dart';
import 'package:fitsocial_app/features/safety/domain/safety_models.dart';
import 'package:fitsocial_app/features/safety/presentation/hold_to_alert.dart';

class _Repo implements PanicRepository {
  int raised = 0;

  @override
  Future<PanicRaised> raise(PanicDraft draft) async {
    raised++;
    return PanicRaised(eventId: 'e$raised', delivered: Future.value(true));
  }

  @override
  Future<void> resolve(String eventId) async {}
  @override
  Future<void> markDuress(String eventId) async {}
  @override
  Future<void> updatePosition(String eventId, SharedPosition position) async {}
  @override
  Future<List<String>> openEventIds(String userId) async => const [];
  @override
  Stream<List<PanicAcknowledgement>> watchAcknowledgements(String eventId) =>
      const Stream.empty();
  @override
  Future<int> acceptedContactCount(String userId) async => 1;
}

class _Device implements PanicDevice {
  @override
  Future<int?> batteryPercent() async => 50;
}

class _Locator implements PanicLocator {
  @override
  Future<PanicPosition?> current() async => null;
  @override
  Future<PanicPosition?> lastKnown() async => null;
  @override
  Stream<PanicPosition> track() => const Stream.empty();
}

void main() {
  late _Repo repo;

  Future<void> pump(WidgetTester tester) async {
    repo = _Repo();
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Center(child: HoldToAlertButton()),
        ),
      ),
      GoRoute(
        path: '/safety/panic',
        builder: (_, __) => const Scaffold(body: Text('ALERT SCREEN')),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        panicControllerProvider.overrideWith((ref) => PanicController(
              repository: repo,
              device: _Device(),
              locator: _Locator(),
              userId: () => 'me',
              settings: () => SafetySettings.defaults,
            )),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ));
  }

  testWidgets('letting go early sends nothing', (tester) async {
    await pump(tester);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(HoldToAlertButton)));
    await tester.pump(const Duration(milliseconds: 1200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.raised, 0);
    expect(find.text('ALERT SCREEN'), findsNothing);
  });

  testWidgets('holding for two seconds sends and opens the alert', (tester) async {
    await pump(tester);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(HoldToAlertButton)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(holdToAlertDuration);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.raised, 1);
    expect(find.text('ALERT SCREEN'), findsOneWidget);
  });
}
