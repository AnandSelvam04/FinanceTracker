/// The gaps and paddings the app is laid out with.
///
/// Padding used to be typed in per screen (6, 10, 14, 18 and 20 alongside
/// the round values), so the same kind of gap differed from one screen to
/// the next. Everything now steps through this one scale.
class Space {
  Space._();

  /// A hairline nudge between two lines that belong together.
  static const double xxs = 2;

  /// Between a label and the thing it labels.
  static const double xs = 4;

  /// Between neighbouring items in a row or list.
  static const double sm = 8;

  /// Inside a compact card or chip row; between small groups.
  static const double md = 12;

  /// The standard inset: screen edges and inside a card.
  static const double lg = 16;

  /// Between sections.
  static const double xl = 24;

  /// Around a full-screen message or illustration.
  static const double xxl = 32;
}

/// Corner radii, matched to the size of the thing being rounded.
class Radii {
  Radii._();

  /// Thin bars and legend swatches.
  static const double xs = 4;

  /// Small tiles, tooltips and progress bars.
  static const double sm = 8;

  /// Controls: buttons, inputs, chips, list rows and icon badges.
  static const double md = 12;

  /// Cards and the floating action button.
  static const double lg = 16;

  /// Sheets and dialogs.
  static const double xl = 24;
}
