import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/config/runtime_settings.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/api_connection_test_result.dart';
import '../../data/models/product.dart';
import '../../data/models/product_suggestion.dart';
import '../../data/services/gemini_service.dart';
import '../../data/services/rakuten_service.dart';
import '../../data/services/sheets_service.dart';
import '../providers/product_provider.dart';
import '../widgets/product_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _cameraChannel = MethodChannel(
    'pos_steward_camera',
  );

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductProvider>().loadProducts();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.inventory), text: '在庫'),
            Tab(icon: Icon(Icons.analytics), text: '分析'),
            Tab(icon: Icon(Icons.moving), text: '引越'),
            Tab(icon: Icon(Icons.settings), text: '設定'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<ProductProvider>().refresh(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInventoryTab(),
          _buildAnalysisTab(),
          _buildMovingTab(),
          _buildSettingsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showScanBottomSheet,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('スキャン'),
      ),
    );
  }

  Widget _buildInventoryTab() {
    return Consumer<ProductProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Column(
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) {
                      return TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '商品名やバーコードで検索',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    provider.setSearchQuery('');
                                  },
                                )
                              : null,
                        ),
                        onChanged: _onSearchChanged,
                      );
                    },
                  ),
                  const SizedBox(height: AppConstants.smallPadding),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryFilterChips(provider),
                        const SizedBox(width: AppConstants.smallPadding),
                        _buildMovingDecisionFilterChips(provider),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.defaultPadding,
              ),
              child: Row(
                children: [
                  Text(
                    '${provider.filteredProducts.length} 商品',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (provider.searchQuery.isNotEmpty ||
                      provider.selectedCategory != null ||
                      provider.selectedMovingDecision != null)
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        provider.clearFilters();
                      },
                      child: const Text('フィルタクリア'),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildProductsList(provider)),
          ],
        );
      },
    );
  }

  Widget _buildProductsList(ProductProvider provider) {
    if (provider.isLoading && provider.products.isEmpty) {
      return _buildLoadingView();
    }

    if (provider.hasError && provider.products.isEmpty) {
      return _buildStatusView(
        icon: Icons.error_outline,
        iconColor: Colors.red[300],
        message: provider.errorMessage ?? 'エラーが発生しました',
        action: ElevatedButton(
          onPressed: () {
            provider.clearError();
            provider.refresh();
          },
          child: const Text('再試行'),
        ),
      );
    }

    if (provider.filteredProducts.isEmpty) {
      return _buildStatusView(
        icon: Icons.inventory_2_outlined,
        iconColor: Colors.grey[400],
        message: provider.isEmpty ? '商品が登録されていません' : '検索条件に一致する商品がありません',
        action: provider.isEmpty
            ? ElevatedButton.icon(
                onPressed: _showScanBottomSheet,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('商品をスキャン'),
              )
            : null,
      );
    }

    final products = provider.filteredProducts;
    final listView = ListView.builder(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      cacheExtent: 600,
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return RepaintBoundary(
          child: ProductCard(
            product: product,
            onTap: () => _showProductDetails(product),
            onEdit: () => _showEditProductDialog(product),
            onDelete: () => _showDeleteConfirmDialog(product),
            onPrint: () => _handleProductPrint(product),
            onAnalyze: product.hasAiAnalysis
                ? null
                : () => _handleProductAnalyze(product),
          ),
        );
      },
    );

    if (!provider.isLoading) {
      return listView;
    }

    return Stack(
      children: [
        listView,
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('ロード中...'),
        ],
      ),
    );
  }

  Widget _buildStatusView({
    required IconData icon,
    required Color? iconColor,
    required String message,
    Widget? action,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: iconColor),
                  const SizedBox(height: AppConstants.defaultPadding),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (action != null) ...[
                    const SizedBox(height: AppConstants.defaultPadding),
                    action,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryFilterChips(ProductProvider provider) {
    return Wrap(
      spacing: AppConstants.smallPadding,
      children: AppConstants.productCategories.map((category) {
        final isSelected = provider.selectedCategory == category;
        return FilterChip(
          label: Text(category),
          selected: isSelected,
          onSelected: (selected) {
            provider.setSelectedCategory(selected ? category : null);
          },
        );
      }).toList(),
    );
  }

  Widget _buildMovingDecisionFilterChips(ProductProvider provider) {
    return Wrap(
      spacing: AppConstants.smallPadding,
      children: AppConstants.movingDecisions.map((decision) {
        final isSelected = provider.selectedMovingDecision == decision;
        final label = AppConstants.movingDecisionLabels[decision] ?? decision;
        return FilterChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (selected) {
            provider.setSelectedMovingDecision(selected ? decision : null);
          },
        );
      }).toList(),
    );
  }

  Widget _buildAnalysisTab() {
    return Consumer<ProductProvider>(
      builder: (context, provider, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatisticsCards(provider),
              const SizedBox(height: AppConstants.largePadding),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.psychology,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: AppConstants.smallPadding),
                          Text(
                            'AI分析',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.defaultPadding),
                      Text(
                        '分析済み商品: ${provider.products.where((p) => p.hasAiAnalysis).length}/${provider.products.length}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (provider.getAverageConfidence() > 0) ...[
                        const SizedBox(height: AppConstants.smallPadding),
                        Text(
                          '平均信頼度: ${(provider.getAverageConfidence() * 100).toInt()}%',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: AppConstants.defaultPadding),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: provider.isLoading
                              ? null
                              : () => provider.analyzeAllProductsWithAI(),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('全商品をAI分析'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatisticsCards(ProductProvider provider) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            child: Row(
              children: [
                Icon(
                  Icons.inventory,
                  size: 32,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: AppConstants.defaultPadding),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '合計商品数',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '${provider.totalProductCount}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppConstants.defaultPadding),
        if (provider.categoryCounts.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'カテゴリ別統計',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppConstants.smallPadding),
                  ...provider.categoryCounts.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text(entry.key), Text('${entry.value}')],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMovingTab() {
    return Consumer<ProductProvider>(
      builder: (context, provider, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMovingSummaryCards(provider),
              const SizedBox(height: AppConstants.largePadding),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '引っ越しアクション',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppConstants.defaultPadding),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: provider.products.isEmpty
                              ? null
                              : _handleInventoryPrint,
                          icon: const Icon(Icons.print),
                          label: const Text('在庫リストを印刷'),
                        ),
                      ),
                      const SizedBox(height: AppConstants.smallPadding),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              provider.products.isEmpty || provider.isLoading
                              ? null
                              : () async {
                                  final result = await provider
                                      .exportToGoogleSheets();
                                  if (!context.mounted || result == null) {
                                    return;
                                  }

                                  _showMessage(
                                    result.message,
                                    isError: !result.success,
                                  );
                                },
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('Google Sheetsにエクスポート'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMovingSummaryCards(ProductProvider provider) {
    return Column(
      children: AppConstants.movingDecisions.map((decision) {
        final count = provider.getProductCountByMovingDecision(decision);
        final label = AppConstants.movingDecisionLabels[decision]!;
        final description = AppConstants.movingDecisionDescriptions[decision]!;

        Color cardColor;
        IconData cardIcon;

        switch (decision) {
          case 'keep':
            cardColor = Colors.green;
            cardIcon = Icons.home;
            break;
          case 'parents_home':
            cardColor = Colors.brown;
            cardIcon = Icons.family_restroom;
            break;
          case 'discard':
            cardColor = Colors.red;
            cardIcon = Icons.delete;
            break;
          case 'sell':
            cardColor = Colors.orange;
            cardIcon = Icons.attach_money;
            break;
          default:
            cardColor = Colors.grey;
            cardIcon = Icons.help;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: AppConstants.defaultPadding),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Row(
                children: [
                  Icon(cardIcon, size: 32, color: cardColor),
                  const SizedBox(width: AppConstants.defaultPadding),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$count',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(color: cardColor),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.vpn_key),
                title: const Text('APIキー設定'),
                subtitle: Text(_buildApiSettingsSummary()),
                onTap: _showApiSettingsDialog,
              ),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('アプリ情報'),
                subtitle: Text('バージョン ${AppConstants.version}'),
              ),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('QR印刷テスト'),
                subtitle: const Text('プリンタ動作確認'),
                onTap: () async {
                  try {
                    await context.read<ProductProvider>().printQrCode(
                      'sunmi_inventory_app_test',
                      label: 'テストQR',
                    );
                    if (!mounted) return;
                    _showMessage('テストQRを印刷しました');
                  } catch (e) {
                    if (!mounted) return;
                    _showMessage('$e', isError: true);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('バーコード印刷テスト'),
                subtitle: const Text('EAN-13の読み取り確認'),
                onTap: () async {
                  try {
                    await context.read<ProductProvider>().printBarcode(
                      '4901234567894',
                      label: 'テストEAN13',
                    );
                    if (!mounted) return;
                    _showMessage('テストバーコードを印刷しました');
                  } catch (e) {
                    if (!mounted) return;
                    _showMessage('$e', isError: true);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep),
                title: const Text('全データ削除'),
                subtitle: const Text('すべての商品データを削除します'),
                onTap: _showDeleteAllConfirmDialog,
              ),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('デバッグモード'),
                subtitle: Text(AppConstants.isDebugMode ? '有効' : '無効'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showScanBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '商品登録方法を選択',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppConstants.defaultPadding),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('バーコード / QRスキャン'),
                subtitle: const Text('カメラで読み取って登録・参照'),
                onTap: () {
                  Navigator.pop(context);
                  _scanAndAddProduct();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('手動入力'),
                subtitle: const Text('商品情報を手動で入力して登録'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddProductDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('商品名から候補検索'),
                subtitle: const Text('DB / API / AI候補から選択して登録'),
                onTap: () {
                  Navigator.pop(context);
                  _searchByNameAndAddProduct();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanAndAddProduct() async {
    final payload = await showDialog<_ScanPayload>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ScannerDialog(),
    );

    if (!mounted || payload == null) {
      return;
    }

    final rawValue = payload.rawValue.trim();
    if (rawValue.isEmpty) {
      _showMessage('読み取り結果が空です', isError: true);
      return;
    }

    final provider = context.read<ProductProvider>();
    final barcode = _extractBarcodeCandidate(rawValue);
    var loadingShown = false;

    try {
      showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('候補を検索中...'),
            ],
          ),
        ),
      );
      loadingShown = true;

      final suggestions = await provider.suggestProductsFromScan(
        rawValue: rawValue,
        barcode: barcode,
        updateState: false,
      );

      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }

      if (!mounted) return;

      if (suggestions.isEmpty) {
        if (payload.isQr) {
          try {
            await provider.printQrCode(payload.rawValue, label: 'スキャンQR');
            if (mounted) {
              _showMessage('読み取ったQRコードを印刷しました');
            }
          } catch (e) {
            if (mounted) {
              _showMessage('$e', isError: true);
            }
          }
        }
        _showScannedDataDialog(payload);
        return;
      }

      var resolvedProduct = await _resolveSuggestionToProduct(
        suggestions: suggestions,
        title: 'スキャン候補を選択',
        fallbackBarcode: barcode,
        contextRawData: rawValue,
        manualDraftName: payload.isQr ? 'QR商品' : 'スキャン商品',
      );
      if (!mounted || resolvedProduct == null) return;

      if (!resolvedProduct.hasAiAnalysis) {
        final analyzed = await provider.analyzeProductWithAI(
          resolvedProduct,
          updateState: false,
        );
        resolvedProduct = analyzed ?? resolvedProduct;
      }

      await _printScanLabels(resolvedProduct, payload);
      if (!mounted) return;

      _showProductDetails(resolvedProduct, scannedPayload: payload);
    } catch (e) {
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      _showMessage('スキャンエラー: $e', isError: true);
    }
  }

  Future<void> _searchByNameAndAddProduct() async {
    final query = await _showNameSearchDialog();
    if (!mounted || query == null || query.trim().isEmpty) {
      return;
    }

    final provider = context.read<ProductProvider>();
    var loadingShown = false;

    try {
      showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('候補を検索中...'),
            ],
          ),
        ),
      );
      loadingShown = true;

      final suggestions = await provider.suggestProductsByName(
        query,
        updateState: false,
      );

      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      if (!mounted) return;

      if (suggestions.isEmpty) {
        _showMessage('候補が見つかりませんでした', isError: true);
        return;
      }

      var resolvedProduct = await _resolveSuggestionToProduct(
        suggestions: suggestions,
        title: '商品候補を選択',
        contextRawData: query,
        manualDraftName: query,
      );
      if (!mounted || resolvedProduct == null) return;

      if (!resolvedProduct.hasAiAnalysis) {
        final analyzed = await provider.analyzeProductWithAI(
          resolvedProduct,
          updateState: false,
        );
        resolvedProduct = analyzed ?? resolvedProduct;
      }

      if (!mounted) return;
      _showMessage('候補から商品を確定しました');
      _showProductDetails(resolvedProduct);
    } catch (e) {
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      _showMessage('候補検索エラー: $e', isError: true);
    }
  }

  Future<String?> _showNameSearchDialog() async {
    final controller = TextEditingController(
      text: _searchController.text.trim(),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('商品名から候補検索'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '商品名を入力'),
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            final query = value.trim();
            if (query.isNotEmpty) {
              Navigator.pop(dialogContext, query);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              final query = controller.text.trim();
              if (query.isEmpty) return;
              Navigator.pop(dialogContext, query);
            },
            child: const Text('検索'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<Product?> _resolveSuggestionToProduct({
    required List<ProductSuggestion> suggestions,
    required String title,
    String? fallbackBarcode,
    String? contextRawData,
    String? manualDraftName,
  }) async {
    final provider = context.read<ProductProvider>();
    final selection = await _showSuggestionPickerDialog(
      title: title,
      suggestions: suggestions,
    );
    if (!mounted || selection == null) {
      return null;
    }

    if (selection.isManual) {
      return _showProductFormDialog(
        initialProduct: _buildManualDraft(
          name: manualDraftName,
          barcode: fallbackBarcode,
          notes: contextRawData,
        ),
        showSavedMessage: false,
      );
    }

    final suggestion = selection.suggestion;
    if (suggestion == null) {
      return null;
    }

    final existing = _findExistingProductFromSuggestion(
      provider,
      suggestion,
      fallbackBarcode: fallbackBarcode,
    );
    if (existing != null) {
      _showMessage('既存の登録商品を表示します');
      return existing;
    }

    final draft = _buildDraftFromSuggestion(
      suggestion,
      fallbackBarcode: fallbackBarcode,
      contextRawData: contextRawData,
    );

    return _showProductFormDialog(
      initialProduct: draft,
      showSavedMessage: false,
    );
  }

  Product? _findExistingProductFromSuggestion(
    ProductProvider provider,
    ProductSuggestion suggestion, {
    String? fallbackBarcode,
  }) {
    if (suggestion.existingProductId != null) {
      final existing = provider.getProductById(suggestion.existingProductId!);
      if (existing != null) {
        return existing;
      }
    }

    final barcode = _resolveSuggestionBarcode(
      suggestion,
      fallbackBarcode: fallbackBarcode,
    );
    if (barcode == null) {
      return null;
    }

    for (final item in provider.products) {
      if (item.barcode == barcode) {
        return item;
      }
    }
    return null;
  }

  Future<_SuggestionPickerResult?> _showSuggestionPickerDialog({
    required String title,
    required List<ProductSuggestion> suggestions,
  }) {
    return showDialog<_SuggestionPickerResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: suggestions.map((item) {
                final barcode = item.barcode?.trim();
                final secondary = <String>[
                  if (barcode != null && barcode.isNotEmpty) 'バーコード: $barcode',
                  'カテゴリ: ${item.category}',
                  if (item.price != null)
                    '価格: ¥${item.price!.toStringAsFixed(0)}',
                  '候補元: ${item.source}',
                  '信頼度: ${(item.confidence * 100).toInt()}%',
                  if (item.reason != null && item.reason!.isNotEmpty)
                    '根拠: ${item.reason}',
                ].join('\n');

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _buildSuggestionImageThumbnail(item.imageUrl),
                    title: Text(item.name),
                    subtitle: Text(secondary),
                    isThreeLine: true,
                    onTap: () => Navigator.pop(
                      dialogContext,
                      _SuggestionPickerResult(suggestion: item),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              const _SuggestionPickerResult(isManual: true),
            ),
            child: const Text('手動入力'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionImageThumbnail(String? imageUrl) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return const CircleAvatar(
        radius: 22,
        child: Icon(Icons.inventory_2_outlined, size: 18),
      );
    }

    final image = _isRemoteImageUrl(url)
        ? Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image),
          )
        : Image.file(
            File(url),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(width: 44, height: 44, child: image),
    );
  }

  Product _buildDraftFromSuggestion(
    ProductSuggestion suggestion, {
    String? fallbackBarcode,
    String? contextRawData,
  }) {
    final now = DateTime.now();
    final barcode = _resolveSuggestionBarcode(
      suggestion,
      fallbackBarcode: fallbackBarcode,
    );
    final notes = <String>[
      '候補元: ${suggestion.source}',
      if (suggestion.reason != null && suggestion.reason!.trim().isNotEmpty)
        suggestion.reason!.trim(),
      if (contextRawData != null && contextRawData.trim().isNotEmpty)
        '入力: ${contextRawData.trim()}',
    ].join(' / ');

    return Product(
      barcode: barcode ?? '',
      name: suggestion.name.trim().isEmpty ? '未設定商品' : suggestion.name.trim(),
      category: AppConstants.productCategories.contains(suggestion.category)
          ? suggestion.category
          : AppConstants.defaultCategory,
      price: suggestion.price,
      description: suggestion.description?.trim().isEmpty == true
          ? null
          : suggestion.description?.trim(),
      imageUrl: suggestion.imageUrl,
      brand: suggestion.brand,
      createdAt: now,
      updatedAt: now,
      notes: notes,
    );
  }

  Product _buildManualDraft({String? name, String? barcode, String? notes}) {
    final now = DateTime.now();
    return Product(
      barcode: barcode?.trim() ?? '',
      name: (name == null || name.trim().isEmpty) ? '' : name.trim(),
      category: AppConstants.defaultCategory,
      createdAt: now,
      updatedAt: now,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
    );
  }

  String? _resolveSuggestionBarcode(
    ProductSuggestion suggestion, {
    String? fallbackBarcode,
  }) {
    final candidate = suggestion.barcode?.replaceAll(RegExp(r'[^0-9]'), '');
    if (candidate != null && AppUtils.isValidBarcode(candidate)) {
      return candidate;
    }
    final fallback = fallbackBarcode?.replaceAll(RegExp(r'[^0-9]'), '');
    if (fallback != null && AppUtils.isValidBarcode(fallback)) {
      return fallback;
    }
    return null;
  }

  String? _extractBarcodeCandidate(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;

    const barcodePrefix = 'barcode:';
    if (raw.length >= barcodePrefix.length &&
        raw.substring(0, barcodePrefix.length).toLowerCase() == barcodePrefix) {
      final candidate = raw.substring(barcodePrefix.length).trim();
      if (AppUtils.isValidBarcode(candidate)) {
        return candidate;
      }
    }

    if (AppUtils.isValidBarcode(raw)) {
      return raw;
    }

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final barcodeFromQuery =
          uri.queryParameters['barcode'] ?? uri.queryParameters['code'];
      if (barcodeFromQuery != null &&
          AppUtils.isValidBarcode(barcodeFromQuery)) {
        return barcodeFromQuery;
      }

      final digitsInPath = RegExp(r'\d{8,18}').firstMatch(uri.path);
      if (digitsInPath != null) {
        final candidate = digitsInPath.group(0)!;
        if (AppUtils.isValidBarcode(candidate)) {
          return candidate;
        }
      }
    }

    final digits = RegExp(r'\d{8,18}').firstMatch(raw);
    if (digits != null) {
      final candidate = digits.group(0)!;
      if (AppUtils.isValidBarcode(candidate)) {
        return candidate;
      }
    }

    final compactDigits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (AppUtils.isValidBarcode(compactDigits)) {
      return compactDigits;
    }

    return null;
  }

  Product _findLocalProductByBarcode(
    ProductProvider provider,
    String barcode, {
    required Product fallback,
  }) {
    for (final item in provider.products) {
      if (item.barcode == barcode) {
        return item;
      }
    }
    return fallback;
  }

  Future<void> _printScanLabels(Product product, _ScanPayload payload) async {
    final provider = context.read<ProductProvider>();

    try {
      await provider.printProductTag(product);
      if (payload.isQr) {
        await provider.printQrCode(payload.rawValue, label: 'スキャンQR');
      }
      if (!mounted) return;
      _showMessage(payload.isQr ? '商品タグとQRを印刷しました' : '商品タグを印刷しました');
    } catch (e) {
      if (!mounted) return;
      _showMessage('$e', isError: true);
    }
  }

  Future<void> _handleProductAnalyze(Product product) async {
    final provider = context.read<ProductProvider>();
    final analyzed = await provider.analyzeProductWithAI(product);
    if (!mounted || analyzed == null) return;
    _showMessage('AI分析を更新しました');
  }

  Future<void> _handleProductPrint(Product product) async {
    try {
      await context.read<ProductProvider>().printProductTag(product);
      if (!mounted) return;
      _showMessage('商品タグを印刷しました');
    } catch (e) {
      if (!mounted) return;
      _showMessage('$e', isError: true);
    }
  }

  Future<void> _handleInventoryPrint() async {
    try {
      await context.read<ProductProvider>().printInventoryList();
      if (!mounted) return;
      _showMessage('在庫リストを印刷しました');
    } catch (e) {
      if (!mounted) return;
      _showMessage('$e', isError: true);
    }
  }

  void _showProductDetails(Product product, {_ScanPayload? scannedPayload}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(product.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.imageUrl != null && product.imageUrl!.isNotEmpty) ...[
                _buildProductImagePreview(product.imageUrl, height: 190),
                const SizedBox(height: 8),
              ],
              Text('バーコード: ${product.barcode}'),
              Text('カテゴリ: ${product.category}'),
              if (product.price != null) Text('価格: ${product.displayPrice}'),
              Text('数量: ${product.quantity}'),
              if (product.description != null &&
                  product.description!.isNotEmpty)
                Text('説明: ${product.description}'),
              if (product.notes != null && product.notes!.isNotEmpty)
                Text('メモ: ${product.notes}'),
              if (product.hasAiAnalysis) ...[
                const SizedBox(height: 8),
                Text(
                  'AI判定: ${AppConstants.movingDecisionLabels[product.movingDecision] ?? product.movingDecision}',
                ),
                if (product.storageLocation != null)
                  Text('保管場所: ${product.storageLocation}'),
                if (product.aiConfidence != null)
                  Text('信頼度: ${(product.aiConfidence! * 100).toInt()}%'),
              ],
              if (scannedPayload != null) ...[
                const SizedBox(height: 8),
                Text('読み取り種別: ${scannedPayload.formatLabel}'),
                Text(
                  '読み取りデータ: ${scannedPayload.rawValue}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showEditProductDialog(product);
            },
            child: const Text('編集'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _handleProductPrint(product);
            },
            child: const Text('印刷'),
          ),
        ],
      ),
    );
  }

  void _showAddProductDialog() {
    _showProductFormDialog();
  }

  void _showEditProductDialog(Product product) {
    _showProductFormDialog(existingProduct: product);
  }

  Future<Product?> _showProductFormDialog({
    Product? existingProduct,
    Product? initialProduct,
    bool showSavedMessage = true,
  }) {
    final seedProduct = existingProduct ?? initialProduct;
    final isEdit = existingProduct != null;
    final nameController = TextEditingController(text: seedProduct?.name ?? '');
    final barcodeController = TextEditingController(
      text: seedProduct?.barcode ?? '',
    );
    final priceController = TextEditingController(
      text: seedProduct?.price?.toStringAsFixed(0) ?? '',
    );
    final quantityController = TextEditingController(
      text: (seedProduct?.quantity ?? 1).toString(),
    );
    final descriptionController = TextEditingController(
      text: seedProduct?.description ?? '',
    );
    final notesController = TextEditingController(
      text: seedProduct?.notes ?? '',
    );

    String selectedCategory =
        seedProduct?.category ?? AppConstants.defaultCategory;
    String selectedMovingDecision = seedProduct?.movingDecision ?? '';
    String selectedStorageLocation = seedProduct?.storageLocation ?? '';
    String? selectedImageUrl = seedProduct?.imageUrl;
    bool isSaving = false;
    final formKey = GlobalKey<FormState>();

    return showDialog<Product?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? '商品を編集' : '商品を追加'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: '商品名 *'),
                          validator: AppUtils.validateProductName,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: barcodeController,
                          decoration: InputDecoration(
                            labelText: 'バーコード *',
                            suffixIcon: IconButton(
                              tooltip: 'スキャン',
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final payload =
                                          await showDialog<_ScanPayload>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (_) =>
                                                const _ScannerDialog(),
                                          );
                                      if (!dialogContext.mounted ||
                                          payload == null) {
                                        return;
                                      }

                                      final scanned = _extractBarcodeCandidate(
                                        payload.rawValue,
                                      );
                                      if (scanned == null ||
                                          !AppUtils.isValidBarcode(scanned)) {
                                        _showMessage(
                                          'バーコードを認識できませんでした',
                                          isError: true,
                                        );
                                        return;
                                      }

                                      setDialogState(() {
                                        barcodeController.text = scanned;
                                      });
                                    },
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final input = value?.trim() ?? '';
                            if (!AppUtils.isValidBarcode(input)) {
                              return '8〜18桁の数値バーコードを入力してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        if (selectedImageUrl != null &&
                            selectedImageUrl!.trim().isNotEmpty) ...[
                          _buildProductImagePreview(
                            selectedImageUrl,
                            height: 170,
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final capturedPath =
                                            await _captureProductImage();
                                        if (!dialogContext.mounted ||
                                            capturedPath == null) {
                                          return;
                                        }
                                        setDialogState(() {
                                          selectedImageUrl = capturedPath;
                                        });
                                      },
                                icon: const Icon(Icons.photo_camera),
                                label: Text(
                                  selectedImageUrl != null &&
                                          selectedImageUrl!.trim().isNotEmpty
                                      ? '写真を撮り直す'
                                      : '写真を撮影',
                                ),
                              ),
                            ),
                            if (selectedImageUrl != null &&
                                selectedImageUrl!.trim().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: '画像を削除',
                                onPressed: isSaving
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          selectedImageUrl = null;
                                        });
                                      },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (selectedImageUrl != null &&
                            selectedImageUrl!.trim().isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _isRemoteImageUrl(selectedImageUrl!)
                                  ? '画像: 楽天API'
                                  : '画像: 端末カメラ',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          decoration: const InputDecoration(labelText: 'カテゴリ'),
                          items: AppConstants.productCategories
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              selectedCategory = value;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: priceController,
                          decoration: const InputDecoration(labelText: '価格'),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: quantityController,
                          decoration: const InputDecoration(labelText: '数量'),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final quantity = int.tryParse(value ?? '');
                            if (quantity == null || quantity <= 0) {
                              return '1以上の数量を入力してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedMovingDecision,
                          decoration: const InputDecoration(
                            labelText: '引っ越し判定',
                          ),
                          items:
                              const [
                                    DropdownMenuItem(
                                      value: '',
                                      child: Text('未設定'),
                                    ),
                                  ]
                                  .followedBy(
                                    AppConstants.movingDecisions.map(
                                      (decision) => DropdownMenuItem(
                                        value: decision,
                                        child: Text(
                                          AppConstants
                                                  .movingDecisionLabels[decision] ??
                                              decision,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedMovingDecision = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedStorageLocation,
                          decoration: const InputDecoration(labelText: '保管場所'),
                          items:
                              const [
                                    DropdownMenuItem(
                                      value: '',
                                      child: Text('未設定'),
                                    ),
                                  ]
                                  .followedBy(
                                    AppConstants.storageLocations.map(
                                      (location) => DropdownMenuItem(
                                        value: location,
                                        child: Text(location),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedStorageLocation = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(labelText: '説明'),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: notesController,
                          decoration: const InputDecoration(labelText: 'メモ'),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            final provider = context.read<ProductProvider>();
                            final now = DateTime.now();
                            final price = double.tryParse(
                              priceController.text.trim().replaceAll(',', ''),
                            );
                            final quantity =
                                int.tryParse(quantityController.text.trim()) ??
                                1;

                            final draft = Product(
                              id: existingProduct?.id,
                              barcode: barcodeController.text.trim(),
                              name: nameController.text.trim(),
                              category: selectedCategory,
                              price: price,
                              description:
                                  descriptionController.text.trim().isEmpty
                                  ? null
                                  : descriptionController.text.trim(),
                              imageUrl: selectedImageUrl?.trim().isEmpty ?? true
                                  ? null
                                  : selectedImageUrl!.trim(),
                              brand:
                                  existingProduct?.brand ??
                                  initialProduct?.brand,
                              createdAt:
                                  existingProduct?.createdAt ??
                                  initialProduct?.createdAt ??
                                  now,
                              updatedAt: now,
                              movingDecision: selectedMovingDecision.isEmpty
                                  ? null
                                  : selectedMovingDecision,
                              storageLocation: selectedStorageLocation.isEmpty
                                  ? null
                                  : selectedStorageLocation,
                              analysisNotes:
                                  existingProduct?.analysisNotes ??
                                  initialProduct?.analysisNotes,
                              aiConfidence:
                                  existingProduct?.aiConfidence ??
                                  initialProduct?.aiConfidence,
                              quantity: quantity,
                              location:
                                  existingProduct?.location ??
                                  initialProduct?.location,
                              isScanned:
                                  existingProduct?.isScanned ??
                                  initialProduct?.isScanned ??
                                  true,
                              notes: notesController.text.trim().isEmpty
                                  ? null
                                  : notesController.text.trim(),
                            );

                            Product savedProduct;
                            if (isEdit) {
                              await provider.updateProduct(draft);
                              savedProduct = draft;
                            } else {
                              await provider.addProduct(draft);
                              savedProduct = _findLocalProductByBarcode(
                                provider,
                                draft.barcode,
                                fallback: draft,
                              );
                            }

                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext, savedProduct);
                            if (showSavedMessage) {
                              _showMessage(isEdit ? '商品を更新しました' : '商品を追加しました');
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            _showMessage('保存に失敗しました: $e', isError: true);
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                              });
                            }
                          }
                        },
                  child: Text(isEdit ? '更新' : '追加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showApiSettingsDialog() {
    final geminiController = TextEditingController(
      text: RuntimeSettings.geminiApiKey,
    );
    final rakutenApplicationIdController = TextEditingController(
      text: RuntimeSettings.rakutenApplicationId,
    );
    final rakutenAccessKeyController = TextEditingController(
      text: RuntimeSettings.rakutenAccessKey,
    );
    final rakutenAffiliateIdController = TextEditingController(
      text: RuntimeSettings.rakutenAffiliateId,
    );
    final spreadsheetIdController = TextEditingController(
      text: RuntimeSettings.googleSheetsSpreadsheetId,
    );
    final serviceAccountController = TextEditingController(
      text: RuntimeSettings.googleServiceAccountJson,
    );

    bool isSaving = false;
    bool didSave = false;
    ApiConnectionTestResult? geminiTestResult;
    ApiConnectionTestResult? rakutenTestResult;
    ApiConnectionTestResult? sheetsTestResult;

    showDialog<_ApiSettingsDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget buildTestResultRow(
              String label,
              ApiConnectionTestResult? result,
            ) {
              if (result == null) {
                return const SizedBox.shrink();
              }

              final isSuccess = result.success;
              final color = isSuccess
                  ? Colors.green.shade700
                  : Colors.red.shade700;
              final icon = isSuccess ? Icons.check_circle : Icons.error_outline;

              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$label: ${result.message}',
                        style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('APIキー設定'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: geminiController,
                        decoration: const InputDecoration(
                          labelText: 'Gemini APIキー',
                        ),
                      ),
                      buildTestResultRow('Gemini', geminiTestResult),
                      const SizedBox(height: 8),
                      TextField(
                        controller: rakutenApplicationIdController,
                        decoration: const InputDecoration(
                          labelText: 'Rakuten Application ID',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: rakutenAccessKeyController,
                        decoration: const InputDecoration(
                          labelText: 'Rakuten Access Key',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: rakutenAffiliateIdController,
                        decoration: const InputDecoration(
                          labelText: 'Rakuten Affiliate ID (任意)',
                        ),
                      ),
                      buildTestResultRow('Rakuten', rakutenTestResult),
                      const SizedBox(height: 8),
                      TextField(
                        controller: spreadsheetIdController,
                        decoration: const InputDecoration(
                          labelText: 'Google Sheets Spreadsheet ID',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: serviceAccountController,
                        decoration: const InputDecoration(
                          labelText: 'Google Service Account JSON',
                        ),
                        minLines: 3,
                        maxLines: 6,
                      ),
                      buildTestResultRow('Sheets', sheetsTestResult),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(
                          dialogContext,
                          _ApiSettingsDialogResult(saved: didSave),
                        ),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() {
                            isSaving = true;
                            geminiTestResult = null;
                            rakutenTestResult = null;
                            sheetsTestResult = null;
                          });

                          try {
                            final geminiApiKey = geminiController.text.trim();
                            final rakutenApplicationId =
                                rakutenApplicationIdController.text.trim();
                            final rakutenAccessKey = rakutenAccessKeyController
                                .text
                                .trim();
                            final rakutenAffiliateId =
                                rakutenAffiliateIdController.text.trim();
                            final spreadsheetId = spreadsheetIdController.text
                                .trim();
                            final serviceAccountJson = serviceAccountController
                                .text
                                .trim();

                            await RuntimeSettings.save(
                              geminiApiKey: geminiApiKey,
                              rakutenApplicationId: rakutenApplicationId,
                              rakutenAccessKey: rakutenAccessKey,
                              rakutenAffiliateId: rakutenAffiliateId,
                              googleSheetsSpreadsheetId: spreadsheetId,
                              googleServiceAccountJson: serviceAccountJson,
                            );
                            didSave = true;

                            final geminiService = GeminiService(
                              apiKey: geminiApiKey,
                            );
                            final rakutenService = RakutenService(
                              applicationId: rakutenApplicationId,
                              accessKey: rakutenAccessKey,
                              affiliateId: rakutenAffiliateId,
                            );
                            final sheetsService = SheetsService(
                              spreadsheetId: spreadsheetId,
                              serviceAccountJson: serviceAccountJson,
                            );
                            final shouldTestGemini = geminiApiKey.isNotEmpty;
                            final shouldTestSheets =
                                spreadsheetId.isNotEmpty ||
                                serviceAccountJson.isNotEmpty;

                            final results =
                                await Future.wait<ApiConnectionTestResult>([
                                  if (shouldTestGemini)
                                    geminiService.testConnection(
                                      apiKey: geminiApiKey,
                                    )
                                  else
                                    Future.value(
                                      const ApiConnectionTestResult(
                                        success: true,
                                        message: 'Geminiは未設定（後で設定可能）',
                                      ),
                                    ),
                                  rakutenService.testConnection(
                                    applicationId: rakutenApplicationId,
                                    accessKey: rakutenAccessKey,
                                    affiliateId: rakutenAffiliateId,
                                  ),
                                  if (shouldTestSheets)
                                    sheetsService.testConnection(
                                      spreadsheetId: spreadsheetId,
                                      serviceAccountJson: serviceAccountJson,
                                    )
                                  else
                                    Future.value(
                                      const ApiConnectionTestResult(
                                        success: true,
                                        message: 'Sheetsは未設定（後で設定可能）',
                                      ),
                                    ),
                                ]);

                            final geminiResult = results[0];
                            final rakutenResult = results[1];
                            final sheetsResult = results[2];
                            debugPrint(
                              '[API_TEST] Gemini success=${geminiResult.success} message=${geminiResult.message}',
                            );
                            debugPrint(
                              '[API_TEST] Rakuten success=${rakutenResult.success} message=${rakutenResult.message}',
                            );
                            debugPrint(
                              '[API_TEST] Sheets success=${sheetsResult.success} message=${sheetsResult.message}',
                            );

                            if (!dialogContext.mounted) return;
                            final allSuccess =
                                rakutenResult.success &&
                                (!shouldTestGemini || geminiResult.success) &&
                                (!shouldTestSheets || sheetsResult.success);
                            if (allSuccess) {
                              final successMessage = switch ((
                                shouldTestGemini,
                                shouldTestSheets,
                              )) {
                                (true, true) => 'APIキー設定を保存しました（接続OK）',
                                (true, false) =>
                                  'Rakuten/Gemini設定を保存しました（Sheetsは未設定）',
                                (false, true) =>
                                  'Rakuten/Sheets設定を保存しました（Geminiは未設定）',
                                (false, false) =>
                                  'Rakuten設定を保存しました（Gemini/Sheetsは未設定のまま）',
                              };
                              Navigator.pop(
                                dialogContext,
                                _ApiSettingsDialogResult(
                                  saved: true,
                                  successMessage: successMessage,
                                ),
                              );
                            } else {
                              setDialogState(() {
                                geminiTestResult = geminiResult;
                                rakutenTestResult = rakutenResult;
                                sheetsTestResult = sheetsResult;
                                isSaving = false;
                              });
                              _showMessage(
                                '設定は保存しました。接続テスト結果を確認してください。',
                                isError: true,
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            _showMessage('設定保存に失敗しました: $e', isError: true);
                            setDialogState(() {
                              isSaving = false;
                            });
                          }
                        },
                  child: Text(isSaving ? '保存中...' : '保存して接続テスト'),
                ),
              ],
            );
          },
        );
      },
    ).then((result) {
      geminiController.dispose();
      rakutenApplicationIdController.dispose();
      rakutenAccessKeyController.dispose();
      rakutenAffiliateIdController.dispose();
      spreadsheetIdController.dispose();
      serviceAccountController.dispose();

      if (result?.saved == true && mounted) {
        setState(() {});
      }
      if (result?.successMessage != null && mounted) {
        _showMessage(result!.successMessage!);
      }
    });
  }

  void _showScannedDataDialog(_ScanPayload payload) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('スキャン結果'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('種別: ${payload.formatLabel}'),
            const SizedBox(height: 8),
            SelectableText(payload.rawValue),
            const SizedBox(height: 8),
            const Text('このデータから商品バーコードを抽出できなかったため、情報のみ表示しています。'),
          ],
        ),
        actions: [
          if (payload.isQr)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await context.read<ProductProvider>().printQrCode(
                    payload.rawValue,
                    label: 'スキャンQR',
                  );
                  if (!mounted) return;
                  _showMessage('QRコードを印刷しました');
                } catch (e) {
                  if (!mounted) return;
                  _showMessage('$e', isError: true);
                }
              },
              child: const Text('QR印刷'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(Product product) {
    final productProvider = context.read<ProductProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${product.name}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (product.id != null) {
                productProvider.deleteProduct(product.id!);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAllConfirmDialog() {
    final productProvider = context.read<ProductProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('全データ削除確認'),
        content: const Text('すべての商品データを削除しますか？この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              productProvider.deleteAllProducts();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('全削除'),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      context.read<ProductProvider>().setSearchQuery(value);
    });
  }

  Future<String?> _captureProductImage() async {
    try {
      final capturedPath = await _cameraChannel.invokeMethod<String>(
        'capturePhoto',
      );
      if (capturedPath == null || capturedPath.trim().isEmpty) {
        return null;
      }
      return capturedPath.trim();
    } catch (e) {
      if (mounted) {
        _showMessage('写真撮影に失敗しました: $e', isError: true);
      }
      return null;
    }
  }

  bool _isRemoteImageUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  Widget _buildProductImagePreview(String? imageUrl, {double height = 140}) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.grey.shade100,
        ),
        child: const Text('画像なし'),
      );
    }

    final imageWidget = _isRemoteImageUrl(url)
        ? Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Text('画像読込失敗')),
          )
        : Image.file(
            File(url),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Text('画像読込失敗')),
          );

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageWidget,
    );
  }

  String _buildApiSettingsSummary() {
    final gemini = RuntimeSettings.geminiApiKey.isNotEmpty ? '済' : '未';
    final rakuten =
        RuntimeSettings.rakutenApplicationId.isNotEmpty &&
            RuntimeSettings.rakutenAccessKey.isNotEmpty
        ? '済'
        : '未';
    final sheets = RuntimeSettings.googleSheetsSpreadsheetId.isNotEmpty
        ? '済'
        : '未';
    return 'Gemini:$gemini / Rakuten:$rakuten / Sheets:$sheets';
  }

  void _showMessage(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }
}

