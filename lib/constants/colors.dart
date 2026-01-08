import 'package:flutter/material.dart';

/// Centralized color constants for the Lemonade Mobile app.
/// Contains all manually declared colors used throughout the application.
class AppColors {
  // ===== EXISTING THEME COLORS =====
  // Light theme colors
  static const primaryLight = Color(0xFF6366F1); // Indigo
  static const secondaryLight = Color(0xFF8B5CF6); // Purple
  static const backgroundLight = Color(0xFFFAFAFA);
  static const surfaceLight = Colors.white;
  static const surfaceVariantLight = Color(0xFFF8FAFC);
  static const errorLight = Color(0xFFEF4444);
  static const onPrimaryLight = Colors.white;
  static const onBackgroundLight = Color(0xFF1F2937);
  static const onSurfaceLight = Color(0xFF374151);
  static const userMessageLight = Color(0xFF6366F1);
  static const assistantMessageLight = Color(0xFFF1F5F9);
  static const borderLight = Color(0xFFE5E7EB);

  // Dark theme colors
  static const primaryDark = Color(0xFF818CF8); // Lighter indigo for dark
  static const secondaryDark = Color(0xFFA78BFA); // Lighter purple for dark
  static const backgroundDark = Color(0xFF0F172A); // Dark slate
  static const surfaceDark = Color(0xFF1E293B); // Slate
  static const surfaceVariantDark = Color(0xFF334155); // Lighter slate
  static const errorDark = Color(0xFFF87171);
  static const onPrimaryDark = Colors.white;
  static const onBackgroundDark = Color(0xFFF1F5F9);
  static const onSurfaceDark = Color(0xFFE2E8F0);
  static const userMessageDark = Color(0xFF6366F1);
  static const assistantMessageDark = Color(0xFF334155);
  static const borderDark = Color(0xFF475569);

  // ===== SYNTAX HIGHLIGHTING COLORS =====
  // Dark theme syntax highlighting
  static const syntaxRootDark = Color(0xFFE6EDF3);
  static const syntaxKeywordDark = Color(0xFFFD7B31);
  static const syntaxStringDark = Color(0xFFA5D6FF);
  static const syntaxCommentDark = Color(0xFF8B949E);
  static const syntaxNumberDark = Color(0xFF79C0FF);
  static const syntaxFunctionDark = Color(0xFFD2A8FF);
  static const syntaxTypeDark = Color(0xFF7EE787);
  static const syntaxVariableDark = Color(0xFFF85149);

  // Light theme syntax highlighting
  static const syntaxRootLight = Color(0xFF1F2328);
  static const syntaxKeywordLight = Color(0xFFCF222E);
  static const syntaxStringLight = Color(0xFF0A3069);
  static const syntaxCommentLight = Color(0xFF6E7781);
  static const syntaxNumberLight = Color(0xFF0550AE);
  static const syntaxFunctionLight = Color(0xFF8250DF);
  static const syntaxTypeLight = Color(0xFF953800);
  static const syntaxVariableLight = Color(0xFFCF222E);

  // ===== CODE BLOCK COLORS =====
  static const codeBlockBackgroundDark = Color(0xFF161B22);
  static const codeBlockBackgroundLight = Color(0xFFF6F8FA);
  static const codeBlockBorderDark = Color(0xFF30363D);
  static const codeBlockBorderLight = Color(0xFFD1D9E0);
  static const codeBlockTextDark = Color(0xFFCCCCCC);
  static const codeBlockTextLight = Color(0xFF666666);

  // ===== INLINE CODE COLORS =====
  static const inlineCodeKeywordDark = Color(0xFF2D7D9A);
  static const inlineCodeKeywordLight = Color(0xFF005CC5);
  static const inlineCodeStringDark = Color(0xFF4F8F4F);
  static const inlineCodeStringLight = Color(0xFF22863A);
  static const inlineCodeBackgroundDark = Color(0x1AFFFFFF);
  static const inlineCodeBackgroundLight = Color(0x1A000000);

  // ===== BLOCKQUOTE COLORS =====
  static const blockquoteBackground = Color(0x0F388BFD);
  static const blockquoteBorderDark = Color(0xFF58A6FF);
  static const blockquoteBorderLight = Color(0xFF388BFD);

  // ===== TABLE COLORS =====
  static const tableBorderDark = Color(0xFF30363D);
  static const tableBorderLight = Color(0xFFD1D9E0);

  // ===== MODEL CAPABILITY ICON COLORS =====
  static const capabilityVision = Colors.blue;
  static const capabilityImageGeneration = Colors.green;
  static const capabilityTextOnly = Colors.grey;

  // ===== UI ELEMENT COLORS =====
  static const hintText = Colors.grey;
  static const serverAlive = Colors.green;
  static const serverDead = Colors.red;

  // ===== SHADOW COLORS =====
  static const shadowLight = Color(0x0F000000);
  static const shadowDark = Color(0x4D000000);

  // ===== SEMANTIC COLORS =====
  static const transparent = Colors.transparent;
  static const white = Colors.white;
  static const black = Colors.black;

  // ===== UTILITY METHODS =====
  /// Get syntax highlighting theme for dark mode
  static Map<String, TextStyle> getSyntaxThemeDark() => {
    'root': TextStyle(color: syntaxRootDark, backgroundColor: transparent),
    'keyword': TextStyle(color: syntaxKeywordDark, fontWeight: FontWeight.bold),
    'string': TextStyle(color: syntaxStringDark),
    'comment': TextStyle(color: syntaxCommentDark),
    'number': TextStyle(color: syntaxNumberDark),
    'function': TextStyle(color: syntaxFunctionDark),
    'type': TextStyle(color: syntaxTypeDark),
    'variable': TextStyle(color: syntaxVariableDark),
  };

  /// Get syntax highlighting theme for light mode
  static Map<String, TextStyle> getSyntaxThemeLight() => {
    'root': TextStyle(color: syntaxRootLight, backgroundColor: transparent),
    'keyword': TextStyle(color: syntaxKeywordLight, fontWeight: FontWeight.bold),
    'string': TextStyle(color: syntaxStringLight),
    'comment': TextStyle(color: syntaxCommentLight),
    'number': TextStyle(color: syntaxNumberLight),
    'function': TextStyle(color: syntaxFunctionLight),
    'type': TextStyle(color: syntaxTypeLight),
    'variable': TextStyle(color: syntaxVariableLight),
  };
}
