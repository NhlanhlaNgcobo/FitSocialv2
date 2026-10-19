import 'package:fitsocial_app/features/main/domain/daily_prompts.dart';
import 'package:fitsocial_app/features/notes/domain/note_models.dart';
import 'package:fitsocial_app/features/notes/presentation/note_sheets.dart';
import 'package:fitsocial_app/features/notifications/domain/notification_models.dart';
import 'package:fitsocial_app/features/pulse/domain/pulse_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 19, 12);

FitNote _note(String authorId, {int hoursAgo = 1, String text = 'Pap'}) {
  final createdAt = _now.subtract(Duration(hours: hoursAgo));
  return FitNote(
    authorId: authorId,
    authorName: '$authorId Surname',
    noteId: 'n_$authorId',
    text: text,
    promptId: '2026-10-19',
    promptText: "What's your go-to post-run meal?",
    createdAt: createdAt,
    expiresAt: createdAt.add(NoteTiming.lifetime),
  );
}

PulseTrayEntry _pulse(String authorId,
    {required bool unseen, bool own = false}) {
  final segment = PulseSegment(
    id: 'p_$authorId',
    authorId: authorId,
    authorName: authorId,
    type: PulseMediaType.text,
    createdAt: _now.subtract(const Duration(hours: 2)),
    expiresAt: _now.add(const Duration(hours: 22)),
  );
  return PulseTrayEntry(
    authorId: authorId,
    authorName: authorId,
    segments: [segment],
    isOwn: own,
    hasUnseen: unseen,
    firstUnseenIndex: 0,
  );
}

void main() {
  group('buildTrayTiles', () {
    test('unseen Pulses, then Notes newest first, then watched Pulses', () {
      final tiles = buildTrayTiles(
        pulses: [
          _pulse('me', unseen: false, own: true),
          _pulse('ringNew', unseen: true),
          _pulse('ringOld', unseen: false),
          _pulse('ringOldWithNote', unseen: false),
        ],
        notes: [
          _note('noteOnlyOlder', hoursAgo: 5),
          _note('noteOnlyNewer', hoursAgo: 1),
          _note('ringOldWithNote', hoursAgo: 3),
          _note('me'),
        ],
        currentUserId: 'me',
        now: _now,
      );

      expect(tiles.map((tile) => tile.authorId), [
        'ringNew',
        'noteOnlyNewer',
        'ringOldWithNote',
        'noteOnlyOlder',
        'ringOld',
      ]);
      // One tile carries both when somebody has both.
      final both = tiles.firstWhere((t) => t.authorId == 'ringOldWithNote');
      expect(both.pulse, isNotNull);
      expect(both.note, isNotNull);
    });

    test('your own Note never appears as somebody else', () {
      final tiles = buildTrayTiles(
        pulses: const [],
        notes: [_note('me')],
        currentUserId: 'me',
        now: _now,
      );
      expect(tiles, isEmpty);
    });

    test('an expired Note is dropped even if the server still has it', () {
      final tiles = buildTrayTiles(
        pulses: const [],
        notes: [_note('late', hoursAgo: 25)],
        currentUserId: 'me',
        now: _now,
      );
      expect(tiles, isEmpty);
    });
  });

  group('NoteDraft', () {
    final prompt = DailyPrompts.forDay(_now);

    test('needs 1 to 60 characters after trimming', () {
      expect(NoteDraft(prompt: prompt, text: '   ').isPublishable, isFalse);
      expect(NoteDraft(prompt: prompt, text: ' Pap ').isPublishable, isTrue);
      expect(
        NoteDraft(prompt: prompt, text: 'x' * 61).isPublishable,
        isFalse,
      );
    });
  });

  test('no question asks for a photo a Note cannot carry', () {
    for (final question in DailyPrompts.all) {
      expect(question, isNot(startsWith('Show us')), reason: question);
      expect(question, isNot(contains('Tag them')), reason: question);
    }
  });

  test('hearts read as a sentence', () {
    NoteHeart heart(String name) =>
        NoteHeart(userId: name, userName: '$name X', noteId: 'n');
    expect(heartsLabel(const []), 'No likes yet');
    expect(heartsLabel([heart('Thabo')]), 'Thabo liked this');
    expect(
      heartsLabel([heart('Thabo'), heart('Lerato')]),
      'Thabo and Lerato liked this',
    );
    expect(
      heartsLabel([heart('Thabo'), heart('Lerato'), heart('Sipho')]),
      'Thabo, Lerato and 1 other liked this',
    );
  });

  test('a reply notification says what was said and opens the replier', () {
    const reply = FitNotification(
      id: 'noteReply_1',
      type: FitNotificationType.noteReply,
      actorId: 'u2',
      actorName: 'Thabo',
      isRead: false,
      replyText: 'Same here!',
    );
    expect(reply.message, 'replied to your note: Same here!');
    expect(reply.route, '/user/u2');
    expect(FitNotificationType.fromKey('noteHeart'),
        FitNotificationType.noteHeart);
  });
}
