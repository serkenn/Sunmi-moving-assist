import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/product.dart';
import '../models/product_suggestion.dart';

class OpenFoodFactsService {
  final http.Client _httpClient;

  OpenFoodFactsService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  Future<List<ProductSuggestion>> searchSuggestionsByBarcode(
    String barcode, {
    int maxResults = 1,
  }) async {
    final compact = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (!AppUtils.isValidBarcode(compact) || maxResults <= 0) {
      return const [];
    }

    for (final catalog in _catalogs) {
      final suggestion = await _searchFromCatalog(
        barcode: compact,
        catalog: catalog,
      );
      if (suggestion != null) {
        return [suggestion];
      }
    }

    return const [];
  }

  Future<Product?> searchByBarcode(String barcode) async {
    final suggestions = await searchSuggestionsByBarcode(barcode);
    if (suggestions.isEmpty) {
      return null;
    }

    final product = suggestions.first.toProduct(fallbackBarcode: barcode);
    if (product == null) {
      return null;
    }
    return product.copyWith(notes: '取得元: OpenFoodFacts');
  }

  Future<ProductSuggestion?> _searchFromCatalog({
    required String barcode,
    required _OpenFactsCatalog catalog,
  }) async {
    final uri =
        Uri.parse(
          'https://${catalog.host}/api/v2/product/$barcode.json',
        ).replace(
          queryParameters: {
            'fields':
                'code,product_name,product_name_ja,product_name_en,generic_name,generic_name_ja,brands,categories,quantity,image_url',
          },
        );

    try {
      final response = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(milliseconds: AppConstants.networkTimeout));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final status = decoded['status'];
      if (status is! int || status != 1) {
        return null;
      }

      final rawProduct = decoded['product'];
      if (rawProduct is! Map<String, dynamic>) {
        return null;
      }

      return _toSuggestion(
        rawProduct,
        barcode: barcode,
        source: catalog.source,
        category: catalog.defaultCategory,
      );
    } catch (_) {
      return null;
    }
  }

  ProductSuggestion? _toSuggestion(
    Map<String, dynamic> product, {
    required String barcode,
    required String source,
    required String category,
  }) {
    final name = _firstNonEmptyString([
      product['product_name_ja'],
      product['product_name'],
      product['product_name_en'],
      product['generic_name_ja'],
      product['generic_name'],
    ]);
    if (name == null) {
      return null;
    }

    final brand = _asNonEmptyString(product['brands']);
    final categories = _asNonEmptyString(product['categories']);
    final quantity = _asNonEmptyString(product['quantity']);

    final descriptionParts = <String>[
      if (quantity != null) '内容量: $quantity',
      if (categories != null) '分類: ${_normalizeWhitespace(categories)}',
    ];

    return ProductSuggestion(
      name: name,
      barcode: barcode,
      category: category,
      description: descriptionParts.isEmpty
          ? null
          : descriptionParts.join(' / '),
      imageUrl: _asNonEmptyString(product['image_url']),
      brand: brand,
      source: source,
      confidence: 0.95,
      reason: 'JANコード一致',
    );
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = _asNonEmptyString(value);
      if (text != null) {
        return text;
      }
    }
    return null;
  }

  String? _asNonEmptyString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return text;
  }

  String _normalizeWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _OpenFactsCatalog {
  final String host;
  final String source;
  final String defaultCategory;

  const _OpenFactsCatalog({
    required this.host,
    required this.source,
    required this.defaultCategory,
  });
}

const List<_OpenFactsCatalog> _catalogs = [
  _OpenFactsCatalog(
    host: 'world.openfoodfacts.org',
    source: 'OpenFoodFacts(JAN)',
    defaultCategory: '食品・飲料',
  ),
  _OpenFactsCatalog(
    host: 'world.openbeautyfacts.org',
    source: 'OpenBeautyFacts(JAN)',
    defaultCategory: '化粧品・美容',
  ),
  _OpenFactsCatalog(
    host: 'world.openpetfoodfacts.org',
    source: 'OpenPetFoodFacts(JAN)',
    defaultCategory: '日用品・消耗品',
  ),
  _OpenFactsCatalog(
    host: 'world.openproductsfacts.org',
    source: 'OpenProductsFacts(JAN)',
    defaultCategory: 'その他',
  ),
];
