import 'app_models.dart';

/// The question at the top of the feed, one a day.
///
/// A feed of logs gives people something to look at; a question gives them
/// something to say. These are written to be answered in a line or a photo by
/// somebody who trained today or didn't — never a quiz, never a lecture — and
/// every one of them is something another member would actually want to read
/// the answers to.
///
/// The list is walked in order, one per local day, so everybody in the same
/// timezone sees the same question and their answers land together. Add to the
/// end: reordering would change what today's question is for everyone mid-day.
class DailyPrompts {
  const DailyPrompts._();

  static const List<String> all = [
    "What's your go-to post-run meal?",
    'Show us where you train today.',
    "What's one lift you're chasing a PR on?",
    'Morning or evening training — and why?',
    "What's on your training playlist right now?",
    "Best piece of advice a coach ever gave you?",
    "What's your rest-day ritual?",
    'Which race is on your bucket list?',
    'Your cheapest high-protein meal — go.',
    "What got you back after your last time off?",
    "What's the hardest session you've done this month?",
    'Show us your pre-workout fuel.',
    'Who do you train with, and why them?',
    "What's one habit that changed your fitness the most?",
    'Parkrun, gym or somewhere else this weekend?',
    "What's a stretch or mobility move you swear by?",
    'How do you stay moving when it rains?',
    "What's your current weekly goal?",
    'Rate your sleep last night out of 10. Does it show in training?',
    'Favourite route in your city — where is it?',
    "What's a workout you hate but do anyway?",
    'What does a good training week look like for you?',
    'Share a meal prep win from this week.',
    "What's one thing you'd tell someone on day one?",
    'Hydration check: how much water so far today?',
    "What's your warm-up, start to finish?",
    'Which FitSocial member keeps you going? Tag them.',
    "What's something you can do now that you couldn't a year ago?",
    'Solo sessions or group sessions?',
    "What's the next event you're training for?",
  ];

  /// Today's question, keyed by the local day so answers group by it.
  static PostPrompt forDay(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    // Days since a fixed start, rather than day-of-year: the walk never jumps
    // back to the first question on the 1st of January.
    final index =
        day.difference(DateTime(2026, 1, 1)).inHours ~/ 24 % all.length;
    return PostPrompt(id: dayKey(day), text: all[index]);
  }

  /// `YYYY-MM-DD` for [day].
  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