class _ScanPayload {
  final String rawValue;
  final BarcodeFormat format;

  const _ScanPayload({required this.rawValue, required this.format});

  bool get isQr => format == BarcodeFormat.qrCode;

  String get formatLabel => format.toString().split('.').last;
}

class _SuggestionPickerResult {
  final ProductSuggestion? suggestion;
  final bool isManual;

  const _SuggestionPickerResult({this.suggestion, this.isManual = false});
}

class _ApiSettingsDialogResult {
  final bool saved;
  final String? successMessage;

  const _ApiSettingsDialogResult({required this.saved, this.successMessage});
}

class _ScannerDialog extends StatefulWidget {
  const _ScannerDialog();

  @override
  State<_ScannerDialog> createState() => _ScannerDialogState();
}

class _ScannerDialogState extends State<_ScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
    facing: CameraFacing.back,
    torchEnabled: false,
    cameraResolution: const Size(1600, 1200),
  );

  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;

    for (final code in capture.barcodes) {
      final raw = code.rawValue?.trim();
      debugPrint('[SCAN] format=${code.format} raw=${code.rawValue}');
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(
          context,
        ).pop(_ScanPayload(rawValue: raw, format: code.format));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 460,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'バーコード / QRをスキャン',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('コードを中央に合わせてください'),
            ),
          ],
        ),
      ),
    );
  }
}
