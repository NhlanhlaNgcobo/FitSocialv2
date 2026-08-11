import 'package:fitsocial_app/features/main/domain/mentions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Convenience: just the handles a body of text names, in order, with repeats.
List<String> spanNames(String text) =>
    parseMentions(text).map((span) => span.username).toList();

void main() {
  group('parseMentions', () {
    test('finds a handle written on its own', () {
      expect(spanNames('great session @bear'), ['bear']);
    });

    test('normalizes case, so @Bear and @bear are one account', () {
      expect(spanNames('@Bear and @BEAR'), ['bear', 'bear']);
    });

    test('gives trailing punctuation back to the sentence', () {
      final spans = parseMentions('thanks @bear.');
      expect(spans.single.username, 'bear');
      // The span must stop before the full stop, or the link swallows it.
      expect(spans.single.end, 'thanks @bear'.length);
    });

    test('leaves an email address alone', () {
      expect(spanNames('mail me at bear@example.com'), isEmpty);
    });

    test('ignores a run that could not be a username', () {
      // Too short, doubled dots, and a reserved name nobody may hold.
      expect(spanNames('@ab @bear..rsa @admin'), isEmpty);
    });

    test('handles back to back mentions', () {
      expect(spanNames('@bear @nhlanhla, good run'), ['bear', 'nhlanhla']);
    });

    test('a bare @ names nobody', () {
      expect(spanNames('what @ even is this'), isEmpty);
    });

    test('spans cover exactly the handle, @ included', () {
      const text = 'up next: @bear.rsa trains';
      final span = parseMentions(text).single;
      expect(text.substring(span.start, span.end), '@bear.rsa');
    });
  });

  group('mentionedUsernames', () {
    test('deduplicates, keeping first-mention order', () {
      expect(
        mentionedUsernames('@nhlanhla then @bear then @nhlanhla again'),
        ['nhlanhla', 'bear'],
      );
    });

    test('caps how many people one item can notify', () {
      final text = List.generate(20, (i) => '@runner$i').join(' ');
      expect(mentionedUsernames(text), hasLength(maxMentionsPerItem));
    });

    test('text without an @ costs nothing and names nobody', () {
      expect(mentionedUsernames('a good clean session'), isEmpty);
    });
  });

  group('mentionQueryAt', () {
    test('opens on a bare @, before anything has been typed', () {
      final query = mentionQueryAt('nice one @', 10);
      expect(query, isNotNull);
      expect(query!.prefix, '');
      expect(query.start, 9);
    });

    test('reports what has been typed so far', () {
      expect(mentionQueryAt('nice one @bea', 13)!.prefix, 'bea');
    });

    test('is null when the cursor has moved past the handle', () {
      // The space ends the token.
      expect(mentionQueryAt('nice one @bear ', 15), isNull);
    });

    test('is null inside an email address', () {
      expect(mentionQueryAt('bear@example', 12), isNull);
    });

    test('is null when the cursor is before the @', () {
      expect(mentionQueryAt('hi @bear', 2), isNull);
    });

    test('closes once the token outgrows a username', () {
      final text = '@${'a' * 30}';
      expect(mentionQueryAt(text, text.length), isNull);
    });

    test('reads the handle the cursor is in, not the last one in the text', () {
      const text = '@bear and @nhl';
      expect(mentionQueryAt(text, 5)!.prefix, 'bear');
      expect(mentionQueryAt(text, text.length)!.prefix, 'nhl');
    });
  });

  group('completeMention', () {
    test('replaces the typed handle and leaves the cursor after it', () {
      const text = 'nice one @bea';
      final completion =
          completeMention(text, mentionQueryAt(text, 13)!, 'bear.rsa');

      expect(completion.text, 'nice one @bear.rsa ');
      expect(completion.cursor, completion.text.length);
    });

    test('keeps whatever followed the handle', () {
      const text = 'nice one @bea, well done';
      final completion =
          completeMention(text, mentionQueryAt(text, 13)!, 'bear');

      expect(completion.text, 'nice one @bear , well done');
    });

    test('the completed handle is one the parser then recognises', () {
      const text = 'hey @b';
      final completion =
          completeMention(text, mentionQueryAt(text, 6)!, 'nhlanhla');

      expect(mentionedUsernames(completion.text), ['nhlanhla']);
    });
  });
}
