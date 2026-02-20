import 'dart:async';
import 'package:flutter/foundation.dart' show Uint8List, debugPrint;
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sunmi_printer_plus/enums.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:sunmi_printer_plus/sunmi_style.dart';
import '../../core/constants/app_constants.dart';
import '../models/product.dart';

// Abstract interface for hardware operations
abstract class HardwareService {
  Future<String?> scanBarcode();
  Future<void> printProductTag(Product product);
  Future<void> printInventoryList(List<Product> products);
  Future<void> printQrCode(String data, {String? label});
  Future<void> printBarcode(String data, {String? label});
  Future<Uint8List?> capturePhoto();
  Future<bool> isPrinterAvailable();
  Future<bool> isCameraAvailable();
  Future<bool> isScannerAvailable();
}

// Production implementation for Sunmi V1-B18
class SunmiHardwareService implements HardwareService {
  static const MethodChannel _nativePrinterChannel = MethodChannel(
    'pos_steward_printer',
  );
  static const double _nativeTextSize = 16.0;
  static const int _nativeQrModuleSize = 4;
  static const int _nativeQrErrorLevel = 2;
  static const int _nativeBarcodeHeight = 130;
  static const int _nativeBarcodeWidth = 3;
  static const int _nativeQrSizePx = 200;
  static const int _nativeBarcodeWidthPx = 360;
  static const int _nativeBarcodeHeightPx = 130;

  MobileScannerController? _scannerController;
  bool _isInitialized = false;
  bool _printerServiceBound = false;

  static const Duration _printerBindPollInterval = Duration(milliseconds: 150);
  static const int _printerBindPollAttempts = 12;

