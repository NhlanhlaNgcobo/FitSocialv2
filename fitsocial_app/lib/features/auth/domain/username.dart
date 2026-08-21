/// The rules a username has to obey, in one place.
///
/// A username is the account's identity: it is the profile URL, what an
/// `@`-mention resolves to, and one of the two things you can sign in with. It
/// is therefore unique, unlike the display name, which nobody owns and anybody
/// may duplicate.
///
/// Uniqueness is enforced by document id in the `usernames` collection, so
/// every layer that touches a username has to agree on exactly which string
/// becomes that id. That agreement is [normalizeUsername] and nothing else may
/// re-derive it: the setup screen, the edit screen, the reservation
/// repository, the security rules and the login Cloud Function all key off the
/// same normalized form, and a second opinion anywhere would open the very
/// collision this file exists to prevent.
library;

/// How long an account must wait between username changes.
///
/// Not a load-shedding measure — an anti-impersonation one. Without a cooldown
/// a handle can be worn, used to trade on somebody's reputation, and shed
/// within an afternoon. Fourteen days makes each identity change expensive
/// enough to be deliberate.
///
/// Firestore rules enforce this independently, so a client that skipped the
/// check still gets refused. The duration is duplicated there as
/// `duration.value(14, 'd')` because rules cannot import Dart — change one and
/// you must change the other.
const Duration usernameChangeCooldown = Duration(days: 14);

/// How long a vacated username stays reserved for the account that left it.
///
/// Releasing a handle the instant its owner renames is what makes renaming
/// dangerous: every stale mention, screenshot and link pointing at `@bear`
/// would resolve to whoever grabbed it next, and the original owner could not
/// take it back because [usernameChangeCooldown] has them locked out. Holding
/// it for the same fourteen days closes that window and leaves an undo.
///
/// Also duplicated in firestore.rules — see the note above.
const Duration usernameGracePeriod = Duration(days: 14);

const int usernameMinLength = 3;
const int usernameMaxLength = 20;

/// Characters a username may contain, after normalization.
final RegExp _allowedUsername = RegExp(r'^[a-z0-9._]+$');

/// Must open and close on something substantial. A username of pure
/// punctuation passes the character filter but reads as nothing at all.
final RegExp _startsAlphanumeric = RegExp(r'^[a-z0-9]');
final RegExp _endsAlphanumeric = RegExp(r'[a-z0-9]$');

/// The canonical form of [raw]: the exact string used as the `usernames`
/// document id, and the exact string stored on the profile.
///
/// Lowercasing is what makes `@Bear` and `@bear` the same account rather than
/// two accounts one shift key apart — the single cheapest impersonation vector
/// there is. Stored handles predating this are inconsistent about the leading
/// '@' (some carry it, some don't), so it is stripped here too and never
/// persisted; the '@' is decoration the UI adds back when it draws one.
String normalizeUsername(String? raw) {
  return (raw ?? '').trim().replaceAll(RegExp(r'^@+'), '').trim().toLowerCase();
}

/// Why a username was rejected, or null when it is well-formed.
///
/// Only ever judges the *shape* of the string. Whether anyone already holds it
/// is a question for the reservation collection, not for a regex.
String? validateUsernameFormat(String? raw) {
  final username = normalizeUsername(raw);

  if (username.isEmpty) return 'Pick a username.';
  if (username.length < usernameMinLength) {
    return 'Use at least $usernameMinLength characters.';
  }
  if (username.length > usernameMaxLength) {
    return 'Use at most $usernameMaxLength characters.';
  }
  if (!_allowedUsername.hasMatch(username)) {
    return 'Letters, numbers, dots and underscores only.';
  }
  if (!_startsAlphanumeric.hasMatch(username) ||
      !_endsAlphanumeric.hasMatch(username)) {
    return 'Start and end with a letter or number.';
  }
  if (username.contains('..')) {
    return "Dots can't sit next to each other.";
  }
  if (_reservedUsernames.contains(username)) {
    return 'That username is reserved.';
  }
  return null;
}

/// Names that must never belong to a person.
///
/// Two separate hazards. The first is routing: the profile URL is
/// `fitsocial.app/<username>`, so a user holding `settings` would sit on top of
/// a path the app may want. The second is authority: an account called
/// `support` or `admin` can ask for a password and be believed.
const Set<String> _reservedUsernames = {
  'admin',
  'administrator',
  'fitsocial',
  'support',
  'help',
  'staff',
  'team',
  'official',
  'moderator',
  'mod',
  'root',
  'system',
  'security',
  'billing',
  'settings',
  'about',
  'explore',
  'search',
  'home',
  'login',
  'logout',
  'signup',
  'register',
  'privacy',
  'terms',
  'api',
  'www',
  'me',
  'you',
  'null',
  'undefined',
};

