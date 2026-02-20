import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/config/runtime_settings.dart';
import '../models/api_connection_test_result.dart';
import '../models/product.dart';
import '../models/product_suggestion.dart';

class RakutenService {
  final http.Client _httpClient;
  final String? _applicationIdOverride;
  final String? _accessKeyOverride;
  final String? _affiliateIdOverride;

  RakutenService({
    http.Client? httpClient,
    String? applicationId,
    String? accessKey,
    String? affiliateId,
  }) : _httpClient = httpClient ?? http.Client(),
       _applicationIdOverride = applicationId,
       _accessKeyOverride = accessKey,
       _affiliateIdOverride = affiliateId;

  Future<List<ProductSuggestion>> searchSuggestionsByBarcode(
    String barcode, {
    int hits = 3,
  }) async {
    final trimmed = barcode.trim();
    if (!AppUtils.isValidBarcode(trimmed)) {
      return const [];
    }

    return _searchSuggestionsByKeyword(
      keyword: trimmed,
      preferredBarcode: trimmed,
      hits: hits,
      source: '楽天API(バーコード)',
      baseConfidence: 0.92,
    );
  }

  Future<List<ProductSuggestion>> searchSuggestionsByKeyword(
    String keyword, {
    int hits = 5,
    String? preferredBarcode,
  }) async {
    final normalizedKeyword = keyword.trim();
    if (normalizedKeyword.isEmpty) {
      return const [];
    }

    return _searchSuggestionsByKeyword(
      keyword: normalizedKeyword,
      preferredBarcode: preferredBarcode?.trim(),
      hits: hits,
      source: '楽天API(商品名)',
      baseConfidence: 0.74,
    );
  }

  Future<Product?> searchByBarcode(String barcode) async {
    final suggestions = await searchSuggestionsByBarcode(barcode, hits: 1);
    if (suggestions.isEmpty) {
      return null;
    }

    final product = suggestions.first.toProduct(fallbackBarcode: barcode);
    if (product == null) {
      return null;
    }
    return product.copyWith(notes: '取得元: 楽天API');
  }

  Future<ApiConnectionTestResult> testConnection({
    String? applicationId,
    String? accessKey,
    String? affiliateId,
  }) async {
    final appId = _resolveApplicationId(applicationId: applicationId);
    if (appId.isEmpty) {
      return ApiConnectionTestResult.ng('Rakuten Application IDが未設定です');
    }
    final appIdFormatError = _validateApplicationId(appId);
    if (appIdFormatError != null) {
      return ApiConnectionTestResult.ng(appIdFormatError);
    }
    final resolvedAccessKey = _resolveAccessKey(accessKey: accessKey);
    final accessKeyError = _validateAccessKey(resolvedAccessKey);
    if (accessKeyError != null) {
      return ApiConnectionTestResult.ng(accessKeyError);
    }

    final resolvedAffiliateId = _resolveAffiliateId(affiliateId: affiliateId);
    final resolvedAffiliateOrEmpty = _isLikelyAffiliateId(resolvedAffiliateId)
        ? resolvedAffiliateId
        : '';
    final primaryResult = await _performConnectionTest(
      applicationId: appId,
      accessKey: resolvedAccessKey,
      affiliateId: resolvedAffiliateOrEmpty,
    );
    if (primaryResult.success || resolvedAffiliateId.isEmpty) {
      return primaryResult;
    }

    final fallbackResult = await _performConnectionTest(
      applicationId: appId,
      accessKey: resolvedAccessKey,
      affiliateId: '',
    );
    if (fallbackResult.success) {
      return ApiConnectionTestResult.ok(
        _isLikelyAffiliateId(resolvedAffiliateId)
            ? 'Rakuten API接続OK（Affiliate IDなしで成功）'
            : 'Rakuten API接続OK（Affiliate ID形式不正のため未使用）',
      );
    }
    return primaryResult;
  }

