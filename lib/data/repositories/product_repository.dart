import '../../core/constants/app_constants.dart';
import '../../core/database/database_helper.dart';
import '../models/product.dart';
import '../models/product_suggestion.dart';
import '../services/gemini_service.dart';
import '../services/hardware_service.dart';
import '../services/open_food_facts_service.dart';
import '../services/rakuten_service.dart';
import '../services/sheets_service.dart';

// Abstract repository interface
abstract class ProductRepository {
  // Basic CRUD operations
  Future<Product?> getProductById(int id);
  Future<Product?> getProductByBarcode(String barcode);
  Future<List<Product>> getAllProducts({
    String? category,
    String? searchQuery,
    String? movingDecision,
    int? limit,
    int? offset,
  });
  Future<int> saveProduct(Product product);
  Future<int> updateProduct(Product product);
  Future<int> deleteProduct(int id);
  Future<int> deleteAllProducts();

  // Barcode scanning
  Future<String?> scanBarcode();

  // Product search and analysis
  Future<Product?> searchProductByBarcode(String barcode);
  Future<List<ProductSuggestion>> suggestProductsByName(String query);
  Future<List<ProductSuggestion>> suggestProductsFromScan({
    required String rawValue,
    String? barcode,
  });
  Future<Product> analyzeProductWithAI(Product product);

  // Hardware operations
  Future<void> printProductTag(Product product);
  Future<void> printInventoryList(List<Product> products);
  Future<void> printQrCode(String data, {String? label});
  Future<void> printBarcode(String data, {String? label});

  // Statistics
  Future<int> getProductCount({String? category, String? movingDecision});
  Future<Map<String, int>> getCategoryCounts();
  Future<Map<String, int>> getMovingDecisionCounts();

  // Batch operations
  Future<void> saveProductsBatch(List<Product> products);

  // Export
  Future<SheetsExportResult> exportToGoogleSheets(List<Product> products);
}

// Implementation class
class ProductRepositoryImpl implements ProductRepository {
  final DatabaseHelper _databaseHelper;
  final HardwareService _hardwareService;
  final RakutenService _rakutenService;
  final OpenFoodFactsService _openFoodFactsService;
  final GeminiService _geminiService;
  final SheetsService _sheetsService;

  ProductRepositoryImpl(
    this._databaseHelper,
    this._hardwareService, {
    RakutenService? rakutenService,
    OpenFoodFactsService? openFoodFactsService,
    GeminiService? geminiService,
    SheetsService? sheetsService,
  }) : _rakutenService = rakutenService ?? RakutenService(),
       _openFoodFactsService = openFoodFactsService ?? OpenFoodFactsService(),
       _geminiService = geminiService ?? GeminiService(),
       _sheetsService = sheetsService ?? SheetsService();

  // Basic CRUD operations
  @override
  Future<Product?> getProductById(int id) async {
    try {
      return await _databaseHelper.getProductById(id);
    } catch (e) {
      throw ProductRepositoryException('Failed to get product by id: $e');
    }
  }

