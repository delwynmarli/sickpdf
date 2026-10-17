import 'package:flutter/material.dart';

/// Central design tokens for sickPDF.
///
/// Editorial minimalism: warm near-white background, deep charcoal text, and
/// a single restrained teal accent reserved for primary actions, selection,
/// and progress. Everything else stays neutral. Avoid adding brand hues;
/// reuse these tokens so every screen stays cohesive.
abstract final class AppColors {
  /// Deep charcoal used for primary text and strong surfaces.
  static const charcoal = Color(0xFF202321);

  /// Legacy alias kept for screens not yet migrated off the old token.
  static const navy = charcoal;

  /// Single brand accent. Reserved for primary actions and brand marks.
  static const teal = Color(0xFF147D73);

  /// Bright teal used on dark surfaces where contrast is required.
  static const tealBright = Color(0xFF6FD6C9);

  /// Legacy alias.
  static const green = teal;

  /// Legacy alias.
  static const greenBright = tealBright;

  /// Warm near-white app background.
  static const background = Color(0xFFFAFAF8);

  /// Card / dialog surface.
  static const surface = Colors.white;

  /// Muted secondary surface (chips, subtle fills).
  static const surfaceMuted = Color(0xFFF1F3F0);

  /// Hairline border for cards, fields, and dividers.
  static const border = Color(0xFFE7E9E6);

  /// Secondary text color.
  static const textMuted = Color(0xFF737873);

  /// Danger color for destructive actions and errors.
  static const danger = Color(0xFFB3261E);

  /// Success color for positive status that is not the brand accent.
  static const success = Color(0xFF2A6E4F);
}

/// Spacing scale (dp). Keep to these steps to keep rhythm consistent.
abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Standard horizontal screen padding.
  static const screen = md;

  /// Minimum interactive target size (Material/Android accessibility).
  static const minTarget = 48.0;
}

/// Corner radii. Small set, applied consistently.
abstract final class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
}

/// Builds the single app-wide [ThemeData] used by [MaterialApp].
ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  final background = isDark ? const Color(0xFF161816) : AppColors.background;
  final surface = isDark ? const Color(0xFF1F2220) : AppColors.surface;
  final border = isDark ? const Color(0xFF31342F) : AppColors.border;
  final onSurface = isDark ? const Color(0xFFE9EBE7) : AppColors.charcoal;
  final muted = isDark ? const Color(0xFF9EA39B) : AppColors.textMuted;
  final accent = isDark ? AppColors.tealBright : AppColors.teal;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    brightness: brightness,
  ).copyWith(
    primary: accent,
    onPrimary: isDark ? AppColors.charcoal : Colors.white,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: muted,
    outlineVariant: border,
    error: AppColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    // Rely on the platform default font so text respects user font scaling.
    visualDensity: VisualDensity.standard,
  );

  final text = base.textTheme;

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF191C1A) : AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.teal, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: isDark ? AppColors.charcoal : Colors.white,
        disabledBackgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFE4E7E3),
        disabledForegroundColor: muted,
        minimumSize: const Size.fromHeight(AppSpacing.minTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        minimumSize: const Size.fromHeight(AppSpacing.minTarget),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        minimumSize: const Size(48, AppSpacing.minTarget),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.teal,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.teal,
      thumbColor: AppColors.teal,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? null : muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.teal.withValues(alpha: 0.4)
            : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.teal
            : null,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.teal
            : muted,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF2A2D2A) : AppColors.charcoal,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      height: 66,
      indicatorColor: AppColors.teal.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? onSurface : muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? accent : muted,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: onSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      titleTextStyle: text.titleMedium?.copyWith(
        color: onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    textTheme: text.apply(bodyColor: onSurface, displayColor: onSurface),
  );
}