  Future<List<ProductSuggestion>> _searchSuggestionsByKeyword({
    required String keyword,
    required int hits,
    required String source,
    required double baseConfidence,
    String? preferredBarcode,
  }) async {
    final applicationId = _resolveApplicationId();
    final accessKey = _resolveAccessKey();
    if (applicationId.isEmpty || accessKey.isEmpty || keyword.isEmpty) {
      return const [];
    }

    final safeHits = hits.clamp(1, 10);
    final uri = Uri.parse(AppConstants.rakutenProductSearchUrl).replace(
      queryParameters: _buildQueryParameters(
        applicationId: applicationId,
        accessKey: accessKey,
        keyword: keyword,
        hits: '$safeHits',
        sort: '+itemPrice',
        affiliateId: '',
      ),
    );

    try {
      final response = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(milliseconds: AppConstants.networkTimeout));

      if (response.statusCode != 200) {
        throw RakutenServiceException(
          'Rakuten API request failed: ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const [];
      }

      final rawItems = decoded['Items'];
      if (rawItems is! List || rawItems.isEmpty) {
        return const [];
      }

      final suggestions = <ProductSuggestion>[];
      for (int i = 0; i < rawItems.length; i++) {
        final item = _extractItem(rawItems[i]);
        if (item == null) {
          continue;
        }
        final suggestion = _toSuggestion(
          item,
          source: source,
          preferredBarcode: preferredBarcode,
          confidence: (baseConfidence - (i * 0.05)).clamp(0.45, 0.99),
        );
        if (suggestion != null) {
          suggestions.add(suggestion);
        }
      }

      return suggestions;
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _extractItem(dynamic itemWrapper) {
    if (itemWrapper is Map<String, dynamic>) {
      final nested = itemWrapper['Item'];
      if (nested is Map<String, dynamic>) {
        return nested;
      }
      return itemWrapper;
    }
    return null;
  }

  String? _extractImageUrl(Map<String, dynamic> item) {
    final mediumImageUrls = item['mediumImageUrls'];
    if (mediumImageUrls is List && mediumImageUrls.isNotEmpty) {
      final first = mediumImageUrls.first;
      if (first is Map<String, dynamic>) {
        final imageUrl = first['imageUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          return imageUrl;
        }
      } else if (first is String && first.isNotEmpty) {
        return first;
      }
    }
    return null;
  }

  ProductSuggestion? _toSuggestion(
    Map<String, dynamic> item, {
    required String source,
    required double confidence,
    String? preferredBarcode,
  }) {
    final name = (item['itemName'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }

    final descriptionRaw = item['itemCaption'] as String?;
    final description = descriptionRaw == null
        ? null
        : _stripHtml(descriptionRaw).trim();

    final category = _inferCategory('$name ${description ?? ''}');
    final barcode = _extractBarcode(item, preferredBarcode: preferredBarcode);

    return ProductSuggestion(
      name: name,
      barcode: barcode,
      category: category,
      price: _toDouble(item['itemPrice']),
      description: description?.isEmpty == true ? null : description,
      imageUrl: _extractImageUrl(item),
      brand: (item['shopName'] as String?)?.trim(),
      source: source,
      confidence: confidence,
      reason: '楽天の商品検索結果',
    );
  }

  String? _extractBarcode(
    Map<String, dynamic> item, {
    String? preferredBarcode,
  }) {
    final rawCandidates = <String?>[
      item['jan'] as String?,
      item['JAN'] as String?,
      item['isbn'] as String?,
      item['ISBN'] as String?,
      item['itemCode'] as String?,
      preferredBarcode,
    ];

    for (final raw in rawCandidates) {
      if (raw == null) continue;
      final compact = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (AppUtils.isValidBarcode(compact)) {
        return compact;
      }
    }
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _inferCategory(String source) {
    final text = source.toLowerCase();

    if (_containsAny(text, ['米', '食品', '飲料', 'コーヒー', 'お茶', '調味料'])) {
      return '食品・飲料';
    }
    if (_containsAny(text, ['掃除機', '冷蔵庫', '洗濯機', 'テレビ', 'イヤホン', 'pc'])) {
      return '家電・AV機器';
    }
    if (_containsAny(text, ['ソファ', '椅子', '机', '収納', 'インテリア', 'カーテン'])) {
      return '家具・インテリア';
    }
    if (_containsAny(text, ['シャツ', 'パンツ', 'ジャケット', '靴', 'バッグ', 'アパレル'])) {
      return '衣類・ファッション';
    }
    if (_containsAny(text, ['本', '雑誌', 'book', '文庫', 'コミック'])) {
      return '本・雑誌';
    }
    if (_containsAny(text, ['ゲーム', 'おもちゃ', '玩具', 'フィギュア'])) {
      return 'ゲーム・おもちゃ';
    }
    if (_containsAny(text, ['洗剤', '日用品', 'ティッシュ', 'トイレットペーパー'])) {
      return '日用品・消耗品';
    }
    if (_containsAny(text, ['化粧', 'コスメ', '美容', 'スキンケア'])) {
      return '化粧品・美容';
    }
    if (_containsAny(text, ['スポーツ', 'アウトドア', 'キャンプ', 'ランニング'])) {
      return 'スポーツ・アウトドア';
    }

    return AppConstants.defaultCategory;
  }

  bool _containsAny(String source, List<String> words) {
    for (final word in words) {
      if (source.contains(word.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String _shortError(Object e) {
    final text = e.toString().trim();
    if (text.length <= 120) {
      return text;
    }
    return '${text.substring(0, 120)}...';
  }

  Future<ApiConnectionTestResult> _performConnectionTest({
    required String applicationId,
    required String accessKey,
    required String affiliateId,
  }) async {
    final uri = Uri.parse(AppConstants.rakutenProductSearchUrl).replace(
      queryParameters: _buildQueryParameters(
        applicationId: applicationId,
        accessKey: accessKey,
        affiliateId: affiliateId,
        keyword: 'テスト',
        hits: '1',
      ),
    );

    try {
      final response = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(milliseconds: AppConstants.networkTimeout));

      if (response.statusCode != 200) {
        final apiError = _extractApiErrorMessage(response.body);
        return ApiConnectionTestResult.ng(
          apiError == null
              ? 'Rakuten API接続失敗 (HTTP ${response.statusCode})'
              : 'Rakuten API接続失敗 (HTTP ${response.statusCode}): $apiError',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ApiConnectionTestResult.ng('Rakuten API応答の形式が不正です');
      }

      final error = decoded['error']?.toString();
      final errorDescription = decoded['error_description']?.toString();
      if ((error != null && error.isNotEmpty) ||
          (errorDescription != null && errorDescription.isNotEmpty)) {
        final reason = [
          if (errorDescription != null && errorDescription.isNotEmpty)
            errorDescription,
          if (error != null && error.isNotEmpty) error,
        ].join(' / ');
        return ApiConnectionTestResult.ng('Rakuten APIエラー: $reason');
      }

      return ApiConnectionTestResult.ok('Rakuten API接続OK');
    } catch (e) {
      return ApiConnectionTestResult.ng('Rakuten API通信失敗: ${_shortError(e)}');
    }
  }

  String? _extractApiErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final error = decoded['error']?.toString().trim();
      final errorDescription = decoded['error_description']?.toString().trim();
      final parts = <String>[
        if (errorDescription != null && errorDescription.isNotEmpty)
          errorDescription,
        if (error != null && error.isNotEmpty) error,
      ];
      if (parts.isEmpty) {
        return null;
      }
      return parts.join(' / ');
    } catch (_) {
      return null;
    }
  }

  String _resolveApplicationId({String? applicationId}) {
    final resolved = _normalizeCredential(
      applicationId ??
          _applicationIdOverride ??
          RuntimeSettings.rakutenApplicationId,
    );
    if (resolved.isNotEmpty) {
      return resolved;
    }

    // Legacy fallback (older setting key name).
    final legacy = _normalizeCredential(RuntimeSettings.rakutenApiKey);
    if (_isLikelyApplicationId(legacy)) {
      return legacy;
    }
    return '';
  }

  String _resolveAffiliateId({String? affiliateId}) {
    return _normalizeCredential(
      affiliateId ?? _affiliateIdOverride ?? RuntimeSettings.rakutenAffiliateId,
    );
  }

  String _resolveAccessKey({String? accessKey}) {
    return _normalizeCredential(
      accessKey ?? _accessKeyOverride ?? RuntimeSettings.rakutenAccessKey,
    );
  }

  String _normalizeCredential(String value) {
    var text = value.trim();
    while (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  bool _isLikelyApplicationId(String value) {
    if (value.isEmpty) return false;
    return !value.toLowerCase().startsWith('pk_');
  }

  String? _validateApplicationId(String value) {
    final appId = _normalizeCredential(value);
    if (appId.isEmpty) {
      return 'Rakuten Application IDが未設定です';
    }
    if (appId.toLowerCase().startsWith('pk_')) {
      return 'Rakuten Application ID形式が不正です（pk_ ではなく楽天WebServiceのアプリIDを入力してください）';
    }
    return null;
  }

  String? _validateAccessKey(String value) {
    if (_normalizeCredential(value).isEmpty) {
      return 'Rakuten Access Keyが未設定です';
    }
    return null;
  }

  bool _isLikelyAffiliateId(String value) {
    final affiliateId = _normalizeCredential(value);
    if (affiliateId.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}\.[0-9a-fA-F]{8}\.[0-9a-fA-F]{8}\.[0-9a-fA-F]{8}$',
    ).hasMatch(affiliateId);
  }

  Map<String, String> _buildQueryParameters({
    required String applicationId,
    required String accessKey,
    required String keyword,
    required String hits,
    String? sort,
    String? affiliateId,
  }) {
    final params = <String, String>{
      'applicationId': applicationId,
      'accessKey': accessKey,
      'format': 'json',
      'keyword': keyword,
      'hits': hits,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
    };

    final resolvedAffiliateId = _resolveAffiliateId(affiliateId: affiliateId);
    if (resolvedAffiliateId.isNotEmpty) {
      params['affiliateId'] = resolvedAffiliateId;
    }

    return params;
  }
}

class RakutenServiceException implements Exception {
  final String message;

  RakutenServiceException(this.message);

  @override
  String toString() => 'RakutenServiceException: $message';
}
