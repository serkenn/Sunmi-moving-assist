import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Core imports
import 'core/constants/app_constants.dart';
import 'core/config/runtime_settings.dart';
import 'core/database/database_helper.dart';

// Data layer imports
import 'data/services/hardware_service.dart';
import 'data/repositories/product_repository.dart';

// Presentation layer imports
import 'presentation/screens/home_screen.dart';
import 'presentation/providers/product_provider.dart';

void main() async {
  // Ensure Flutter widgets are initialized
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeSettings.load();

  runApp(const SunmiInventoryApp());
}

class SunmiInventoryApp extends StatelessWidget {
  const SunmiInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Database provider
        Provider<DatabaseHelper>(create: (_) => DatabaseHelper()),

        // Hardware service provider
        Provider<HardwareService>(
          create: (_) {
            const useMockHardware = bool.fromEnvironment(
              'USE_MOCK_HARDWARE',
              defaultValue: false,
            );
            if (useMockHardware) return MockHardwareService();
            if (Platform.isAndroid) return SunmiHardwareService();
            return MockHardwareService();
          },
        ),

        // Repository provider
        ProxyProvider2<DatabaseHelper, HardwareService, ProductRepository>(
          create: (context) => ProductRepositoryImpl(
            context.read<DatabaseHelper>(),
            context.read<HardwareService>(),
          ),
          update: (context, database, hardware, previous) =>
              previous ?? ProductRepositoryImpl(database, hardware),
        ),

        // Product provider for state management
        ChangeNotifierProxyProvider<ProductRepository, ProductProvider>(
          create: (context) =>
              ProductProvider(context.read<ProductRepository>()),
          update: (context, repository, previous) =>
              previous ?? ProductProvider(repository),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: _buildAppTheme(),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      primarySwatch: MaterialColor(
        AppConstants.primaryColorValue,
        _buildColorSwatch(AppConstants.primaryColorValue),
      ),
      primaryColor: const Color(AppConstants.primaryColorValue),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(AppConstants.primaryColorValue),
        secondary: const Color(AppConstants.secondaryColorValue),
        error: const Color(AppConstants.errorColorValue),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(AppConstants.primaryColorValue),
        foregroundColor: Colors.white,
        elevation: AppConstants.cardElevation,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: AppConstants.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(AppConstants.primaryColorValue),
          foregroundColor: Colors.white,
          elevation: AppConstants.cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.defaultPadding,
            vertical: AppConstants.smallPadding,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(AppConstants.secondaryColorValue),
        foregroundColor: Colors.white,
        elevation: AppConstants.cardElevation,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.defaultPadding,
          vertical: AppConstants.smallPadding,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(AppConstants.primaryColorValue),
        unselectedItemColor: Colors.grey,
        elevation: AppConstants.cardElevation,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey[200],
        selectedColor: const Color(AppConstants.primaryColorValue),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.smallPadding,
          vertical: 2,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
        bodyMedium: TextStyle(fontSize: 14, color: Colors.black54),
        bodySmall: TextStyle(fontSize: 12, color: Colors.black54),
      ),
      useMaterial3: true,
    );
  }

  Map<int, Color> _buildColorSwatch(int primaryValue) {
    final Color primaryColor = Color(primaryValue);

    return {
      50: primaryColor.withValues(alpha: 0.1),
      100: primaryColor.withValues(alpha: 0.2),
      200: primaryColor.withValues(alpha: 0.3),
      300: primaryColor.withValues(alpha: 0.4),
      400: primaryColor.withValues(alpha: 0.5),
      500: primaryColor.withValues(alpha: 0.6),
      600: primaryColor.withValues(alpha: 0.7),
      700: primaryColor.withValues(alpha: 0.8),
      800: primaryColor.withValues(alpha: 0.9),
      900: primaryColor,
    };
  }
}
