import 'package:flutter/material.dart';

/// Estética alinhada ao 7me: azul marinho + branco, minimalista, tipografia
/// limpa, cartões com bastante espaço em branco, sem ruído visual.
abstract final class AppColors {
  static const navy = Color(0xFF17284C);
  static const navyLight = Color(0xFF2A4270);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7F8FA);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Altura mínima de qualquer alvo tocável.
///
/// 48, e não 44: 44 é o mínimo da Apple e 48 o do Material. Escolher o maior
/// atende os dois, e a diferença de 4 px não aperta nenhuma tela deste app.
const _minTapTarget = 48.0;

abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: Brightness.light,
      primary: AppColors.navy,
      surface: AppColors.background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      // SC-004 da feature 010 exige 44×44 em todo alvo tocável, e a conferência
      // manual de 2026-08-10 mediu os botões da Home entre 32 e 36 px de
      // altura — nenhum passava. A causa é o padrão do Material, que encolhe o
      // alvo em telas densas; a largura nunca foi o problema, a altura sempre
      // foi.
      //
      // `MaterialTapTargetSize.padded` garante o mínimo de 48 do Material
      // mesmo quando o visual é menor, e o `minimumSize` fixa a altura visível.
      // Os dois juntos, porque um sozinho deixa passar: `padded` aumenta a área
      // sem aumentar o desenho, e quem olha a tela continua vendo um botão
      // apertado.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // E `visualDensity` padrão, não o adaptativo.
      //
      // O adaptativo é o default e, em desktop e web, subtrai até 8 px na
      // vertical. Foi ele que transformou o mínimo de 48 em 40 medidos — o
      // conserto anterior parecia certo no código e continuava reprovando na
      // tela. Só a medição no navegador mostrou.
      visualDensity: VisualDensity.standard,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, _minTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, _minTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, _minTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.navy,
        ),
      ),
    );
  }
}
