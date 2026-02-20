import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

import '../../core/constants/app_constants.dart';
import '../../core/config/runtime_settings.dart';
import '../models/api_connection_test_result.dart';
import '../models/product.dart';

class SheetsService {
  final String? _spreadsheetIdOverride;
  final String? _serviceAccountJsonOverride;

  SheetsService({String? spreadsheetId, String? serviceAccountJson})
    : _spreadsheetIdOverride = spreadsheetId,
      _serviceAccountJsonOverride = serviceAccountJson;

  Future<SheetsExportResult> exportProducts(List<Product> products) async {
    final spreadsheetId = _normalizeSpreadsheetId(
      _spreadsheetIdOverride ?? RuntimeSettings.googleSheetsSpreadsheetId,
    );
    final serviceAccountJson =
        _serviceAccountJsonOverride ?? RuntimeSettings.googleServiceAccountJson;
    final serviceAccountEmail = _extractServiceAccountEmail(serviceAccountJson);
    debugPrint(
      '[SHEETS] export start count=${products.length} spreadsheet=${_compactId(spreadsheetId)} serviceJsonLen=${serviceAccountJson.length} serviceAccount=${serviceAccountEmail ?? "<unknown>"}',
    );

    if (spreadsheetId.isEmpty || serviceAccountJson.isEmpty) {
      return const SheetsExportResult(
        success: false,
        rowCount: 0,
        message:
            'Google Sheets設定が不足しています。--dart-define=GOOGLE_SHEETS_SPREADSHEET_ID と '
            '--dart-define=GOOGLE_SERVICE_ACCOUNT_JSON を指定してください。',
      );
    }

    if (products.isEmpty) {
      return const SheetsExportResult(
        success: false,
        rowCount: 0,
        message: 'エクスポート対象の商品がありません。',
      );
    }

    AutoRefreshingAuthClient? client;
    try {
      final credentials = ServiceAccountCredentials.fromJson(
        _parseServiceAccountJson(serviceAccountJson),
      );

      client = await clientViaServiceAccount(credentials, [
        sheets.SheetsApi.spreadsheetsScope,
      ]);

      final api = sheets.SheetsApi(client);
      final targetSheetTitle = await _resolveTargetSheetTitle(
        api,
        spreadsheetId,
      );
      debugPrint('[SHEETS] target sheet="$targetSheetTitle"');
      final sheetRangeAll = _buildA1Range(targetSheetTitle, 'A:Z');
      final sheetRangeStart = _buildA1Range(targetSheetTitle, 'A1');

      final values = <List<Object?>>[_header, ...products.map(_productToRow)];

      final valueRange = sheets.ValueRange(values: values);
      await api.spreadsheets.values.clear(
        sheets.ClearValuesRequest(),
        spreadsheetId,
        sheetRangeAll,
      );
      debugPrint('[SHEETS] clear done range=$sheetRangeAll');
      final updateResult = await api.spreadsheets.values.update(
        valueRange,
        spreadsheetId,
        sheetRangeStart,
        valueInputOption: 'USER_ENTERED',
      );
      final updatedRows = updateResult.updatedRows ?? 0;
      final updatedCells = updateResult.updatedCells ?? 0;
      debugPrint(
        '[SHEETS] update done range=$sheetRangeStart updatedRows=$updatedRows updatedCells=$updatedCells',
      );
      if (updatedRows == 0) {
        debugPrint('[SHEETS] update result has 0 rows');
        return const SheetsExportResult(
          success: false,
          rowCount: 0,
          message: 'Google Sheetsへの書き込み結果が0行でした。シート権限と範囲を確認してください。',
        );
      }

      return SheetsExportResult(
        success: true,
        rowCount: products.length,
        message:
            'Google Sheets「$targetSheetTitle」に${products.length}件をエクスポートしました。',
      );
    } catch (e) {
      debugPrint('[SHEETS] export error=$e');
      final resolvedError = _humanizeSheetsError(
        e.toString(),
        serviceAccountEmail: serviceAccountEmail,
      );
      return SheetsExportResult(
        success: false,
        rowCount: 0,
        message: 'Google Sheetsエクスポートに失敗しました: $resolvedError',
      );
    } finally {
      client?.close();
    }
  }

