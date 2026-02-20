class AppConstants {
  // App Information
  static const String appName = 'Sunmi在庫管理';
  static const String version = '1.0.0';

  // Database
  static const String databaseName = 'inventory.db';
  static const int databaseVersion = 1;
  static const String productsTable = 'products';

  // API Keys / IDs (to be set from environment variables)
  static const String rakutenApiKey = String.fromEnvironment(
    'RAKUTEN_API_KEY',
    defaultValue: '',
  );
  static const String rakutenApplicationId = String.fromEnvironment(
    'RAKUTEN_APPLICATION_ID',
    defaultValue: '',
  );
  static const String rakutenAccessKey = String.fromEnvironment(
    'RAKUTEN_ACCESS_KEY',
    defaultValue: '',
  );
  static const String rakutenAffiliateId = String.fromEnvironment(
    'RAKUTEN_AFFILIATE_ID',
    defaultValue: '',
  );
  static const String amazonApiKey = String.fromEnvironment(
    'AMAZON_API_KEY',
    defaultValue: '',
  );
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
  static const String googleSheetsSpreadsheetId = String.fromEnvironment(
    'GOOGLE_SHEETS_SPREADSHEET_ID',
    defaultValue: '',
  );
  static const String googleServiceAccountJson = String.fromEnvironment(
    'GOOGLE_SERVICE_ACCOUNT_JSON',
    defaultValue: '',
  );

  // API URLs
  static const String rakutenBaseUrl =
      'https://openapi.rakuten.co.jp/ichibams/api';
  static const String rakutenProductSearchUrl =
      '$rakutenBaseUrl/IchibaItem/Search/20170706';

  // Hardware Settings
  static const int scanTimeout = 10000; // milliseconds
  static const int printRetryCount = 3;

  // AI Analysis
  static const String aiModel = 'gemini-2.0-flash';
  static const double aiConfidenceThreshold = 0.7;
  static const int aiAnalysisMaxRetries = 2;

  // Categories
  static const List<String> productCategories = [
    '食品・飲料',
    '家電・AV機器',
    '家具・インテリア',
    '衣類・ファッション',
    '本・雑誌',
    'ゲーム・おもちゃ',
    '日用品・消耗品',
    '化粧品・美容',
    'スポーツ・アウトドア',
    'その他',
  ];

  // Moving Decisions
  static const List<String> movingDecisions = [
    'keep', // 持参
    'parents_home', // 実家保管
    'discard', // 廃棄
    'sell', // 売却
  ];

  static const Map<String, String> movingDecisionLabels = {
    'keep': '持参',
    'parents_home': '実家保管',
    'discard': '廃棄',
    'sell': '売却',
  };

  static const Map<String, String> movingDecisionDescriptions = {
    'keep': '引っ越し先に持参する',
    'parents_home': '実家で保管する',
    'discard': '廃棄・処分する',
    'sell': 'リサイクルショップ等で売却する',
  };

  // Colors (Material Design based)
  static const int primaryColorValue = 0xFF1976D2; // Blue 700
  static const int secondaryColorValue = 0xFF388E3C; // Green 600
  static const int errorColorValue = 0xFFD32F2F; // Red 700

  // Storage Locations
  static const List<String> storageLocations = [
    '実家',
    'リビング',
    '寝室',
    'キッチン',
    '洗面所',
    'クローゼット',
    '押入れ',
    '倉庫',
    'ガレージ',
    'その他',
  ];

  // Printer Settings
  static const Map<String, String> printerSettings = {
    'paperWidth': '58', // mm
    'fontSize': 'normal',
    'alignment': 'left',
  };

  // Export Settings
  static const String defaultExportFileName = 'inventory_export';
  static const List<String> exportFormats = ['csv', 'xlsx', 'json'];

  // Validation
  static const int minBarcodeLength = 8;
  static const int maxBarcodeLength = 18;
  static const int maxProductNameLength = 100;
  static const int maxDescriptionLength = 500;
  static const int maxNotesLength = 200;

  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 8.0;
  static const double cardElevation = 2.0;

  // Timeouts
  static const int networkTimeout = 30000; // milliseconds
  static const int cacheTimeout = 86400000; // 24 hours in milliseconds

  // Default values
  static const String defaultCategory = 'その他';
  static const String unknownBrand = '不明';
  static const String noDescription = '説明なし';

  // Feature Flags
  static const bool enableAiAnalysis = true;
  static const bool enableCloudSync = true;
  static const bool enablePrinting = true;
  static const bool enableCameraCapture = true;

  // Debug
  static const bool isDebugMode =
      bool.fromEnvironment('dart.vm.product') == false;
}

// Utility class for app-wide helper functions
class AppUtils {
  static String formatDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  static String truncateString(String input, int maxLength) {
    if (input.length <= maxLength) return input;
    return '${input.substring(0, maxLength)}...';
  }

  static bool isValidBarcode(String barcode) {
    if (barcode.isEmpty) return false;
    if (barcode.length < AppConstants.minBarcodeLength ||
        barcode.length > AppConstants.maxBarcodeLength) {
      return false;
    }
    return RegExp(r'^[0-9]+$').hasMatch(barcode);
  }

  static String? validateProductName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return '商品名を入力してください';
    }
    if (name.length > AppConstants.maxProductNameLength) {
      return '商品名は${AppConstants.maxProductNameLength}文字以内で入力してください';
    }
    return null;
  }
}