/// What the `usernames` collection says about one name.
enum UsernameStatus {
  /// Nobody holds it and no grace period covers it.
  available,

  /// Held by another account right now.
  taken,

  /// Already this account's own username. Saving it again is a no-op, not a
  /// collision — worth its own case so the UI doesn't tell you your own
  /// username is unavailable.
  yours,

  /// Vacated by another account, still inside [usernameGracePeriod]. Reads as
  /// taken to everyone except the account that left it.
  heldByPrevious,

  /// Vacated by *this* account and still inside the grace period, so it can be
  /// reclaimed. This is the undo that makes renaming survivable.
  reclaimable,
}

/// The verdict on one candidate username, ready for the UI to render.
class UsernameAvailability {
  const UsernameAvailability({required this.status, this.formatError});

  /// A candidate that never reached the collection because its shape was
  /// wrong. Carries the reason so the field can say what to fix.
  const UsernameAvailability.malformed(String reason)
      : status = UsernameStatus.taken,
        formatError = reason;

  final UsernameStatus status;
  final String? formatError;

  /// Whether saving this username would succeed.
  bool get canUse =>
      formatError == null &&
      (status == UsernameStatus.available ||
          status == UsernameStatus.yours ||
          status == UsernameStatus.reclaimable);

  /// One line for the field to show beneath itself.
  String? get message {
    if (formatError != null) return formatError;
    switch (status) {
      case UsernameStatus.available:
        return 'Available.';
      case UsernameStatus.yours:
        return 'This is already your username.';
      case UsernameStatus.reclaimable:
        return 'Yours to take back — you used this one before.';
      case UsernameStatus.taken:
      case UsernameStatus.heldByPrevious:
        return 'That username is taken.';
    }
  }
}

/// How long until [lastChangedAt] clears [usernameChangeCooldown], or null when
/// the username can be changed right now.
///
/// A null [lastChangedAt] means the account has never renamed — the first
/// change is always free, so only subsequent ones are throttled.
Duration? usernameCooldownRemaining(DateTime? lastChangedAt, {DateTime? now}) {
  if (lastChangedAt == null) return null;
  final current = now ?? DateTime.now();
  final unlocksAt = lastChangedAt.add(usernameChangeCooldown);
  if (!unlocksAt.isAfter(current)) return null;
  return unlocksAt.difference(current);
}

/// [remaining] as something worth putting in front of a person.
///
/// Rounds up rather than down: with eleven hours left, "12 hours" overpromises
/// the wait while "11 hours" risks reading as available sooner than it is. The
/// honest answer to "how long until I can do this" is the ceiling.
String describeCooldownRemaining(Duration remaining) {
  if (remaining.inHours >= 24) {
    final days = (remaining.inHours / 24).ceil();
    return days == 1 ? '1 day' : '$days days';
  }
  if (remaining.inMinutes >= 60) {
    final hours = (remaining.inMinutes / 60).ceil();
    return hours == 1 ? '1 hour' : '$hours hours';
  }
  final minutes = remaining.inMinutes.clamp(1, 59);
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}

/// Thrown when a username is claimed between the availability check and the
/// save. The check is advisory — it is a read, and someone else can commit in
/// the gap — so the transaction re-checks and this is how it says no.
class UsernameTakenException implements Exception {
  const UsernameTakenException(this.username);

  final String username;

  @override
  String toString() => 'Username @$username is already taken.';
}

/// Thrown when a rename lands inside [usernameChangeCooldown].
class UsernameChangeTooSoonException implements Exception {
  const UsernameChangeTooSoonException(this.remaining);

  final Duration remaining;

  @override
  String toString() => 'Username was changed too recently. '
      'Try again in ${describeCooldownRemaining(remaining)}.';
}

/// Whether [identifier] should be treated as an email address at sign-in.
///
/// The login field takes either, so something has to decide which. An interior
/// '@' is the test: it is legal in an email address and excluded from usernames
/// by [_allowedUsername], so no string can plausibly be both.
///
/// The leading '@' is stripped before looking, because people type their
/// username the way they see it written. Testing for '@' anywhere would send
/// `@bear` down the email path and fail a login that was perfectly valid.
bool looksLikeEmail(String identifier) {
  return identifier.trim().replaceAll(RegExp(r'^@+'), '').contains('@');
}
