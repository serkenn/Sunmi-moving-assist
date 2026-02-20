import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../../core/constants/app_constants.dart';
import '../../core/config/runtime_settings.dart';
import '../models/api_connection_test_result.dart';
import '../models/product.dart';
import '../models/product_suggestion.dart';

class GeminiService {
  final String? _apiKeyOverride;

  GeminiService({String? apiKey}) : _apiKeyOverride = apiKey;

  Future<Product> analyzeProduct(Product product) async {
    final apiKey = _apiKeyOverride ?? RuntimeSettings.geminiApiKey;
    if (apiKey.isEmpty) {
      return _fallbackAnalysis(
        product,
        reason: 'Gemini APIキー未設定のため、ルールベース分析にフォールバックしました。',
      );
    }

    try {
      final prompt = _buildPrompt(product);
      final response = await _generateContentWithModelFallback(
        apiKey: apiKey,
        contents: [Content.text(prompt)],
      );
      final responseText = response.text ?? '';

      final parsed = _parseResponse(responseText);
      if (parsed == null) {
        return _fallbackAnalysis(
          product,
          reason: 'Geminiの応答を解析できなかったため、ルールベース分析にフォールバックしました。',
        );
      }

      return product.copyWith(
        movingDecision: parsed.movingDecision,
        storageLocation: parsed.storageLocation,
        aiConfidence: parsed.confidence,
        analysisNotes: parsed.notes,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return _fallbackAnalysis(
        product,
        reason: 'Gemini呼び出しに失敗したため、ルールベース分析にフォールバックしました。',
      );
    }
  }

  Future<List<ProductSuggestion>> suggestProductCandidates({
    required String rawInput,
    String? barcodeHint,
    String? nameHint,
    int maxResults = 4,
  }) async {
    final trimmedRaw = rawInput.trim();
    final trimmedName = nameHint?.trim();
    final trimmedBarcode = barcodeHint?.trim();
    final safeMaxResults = maxResults.clamp(1, 8);

    final apiKey = _apiKeyOverride ?? RuntimeSettings.geminiApiKey;
    if (apiKey.isEmpty) {
      return _fallbackProductCandidates(
        rawInput: trimmedRaw,
        barcodeHint: trimmedBarcode,
        nameHint: trimmedName,
        maxResults: safeMaxResults,
        source: 'AI推定(ルール)',
      );
    }

    try {
      final prompt = _buildSuggestionPrompt(
        rawInput: trimmedRaw,
        barcodeHint: trimmedBarcode,
        nameHint: trimmedName,
        maxResults: safeMaxResults,
      );
      final response = await _generateContentWithModelFallback(
        apiKey: apiKey,
        contents: [Content.text(prompt)],
      );
      final responseText = response.text ?? '';
      final parsed = _parseSuggestionResponse(responseText);
      if (parsed.isEmpty) {
        return _fallbackProductCandidates(
          rawInput: trimmedRaw,
          barcodeHint: trimmedBarcode,
          nameHint: trimmedName,
          maxResults: safeMaxResults,
          source: 'AI推定(簡易候補)',
        );
      }
      return parsed.take(safeMaxResults).toList();
    } catch (_) {
      return _fallbackProductCandidates(
        rawInput: trimmedRaw,
        barcodeHint: trimmedBarcode,
        nameHint: trimmedName,
        maxResults: safeMaxResults,
        source: 'AI推定(簡易候補)',
      );
    }
  }

  Future<ApiConnectionTestResult> testConnection({String? apiKey}) async {
    final key = (apiKey ?? _apiKeyOverride ?? RuntimeSettings.geminiApiKey)
        .trim();
    if (key.isEmpty) {
      return ApiConnectionTestResult.ng('Gemini APIキーが未設定です');
    }

    try {
      final response = await _generateContentWithModelFallback(
        apiKey: key,
        contents: [Content.text('OKとだけ返してください。')],
      );
      final text = (response.text ?? '').trim();
      if (text.isEmpty) {
        return ApiConnectionTestResult.ng('Gemini API応答が空です');
      }
      return ApiConnectionTestResult.ok('Gemini API接続OK');
    } catch (e) {
      return ApiConnectionTestResult.ng('Gemini API接続失敗: ${_shortError(e)}');
    }
  }

  String _buildSuggestionPrompt({
    required String rawInput,
    required String? barcodeHint,
    required String? nameHint,
    required int maxResults,
  }) {
    return '''
あなたは在庫管理アプリの入力補助AIです。
ユーザーが読み取ったデータまたは商品名から、商品候補を推定してください。

入力データ:
- rawInput: ${rawInput.isEmpty ? 'なし' : rawInput}
- barcodeHint: ${barcodeHint ?? 'なし'}
- nameHint: ${nameHint ?? 'なし'}

要件:
- 必ずJSON配列だけを返す
- 最大$maxResults件
- 各要素は次のキーを持つ:
  name (必須, 40文字以内)
  barcode (任意, 数字8-18桁)
  category (必須, 次から選択: ${AppConstants.productCategories.join(', ')})
  price (任意, 数値)
  description (任意, 120文字以内)
  confidence (必須, 0.0-1.0)
  reason (任意, 推定根拠)
''';
  }

  List<ProductSuggestion> _parseSuggestionResponse(String input) {
    final jsonText = _extractJsonArray(input);
    if (jsonText == null) return const [];

    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      return const [];
    }

    final suggestions = <ProductSuggestion>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final name = (item['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        continue;
      }

      final rawBarcode = item['barcode']?.toString().trim();
      String? normalizedBarcode;
      if (rawBarcode != null && rawBarcode.isNotEmpty) {
        final compact = rawBarcode.replaceAll(RegExp(r'[^0-9]'), '');
        if (AppUtils.isValidBarcode(compact)) {
          normalizedBarcode = compact;
        }
      }

      final rawCategory = (item['category'] as String?)?.trim();
      final category = AppConstants.productCategories.contains(rawCategory)
          ? rawCategory!
          : _inferCategoryFromText(
              '$name ${item['description']?.toString() ?? ''}',
            );

      final confidence = (_toDouble(item['confidence']) ?? 0.55)
          .clamp(0.0, 1.0)
          .toDouble();

      suggestions.add(
        ProductSuggestion(
          name: name,
          barcode: normalizedBarcode,
          category: category,
          price: _toDouble(item['price']),
          description: (item['description'] as String?)?.trim(),
          source: 'AI推定',
          confidence: confidence,
          reason: (item['reason'] as String?)?.trim(),
        ),
      );
    }

    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return suggestions;
  }

