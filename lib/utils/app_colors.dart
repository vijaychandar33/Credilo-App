import 'package:flutter/material.dart';

/// Professional minimal color palette for the app
class AppColors {
  // Primary colors - Soft purple palette for dark mode contrast
  static const Color primary = Color(0xFF9D4EDD); // Vibrant violet
  static const Color primaryLight = Color(0xFFC77DFF); // Lighter purple for accents
  static const Color primaryDark = Color(0xFF7B2CBF); // Deeper purple
  
  // Neutral colors
  static const Color background = Color(0xFF000000); // Pure black
  static const Color surface = Color(0xFF121212); // Dark grey
  static const Color surfaceElevated = Color(0xFF1E1E1E); // Elevated surface
  static const Color surfaceContainer = Color(0xFF2A2A2A); // Container surface
  
  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF); // White
  static const Color textSecondary = Color(0xFFB3B3B3); // Light grey
  static const Color textTertiary = Color(0xFF808080); // Medium grey
  static const Color textDisabled = Color(0xFF4A4A4A); // Dark grey
  
  // Semantic colors
  static const Color success = Color(0xFF10B981); // Green
  static const Color error = Color(0xFFEF4444); // Red
  static const Color warning = Color(0xFFF59E0B); // Amber
  
  // Border colors
  static const Color border = Color(0xFF333333); // Dark grey border
  static const Color borderFocused = primary; // Primary blue for focused inputs
  
  // Overlay colors
  static Color overlay = Colors.black.withValues(alpha: 0.1);
  static Color overlayDark = Colors.black.withValues(alpha: 0.3);
}

