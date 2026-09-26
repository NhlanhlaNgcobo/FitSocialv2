import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import 'app_photo.dart';
import 'fit_social_logo.dart';
import 'liquid_glass.dart';
import 'network_photo_aspect.dart';
import 'picture_ratio.dart';
import 'run_summary_card.dart' show runCardExportGround;

/// A logged workout drawn as the page it came from: a ruled log sheet.
///
/// The payload a workout post renders in place of a photo. Shared between the
/// feed card and the post detail page so a workout looks the same in both — the
/// detail page only widens the margin.
///
/// The shape is a training log rather than a summary block, and that is the
/// whole design. Totals sit in a ruled strip across the top; under it, one line
/// per exercise with the name at the left, the load at the right, and a dotted
/// leader carrying the eye between them. Numbers are set in tabular figures so
/// the loads stack into a column that can be read down — which is what a lifter
/// does with a log, and what a row of grey chips made impossible.
///
/// With a [backgroundImageUrl] the sheet gives way to the user's photo under a
/// scrim. That flips every colour decision in here: on a photo the card is no
/// longer sitting on a themed surface, so text that followed the palette would
/// go black-on-dark-photo the moment the viewer used the light theme.
class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({
    required this.workoutData,
    required this.activity,
    this.backgroundImageUrl,
    this.backgroundImage,
    this.aspectRatio,
    this.forExport = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 14),
    super.key,
  }) : assert(
          backgroundImageUrl == null || backgroundImage == null,
          'Give the card a URL or a provider, not both.',
        );

  /// The post's raw `workoutData` map. Absent keys simply drop their row, so a
  /// half-filled log still renders.
  final Map<String, dynamic>? workoutData;

  /// Fallback title when the log never carried one.
  final String activity;

  /// A photo to draw behind the card. Null keeps the ruled sheet, which is what
  /// every workout logged before this existed still uses.
  final String? backgroundImageUrl;

  /// The photo as a provider already in hand, for callers that are not drawing
  /// from a URL: the exporter, which has just decoded the photo and must draw
  /// exactly that entry, and the log screen's local file before upload.
  final ImageProvider? backgroundImage;

  /// The photo's width/height, when the caller already knows it. Skips the
  /// measuring pass in [NetworkPhotoAspect], which cannot run inside the
  /// exporter's two-frame capture — and could not measure a [backgroundImage]
  /// anyway, since it resolves by URL.
  final double? aspectRatio;

  /// Being drawn into a file rather than onto a page.
  ///
  /// With no photo the card normally looks through its glass to the app's
  /// backdrop; a file has no backdrop, so the export paints the ground the
  /// lens would have shown — the same one the run card exports on.
  final bool forExport;

  final EdgeInsetsGeometry margin;

  /// Identifies the photo behind the sheet.
  ///
  /// The wordmark draws an image of its own, so "is there an Image in this
  /// card" stopped being the same question as "is the user's photo showing".
  @visibleForTesting
  static const Key backdropKey = ValueKey('workout-card-backdrop');

  /// How many exercises the sheet prints before it stops.
  ///
  /// A feed card is a summary, not the document. Five lines is roughly where a
  /// post stops being scannable, and the sixth line earns more as a count than
  /// as another name — the detail page has room for all of them.
  static const int _maxRows = 5;

  /// One value from the log, as text, whatever Firestore is holding it as.
  ///
  /// A cast would be wrong here for the same reason [_exercise] handles two
  /// shapes: the app writes `duration` and `calories` as labels ('45 min'),
  /// but the sibling `workouts` document writes the same names as numbers, and
  /// a post whose map came from that shape would throw mid-layout — which does
  /// not merely drop the row, it blanks the whole page the card sits on.
  /// Returns null for an absent or empty value, so the row drops as intended.
  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// One exercise, parsed out of whatever shape the document is holding.
  ///
  /// Firestore stores each exercise as a map, so calling toString() on it
  /// renders the literal `{reps: 25, sets: 5, name: legs}` in the feed. Older
  /// posts wrote plain strings, so both shapes have to survive here — a string
  /// becomes a name with no numbers, which the sheet prints as a bare line.
  ///
  /// Returns null for anything with no name to print.
  static _Exercise? _exercise(dynamic raw) {
    if (raw is! Map) {
      final name = raw?.toString().trim() ?? '';
      return name.isEmpty ? null : _Exercise(name: name);
    }
    final name = raw['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;

    // Same defensive read as _text: these arrive as numbers from the app and
    // as strings from documents written by hand or by an older build.
    int? asInt(Object? value) =>
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    double? asDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');

    return _Exercise(
      name: name,
      sets: asInt(raw['sets']),
      reps: asInt(raw['reps']),
      weightKg: asDouble(raw['weightKg']),
    );
  }

  /// `3885` → `3,885`. Group separators only matter above a thousand, which is
  /// exactly where session volume lives.
  static String _grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// `22.5` → `22.5`, `60.0` → `60`. A trailing `.0` on a plate weight is
  /// noise, and it is the difference between the load column lining up and not.
  static String _trimmed(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final data = workoutData ?? const {};
    final title = _text(data['title']) ?? activity;
    final duration = _text(data['duration']);
    final calories = _text(data['calories']);
    final exercises = (data['exercises'] as List<dynamic>?)
            ?.map(_exercise)
            .whereType<_Exercise>()
            .toList() ??
        const <_Exercise>[];

    final totalSets = exercises.fold<int>(0, (sum, e) => sum + (e.sets ?? 0));
    final totalReps = exercises.fold<int>(0, (sum, e) => sum + e.totalReps);
    final volume = exercises.fold<double>(0, (sum, e) => sum + e.volumeKg);
    // The column only earns its width if something is in it. A log of
    // bodyweight work draws sets and reps and stops there.
    final hasLoads = exercises.any((e) => e.weightKg != null);

    final photo = backgroundImage ??
        (backgroundImageUrl == null ? null : appPhoto(backgroundImageUrl!));
    final skin = _CardSkin.resolve(palette, hasPhoto: photo != null);

    // Volume first when it exists — it is the one figure that says how hard the
    // session was. Duration is in the line under the title, so it is not
    // repeated here.
    final stats = <_Stat>[
      if (volume > 0)
        _Stat(label: 'Volume', value: _grouped(volume.round()), unit: 'kg'),
      if (totalSets > 0) _Stat(label: 'Sets', value: '$totalSets'),
      if (calories != null) _Stat(label: 'Calories', value: calories),
      if (totalReps > 0) _Stat(label: 'Reps', value: '$totalReps'),
    ].take(3).toList();

    final heaviest = hasLoads
        ? exercises
            .where((e) => e.weightKg != null)
            .reduce((a, b) => b.weightKg! > a.weightKg! ? b : a)
        : null;

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: skin.text,
                      ),
                    ),
                    if (duration != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        duration.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: skin.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // The app signing its own card, at the size and weight the run
              // and meal cards already sign theirs — a workout screenshotted
              // into someone else's feed should say where it came from too.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: FitSocialLogo(
                  size: 13,
                  animated: false,
                  color: skin.text,
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            _StatStrip(stats: stats, skin: skin),
          ],
          if (exercises.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              exercises.length == 1
                  ? '1 EXERCISE'
                  : '${exercises.length} EXERCISES',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: skin.accent,
              ),
            ),
            const SizedBox(height: 6),
            for (final exercise in exercises.take(_maxRows))
              _ExerciseRow(
                exercise: exercise,
                showLoad: hasLoads,
                skin: skin,
              ),
            if (exercises.length > _maxRows)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${exercises.length - _maxRows} more',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: skin.accent,
                  ),
                ),
              ),
          ],
          if (totalReps > 0) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: skin.stroke),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '$totalReps reps total',
                  style: TextStyle(fontSize: 11.5, color: skin.muted),
                ),
                if (heaviest != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(
                      // Lift then load, the same order the rows above read in,
                      // and short enough to survive beside the rep count — the
                      // longer "Heaviest 60 kg · Bench press" ellipsised the
                      // name off the end, which is the half worth keeping.
                      '${heaviest.name} · ${_trimmed(heaviest.weightKg!)} kg',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11.5, color: skin.muted),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    return Container(
      // Inset from the card's edges — a rounded block flush against the
      // enclosing card's sides reads as a mis-clipped card-in-a-card.
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.border, width: 1),
      ),
      child: ClipRRect(
        // Inset by the border width so the photo stops at the inside edge of
        // the stroke rather than painting over it.
        borderRadius: BorderRadius.circular(19),
        child: photo == null
            ? forExport
                // Being captured to a file: no backdrop to look through to,
                // so paint the ground the lens would have shown.
                ? ColoredBox(
                    color: runCardExportGround(palette),
                    child: _Portrait(child: content),
                  )
                : LiquidGlass(
                    // With no photo there is nothing for the card to sit on,
                    // so it looks through to the app's backdrop rather than
                    // painting a slab of its own. This is what the flat
                    // gradient used to do, and why this card stayed opaque
                    // while the rest turned to glass.
                    borderRadius: BorderRadius.circular(19),
                    // The ClipRRect above already holds this shape.
                    clip: false,
                    child: _Portrait(child: content),
                  )
            : _PhotoBacked(
                image: photo,
                imageUrl: backgroundImageUrl,
                pinnedRatio: aspectRatio,
                fallbackColor: skin.photoFallback,
                child: content,
              ),
      ),
    );
  }
}

