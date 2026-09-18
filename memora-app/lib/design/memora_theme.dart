import 'package:flutter/material.dart';

import 'memora_colors.dart';
import 'memora_spacing.dart';
import 'memora_typography.dart';

/// The app's single [ThemeData] — the "Aurora" visual system, **light-first**
/// since the 60-30-10 pivot (sin spec de Kiro, decidido directamente con el
/// usuario tras validar el sistema dark-first varias veces en dispositivo y
/// seguir viéndolo "sin vida"/"muy oscuro"). Applied once via
/// `MaterialApp(theme: ...)`; individual screens should reach for
/// `Theme.of(context)` / the components in `lib/design/widgets/` instead of
/// hardcoding colors or text styles.
///
/// **Renamed from `MemoraTheme.dark`**: that name actively lied about this
/// theme now (`Brightness.light`, [MemoraColors.paper] canvas) — the single
/// call site is `lib/main.dart`'s `MaterialApp(theme: MemoraTheme.theme)`.
abstract final class MemoraTheme {
  static ThemeData get theme {
    final colorScheme = const ColorScheme.light().copyWith(
      brightness: Brightness.light,
      surface: MemoraColors.paper,
      onSurface: MemoraColors.deepInk,
      primary: MemoraColors.glassBlueOnLight,
      onPrimary: MemoraColors.paper,
      secondary: MemoraColors.auraVioletOnLight,
      onSecondary: MemoraColors.paper,
      error: MemoraColors.semanticError,
      onError: MemoraColors.paper,
      outline: MemoraColors.border,
    );

    final textTheme = MemoraTypography.textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: MemoraColors.paper,
      textTheme: textTheme,
      fontFamily: textTheme.bodyMedium?.fontFamily,
      splashFactory: InkRipple.splashFactory,
      dividerTheme: const DividerThemeData(
        color: MemoraColors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: MemoraColors.paper,
        foregroundColor: MemoraColors.deepInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: const IconThemeData(color: MemoraColors.deepInk),
      ),
      iconTheme: const IconThemeData(color: MemoraColors.deepInk),
      // Raw glassBlue is too light (~1.6:1) to read as a spinner stroke on
      // the light canvas — see MemoraColors.glassBlueOnLight's doc comment.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MemoraColors.glassBlueOnLight,
      ),
      cardTheme: CardThemeData(
        color: MemoraColors.surface1,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MemoraRadius.card),
          side: const BorderSide(color: MemoraColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MemoraColors.surface2,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MemoraRadius.card),
        ),
      ),
      // Deliberately kept on the light canvas (surface2/Mist + Deep Ink
      // text), not flipped to a dark "inverse surface" toast: keeps this
      // theme's token set (borders, semantic colors) working unmodified
      // here instead of needing a second set of "on dark" overrides just
      // for snackbars.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MemoraColors.surface2,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: MemoraColors.deepInk,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MemoraRadius.card),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Mist (surface2) rather than surface1: a "recessed" fill distinct
        // from the softer surface1 card tone most forms sit inside (see
        // create_album_screen.dart) — same fill either way if a field ever
        // lives directly on a surface2 card (its own border still delimits
        // it, same as any outlined chip on a matching background).
        fillColor: MemoraColors.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MemoraSpacing.md,
          vertical: MemoraSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MemoraRadius.card),
          borderSide: const BorderSide(color: MemoraColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MemoraRadius.card),
          borderSide: const BorderSide(color: MemoraColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MemoraRadius.card),
          borderSide: const BorderSide(color: MemoraColors.glassBlueOnLight),
        ),
        hintStyle: textTheme.bodyMedium,
        labelStyle: textTheme.bodyMedium,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MemoraColors.surface2,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: MemoraColors.deepInk,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MemoraSpacing.sm,
          vertical: MemoraSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MemoraRadius.pill),
          side: const BorderSide(color: MemoraColors.border),
        ),
      ),
    );
  }
}
