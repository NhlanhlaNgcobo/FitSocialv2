abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// The corner radii a glass surface is allowed to have.
///
/// Liquid glass makes a radius structural rather than decorative: the shader
/// builds its distance field from the corners, so the rim, the bend and the
/// clip all have to agree on the same number. When every call site picked its
/// own the app ended up with nine of them — 14, 16, 18, 19, 20, 22, 24, 28 —
/// and panes sitting side by side on one screen read as different materials
/// rather than as one.
///
/// Four values, because there are only four jobs:
///
/// * [card] is a pane on the page. It matches `cardTheme` and [DarkCard], so a
///   card built by hand lands on the same shape as one built by the widget.
/// * [nested] is a surface *inside* a pane — a thumbnail, an inner well. It
///   has to be visibly tighter than its container or the two corners fight.
/// * [field] is a form control — a text input, a picker row. Matches
///   `inputDecorationTheme`, so a control built by hand sits level with the
///   inputs beside it.
/// * [pill] is anything capsule-shaped: chips, badges, the nav's selection.
abstract final class AppRadius {
  static const double card = 24;
  static const double field = 18;
  static const double nested = 16;
  static const double pill = 999;
}
