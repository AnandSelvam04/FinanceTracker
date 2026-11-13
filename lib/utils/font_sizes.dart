/// The app's text sizes, smallest to largest.
///
/// Screens used to type a size in wherever they set one (thirteen different
/// values, with 10 and 11 among them), so the same kind of line was a
/// different size from one screen to the next and some figures were too
/// small to read comfortably. Every size now comes from this scale; outside a
/// chart or the calendar grid, nothing is below [caption].
///
/// These are sizes only. Weight and colour stay with the widget, and the
/// system's text-size setting still scales all of them.
class FontSizes {
  FontSizes._();

  /// Axis ticks on charts and the amounts inside the spending calendar's
  /// day cells, where a label has a few pixels to itself. Not for anything
  /// else.
  static const double tick = 11;

  /// Supporting detail: a muted second line, a label above a figure.
  static const double caption = 12;

  /// Ordinary reading text.
  static const double body = 14;

  /// A row's main figure or name.
  static const double bodyLarge = 16;

  /// A sheet's or card's own title.
  static const double title = 18;

  /// A screen-level heading or a card's headline figure.
  static const double heading = 20;

  /// The one big number on a screen: the amount being entered, the total.
  static const double display = 28;
}
