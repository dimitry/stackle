import 'package:flutter/material.dart';

import 'app_tokens.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Avenir Next',
    scaffoldBackgroundColor: appMainSurfaceColor,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFECECEC),
          secondary: const Color(0xFF8C8C8C),
          surface: const Color(0xFF0E0E0E),
          surfaceContainerHighest: const Color(0xFF1B1B1B),
          onSurface: Colors.white,
        ),
    popupMenuTheme: const PopupMenuThemeData(
      color: appPopupColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      menuPadding: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: appDialogBorderColor),
      ),
      textStyle: TextStyle(
        fontFamily: 'Avenir Next',
        color: Color(0xFFEAEAEA),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF101010),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: appDialogBorderColor),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Avenir Next',
        color: Color(0xFFF0F0F0),
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Avenir Next',
        color: Color(0xFFD2D2D2),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: appInputFillColor,
      hintStyle: TextStyle(
        fontFamily: 'Avenir Next',
        color: Color(0xFF8A8A8A),
        fontSize: 13,
      ),
      labelStyle: TextStyle(
        fontFamily: 'Avenir Next',
        color: Color(0xFFC8C8C8),
        fontSize: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2B2B2B)),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF2B2B2B)),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE7E7E7),
        textStyle: const TextStyle(
          fontFamily: 'Avenir Next',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF242424),
        foregroundColor: const Color(0xFFF4F4F4),
        textStyle: const TextStyle(
          fontFamily: 'Avenir Next',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFEAEAEA),
        side: const BorderSide(color: Color(0xFF333333)),
        textStyle: const TextStyle(
          fontFamily: 'Avenir Next',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF151515),
      contentTextStyle: const TextStyle(
        fontFamily: 'Avenir Next',
        color: Color(0xFFEDEDED),
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: const Color(0xFFC8E1FF),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: appDialogBorderColor),
      ),
    ),
  );
}