  Future<ApiConnectionTestResult> testConnection({
    String? spreadsheetId,
    String? serviceAccountJson,
  }) async {
    final resolvedSpreadsheetId = _normalizeSpreadsheetId(
      spreadsheetId ?? RuntimeSettings.googleSheetsSpreadsheetId,
    );
    final resolvedServiceAccountJson =
        (serviceAccountJson ?? RuntimeSettings.googleServiceAccountJson).trim();
    final serviceAccountEmail = _extractServiceAccountEmail(
      resolvedServiceAccountJson,
    );
    debugPrint(
      '[SHEETS] test start spreadsheet=${_compactId(resolvedSpreadsheetId)} serviceJsonLen=${resolvedServiceAccountJson.length} serviceAccount=${serviceAccountEmail ?? "<unknown>"}',
    );

    if (resolvedSpreadsheetId.isEmpty) {
      return ApiConnectionTestResult.ng('Google Sheets Spreadsheet IDが未設定です');
    }
    if (resolvedServiceAccountJson.isEmpty) {
      return ApiConnectionTestResult.ng('Google Service Account JSONが未設定です');
    }

    AutoRefreshingAuthClient? client;
    try {
      final credentials = ServiceAccountCredentials.fromJson(
        _parseServiceAccountJson(resolvedServiceAccountJson),
      );
      client = await clientViaServiceAccount(credentials, [
        sheets.SheetsApi.spreadsheetsScope,
      ]);

      final api = sheets.SheetsApi(client);
      final spreadsheet = await api.spreadsheets.get(resolvedSpreadsheetId);
      final sheetList = spreadsheet.sheets;
      final firstTitle = (sheetList != null && sheetList.isNotEmpty)
          ? (sheetList.first.properties?.title?.trim() ?? '')
          : '';

      if (firstTitle.isNotEmpty) {
        debugPrint('[SHEETS] test success firstSheet="$firstTitle"');
        return ApiConnectionTestResult.ok('Sheets接続OK（先頭シート: $firstTitle）');
      }
      debugPrint('[SHEETS] test success (sheet title unavailable)');
      return const ApiConnectionTestResult(
        success: true,
        message: 'Sheets接続OK',
      );
    } catch (e) {
      debugPrint('[SHEETS] test error=$e');
      return ApiConnectionTestResult.ng(
        'Google Sheets接続失敗: ${_humanizeSheetsError(e.toString(), serviceAccountEmail: serviceAccountEmail)}',
      );
    } finally {
      client?.close();
    }
  }

  static const String _sheetName = 'Inventory';

  static const List<Object> _header = [
    'ID',
    'バーコード',
    '商品名',
    'カテゴリ',
    '価格',
    '数量',
    '画像URL',
    '移動判定',
    '保管場所',
    '信頼度',
    'メモ',
    '作成日時',
    '更新日時',
  ];

  List<Object?> _productToRow(Product product) {
    return [
      product.id,
      product.barcode,
      product.name,
      product.category,
      product.price,
      product.quantity,
      product.imageUrl,
      product.movingDecision,
      product.storageLocation,
      product.aiConfidence,
      product.analysisNotes ?? product.notes,
      AppUtils.formatDateTime(product.createdAt),
      AppUtils.formatDateTime(product.updatedAt),
    ];
  }

