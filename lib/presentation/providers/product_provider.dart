import 'package:flutter/foundation.dart';
import '../../data/models/product.dart';
import '../../data/models/product_suggestion.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/services/sheets_service.dart';

enum ProductProviderState { idle, loading, success, error }

class ProductProvider extends ChangeNotifier {
  final ProductRepository _repository;

  ProductProvider(this._repository);

  // State management
  ProductProviderState _state = ProductProviderState.loading;
  String? _errorMessage;

  // Product data
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  Product? _selectedProduct;

  // Search and filter
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedMovingDecision;

  // Statistics
  Map<String, int> _categoryCounts = {};
  Map<String, int> _movingDecisionCounts = {};
  int _totalProductCount = 0;

  // Getters
  ProductProviderState get state => _state;
  String? get errorMessage => _errorMessage;
  List<Product> get products => List.unmodifiable(_products);
  Product? get selectedProduct => _selectedProduct;
  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  String? get selectedMovingDecision => _selectedMovingDecision;
  Map<String, int> get categoryCounts => Map.unmodifiable(_categoryCounts);
  Map<String, int> get movingDecisionCounts =>
      Map.unmodifiable(_movingDecisionCounts);
  int get totalProductCount => _totalProductCount;

  bool get isLoading => _state == ProductProviderState.loading;
  bool get hasError => _state == ProductProviderState.error;
  bool get isEmpty => _products.isEmpty;

  // Filtered products based on search and filters
  List<Product> get filteredProducts => List.unmodifiable(_filteredProducts);

  // Product operations
  Future<void> loadProducts() async {
    _setState(ProductProviderState.loading);

    try {
      _products = await _repository.getAllProducts();
      _rebuildFilteredProducts();
      await _loadStatistics();
      _setState(ProductProviderState.success);
    } catch (e) {
      _setError('商品の読み込みに失敗しました: $e');
    }
  }

  Future<void> addProduct(Product product) async {
    _setState(ProductProviderState.loading);

    try {
      final productId = await _repository.saveProduct(product);
      final savedProduct = product.copyWith(id: productId);

      _products.insert(0, savedProduct);
      _rebuildFilteredProducts();
      await _loadStatistics();
      _setState(ProductProviderState.success);
    } catch (e) {
      _setError('商品の追加に失敗しました: $e');
    }
  }

  Future<void> updateProduct(Product product) async {
    _setState(ProductProviderState.loading);

    try {
      await _repository.updateProduct(product);

      final index = _products.indexWhere((p) => p.id == product.id);
      if (index != -1) {
        _products[index] = product;
      }

      if (_selectedProduct?.id == product.id) {
        _selectedProduct = product;
      }

      _rebuildFilteredProducts();
      await _loadStatistics();
      _setState(ProductProviderState.success);
    } catch (e) {
      _setError('商品の更新に失敗しました: $e');
    }
  }

  Future<void> deleteProduct(int productId) async {
    _setState(ProductProviderState.loading);

    try {
      await _repository.deleteProduct(productId);

      _products.removeWhere((product) => product.id == productId);

      if (_selectedProduct?.id == productId) {
        _selectedProduct = null;
      }

      _rebuildFilteredProducts();
      await _loadStatistics();
      _setState(ProductProviderState.success);
    } catch (e) {
      _setError('商品の削除に失敗しました: $e');
    }
  }

  Future<void> deleteAllProducts() async {
    _setState(ProductProviderState.loading);

    try {
      await _repository.deleteAllProducts();
      _products.clear();
      _filteredProducts.clear();
      _selectedProduct = null;
      await _loadStatistics();
      _setState(ProductProviderState.success);
    } catch (e) {
      _setError('全商品の削除に失敗しました: $e');
    }
  }

  // Barcode scanning
  Future<String?> scanBarcode() async {
    try {
      return await _repository.scanBarcode();
    } catch (e) {
      _setError('バーコードスキャンに失敗しました: $e');
      return null;
    }
  }

  Future<Product?> searchProductByBarcode(String barcode) async {
    _setState(ProductProviderState.loading);

    try {
      final product = await _repository.searchProductByBarcode(barcode);
      if (product != null) {
        _upsertLocalProduct(product);
        _rebuildFilteredProducts();
      }
      _setState(ProductProviderState.success);
      return product;
    } catch (e) {
      _setError('商品検索に失敗しました: $e');
      return null;
    }
  }