  // Initialize hardware components
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize scanner
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );

      _isInitialized = true;
    } catch (e) {
      throw HardwareException('Failed to initialize hardware: $e');
    }
  }

  @override
  Future<String?> scanBarcode() async {
    if (!_isInitialized) await initialize();

    try {
      final Completer<String?> completer = Completer();
      StreamSubscription<BarcodeCapture>? subscription;

      // Set up barcode detection
      subscription = _scannerController!.barcodes.listen((capture) {
        final List<Barcode> barcodes = capture.barcodes;

        if (barcodes.isNotEmpty) {
          final barcode = barcodes.first;
          if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
            subscription?.cancel();
            _scannerController!.stop();

            if (!completer.isCompleted) {
              completer.complete(barcode.rawValue);
            }
          }
        }
      });

      // Start scanning
      await _scannerController!.start();

      // Set timeout
      Timer(Duration(milliseconds: AppConstants.scanTimeout), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          _scannerController!.stop();
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e) {
      throw HardwareException('Barcode scanning failed: $e');
    }
  }

  @override
  Future<void> printProductTag(Product product) async {
    debugPrint('[PRINT] printProductTag start barcode=${product.barcode}');
    final nativeLines = <String>[
      '=== 商品タグ ===',
      '',
      '物品名:',
      product.name,
      '番号:',
      product.barcode,
      if (product.brand != null) 'ブランド: ${product.brand}',
      'カテゴリ: ${product.category}',
      if (product.price != null) '価格: ${product.displayPrice}',
      '数量: ${product.quantity}',
    ];
    if (product.hasAiAnalysis) {
      final decisionLabel =
          AppConstants.movingDecisionLabels[product.movingDecision] ??
          product.movingDecision;
      nativeLines.addAll([
        '--- AI判定 ---',
        '判定: $decisionLabel',
        if (product.storageLocation != null) '保管場所: ${product.storageLocation}',
        if (product.aiConfidence != null)
          '信頼度: ${(product.aiConfidence! * 100).toInt()}%',
      ]);
    }
    nativeLines.add(AppUtils.formatDateTime(DateTime.now()));

    final nativePrinted = await _tryNativePrintPayload(
      lines: nativeLines,
      barcode: product.barcode,
      qrData: 'barcode:${product.barcode}',
      alignment: 0,
      textSize: _nativeTextSize,
      qrModuleSize: _nativeQrModuleSize,
      qrErrorLevel: _nativeQrErrorLevel,
      barcodeHeight: _nativeBarcodeHeight,
      barcodeWidth: _nativeBarcodeWidth,
      qrSizePx: _nativeQrSizePx,
      barcodeWidthPx: _nativeBarcodeWidthPx,
      barcodeHeightPx: _nativeBarcodeHeightPx,
      centerFirstLine: true,
      printTextBelowCodes: true,
    );
    if (nativePrinted) {
      debugPrint('[PRINT] printProductTag native success');
      return;
    }

    await _runPrintJob(() async {
      await _disableInverseMode();
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText('=== 商品タグ ===');
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);

      await SunmiPrinter.printText('物品名:');
      await SunmiPrinter.printText(product.name);
      await SunmiPrinter.printText('番号:');
      await SunmiPrinter.printText(product.barcode);
      if (product.brand != null) {
        await SunmiPrinter.printText('ブランド: ${product.brand}');
      }
      await SunmiPrinter.printText('カテゴリ: ${product.category}');

      if (product.price != null) {
        await SunmiPrinter.printText('価格: ${product.displayPrice}');
      }
      await SunmiPrinter.printText('数量: ${product.quantity}');

      if (product.hasAiAnalysis) {
        await SunmiPrinter.lineWrap(1);
        await SunmiPrinter.printText('--- AI判定 ---');

        final decisionLabel =
            AppConstants.movingDecisionLabels[product.movingDecision] ??
            product.movingDecision;
        await SunmiPrinter.printText('判定: $decisionLabel');

        if (product.storageLocation != null) {
          await SunmiPrinter.printText('保管場所: ${product.storageLocation}');
        }

        if (product.aiConfidence != null) {
          final confidence = (product.aiConfidence! * 100).toInt();
          await SunmiPrinter.printText('信頼度: $confidence%');
        }
      }

      await SunmiPrinter.lineWrap(1);
      await _disableInverseMode();
      final barcodeType = _resolveSunmiBarcodeType(product.barcode);
      await SunmiPrinter.printBarCode(
        product.barcode,
        barcodeType: barcodeType,
        height: _nativeBarcodeHeight,
        width: _nativeBarcodeWidth,
        textPosition: SunmiBarcodeTextPos.NO_TEXT,
      );
      await SunmiPrinter.printText(product.barcode);

      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText('QR');
      await _disableInverseMode();
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printQRCode(
        'barcode:${product.barcode}',
        size: _nativeQrModuleSize,
        errorLevel: SunmiQrcodeLevel.LEVEL_Q,
      );
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText('barcode:${product.barcode}');

      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText(AppUtils.formatDateTime(DateTime.now()));
    }, operationName: 'Printing failed');
    debugPrint('[PRINT] printProductTag done barcode=${product.barcode}');
  }

  @override
  Future<void> printInventoryList(List<Product> products) async {
    debugPrint('[PRINT] printInventoryList start count=${products.length}');
    final nativeLines = <String>[
      '=== 在庫リスト ===',
      AppUtils.formatDateTime(DateTime.now()),
      '',
    ];
    for (int i = 0; i < products.length; i++) {
      final product = products[i];
      nativeLines.add('${i + 1}. ${product.name}');
      nativeLines.add('   ${product.barcode}');
      if (product.hasAiAnalysis) {
        final decision =
            AppConstants.movingDecisionLabels[product.movingDecision] ??
            product.movingDecision;
        nativeLines.add('   判定: $decision');
      }
      nativeLines.add('');
    }
    nativeLines.addAll(['--- 集計 ---', '合計商品数: ${products.length}']);
    final keepCount = products.where((p) => p.shouldKeep).length;
    final parentsHomeCount = products
        .where((p) => p.shouldStoreAtParents)
        .length;
    final discardCount = products.where((p) => p.shouldDiscard).length;
    final sellCount = products.where((p) => p.shouldSell).length;
    if (keepCount > 0) nativeLines.add('持参: $keepCount');
    if (parentsHomeCount > 0) nativeLines.add('実家保管: $parentsHomeCount');
    if (discardCount > 0) nativeLines.add('廃棄: $discardCount');
    if (sellCount > 0) nativeLines.add('売却: $sellCount');

    final nativePrinted = await _tryNativePrintPayload(
      lines: nativeLines,
      alignment: 0,
      textSize: _nativeTextSize,
      qrModuleSize: _nativeQrModuleSize,
      qrErrorLevel: _nativeQrErrorLevel,
      barcodeHeight: _nativeBarcodeHeight,
      barcodeWidth: _nativeBarcodeWidth,
      qrSizePx: _nativeQrSizePx,
      barcodeWidthPx: _nativeBarcodeWidthPx,
      barcodeHeightPx: _nativeBarcodeHeightPx,
      printTextBelowCodes: true,
    );
    if (nativePrinted) {
      debugPrint('[PRINT] printInventoryList native success');
      return;
    }

    await _runPrintJob(() async {
      await SunmiPrinter.printText('=== 在庫リスト ===');
      await SunmiPrinter.printText(AppUtils.formatDateTime(DateTime.now()));
      await SunmiPrinter.lineWrap(1);

      for (int i = 0; i < products.length; i++) {
        final product = products[i];

        await SunmiPrinter.printText('${i + 1}. ${product.name}');
        await SunmiPrinter.printText('   ${product.barcode}');

        if (product.hasAiAnalysis) {
          final decision =
              AppConstants.movingDecisionLabels[product.movingDecision] ??
              product.movingDecision;
          await SunmiPrinter.printText('   判定: $decision');
        }

        await SunmiPrinter.lineWrap(1);
      }

      await SunmiPrinter.printText('--- 集計 ---');
      await SunmiPrinter.printText('合計商品数: ${products.length}');

      final keepCount = products.where((p) => p.shouldKeep).length;
      final parentsHomeCount = products
          .where((p) => p.shouldStoreAtParents)
          .length;
      final discardCount = products.where((p) => p.shouldDiscard).length;
      final sellCount = products.where((p) => p.shouldSell).length;

      if (keepCount > 0) await SunmiPrinter.printText('持参: $keepCount');
      if (parentsHomeCount > 0) {
        await SunmiPrinter.printText('実家保管: $parentsHomeCount');
      }
      if (discardCount > 0) await SunmiPrinter.printText('廃棄: $discardCount');
      if (sellCount > 0) await SunmiPrinter.printText('売却: $sellCount');
    }, operationName: 'Inventory list printing failed');
    debugPrint('[PRINT] printInventoryList done count=${products.length}');
  }

  @override
  Future<void> printQrCode(String data, {String? label}) async {
    debugPrint('[PRINT] printQrCode start dataLength=${data.length}');
    final nativeLines = <String>[if (label != null && label.isNotEmpty) label];
    final nativePrinted = await _tryNativePrintPayload(
      lines: nativeLines,
      qrData: data,
      alignment: 0,
      textSize: _nativeTextSize,
      qrModuleSize: _nativeQrModuleSize,
      qrErrorLevel: _nativeQrErrorLevel,
      qrSizePx: _nativeQrSizePx,
      printTextBelowCodes: true,
    );
    if (nativePrinted) {
      debugPrint('[PRINT] printQrCode native success');
      return;
    }

    await _runPrintJob(() async {
      if (label != null && label.isNotEmpty) {
        await SunmiPrinter.printText(
          label,
          style: SunmiStyle(fontSize: SunmiFontSize.SM),
        );
      }
      await _disableInverseMode();
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printQRCode(
        data,
        size: _nativeQrModuleSize,
        errorLevel: SunmiQrcodeLevel.LEVEL_Q,
      );
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText(data);
    }, operationName: 'QR printing failed');
    debugPrint('[PRINT] printQrCode done');
  }

  @override
  Future<void> printBarcode(String data, {String? label}) async {
    final normalized = data.trim();
    if (normalized.isEmpty) {
      throw HardwareException('Barcode data is empty');
    }

    debugPrint('[PRINT] printBarcode start data=$normalized');
    final nativeLines = <String>[if (label != null && label.isNotEmpty) label];
    final nativePrinted = await _tryNativePrintPayload(
      lines: nativeLines,
      barcode: normalized,
      alignment: 0,
      textSize: _nativeTextSize,
      qrModuleSize: _nativeQrModuleSize,
      qrErrorLevel: _nativeQrErrorLevel,
      barcodeHeight: _nativeBarcodeHeight,
      barcodeWidth: _nativeBarcodeWidth,
      qrSizePx: _nativeQrSizePx,
      barcodeWidthPx: _nativeBarcodeWidthPx,
      barcodeHeightPx: _nativeBarcodeHeightPx,
      printTextBelowCodes: true,
    );
    if (nativePrinted) {
      debugPrint('[PRINT] printBarcode native success');
      return;
    }

    await _runPrintJob(() async {
      await _disableInverseMode();
      if (label != null && label.isNotEmpty) {
        await SunmiPrinter.printText(
          label,
          style: SunmiStyle(fontSize: SunmiFontSize.SM),
        );
      }
      final barcodeType = _resolveSunmiBarcodeType(normalized);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printBarCode(
        normalized,
        barcodeType: barcodeType,
        height: _nativeBarcodeHeight,
        width: _nativeBarcodeWidth,
        textPosition: SunmiBarcodeTextPos.NO_TEXT,
      );
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText(
        normalized,
        style: SunmiStyle(
          fontSize: SunmiFontSize.SM,
          align: SunmiPrintAlign.CENTER,
        ),
      );
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
    }, operationName: 'Barcode printing failed');
    debugPrint('[PRINT] printBarcode done');
  }

  SunmiBarcodeType _resolveSunmiBarcodeType(String data) {
    final normalized = data.trim();
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      return SunmiBarcodeType.CODE128;
    }

    switch (normalized.length) {
      case 13:
        return SunmiBarcodeType.JAN13;
      case 12:
        return SunmiBarcodeType.UPCA;
      case 8:
        return SunmiBarcodeType.JAN8;
      default:
        return SunmiBarcodeType.CODE128;
    }
  }

  @override
  Future<Uint8List?> capturePhoto() async {
    // Camera plugin was removed to keep Android 5.1 (API 22) compatibility.
    return null;
  }

  @override
  Future<bool> isPrinterAvailable() async {
    return _bindAndWaitForPrinterService();
  }

  @override
  Future<bool> isCameraAvailable() async {
    return false;
  }

  @override
  Future<bool> isScannerAvailable() async {
    try {
      return _scannerController != null;
    } catch (e) {
      return false;
    }
  }

  // Cleanup resources
  Future<void> dispose() async {
    _scannerController?.dispose();
    if (_printerServiceBound) {
      try {
        await SunmiPrinter.unbindingPrinter();
      } catch (_) {
        // Ignore unbind errors.
      }
      _printerServiceBound = false;
    }
    _isInitialized = false;
  }

  Future<void> _preparePrinter() async {
    debugPrint('[PRINT] _preparePrinter start');
    final available = await _bindAndWaitForPrinterService();
    if (!available) {
      debugPrint('[PRINT] _preparePrinter bind failed');
      throw HardwareException(
        'Printer service bind failed (woyou.aidlservice.jiuiv5)',
      );
    }

    final status = await _safeGetPrinterStatus();
    debugPrint('[PRINT] _preparePrinter status=$status');
    if (status == PrinterStatus.OUT_OF_PAPER) {
      throw HardwareException('Printer is out of paper');
    }
    if (status == PrinterStatus.OPEN_THE_LID) {
      throw HardwareException('Printer cover is open');
    }
    if (status == PrinterStatus.OVERHEATED) {
      throw HardwareException('Printer is overheated');
    }

    try {
      await SunmiPrinter.initPrinter();
      debugPrint('[PRINT] _preparePrinter initPrinter ok');
    } catch (_) {
      // The plugin may swallow native exceptions; continue to print attempt.
      debugPrint('[PRINT] _preparePrinter initPrinter failed but continue');
    }
  }

  Future<void> _safeCut() async {
    try {
      await SunmiPrinter.lineWrap(2);
      await SunmiPrinter.cut();
    } catch (_) {
      // Some Sunmi devices do not support paper cut.
    }
  }

  Future<void> _runPrintJob(
    Future<void> Function() printAction, {
    required String operationName,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt < AppConstants.printRetryCount; attempt++) {
      try {
        debugPrint('[PRINT] attempt=${attempt + 1} start');
        await _preparePrinter();
        await printAction();
        await _safeCut();
        debugPrint('[PRINT] attempt=${attempt + 1} success');
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[PRINT] attempt=${attempt + 1} failed error=$e');
        _printerServiceBound = false;
        await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }

    throw HardwareException('$operationName: $lastError');
  }

  Future<bool> _bindAndWaitForPrinterService() async {
    for (int retry = 0; retry < AppConstants.printRetryCount; retry++) {
      try {
        debugPrint('[PRINT] bindingPrinter retry=${retry + 1}');
        await SunmiPrinter.bindingPrinter();
        _printerServiceBound = true;
        debugPrint('[PRINT] bindingPrinter call ok');
      } catch (_) {
        _printerServiceBound = false;
        debugPrint('[PRINT] bindingPrinter call failed');
      }

      for (int attempt = 0; attempt < _printerBindPollAttempts; attempt++) {
        final status = await _safeGetPrinterStatus();
        debugPrint(
          '[PRINT] bindPoll retry=${retry + 1} poll=${attempt + 1} status=$status',
        );
        if (_isServiceReachableStatus(status)) {
          debugPrint('[PRINT] printer service reachable');
          return true;
        }
        await Future.delayed(_printerBindPollInterval);
      }

      _printerServiceBound = false;
      await Future.delayed(Duration(milliseconds: 220 * (retry + 1)));
    }

    return false;
  }

  Future<PrinterStatus> _safeGetPrinterStatus() async {
    try {
      final status = await SunmiPrinter.getPrinterStatus();
      return status;
    } catch (_) {
      debugPrint('[PRINT] getPrinterStatus exception');
      return PrinterStatus.UNKNOWN;
    }
  }

  Future<bool> _tryNativePrintPayload({
    required List<String> lines,
    String? barcode,
    String? qrData,
    int alignment = 0,
    double textSize = _nativeTextSize,
    int qrModuleSize = _nativeQrModuleSize,
    int qrErrorLevel = _nativeQrErrorLevel,
    int barcodeHeight = _nativeBarcodeHeight,
    int barcodeWidth = _nativeBarcodeWidth,
    int qrSizePx = _nativeQrSizePx,
    int barcodeWidthPx = _nativeBarcodeWidthPx,
    int barcodeHeightPx = _nativeBarcodeHeightPx,
    bool centerFirstLine = false,
    bool printTextBelowCodes = true,
  }) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _nativePrinterChannel
            .invokeMethod<dynamic>('printPayload', <String, dynamic>{
              'lines': lines,
              'barcode': barcode,
              'qrData': qrData,
              'alignment': alignment,
              'textSize': textSize,
              'qrModuleSize': qrModuleSize,
              'qrErrorLevel': qrErrorLevel,
              'barcodeHeight': barcodeHeight,
              'barcodeWidth': barcodeWidth,
              'qrSizePx': qrSizePx,
              'barcodeWidthPx': barcodeWidthPx,
              'barcodeHeightPx': barcodeHeightPx,
              'centerFirstLine': centerFirstLine,
              'printTextBelowCodes': printTextBelowCodes,
            });
        if (result is Map) {
          final ok = result['ok'] == true;
          debugPrint('[PRINT] native result=$result');
          return ok;
        }
        debugPrint('[PRINT] native result (non-map)=$result');
        return false;
      } on PlatformException catch (e) {
        debugPrint(
          '[PRINT] native platform error code=${e.code} message=${e.message} attempt=${attempt + 1}',
        );
        if (e.code == 'BIND_FAILED' && attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        return false;
      } catch (e) {
        debugPrint('[PRINT] native unknown error=$e');
        return false;
      }
    }
    return false;
  }

  Future<void> _disableInverseMode() async {
    try {
      // GS B n (n=0): disable reverse black/white print mode.
      await SunmiPrinter.printRawData(Uint8List.fromList([0x1D, 0x42, 0x00]));
    } catch (_) {
      // Ignore and continue; some firmware may not accept this command.
    }
  }

  bool _isServiceReachableStatus(PrinterStatus status) {
    switch (status) {
      case PrinterStatus.NORMAL:
      case PrinterStatus.ABNORMAL_COMMUNICATION:
      case PrinterStatus.OUT_OF_PAPER:
      case PrinterStatus.PREPARING:
      case PrinterStatus.OVERHEATED:
      case PrinterStatus.OPEN_THE_LID:
      case PrinterStatus.PAPER_CUTTER_ABNORMAL:
      case PrinterStatus.PAPER_CUTTER_RECOVERED:
      case PrinterStatus.NO_BLACK_MARK:
      case PrinterStatus.FAILED_TO_UPGRADE_FIRMWARE:
        return true;
      case PrinterStatus.UNKNOWN:
      case PrinterStatus.ERROR:
      case PrinterStatus.NO_PRINTER_DETECTED:
      case PrinterStatus.EXCEPTION:
        return false;
    }
  }
}