/// The log sheet drawn over the user's photo, at the photo's own shape.
///
/// The card used to take whatever height its rows needed and crop the photo to
/// fit, so a portrait gym shot arrived in the feed as a letterbox of somebody's
/// midriff. Here the photo's real ratio — resolved off the decoded image by
/// [NetworkPhotoAspect], not guessed and not stored — sets a *minimum* height,
/// and the sheet is laid over the top of it.
///
/// A minimum rather than a fixed [AspectRatio] because the two things being
/// reconciled can disagree: a wide photo on a twelve-row session has less
/// natural height than the log needs. Fixing the ratio would clip the log,
/// which is the one thing on the card that cannot be allowed to go missing —
/// so in that case the card grows and the photo gives up its edges instead.
class _PhotoBacked extends StatelessWidget {
  const _PhotoBacked({
    required this.image,
    required this.imageUrl,
    required this.pinnedRatio,
    required this.fallbackColor,
    required this.child,
  });

  final ImageProvider image;

  /// Where [image] came from, when it came from the network — what
  /// [NetworkPhotoAspect] measures by. Null for a local or pre-decoded photo,
  /// which then needs [pinnedRatio] to have any shape but square.
  final String? imageUrl;

  /// The photo's ratio when the caller already has it, in place of measuring.
  final double? pinnedRatio;
  final Color fallbackColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pinned = pinnedRatio;
    final url = imageUrl;
    if (pinned != null || url == null) {
      return _build(context, pinned ?? kPictureAspectRatio);
    }
    return NetworkPhotoAspect(imageUrl: url, builder: _build);
  }

  Widget _build(BuildContext context, double ratio) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: Image(
                key: WorkoutSummaryCard.backdropKey,
                image: image,
                fit: BoxFit.cover,
                // A backdrop that fails to load must not take the workout's
                // numbers down with it — fall back to the flat tint and
                // carry on.
                errorBuilder: (context, error, stackTrace) =>
                    ColoredBox(color: fallbackColor),
              ),
            ),
            // Without this the metrics sit on whatever the photo happens to
            // be, and a bright gym window erases them. Lightest at the top,
            // heaviest under the sheet — the same direction the run and
            // meal cards scrim in, because the sheet sits where their text
            // does.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x59050505),
                      Color(0xB8050505),
                      Color(0xE6050505),
                    ],
                    stops: [0, 0.42, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxWidth / ratio,
              ),
              // Along the bottom, where a media card's words go — a
              // portrait photo then shows its subject above the sheet
              // instead of behind it.
              //
              // A Column rather than an Align or a Spacer: the incoming
              // height here is unbounded above the minimum, which is exactly
              // the case those two cannot size themselves in. A Column takes
              // its children's height, gets clamped up to the minimum, and
              // hands the difference to mainAxisAlignment.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [child],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The sheet with no photo behind it, at least 9:16 tall.
