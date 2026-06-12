import 'package:flutter/painting.dart';

/// Xene design-system color tokens.
///
/// All Color literals in the app must reference this class.
/// To change the brand look without a binary update, expose these values
/// through the backend /config endpoint and read them via uiConfigProvider.
abstract final class XeneTheme {
  // ── Primary brand ──────────────────────────────────────────────────────────
  static const orange = Color(0xFFFF5500);

  // ── Accents ────────────────────────────────────────────────────────────────
  static const teal = Color(0xFF00C5A5);
  static const tealDark = Color(0xFF00A88F);

  // ── Text hierarchy ─────────────────────────────────────────────────────────
  static const ink = Color(0xFF111111);
  // #767676 is the exact WCAG AA threshold (4.5:1) for normal text on white.
  static const muted = Color(0xFF767676);
  static const mutedLight = Color(0xFF767676);
  static const mutedXLight = Color(
    0xFFBBBBBB,
  ); // decorative chrome only — not for body text
  static const textDark = Color(0xFF444444);
  static const textDarker = Color(0xFF555555);
  static const textDeep = Color(0xFF303030);

  // ── Surfaces & borders ─────────────────────────────────────────────────────
  static const border = Color(0xFFE0E0E0);
  static const borderLight = Color(0xFFE8E8E8);
  static const borderHeavy = Color(0xFFE5E5E5);
  static const surface = Color(0xFFF5F5F5);
  static const surfaceLight = Color(0xFFF0F0F0);
  static const surfaceDeep = Color(0xFFFAFAFA);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFD32F2F);
  static const warning = Color(0xFFE65100);
  static const warningBg = Color(0xFFFFF3E0);

  // ── Feature-specific ──────────────────────────────────────────────────────
  /// Bookmark / queue saved indicator.
  static const purple = Color(0xFF8B5CF6);

  // ── Platform brand (external brand standards — do not change) ─────────────
  static const scOrange = Color(0xFFFF5500); // SoundCloud == orange
  static const bcGreen = Color(0xFF4E9A06); // Bandcamp
  static const ytRed = Color(0xFFFF4444); // YouTube
  static const twitchPurple = Color(0xFF9146FF); // Twitch

  // ── Content-type pill palette ──────────────────────────────────────────────
  static const mixGold = Color(0xFFC9A96E);
  static const epPurple = Color(0xFFAB47BC);
  static const albumBlue = Color(0xFF42A5F5);

  // ── High-contrast mode tokens (used by Phase 2D toggle) ───────────────────
  static const highContrastFg = Color(0xFF000000);
  static const highContrastBg = Color(0xFFFFFFFF);
}