// Mock implementation for development and testing
class MockHardwareService implements HardwareService {
  static const List<String> _mockBarcodes = [
    '1234567890123',
    '4901234567890',
    '8901234567890',
    '5901234567890',
  ];

  static const List<String> _mockProductNames = [
    'テスト商品A',
    'サンプル商品B',
    'デモ商品C',
    'モック商品D',
  ];

  int _mockCounter = 0;

  @override
  Future<String?> scanBarcode() async {
    // Simulate scanning delay
    await Future.delayed(const Duration(seconds: 2));

    final barcode = _mockBarcodes[_mockCounter % _mockBarcodes.length];
    _mockCounter++;

    return barcode;
  }

  @override
  Future<void> printProductTag(Product product) async {
    await Future.delayed(const Duration(milliseconds: 500));

    print('MOCK PRINT: Product Tag');
    print('Name: ${product.name}');
    print('Barcode: ${product.barcode}');
    print('Category: ${product.category}');
    if (product.hasAiAnalysis) {
      print('AI Decision: ${product.movingDecision}');
    }
    print('--- End Tag ---');
  }

  @override
  Future<void> printInventoryList(List<Product> products) async {
    await Future.delayed(const Duration(seconds: 1));

    print('MOCK PRINT: Inventory List');
    print('Total Products: ${products.length}');
    for (int i = 0; i < products.length; i++) {
      print('${i + 1}. ${products[i].name} (${products[i].barcode})');
    }
    print('--- End List ---');
  }

  @override
  Future<void> printQrCode(String data, {String? label}) async {
    await Future.delayed(const Duration(milliseconds: 350));
    print('MOCK PRINT: QR CODE');
    print('Label: ${label ?? '-'}');
    print('Data: $data');
    print('--- End QR ---');
  }

  @override
  Future<void> printBarcode(String data, {String? label}) async {
    await Future.delayed(const Duration(milliseconds: 350));
    print('MOCK PRINT: BARCODE');
    print('Label: ${label ?? '-'}');
    print('Data: $data');
    print('--- End BARCODE ---');
  }

  @override
  Future<Uint8List?> capturePhoto() async {
    await Future.delayed(const Duration(seconds: 1));

    // Return empty byte array as mock photo
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG header
  }

  @override
  Future<bool> isPrinterAvailable() async => true;

  @override
  Future<bool> isCameraAvailable() async => true;

  @override
  Future<bool> isScannerAvailable() async => true;
}

class HardwareException implements Exception {
  final String message;

  HardwareException(this.message);

  @override
  String toString() => 'HardwareException: $message';
}