///
/// A minimum, as on a photo: a long session still grows the card rather than
/// losing rows, and a short one has the room to stay unhurried.
class _Portrait extends StatelessWidget {
  const _Portrait({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.maxWidth / kPictureAspectRatio,
        ),
        // A Column for the same reason the photo-backed sheet uses one: the
        // height above the minimum is unbounded, and a Column sizes itself to
        // its child, is clamped up to the minimum, and keeps the log at the
        // top of the space.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [child],
        ),
      ),
    );
  }
}

/// One exercise off the log, with whatever numbers survived the document.
class _Exercise {
  const _Exercise({
    required this.name,
    this.sets,
    this.reps,
    this.weightKg,
  });

  final String name;
  final int? sets;
  final int? reps;
  final double? weightKg;

  int get totalReps => (sets ?? 0) * (reps ?? 0);

  /// Sets × reps × load. Zero unless all three are present, which is what keeps
  /// a half-filled row from quietly dragging the session's volume down.
  double get volumeKg => weightKg == null ? 0 : totalReps * weightKg!;

  /// `4 × 10`, falling back to whichever number is there.
  String? get setsAndReps {
    if (sets != null && reps != null) return '$sets × $reps';
    if (sets != null) return '$sets sets';
    if (reps != null) return '$reps reps';
    return null;
  }
}

