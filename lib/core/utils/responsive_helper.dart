import 'package:flutter/material.dart';

/// Helper para gerenciar responsividade e adaptar layouts
class ResponsiveHelper {
  /// Verifica se está em mobile
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  /// Verifica se está em tablet
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1024;
  }

  /// Verifica se está em desktop
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }

  /// Retorna largura máxima para conteúdo no desktop
  static double getMaxContentWidth(BuildContext context) {
    if (isDesktop(context)) {
      return 1200; // Largura máxima no desktop
    }
    return MediaQuery.of(context).size.width;
  }

  /// Padding responsivo
  static EdgeInsets getPagePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(16);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(24);
    } else {
      return const EdgeInsets.all(32);
    }
  }

  /// Abre modal ou página dependendo do dispositivo
  /// No mobile: abre como página full-screen
  /// No desktop/tablet: abre como modal
  static Future<T?> showResponsiveDialog<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
  }) {
    if (isMobile(context)) {
      // Mobile: navegação full-screen
      return Navigator.push<T>(
        context,
        MaterialPageRoute(
          builder: builder,
          fullscreenDialog: true,
        ),
      );
    } else {
      // Desktop/Tablet: modal
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 600,
              maxHeight: 800,
            ),
            child: builder(context),
          ),
        ),
      );
    }
  }

  /// Abre bottom sheet ou página dependendo do dispositivo
  static Future<T?> showResponsiveBottomSheet<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool isDismissible = true,
  }) {
    if (isMobile(context)) {
      // Mobile: navegação full-screen
      return Navigator.push<T>(
        context,
        MaterialPageRoute(
          builder: builder,
          fullscreenDialog: true,
        ),
      );
    } else {
      // Desktop/Tablet: bottom sheet
      return showModalBottomSheet<T>(
        context: context,
        isDismissible: isDismissible,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
            maxWidth: 600,
          ),
          child: builder(context),
        ),
      );
    }
  }

  /// Widget que centraliza conteúdo no desktop
  static Widget centerContentOnDesktop({
    required BuildContext context,
    required Widget child,
  }) {
    if (isDesktop(context)) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: getMaxContentWidth(context),
          ),
          child: child,
        ),
      );
    }
    return child;
  }

  /// Scaffold com largura máxima no desktop
  static Widget responsiveScaffold({
    required BuildContext context,
    PreferredSizeWidget? appBar,
    required Widget body,
    Widget? floatingActionButton,
    Widget? drawer,
    Widget? bottomNavigationBar,
    Color? backgroundColor,
  }) {
    Widget content = body;

    if (isDesktop(context)) {
      content = Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: getMaxContentWidth(context),
          ),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: body,
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: content,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      bottomNavigationBar: bottomNavigationBar,
      backgroundColor: backgroundColor ?? const Color(0xFFF5F7FA),
    );
  }

  /// Retorna tamanho de fonte responsivo
  static double getResponsiveFontSize(BuildContext context, double baseFontSize) {
    if (isMobile(context)) {
      return baseFontSize;
    } else if (isTablet(context)) {
      return baseFontSize * 1.1;
    } else {
      return baseFontSize * 1.2;
    }
  }

  /// Grid responsivo (número de colunas)
  static int getGridColumns(BuildContext context) {
    if (isMobile(context)) {
      return 1;
    } else if (isTablet(context)) {
      return 2;
    } else {
      return 3;
    }
  }

  /// Espaçamento responsivo
  static double getResponsiveSpacing(BuildContext context, double baseSpacing) {
    if (isMobile(context)) {
      return baseSpacing;
    } else if (isTablet(context)) {
      return baseSpacing * 1.5;
    } else {
      return baseSpacing * 2;
    }
  }
}
