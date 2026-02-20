import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

class RuntimeSettings {
  static const String _settingsFileName = 'runtime_settings.json';

  static bool _loaded = false;

  static String geminiApiKey = AppConstants.geminiApiKey;
  // Legacy field kept for backward compatibility with older runtime files.
  static String rakutenApiKey = AppConstants.rakutenApiKey;
  static String rakutenApplicationId = AppConstants.rakutenApplicationId;
  static String rakutenAccessKey = AppConstants.rakutenAccessKey;
  static String rakutenAffiliateId = AppConstants.rakutenAffiliateId;
  static String googleSheetsSpreadsheetId =
      AppConstants.googleSheetsSpreadsheetId;
  static String googleServiceAccountJson =
      AppConstants.googleServiceAccountJson;

  static Future<void> load() async {
    if (_loaded) return;

    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          geminiApiKey = _normalizeCredential(
            (decoded['geminiApiKey'] as String?) ?? AppConstants.geminiApiKey,
          );
          rakutenApiKey = _normalizeCredential(
            (decoded['rakutenApiKey'] as String?) ?? '',
          );
          rakutenApplicationId = _normalizeCredential(
            (decoded['rakutenApplicationId'] as String?) ??
                AppConstants.rakutenApplicationId,
          );
          if (rakutenApplicationId.isEmpty) {
            // Migrate from legacy key field if present.
            final defaultApplicationId = _normalizeCredential(
              AppConstants.rakutenApplicationId,
            );
            rakutenApplicationId = _isLikelyRakutenApplicationId(rakutenApiKey)
                ? rakutenApiKey
                : (_isLikelyRakutenApplicationId(defaultApplicationId)
                      ? defaultApplicationId
                      : '');
          }
          rakutenAccessKey = _normalizeCredential(
            (decoded['rakutenAccessKey'] as String?) ??
                AppConstants.rakutenAccessKey,
          );
          rakutenAffiliateId = _normalizeCredential(
            (decoded['rakutenAffiliateId'] as String?) ??
                AppConstants.rakutenAffiliateId,
          );
          googleSheetsSpreadsheetId =
              (decoded['googleSheetsSpreadsheetId'] as String?) ??
              AppConstants.googleSheetsSpreadsheetId;
          googleServiceAccountJson =
              (decoded['googleServiceAccountJson'] as String?) ??
              AppConstants.googleServiceAccountJson;
        }
      }
    } catch (_) {
      // Keep compile-time defaults if the settings file is unreadable.
    }

    _loaded = true;
  }

  static Future<void> save({
    required String geminiApiKey,
    required String rakutenApplicationId,
    required String rakutenAccessKey,
    String rakutenAffiliateId = '',
    required String googleSheetsSpreadsheetId,
    required String googleServiceAccountJson,
  }) async {
    RuntimeSettings.geminiApiKey = _normalizeCredential(geminiApiKey);
    RuntimeSettings.rakutenApplicationId = _normalizeCredential(
      rakutenApplicationId,
    );
    RuntimeSettings.rakutenAffiliateId = _normalizeCredential(
      rakutenAffiliateId,
    );
    RuntimeSettings.rakutenAccessKey = _normalizeCredential(rakutenAccessKey);
    // Keep the legacy field in sync so older call sites still work.
    RuntimeSettings.rakutenApiKey = RuntimeSettings.rakutenApplicationId;
    RuntimeSettings.googleSheetsSpreadsheetId = googleSheetsSpreadsheetId
        .trim();
    RuntimeSettings.googleServiceAccountJson = googleServiceAccountJson.trim();

    final file = await _settingsFile();
    final payload = <String, String>{
      'geminiApiKey': RuntimeSettings.geminiApiKey,
      'rakutenApiKey': RuntimeSettings.rakutenApiKey,
      'rakutenApplicationId': RuntimeSettings.rakutenApplicationId,
      'rakutenAccessKey': RuntimeSettings.rakutenAccessKey,
      'rakutenAffiliateId': RuntimeSettings.rakutenAffiliateId,
      'googleSheetsSpreadsheetId': RuntimeSettings.googleSheetsSpreadsheetId,
      'googleServiceAccountJson': RuntimeSettings.googleServiceAccountJson,
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  static Future<File> _settingsFile() async {
    final baseDir = await getDatabasesPath();
    final filePath = p.join(baseDir, _settingsFileName);
    final file = File(filePath);
    await file.parent.create(recursive: true);
    return file;
  }

  static String _normalizeCredential(String value) {
    var text = value.trim();
    while (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  static bool _isLikelyRakutenApplicationId(String value) {
    final text = _normalizeCredential(value);
    if (text.isEmpty) return false;
    // Old API key-like values (e.g. "pk_...") are not Rakuten application IDs.
    return !text.toLowerCase().startsWith('pk_');
  }
}