/// The totals, ruled top and bottom and divided into columns.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.stats, required this.skin});

  final List<_Stat> stats;
  final _CardSkin skin;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) {
        cells.add(Container(width: 1, height: 34, color: skin.stroke));
      }
      cells.add(
        Expanded(
          child: _StatCell(
            stat: stats[i],
            skin: skin,
            // Outer columns hang off the card's own edges and the middle one
            // splits the difference, so the strip reads as one ruled band
            // rather than three centred blocks with gaps at the ends.
            align: i == 0
                ? CrossAxisAlignment.start
                : (i == stats.length - 1
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.center),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: skin.stroke),
          bottom: BorderSide(color: skin.stroke),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child:
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: cells),
    );
  }
}

class _Stat {
  const _Stat({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.stat,
    required this.skin,
    required this.align,
  });

  final _Stat stat;
  final _CardSkin skin;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Never wrapped and never cut short: a label that breaks mid-word —
        // CALORIE / S — takes the whole strip out of alignment, and one that
        // ellipsises leaves a figure nobody can name. Too wide, it shrinks.
        _ShrinkToFit(
          align: align,
          child: Text(
            stat.label.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: skin.muted,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _ShrinkToFit(
          align: align,
          child: Text.rich(
            TextSpan(
              text: stat.value,
              children: [
                if (stat.unit != null)
                  TextSpan(
                    text: ' ${stat.unit}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: skin.muted,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            style: AppTypography.statNumeralCompact.copyWith(color: skin.text),
          ),
        ),
      ],
    );
  }
}

/// One line of text scaled down, never up, until it fits the width it is given.
///
/// What the card uses in place of an ellipsis for anything that must stay on
/// one line: a figure a few percent smaller is still the whole figure.
class _ShrinkToFit extends StatelessWidget {
  const _ShrinkToFit({required this.align, required this.child});

  final CrossAxisAlignment align;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (align) {
      CrossAxisAlignment.end => AlignmentDirectional.centerEnd,
      CrossAxisAlignment.center => AlignmentDirectional.center,
      _ => AlignmentDirectional.centerStart,
    };
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: child,
    );
  }
}