  String? _extractJsonArray(String input) {
    final start = input.indexOf('[');
    final end = input.lastIndexOf(']');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }
    return input.substring(start, end + 1);
  }

  List<ProductSuggestion> _fallbackProductCandidates({
    required String rawInput,
    required String? barcodeHint,
    required String? nameHint,
    required int maxResults,
    required String source,
  }) {
    final text = '${nameHint ?? ''} $rawInput'.trim();
    final inferredCategory = _inferCategoryFromText(text);
    final compactBarcode = barcodeHint?.replaceAll(RegExp(r'[^0-9]'), '');
    final hasValidHintBarcode =
        compactBarcode != null && AppUtils.isValidBarcode(compactBarcode);

    final primaryName = (nameHint != null && nameHint.isNotEmpty)
        ? nameHint
        : (hasValidHintBarcode
              ? 'スキャン候補 ($compactBarcode)'
              : _guessNameFromRawInput(rawInput));

    final baseDescription = rawInput.isEmpty
        ? null
        : (rawInput.length > 120
              ? '${rawInput.substring(0, 120)}...'
              : rawInput);

    final suggestions = <ProductSuggestion>[
      ProductSuggestion(
        name: primaryName,
        barcode: hasValidHintBarcode ? compactBarcode : null,
        category: inferredCategory,
        description: baseDescription,
        source: source,
        confidence: hasValidHintBarcode ? 0.82 : 0.66,
        reason: hasValidHintBarcode ? '読み取りコードから推定した候補' : '入力テキストから推定した候補',
      ),
    ];

    if (nameHint != null && nameHint.isNotEmpty && maxResults >= 2) {
      suggestions.add(
        ProductSuggestion(
          name: '$nameHint（候補）',
          barcode: hasValidHintBarcode ? compactBarcode : null,
          category: inferredCategory,
          source: source,
          confidence: hasValidHintBarcode ? 0.74 : 0.58,
          reason: '商品名ベースの補助候補',
        ),
      );
    }

    return suggestions.take(maxResults).toList();
  }

  String _inferCategoryFromText(String source) {
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

  String _guessNameFromRawInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return '推定商品';
    }

    final url = Uri.tryParse(trimmed);
    if (url != null && url.host.isNotEmpty) {
      return 'Web商品 (${url.host})';
    }

    if (trimmed.length <= 30) {
      return trimmed;
    }
    return '${trimmed.substring(0, 30)}...';
  }

  String _buildPrompt(Product product) {
    final priceText = product.price?.toStringAsFixed(0) ?? '不明';
    final description = product.description ?? '説明なし';
    return '''
あなたは引っ越し支援の在庫アナリストです。以下の商品を評価し、必ずJSONで返答してください。

商品名: ${product.name}
カテゴリ: ${product.category}
価格: $priceText
説明: $description
数量: ${product.quantity}

要件:
1. movingDecision は keep / discard / sell のいずれか
   (実家保管は parents_home)
2. storageLocation は日本語の短い場所名
3. confidence は 0.0〜1.0
4. notes は日本語で80文字以内

返答例:
{"movingDecision":"parents_home","storageLocation":"実家","confidence":0.82,"notes":"使用頻度は低いが思い出品のため実家保管を推奨。"}
''';
  }

  _GeminiAnalysisResult? _parseResponse(String input) {
    final jsonText = _extractJsonObject(input);
    if (jsonText == null) return null;

    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;

    final rawDecision = (decoded['movingDecision'] as String?)?.trim();
    if (rawDecision == null ||
        !AppConstants.movingDecisions.contains(rawDecision)) {
      return null;
    }

    final storageLocation = (decoded['storageLocation'] as String?)?.trim();
    final notes = (decoded['notes'] as String?)?.trim();
    final confidence = _toDouble(decoded['confidence']) ?? 0.7;

    return _GeminiAnalysisResult(
      movingDecision: rawDecision,
      storageLocation: (storageLocation == null || storageLocation.isEmpty)
          ? 'その他'
          : storageLocation,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      notes: (notes == null || notes.isEmpty) ? 'AI分析結果' : notes,
    );
  }

  String? _extractJsonObject(String input) {
    final start = input.indexOf('{');
    final end = input.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }
    return input.substring(start, end + 1);
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _shortError(Object e) {
    final text = e.toString().trim();
    if (text.length <= 120) {
      return text;
    }
    return '${text.substring(0, 120)}...';
  }

  Future<GenerateContentResponse> _generateContentWithModelFallback({
    required String apiKey,
    required List<Content> contents,
  }) async {
    Object? lastError;
    for (final modelName in _candidateModels()) {
      try {
        final model = GenerativeModel(model: modelName, apiKey: apiKey);
        return await model.generateContent(contents);
      } catch (e) {
        lastError = e;
        if (_isModelUnavailableError(e)) {
          continue;
        }
        rethrow;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw Exception('Gemini model candidate is empty');
  }

  List<String> _candidateModels() {
    final seen = <String>{};
    final models = <String>[];
    for (final model in <String>[
      AppConstants.aiModel,
      'gemini-2.5-flash',
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemini-flash-latest',
    ]) {
      final trimmed = model.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        models.add(trimmed);
      }
    }
    return models;
  }

  bool _isModelUnavailableError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('not found for api version') ||
        text.contains('model') && text.contains('not found') ||
        text.contains('unsupported model');
  }

  Product _fallbackAnalysis(Product product, {required String reason}) {
    final source =
        '${product.name} ${product.category} ${product.description ?? ''}'
            .toLowerCase();

    String decision = 'keep';
    String location = 'その他';
    double confidence = 0.72;

    if (_containsAny(source, ['食品', '消耗', '賞味', '飲料'])) {
      decision = 'discard';
      location = 'キッチン';
      confidence = 0.88;
    } else if (_containsAny(source, ['思い出', '卒業', 'アルバム', '写真', '記念'])) {
      decision = 'parents_home';
      location = '実家';
      confidence = 0.86;
    } else if (_containsAny(source, ['本', '雑誌', 'コミック'])) {
      decision = 'sell';
      location = '倉庫';
      confidence = 0.76;
    } else if (_containsAny(source, ['衣類', 'シャツ', 'コート', '靴'])) {
      decision = 'keep';
      location = 'クローゼット';
      confidence = 0.82;
    } else if (_containsAny(source, ['家電', 'pc', 'テレビ', 'モニタ'])) {
      decision = 'keep';
      location = 'リビング';
      confidence = 0.8;
    }

    return product.copyWith(
      movingDecision: decision,
      storageLocation: location,
      aiConfidence: confidence,
      analysisNotes: reason,
      updatedAt: DateTime.now(),
    );
  }

  bool _containsAny(String source, List<String> words) {
    for (final word in words) {
      if (source.contains(word.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}

class _GeminiAnalysisResult {
  final String movingDecision;
  final String storageLocation;
  final double confidence;
  final String notes;

  _GeminiAnalysisResult({
    required this.movingDecision,
    required this.storageLocation,
    required this.confidence,
    required this.notes,
  });
}
