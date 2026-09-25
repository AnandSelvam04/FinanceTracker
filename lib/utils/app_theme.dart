import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Centralized Material 3 theming for the whole app.
///
/// The screens previously relied on a bare `ColorScheme.fromSeed`, so every
/// card, button, input, and nav bar used framework defaults with mismatched
/// corner radii and elevations. Defining the component themes here lifts every
/// screen at once and keeps the look consistent as new screens are added.
class AppTheme {
  AppTheme._();

  /// Brand seed — the vivid indigo/blue of the "Expense Tracker Pro" look.
  /// Kept identical across light/dark so dark mode keeps the brand color
  /// instead of falling back to grey.
  static const Color seed = Color(0xFF4B3FE4); // indigo/blue

  static ThemeData light([Color? seedColor]) =>
      _build(Brightness.light, seedColor ?? seed);
  static ThemeData dark([Color? seedColor]) =>
      _build(Brightness.dark, seedColor ?? seed);

  static ThemeData _build(Brightness brightness, Color seedColor) {
    // Fidelity keeps `primary` true to the seed. The default tonal-spot
    // variant desaturated the vivid brand blue into a muted slate-purple, so
    // the FAB, switches, hero cards and headline totals clashed with the
    // saturated app bar (which paints the raw seed). Fidelity makes every
    // accent read as the same brand colour the header shows.
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final isDark = brightness == Brightness.dark;

    // A curated type scale layered over the Material 3 defaults. Tightening the
    // tracking on the big display/headline sizes and firming up the title/label
    // weights gives figures and section headings a more deliberate, premium
    // feel than the framework's stock spacing — without hard-coding sizes or
    // colours (those still come from the scheme, so the scale adapts to both
    // themes and to text-scaling accessibility settings).
    final baseText = Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: scheme,
    );
    final base = isDark ? baseText.white : baseText.black;
    final textTheme = base.copyWith(
      displayLarge: base.displayLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.0),
      displayMedium: base.displayMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      displaySmall: base.displaySmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineLarge: base.headlineLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium: base.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.25),
      headlineSmall: base.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.25),
      titleLarge: base.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    );

    // Smooth, modern forward/back transitions on every route without touching
    // each Navigator.push call site.
    const pageTransitions = PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      },
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      pageTransitionsTheme: pageTransitions,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarThemeData(
        centerTitle: false,
        scrolledUnderElevation: 0,
        // A bold, saturated brand header (the vivid blue bar from the
        // "Expense Tracker Pro" designs) rather than the muted tonal primary,
        // so the header reads the same in both light and dark. The seed colours
        // the app offers are all deep enough for white to stay legible on top.
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        // A hairline surface-tinted fill reads as a grouped surface without the
        // heavy drop shadows the old elevation:2 cards had.
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        highlightElevation: 6,
        // The full accent (not the muted container) makes the primary action
        // pop against the dashboard's soft surfaces.
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      // Outlined buttons sat beside filled ones (e.g. Scan / Speak on the add
      // screen) as fully rounded pills while their filled siblings were 14px
      // rounded rectangles. Match the shape, padding and weight.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 24,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        // Material 3 sets trailing text in labelSmall (11px), and nearly every
        // list here puts its amount in the trailing slot — so balances and
        // transaction amounts rendered as the smallest text on screen. Money
        // is the point of the row; give it a readable, firm weight.
        leadingAndTrailingTextStyle: textTheme.titleSmall?.copyWith(
          fontSize: 15,
          color: scheme.onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      // Dialogs used the 28px framework default while sheets use 24px; share
      // the sheet's corner and surface so the two overlay kinds match.
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      // Budget, goal and summary bars each wrapped the indicator in their own
      // ClipRRect, which rounds the track but leaves the filled bar with a
      // square leading edge. The theme radius rounds both, in one place.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearMinHeight: 8,
        linearTrackColor: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
    );
  }
}