  String _normalizeSpreadsheetId(String input) {
    final text = input.trim();
    if (text.isEmpty) return '';

    final uri = Uri.tryParse(text);
    if (uri != null && uri.host.contains('docs.google.com')) {
      final segments = uri.pathSegments;
      final dIndex = segments.indexOf('d');
      if (dIndex != -1 && dIndex + 1 < segments.length) {
        final candidate = segments[dIndex + 1].trim();
        if (candidate.isNotEmpty) {
          return candidate;
        }
      }
      final queryId = uri.queryParameters['id']?.trim();
      if (queryId != null && queryId.isNotEmpty) {
        return queryId;
      }
    }

    final match = RegExp(r'/d/([a-zA-Z0-9-_]+)').firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1)!.trim();
    }

    return text;
  }

  Map<String, dynamic> _parseServiceAccountJson(String raw) {
    var text = raw.trim();
    while (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1).trim();
    }

    dynamic decoded = jsonDecode(text);
    if (decoded is String) {
      decoded = jsonDecode(decoded);
    }
    if (decoded is! Map) {
      throw const FormatException('Service Account JSONの形式が不正です');
    }

    final map = Map<String, dynamic>.from(decoded);
    final privateKey = map['private_key'];
    if (privateKey is String && privateKey.contains(r'\n')) {
      map['private_key'] = privateKey.replaceAll(r'\n', '\n');
    }
    return map;
  }

  Future<String> _resolveTargetSheetTitle(
    sheets.SheetsApi api,
    String spreadsheetId,
  ) async {
    final spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final sheetList = spreadsheet.sheets;
    if (sheetList != null && sheetList.isNotEmpty) {
      final firstTitle = sheetList.first.properties?.title?.trim();
      if (firstTitle != null && firstTitle.isNotEmpty) {
        return firstTitle;
      }
    }

    await _ensureSheetExists(api, spreadsheetId, _sheetName);
    return _sheetName;
  }

  String _buildA1Range(String sheetTitle, String range) {
    final escapedTitle = sheetTitle.replaceAll("'", "''");
    return "'$escapedTitle'!$range";
  }

  String _compactId(String id) {
    final text = id.trim();
    if (text.isEmpty) return '<empty>';
    if (text.length <= 10) return text;
    return '${text.substring(0, 4)}...${text.substring(text.length - 4)}';
  }

  String _humanizeSheetsError(String raw, {String? serviceAccountEmail}) {
    final text = raw.trim();
    if (text.isEmpty) return '不明なエラー';

    final lower = text.toLowerCase();
    if (lower.contains('permission') || lower.contains('forbidden')) {
      final shareHint =
          serviceAccountEmail == null || serviceAccountEmail.trim().isEmpty
          ? 'スプレッドシートをService Accountに編集権限で共有してください。'
          : 'スプレッドシートをService Accountに編集権限で共有してください（共有先: ${serviceAccountEmail.trim()}）。';
      return '$text / $shareHint';
    }
    if (lower.contains('not found') || lower.contains('404')) {
      return '$text / Spreadsheet IDが正しいか確認してください。';
    }
    if (lower.contains('invalid_grant') || lower.contains('invalid jwt')) {
      return '$text / Service Account JSONの内容と改行（private_key）を確認してください。';
    }
    return text;
  }

  String? _extractServiceAccountEmail(String raw) {
    try {
      final map = _parseServiceAccountJson(raw);
      final email = (map['client_email'] as String?)?.trim();
      if (email == null || email.isEmpty) {
        return null;
      }
      return email;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureSheetExists(
    sheets.SheetsApi api,
    String spreadsheetId,
    String targetTitle,
  ) async {
    final spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final hasSheet =
        spreadsheet.sheets?.any((sheet) {
          return sheet.properties?.title == targetTitle;
        }) ??
        false;

    if (hasSheet) return;

    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            addSheet: sheets.AddSheetRequest(
              properties: sheets.SheetProperties(title: targetTitle),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }
}

class SheetsExportResult {
  final bool success;
  final int rowCount;
  final String message;

  const SheetsExportResult({
    required this.success,
    required this.rowCount,
    required this.message,
  });
}
