import 'package:flutter/material.dart';

/// Design Token Model for the Bento Glassmorphic Design System.
class AppColors {
  final Color bgPrimary;
  final Color bgSecondary;
  final Color cardBg;
  final Color cardHoverBg;
  final Color subCardBg;
  final Color subCardBorder;
  final Color sidebarBg;
  final Color headerBg;
  final Color headerBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color borderDefault;
  final Color accentColor;
  final Color primaryGlow;
  final Color accentCyan;
  final Color accentEmerald;
  final Color accentAmber;
  final Color accentRose;
  final Color accentPurple;

  Color get accentBlue => accentColor;

  // Mesh background orbs
  final Color orb1;
  final Color orb2;
  final Color orb3;
  final double orbOpacity;

  // Frosted glass surfaces
  final Color glassBg;
  final Color glassBorder;
  final Color glassHighlight;

  const AppColors({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.cardBg,
    required this.cardHoverBg,
    required this.subCardBg,
    required this.subCardBorder,
    required this.sidebarBg,
    required this.headerBg,
    required this.headerBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.borderDefault,
    required this.accentColor,
    required this.primaryGlow,
    required this.accentCyan,
    required this.accentEmerald,
    required this.accentAmber,
    required this.accentRose,
    required this.accentPurple,
    required this.orb1,
    required this.orb2,
    required this.orb3,
    required this.orbOpacity,
    required this.glassBg,
    required this.glassBorder,
    required this.glassHighlight,
  });
}
