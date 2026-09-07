/**
 * The words a push notification carries, built from the notification document.
 *
 * MUST AGREE EXACTLY with `FitNotification.message`, `_likedNoun`,
 * `_challengeNoun` and `route` in
 * lib/features/notifications/domain/notification_models.dart. The list and the
 * tray say the same sentence about the same event, and a disagreement between
 * them is the kind of bug nobody reports — the push reads slightly wrong, the
 * user shrugs, and it stays wrong.
 *
 * Duplicated rather than shared because there is no way to share it: one side
 * is Dart in the app, the other is Node on the server. The same trade is made
 * for `normalizeUsername` in index.js, and the same defence applies —
 * test/push.test.js pins every type on this side, so a tenth kind added in Dart
 * and forgotten here fails a test rather than shipping silent.
 */

/// The seven reaction emoji, keyed as they are stored. Mirrors
/// `FitReaction.emoji` in lib/shared/reactions/fit_reaction.dart.
const REACTION_EMOJI = {
  love: "\u{1F9E1}",
  fire: "\u{1F525}",
  respect: "\u{1F4AF}",
  // Explicit medium skin-tone modifier, as on the Dart side, so every viewer
  // sees the same arm.
  strong: "\u{1F4AA}\u{1F3FD}",
  champion: "\u{1F3C6}",
  celebrate: "\u{1F973}",
  rocket: "\u{1F680}",
};

/**
 * What the acted-on thing is called in the sentence. Unknown and missing types
 * fall back to "post", which is true of everything in the feed.
 */
function likedNoun(postType) {
  switch (postType) {
    case "image":
      return "photo";
    case "meal":
      return "meal";
    case "run":
      return "run";
    case "workout":
      return "workout";
    default:
      return "post";
  }
}

/**
 * The challenge's name where it is known, and a plain noun where it is not, so
 * a row written before the title was carried still reads as a sentence.
 */
function challengeNoun(challengeTitle) {
  const title = String(challengeTitle ?? "");
  return title === "" ? "a challenge" : title;
}

/**
 * The sentence that follows the actor's name, or null for a `type` this build
 * does not know.
 *
 * Returning null rather than guessing mirrors `_fromDoc` on the Dart side: a
 * notification written by a newer app is skipped, not pushed as a blank.
 */
function messageFor(data) {
  const noun = likedNoun(data.postType);

  switch (data.type) {
    case "follow":
      return "started following you";
    case "like": {
      // The emoji carries the whole point of having seven, so it leads the
      // sentence. A row from before reactions has none and keeps the words it
      // was written with.
      const emoji = REACTION_EMOJI[data.reaction];
      return emoji ? `reacted ${emoji} to your ${noun}` : `liked your ${noun}`;
    }
    case "mention":
      return data.commentId
        ? "mentioned you in a comment"
        : `mentioned you in a ${noun}`;
    case "comment":
      return `commented on your ${noun}`;
    case "reply":
      return "replied to your comment";
    case "tag":
      return `tagged you in a ${noun}`;
    case "challengeInvite":
      return `invited you to ${challengeNoun(data.challengeTitle)}`;
    case "challengeAccepted":
      return `joined ${challengeNoun(data.challengeTitle)}`;
    case "challengeCompleted":
      return `You finished ${challengeNoun(data.challengeTitle)}`;
    default:
      return null;
  }
}

/**
 * Where tapping the notification goes. Mirrors `FitNotification.route`.
 *
 * Null when the row arrived without the id its destination needs — the push
 * still sends, and tapping it just opens the app.
 */
function routeFor(data) {
  switch (data.type) {
    case "follow": {
      const actorId = String(data.actorId ?? "");
      return actorId === "" ? null : `/user/${actorId}`;
    }
    case "like":
    case "mention":
    case "comment":
    case "reply":
    case "tag": {
      const postId = String(data.postId ?? "");
      return postId === "" ? null : `/post/${postId}`;
    }
    case "challengeInvite":
    case "challengeAccepted":
    case "challengeCompleted": {
      const challengeId = String(data.challengeId ?? "");
      return challengeId === "" ? null : `/challenge/board/${challengeId}`;
    }
    default:
      return null;
  }
}

/**
 * Title, body and destination for one notification document, or null if there
 * is nothing sensible to say about it.
 *
 * The title is the actor's name and the body is what they did — the same two
 * halves the notification row renders. `challengeCompleted` is the exception:
 * it is addressed to the recipient about their own achievement ("You finished
 * X"), and putting somebody else's name above that sentence would read as
 * though they had finished it.
 */
function notificationCopy(data) {
  if (!data) return null;

  const body = messageFor(data);
  if (!body) return null;

  const actorName = String(data.actorName ?? "").trim();
  const title =
    data.type === "challengeCompleted"
      ? "FitSocial"
      : actorName || "FitSocial Member";

  return { title, body, route: routeFor(data) };
}

module.exports = { notificationCopy, _internals: { messageFor, routeFor, likedNoun, challengeNoun, REACTION_EMOJI } };
