/// The app's picture shape: 9:16, portrait, as width / height.
///
/// Every photo post is shown in this frame, and every run, workout and meal
/// card takes it when it has no photo of its own — on a phone the picture is
/// held upright, and a tall card leaves room for everything the card has to
/// say. A card's own background photo, cropped to another shape, still sets
/// the card's shape. Pulse keeps its own frame.
const double kPictureAspectRatio = 9 / 16;

/// Widest shape a card's own background photo may give it, so one panoramic
/// shot cannot flatten a card to a strip.
const double kWidestPictureRatio = 1.91;

/// The shape a photo post is shown at, from the ratio stored on it: the
/// shape it was cropped to, held between 9:16 and the widest feed shape so
/// one malformed value cannot blow out the feed. Null when nothing usable was
/// stored, and the photo has to be measured instead.
double? photoPostRatio(double? stored) {
  if (stored == null || stored <= 0) return null;
  return stored.clamp(kPictureAspectRatio, kWidestPictureRatio);
}