  Future<List<ProductSuggestion>> suggestProductsByName(
    String query, {
    bool updateState = true,
  }) async {
    if (updateState) {
      _setState(ProductProviderState.loading);
    }
    try {
      final suggestions = await _repository.suggestProductsByName(query);
      if (updateState) {
        _setState(ProductProviderState.success);
      }
      return suggestions;
    } catch (e) {
      if (updateState) {
        _setError('商品候補の取得に失敗しました: $e');
      } else {
        debugPrint('商品候補の取得に失敗しました: $e');
      }
      return const [];
    }
  }

  Future<List<ProductSuggestion>> suggestProductsFromScan({
    required String rawValue,
    String? barcode,
    bool updateState = true,
  }) async {
    if (updateState) {
      _setState(ProductProviderState.loading);
    }
    try {
      final suggestions = await _repository.suggestProductsFromScan(
        rawValue: rawValue,
        barcode: barcode,
      );
      if (updateState) {
        _setState(ProductProviderState.success);
      }
      return suggestions;
    } catch (e) {
      if (updateState) {
        _setError('スキャン候補の取得に失敗しました: $e');
      } else {
        debugPrint('スキャン候補の取得に失敗しました: $e');
      }
      return const [];
    }
  }

  // AI Analysis
  Future<Product?> analyzeProductWithAI(
    Product product, {
    bool updateState = true,
  }) async {
    if (updateState) {
      _setState(ProductProviderState.loading);
    }

    try {
      final analyzedProduct = await _repository.analyzeProductWithAI(product);
      _upsertLocalProduct(analyzedProduct);
      _rebuildFilteredProducts();
      await _loadStatistics();
      if (updateState) {
        _setState(ProductProviderState.success);
      } else {
        notifyListeners();
      }
      return analyzedProduct;
    } catch (e) {
      if (updateState) {
        _setError('AI分析に失敗しました: $e');
      } else {
        debugPrint('AI分析に失敗しました: $e');
      }
      return null;
    }
  }

  // Batch AI Analysis
  Future<void> analyzeAllProductsWithAI() async {
    _setState(ProductProviderState.loading);

    try {
      final productsToAnalyze = _products
          .where((p) => !p.hasAiAnalysis)
          .toList();

      for (final product in productsToAnalyze) {
        final analyzedProduct = await _repository.analyzeProductWithAI(product);
        _upsertLocalProduct(analyzedProduct);

        // Small delay to prevent overwhelming the AI service
        await Future.delayed(const Duration(milliseconds: 500));
      }

      _rebuildFilteredProducts();
      await _loadStatistics();
      _setState(ProductProviderState.success);
    } catch (e) {
      _setError('一括AI分析に失敗しました: $e');
    }
  }

  // Printing
  Future<void> printProductTag(Product product) async {
    try {
      await _repository.printProductTag(product);
    } catch (e) {
      throw Exception('商品タグの印刷に失敗しました: $e');
    }
  }

  Future<void> printInventoryList() async {
    try {
      await _repository.printInventoryList(_products);
    } catch (e) {
      throw Exception('在庫リストの印刷に失敗しました: $e');
    }
  }

  Future<void> printQrCode(String data, {String? label}) async {
    try {
      await _repository.printQrCode(data, label: label);
    } catch (e) {
      throw Exception('QRコードの印刷に失敗しました: $e');
    }
  }

  Future<void> printBarcode(String data, {String? label}) async {
    try {
      await _repository.printBarcode(data, label: label);
    } catch (e) {
      throw Exception('バーコードの印刷に失敗しました: $e');
    }
  }

  Future<SheetsExportResult?> exportToGoogleSheets() async {
    if (_products.isEmpty) {
      _setError('エクスポート対象の商品がありません。');
      return null;
    }

    debugPrint('[SHEETS] provider export start count=${_products.length}');
    _setState(ProductProviderState.loading);

    try {
      final result = await _repository.exportToGoogleSheets(_products);
      debugPrint(
        '[SHEETS] provider export done success=${result.success} rows=${result.rowCount} message=${result.message}',
      );
      if (result.success) {
        _setState(ProductProviderState.success);
      } else {
        _setError(result.message);
      }
      return result;
    } catch (e) {
      debugPrint('[SHEETS] provider export error=$e');
      _setError('Google Sheetsエクスポートに失敗しました: $e');
      return null;
    }
  }

