import '../../core/constants/app_constants.dart';
import 'product.dart';

class ProductSuggestion {
  final String name;
  final String? barcode;
  final String category;
  final double? price;
  final String? description;
  final String source;
  final double confidence;
  final String? reason;
  final String? imageUrl;
  final String? brand;
  final int? existingProductId;

  const ProductSuggestion({
    required this.name,
    this.barcode,
    required this.category,
    this.price,
    this.description,
    required this.source,
    this.confidence = 0.5,
    this.reason,
    this.imageUrl,
    this.brand,
    this.existingProductId,
  });

  bool get hasValidBarcode {
    final code = barcode?.trim();
    if (code == null) return false;
    return RegExp(r'^\d{8,18}$').hasMatch(code);
  }

  ProductSuggestion copyWith({
    String? name,
    String? barcode,
    bool clearBarcode = false,
    String? category,
    double? price,
    bool clearPrice = false,
    String? description,
    bool clearDescription = false,
    String? source,
    double? confidence,
    String? reason,
    bool clearReason = false,
    String? imageUrl,
    bool clearImageUrl = false,
    String? brand,
    bool clearBrand = false,
    int? existingProductId,
    bool clearExistingProductId = false,
  }) {
    return ProductSuggestion(
      name: name ?? this.name,
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      category: category ?? this.category,
      price: clearPrice ? null : (price ?? this.price),
      description: clearDescription ? null : (description ?? this.description),
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      reason: clearReason ? null : (reason ?? this.reason),
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      brand: clearBrand ? null : (brand ?? this.brand),
      existingProductId: clearExistingProductId
          ? null
          : (existingProductId ?? this.existingProductId),
    );
  }

  Product? toProduct({String? fallbackBarcode}) {
    final resolvedBarcode = _resolveBarcode(fallbackBarcode: fallbackBarcode);
    if (resolvedBarcode == null) {
      return null;
    }

    final now = DateTime.now();
    final normalizedName = name.trim().isEmpty ? '未設定商品' : name.trim();
    final normalizedCategory = AppConstants.productCategories.contains(category)
        ? category
        : AppConstants.defaultCategory;

    final notesBuffer = <String>[
      '候補元: $source',
      if (reason != null && reason!.trim().isNotEmpty) reason!.trim(),
    ];

    return Product(
      id: existingProductId,
      barcode: resolvedBarcode,
      name: normalizedName,
      category: normalizedCategory,
      price: price,
      description: description?.trim().isEmpty == true ? null : description,
      imageUrl: imageUrl,
      brand: brand,
      createdAt: now,
      updatedAt: now,
      notes: notesBuffer.join(' / '),
    );
  }

  String? _resolveBarcode({String? fallbackBarcode}) {
    final primary = barcode?.trim();
    if (primary != null && RegExp(r'^\d{8,18}$').hasMatch(primary)) {
      return primary;
    }
    final fallback = fallbackBarcode?.trim();
    if (fallback != null && RegExp(r'^\d{8,18}$').hasMatch(fallback)) {
      return fallback;
    }
    return null;
  }

  factory ProductSuggestion.fromProduct(
    Product product, {
    required String source,
    double confidence = 1.0,
    String? reason,
  }) {
    return ProductSuggestion(
      name: product.name,
      barcode: product.barcode,
      category: product.category,
      price: product.price,
      description: product.description,
      source: source,
      confidence: confidence,
      reason: reason,
      imageUrl: product.imageUrl,
      brand: product.brand,
      existingProductId: product.id,
    );
  }
}