  @override
  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      return await _databaseHelper.getProductByBarcode(barcode);
    } catch (e) {
      throw ProductRepositoryException('Failed to get product by barcode: $e');
    }
  }

  @override
  Future<List<Product>> getAllProducts({
    String? category,
    String? searchQuery,
    String? movingDecision,
    int? limit,
    int? offset,
  }) async {
    try {
      return await _databaseHelper.getAllProducts(
        category: category,
        searchQuery: searchQuery,
        movingDecision: movingDecision,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      throw ProductRepositoryException('Failed to get products: $e');
    }
  }

  @override
  Future<int> saveProduct(Product product) async {
    try {
      if (product.id == null) {
        return await _databaseHelper.insertProduct(product);
      } else {
        return await _databaseHelper.updateProduct(product);
      }
    } catch (e) {
      throw ProductRepositoryException('Failed to save product: $e');
    }
  }

  @override
  Future<int> updateProduct(Product product) async {
    try {
      return await _databaseHelper.updateProduct(product);
    } catch (e) {
      throw ProductRepositoryException('Failed to update product: $e');
    }
  }

  @override
  Future<int> deleteProduct(int id) async {
    try {
      return await _databaseHelper.deleteProduct(id);
    } catch (e) {
      throw ProductRepositoryException('Failed to delete product: $e');
    }
  }

  @override
  Future<int> deleteAllProducts() async {
    try {
      return await _databaseHelper.deleteAllProducts();
    } catch (e) {
      throw ProductRepositoryException('Failed to delete all products: $e');
    }
  }

  // Barcode scanning
  @override
  Future<String?> scanBarcode() async {
    try {
      return await _hardwareService.scanBarcode();
    } catch (e) {
      throw ProductRepositoryException('Failed to scan barcode: $e');
    }
  }

  // Product search and analysis
  @override
  Future<Product?> searchProductByBarcode(String barcode) async {
    try {
      // First check if product exists in local database
      final existingProduct = await getProductByBarcode(barcode);
      if (existingProduct != null) {
        return existingProduct;
      }

      // If not found locally, search via APIs (Rakuten, Amazon)
      final externalProduct = await _searchProductFromExternalAPIs(barcode);
      if (externalProduct == null) {
        return null;
      }

      final savedProductId = await saveProduct(externalProduct);
      return externalProduct.copyWith(id: savedProductId);
    } catch (e) {
      throw ProductRepositoryException('Failed to search product: $e');
    }
  }

  @override
  Future<List<ProductSuggestion>> suggestProductsByName(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    try {
      final suggestions = <ProductSuggestion>[];

      final localMatches = await _databaseHelper.getAllProducts(
        searchQuery: normalizedQuery,
        limit: 8,
      );
      suggestions.addAll(
        localMatches.map(
          (product) => ProductSuggestion.fromProduct(
            product,
            source: 'ローカルDB',
            confidence: 1.0,
            reason: '既存登録商品',
          ),
        ),
      );

      suggestions.addAll(
        await _rakutenService.searchSuggestionsByKeyword(
          normalizedQuery,
          hits: 6,
        ),
      );

      suggestions.addAll(
        await _geminiService.suggestProductCandidates(
          rawInput: normalizedQuery,
          nameHint: normalizedQuery,
          maxResults: 5,
        ),
      );

      return _dedupeAndSortSuggestions(suggestions);
    } catch (e) {
      throw ProductRepositoryException(
        'Failed to suggest products by name: $e',
      );
    }
  }

  @override
  Future<List<ProductSuggestion>> suggestProductsFromScan({
    required String rawValue,
    String? barcode,
  }) async {
    final trimmedRaw = rawValue.trim();
    final normalizedBarcode = _normalizeBarcode(barcode);
    final trimmedBarcode = normalizedBarcode ?? barcode?.trim();

    try {
      final suggestions = <ProductSuggestion>[];

      if (trimmedBarcode != null && trimmedBarcode.isNotEmpty) {
        final existingProduct = await _databaseHelper.getProductByBarcode(
          trimmedBarcode,
        );
        if (existingProduct != null) {
          suggestions.add(
            ProductSuggestion.fromProduct(
              existingProduct,
              source: 'ローカルDB',
              confidence: 1.0,
              reason: 'バーコード一致',
            ),
          );
        }

        suggestions.addAll(
          await _openFoodFactsService.searchSuggestionsByBarcode(
            trimmedBarcode,
            maxResults: 1,
          ),
        );

        suggestions.addAll(
          await _rakutenService.searchSuggestionsByBarcode(
            trimmedBarcode,
            hits: 4,
          ),
        );
      }

      final keywordFromRaw = _extractKeywordFromRaw(trimmedRaw);
      if (keywordFromRaw.isNotEmpty) {
        suggestions.addAll(
          await _rakutenService.searchSuggestionsByKeyword(
            keywordFromRaw,
            hits: 4,
            preferredBarcode: trimmedBarcode,
          ),
        );
      }

      if (_shouldUseAiForScan(
        rawValue: trimmedRaw,
        barcode: trimmedBarcode,
        keywordFromRaw: keywordFromRaw,
      )) {
        suggestions.addAll(
          await _geminiService.suggestProductCandidates(
            rawInput: trimmedRaw,
            barcodeHint: trimmedBarcode,
            nameHint: keywordFromRaw.isEmpty ? null : keywordFromRaw,
            maxResults: 5,
          ),
        );
      }

      if (suggestions.isEmpty &&
          trimmedBarcode != null &&
          trimmedBarcode.isNotEmpty) {
        final barcodeLabel = _barcodeLabel(trimmedBarcode);
        suggestions.add(
          ProductSuggestion(
            name: '$barcodeLabel ($trimmedBarcode)',
            barcode: trimmedBarcode,
            category: 'その他',
            source: 'バーコード推定',
            confidence: 0.55,
            reason: '一致候補が見つからないため仮候補を作成',
            description: trimmedRaw.isEmpty ? null : trimmedRaw,
          ),
        );
      }

      return _dedupeAndSortSuggestions(suggestions);
    } catch (e) {
      throw ProductRepositoryException(
        'Failed to suggest products from scan: $e',
      );
    }
  }

  Future<Product?> _searchProductFromExternalAPIs(String barcode) async {
    // OpenFoodFacts search (JAN/EAN food items)
    final openFoodFactsResult = await _openFoodFactsService.searchByBarcode(
      barcode,
    );
    if (openFoodFactsResult != null) {
      return openFoodFactsResult;
    }

    // Rakuten API search
    final rakutenResult = await _rakutenService.searchByBarcode(barcode);
    if (rakutenResult != null) {
      return rakutenResult;
    }

    // TODO: Implement Amazon API fallback

    return null;
  }

  @override
  Future<Product> analyzeProductWithAI(Product product) async {
    try {
      final analyzedProduct = await _geminiService.analyzeProduct(product);

      if (analyzedProduct.id == null) {
        final insertedId = await _databaseHelper.insertProduct(analyzedProduct);
        return analyzedProduct.copyWith(id: insertedId);
      }

      final updatedRows = await _databaseHelper.updateProduct(analyzedProduct);
      if (updatedRows == 0) {
        final insertedId = await _databaseHelper.insertProduct(
          analyzedProduct.copyWith(id: null),
        );
        return analyzedProduct.copyWith(id: insertedId);
      }

      return analyzedProduct;
    } catch (e) {
      throw ProductRepositoryException('Failed to analyze product with AI: $e');
    }
  }

  // Hardware operations
  @override
  Future<void> printProductTag(Product product) async {
    try {
      await _hardwareService.printProductTag(product);
    } catch (e) {
      throw ProductRepositoryException('Failed to print product tag: $e');
    }
  }

  @override
  Future<void> printInventoryList(List<Product> products) async {
    try {
      await _hardwareService.printInventoryList(products);
    } catch (e) {
      throw ProductRepositoryException('Failed to print inventory list: $e');
    }
  }

  @override
  Future<void> printQrCode(String data, {String? label}) async {
    try {
      await _hardwareService.printQrCode(data, label: label);
    } catch (e) {
      throw ProductRepositoryException('Failed to print QR code: $e');
    }
  }

  @override
  Future<void> printBarcode(String data, {String? label}) async {
    try {
      await _hardwareService.printBarcode(data, label: label);
    } catch (e) {
      throw ProductRepositoryException('Failed to print barcode: $e');
    }
  }

  // Statistics
  @override
  Future<int> getProductCount({
    String? category,
    String? movingDecision,
  }) async {
    try {
      return await _databaseHelper.getProductCount(
        category: category,
        movingDecision: movingDecision,
      );
    } catch (e) {
      throw ProductRepositoryException('Failed to get product count: $e');
    }
  }

  @override
  Future<Map<String, int>> getCategoryCounts() async {
    try {
      return await _databaseHelper.getCategoryCounts();
    } catch (e) {
      throw ProductRepositoryException('Failed to get category counts: $e');
    }
  }

  @override
  Future<Map<String, int>> getMovingDecisionCounts() async {
    try {
      return await _databaseHelper.getMovingDecisionCounts();
    } catch (e) {
      throw ProductRepositoryException(
        'Failed to get moving decision counts: $e',
      );
    }
  }

  List<ProductSuggestion> _dedupeAndSortSuggestions(
    List<ProductSuggestion> suggestions,
  ) {
    final merged = <String, ProductSuggestion>{};

    for (final item in suggestions) {
      final normalizedName = item.name.trim();
      if (normalizedName.isEmpty) continue;

      final normalizedBarcode = _normalizeBarcode(item.barcode);
      final normalizedCategory =
          AppConstants.productCategories.contains(item.category)
          ? item.category
          : AppConstants.defaultCategory;

      final normalized = item.copyWith(
        name: normalizedName,
        barcode: normalizedBarcode,
        category: normalizedCategory,
      );

      final key = normalizedBarcode != null
          ? 'b:$normalizedBarcode'
          : 'n:${normalizedName.toLowerCase()}';
      final existing = merged[key];
      if (existing == null || normalized.confidence > existing.confidence) {
        merged[key] = normalized;
      }
    }

    final result = merged.values.toList()
      ..sort((a, b) {
        final byConfidence = b.confidence.compareTo(a.confidence);
        if (byConfidence != 0) return byConfidence;
        final aHasLocal = a.existingProductId != null;
        final bHasLocal = b.existingProductId != null;
        if (aHasLocal != bHasLocal) {
          return aHasLocal ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });

    return result;
  }

  String? _normalizeBarcode(String? barcode) {
    if (barcode == null) return null;
    final compact = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (compact.length < 8 || compact.length > 18) {
      return null;
    }
    return compact;
  }

  bool _shouldUseAiForScan({
    required String rawValue,
    required String? barcode,
    required String keywordFromRaw,
  }) {
    if (barcode == null || barcode.isEmpty) {
      return true;
    }
    if (keywordFromRaw.isNotEmpty) {
      return true;
    }

    final normalizedRaw = rawValue.trim();
    if (normalizedRaw.isEmpty) {
      return false;
    }

    final compactRaw = normalizedRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final compactBarcode = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (compactRaw == compactBarcode) {
      return false;
    }

    if (normalizedRaw.toLowerCase().startsWith('barcode:')) {
      return false;
    }

    return true;
  }

  String _barcodeLabel(String barcode) {
    if (barcode.length == 8 || barcode.length == 13) {
      return 'JAN商品';
    }
    return 'スキャン商品';
  }

  String _extractKeywordFromRaw(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final fromQuery =
          uri.queryParameters['name'] ??
          uri.queryParameters['title'] ??
          uri.queryParameters['product'] ??
          uri.queryParameters['item'];
      if (fromQuery != null && fromQuery.trim().isNotEmpty) {
        return fromQuery.trim();
      }

      if (uri.pathSegments.isNotEmpty) {
        final decoded = Uri.decodeComponent(uri.pathSegments.last).trim();
        if (decoded.isNotEmpty && !RegExp(r'^\d+$').hasMatch(decoded)) {
          return decoded;
        }
      }
    }

    final withoutPrefix = raw.startsWith('barcode:')
        ? raw.substring('barcode:'.length).trim()
        : raw;
    final cleaned = withoutPrefix.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (cleaned.isEmpty) {
      return '';
    }
    if (RegExp(r'^\d+$').hasMatch(cleaned)) {
      return '';
    }
    return cleaned;
  }

  // Batch operations
  @override
  Future<void> saveProductsBatch(List<Product> products) async {
    try {
      await _databaseHelper.insertProductsBatch(products);
    } catch (e) {
      throw ProductRepositoryException('Failed to save products batch: $e');
    }
  }

  @override
  Future<SheetsExportResult> exportToGoogleSheets(
    List<Product> products,
  ) async {
    try {
      return await _sheetsService.exportProducts(products);
    } catch (e) {
      throw ProductRepositoryException('Failed to export to Google Sheets: $e');
    }
  }
}

// Custom exception class
class ProductRepositoryException implements Exception {
  final String message;

  ProductRepositoryException(this.message);

  @override
  String toString() => 'ProductRepositoryException: $message';
}