  // Search and filtering
  void setSearchQuery(String query) {
    _searchQuery = query;
    _rebuildFilteredProducts();
    notifyListeners();
  }

  void setSelectedCategory(String? category) {
    _selectedCategory = category;
    _rebuildFilteredProducts();
    notifyListeners();
  }

  void setSelectedMovingDecision(String? decision) {
    _selectedMovingDecision = decision;
    _rebuildFilteredProducts();
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedCategory = null;
    _selectedMovingDecision = null;
    _rebuildFilteredProducts();
    notifyListeners();
  }

  // Product selection
  void selectProduct(Product? product) {
    _selectedProduct = product;
    notifyListeners();
  }

  // Get product by ID
  Product? getProductById(int id) {
    try {
      return _products.firstWhere((product) => product.id == id);
    } catch (e) {
      return null;
    }
  }

  // Statistics
  Future<void> _loadStatistics() async {
    try {
      _categoryCounts = await _repository.getCategoryCounts();
      _movingDecisionCounts = await _repository.getMovingDecisionCounts();
      _totalProductCount = await _repository.getProductCount();
    } catch (e) {
      // Don't fail the entire operation if statistics loading fails
      debugPrint('Failed to load statistics: $e');
    }
  }

  // Refresh data
  Future<void> refresh() async {
    await loadProducts();
  }

  // State management helpers
  void _setState(ProductProviderState newState) {
    _state = newState;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _state = ProductProviderState.error;
    _errorMessage = message;
    notifyListeners();
  }

  void _upsertLocalProduct(Product product) {
    int index = -1;
    if (product.id != null) {
      index = _products.indexWhere((p) => p.id == product.id);
    }

    if (index == -1) {
      index = _products.indexWhere((p) => p.barcode == product.barcode);
    }

    if (index == -1) {
      _products.insert(0, product);
      return;
    }

    _products[index] = product;
  }

  void _rebuildFilteredProducts() {
    var filtered = List<Product>.from(_products);
    final normalizedQuery = _searchQuery.trim().toLowerCase();

    if (normalizedQuery.isNotEmpty) {
      filtered = filtered.where((product) {
        final name = product.name.toLowerCase();
        final description = product.description?.toLowerCase() ?? '';
        return name.contains(normalizedQuery) ||
            product.barcode.contains(normalizedQuery) ||
            description.contains(normalizedQuery);
      }).toList();
    }

    if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
      filtered = filtered
          .where((product) => product.category == _selectedCategory)
          .toList();
    }

    if (_selectedMovingDecision != null &&
        _selectedMovingDecision!.isNotEmpty) {
      filtered = filtered
          .where((product) => product.movingDecision == _selectedMovingDecision)
          .toList();
    }

    _filteredProducts = filtered;
  }

  void clearError() {
    if (_state == ProductProviderState.error) {
      _state = ProductProviderState.idle;
      _errorMessage = null;
      notifyListeners();
    }
  }

  // Helper methods for UI
  List<Product> getProductsByCategory(String category) {
    return _products.where((product) => product.category == category).toList();
  }

  List<Product> getProductsByMovingDecision(String decision) {
    return _products
        .where((product) => product.movingDecision == decision)
        .toList();
  }

  int getProductCountByCategory(String category) {
    return _products.where((product) => product.category == category).length;
  }

  int getProductCountByMovingDecision(String decision) {
    return _products
        .where((product) => product.movingDecision == decision)
        .length;
  }

  double getAverageConfidence() {
    final productsWithAnalysis = _products.where((p) => p.aiConfidence != null);
    if (productsWithAnalysis.isEmpty) return 0.0;

    final totalConfidence = productsWithAnalysis
        .map((p) => p.aiConfidence!)
        .reduce((a, b) => a + b);

    return totalConfidence / productsWithAnalysis.length;
  }
}
