import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/observability/app_analytics.dart';
import '../domain/recap.dart';
import 'recap_card.dart';
import 'recap_exporter.dart';

/// Opens the recap sheet for [data]: a preview of the card, the switches for
/// what goes on it, and the button that hands it to the share sheet.
Future<void> showRecapSheet(BuildContext context, RecapCardData data) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RecapSheet(data: data),
  );
}

class RecapSheet extends ConsumerStatefulWidget {
  const RecapSheet({required this.data, super.key});

  final RecapCardData data;

  @override
  ConsumerState<RecapSheet> createState() => _RecapSheetState();
}

class _RecapSheetState extends ConsumerState<RecapSheet> {
  RecapOptions _options = const RecapOptions();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    final analytics = ref.read(appAnalyticsProvider);
    final kind = widget.data.kind.key;
    try {
      final bytes = await renderRecapPng(context, widget.data, _options);
      analytics.log(AnalyticsEvent.recapGenerated, {'kind': kind});
      if (!mounted) return;
      final result = await shareRecapFile(context, bytes, widget.data.kind);
      if (result.status == ShareResultStatus.success) {
        analytics.log(AnalyticsEvent.recapShared, {
          'kind': kind,
          // The package of the app picked, where the platform says.
          if (result.raw.isNotEmpty) 'target': result.raw,
        });
      }
    } on RecapExportException catch (error) {
      _say(error.message);
    } catch (_) {
      _say("Couldn't share the card. Try again in a moment.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final data = widget.data;
    final previewHeight =
        (MediaQuery.sizeOf(context).height * 0.42).clamp(220.0, 420.0);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: previewHeight,
              child: FittedBox(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: RecapCard(data: data, options: _options),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (data.displayName != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show my name'),
                value: _options.showName,
                onChanged: (on) =>
                    setState(() => _options = _options.copyWith(showName: on)),
              ),
            if (data.stats.isNotEmpty || data.hero != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show numbers'),
                value: _options.showNumbers,
                onChanged: (on) => setState(
                  () => _options = _options.copyWith(showNumbers: on),
                ),
              ),
            if (data.hasSensitiveStats)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show heart rate'),
                subtitle: Text(
                  'Health data. Off unless you turn it on.',
                  style: TextStyle(color: palette.muted, fontSize: 12.5),
                ),
                value: _options.showHeartRate && _options.showNumbers,
                onChanged: _options.showNumbers
                    ? (on) => setState(
                          () => _options = _options.copyWith(showHeartRate: on),
                        )
                    : null,
              ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