/// One printed line: name, leader, sets × reps, load.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.exercise,
    required this.showLoad,
    required this.skin,
  });

  final _Exercise exercise;
  final bool showLoad;
  final _CardSkin skin;

  /// The number columns, in the order they sit on the row.
  ///
  /// Fixed rather than sized to their contents, because the point of the sheet
  /// is that the loads line up down the card — a column that jitters by a digit
  /// is not a column. Wide enough for the worst realistic case: `12 × 15` and
  /// `137.5 kg`.
  static const double _setsWidth = 62;
  static const double _loadWidth = 58;

  /// What the leader keeps for itself when the name would otherwise eat the
  /// row. Below about this, the dots stop reading as a leader anyway.
  static const double _minLeader = 12;

  static const double _gapBeforeLeader = 8;
  static const double _gapAfterLeader = 8;
  static const double _gapBeforeLoad = 10;

  @override
  Widget build(BuildContext context) {
    final setsAndReps = exercise.setsAndReps;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Everything to the right of the name is a known width, so the name's
          // cap is whatever is left over. Bounding it this way rather than
          // making it flexible is deliberate twice over: a Flexible that comes
          // in under its share leaves the slack at the *end* of the row, which
          // walks the load column in off the right edge — and a share-of-width
          // cap cannot promise the row fits, which is how a long name and a
          // three-digit load overflowed it.
          final reserved = _gapBeforeLeader +
              _minLeader +
              _gapAfterLeader +
              _setsWidth +
              (showLoad ? _gapBeforeLoad + _loadWidth : 0);
          final nameMax = (constraints.maxWidth - reserved)
              .clamp(0.0, constraints.maxWidth);

          return Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: nameMax),
                // Wraps onto a second line rather than ellipsising — the card
                // is shared as a picture, and a cut-off name cannot be read.
                child: Text(
                  exercise.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: skin.text,
                  ),
                ),
              ),
              const SizedBox(width: _gapBeforeLeader),
              Expanded(child: _DottedLeader(color: skin.stroke)),
              const SizedBox(width: _gapAfterLeader),
              // Past the worst case the columns were sized for, a figure
              // shrinks to fit its column rather than losing its last digits.
              SizedBox(
                width: _setsWidth,
                child: _ShrinkToFit(
                  align: CrossAxisAlignment.end,
                  child: Text(
                    setsAndReps ?? '',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: skin.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (showLoad) ...[
                const SizedBox(width: _gapBeforeLoad),
                SizedBox(
                  width: _loadWidth,
                  child: _ShrinkToFit(
                    align: CrossAxisAlignment.end,
                    child: Text(
                      exercise.weightKg == null
                          ? '—'
                          : '${WorkoutSummaryCard._trimmed(exercise.weightKg!)}'
                              ' kg',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color:
                            exercise.weightKg == null ? skin.muted : skin.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The run of dots between a name and its numbers.
///
/// Drawn rather than assembled out of characters: a row of full stops in the
/// body font spaces itself differently in every writing system the app ships
/// to, and it takes the text baseline with it.
class _DottedLeader extends StatelessWidget {
  const _DottedLeader({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.6,
      child: CustomPaint(painter: _DottedLeaderPainter(color: color)),
    );
  }
}

class _DottedLeaderPainter extends CustomPainter {
  const _DottedLeaderPainter({required this.color});

  final Color color;

  /// Dot pitch. Tight enough to read as a leader, open enough not to turn into
  /// a solid rule at small sizes.
  static const double _pitch = 4;
  static const double _radius = 0.8;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final y = size.height / 2;
    // Laid out from the right, so the dot nearest the numbers always lands the
    // same distance from them however wide the name turned out to be.
    for (var x = size.width - _radius; x >= 0; x -= _pitch) {
      canvas.drawCircle(Offset(x, y), _radius, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedLeaderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The colours the card draws itself in, resolved once for whichever backdrop
/// it has.
///
/// On the themed sheet these follow the palette as they always did. On a photo
/// they are fixed light values: the photo is the same in both themes, so a
/// colour that flipped with the theme would be legible in only one of them.
class _CardSkin {
  const _CardSkin({
    required this.text,
    required this.muted,
    required this.accent,
    required this.stroke,
    required this.border,
    required this.photoFallback,
  });

  factory _CardSkin.resolve(AppPalette palette, {required bool hasPhoto}) {
    if (!hasPhoto) {
      return _CardSkin(
        text: palette.text,
        muted: palette.muted.withValues(alpha: 0.8),
        accent: palette.brandText.withValues(alpha: 0.9),
        stroke: palette.stroke.withValues(alpha: 0.7),
        border: palette.stroke,
        photoFallback: palette.surfaceHigh,
      );
    }

    return _CardSkin(
      text: AppColors.onMedia,
      muted: AppColors.onMedia.withValues(alpha: 0.78),
      // The bright orange, not brandText: on a darkened photo the small-text
      // variant tuned for cream loses against the scrim.
      accent: AppColors.orangeBright,
      stroke: AppColors.onMedia.withValues(alpha: 0.3),
      border: AppColors.onMedia.withValues(alpha: 0.22),
      photoFallback: const Color(0xFF1E1E1E),
    );
  }

  final Color text;
  final Color muted;
  final Color accent;

  /// Rules, dividers and the dotted leader — everything the sheet is ruled
  /// with, which on a log sheet is all one weight.
  final Color stroke;
  final Color border;

  /// Painted when the photo itself fails to load.
  final Color photoFallback;
}
