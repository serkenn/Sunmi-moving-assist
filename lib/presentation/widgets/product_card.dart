import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/product.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPrint;
  final VoidCallback? onAnalyze;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onPrint,
    this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage =
        product.imageUrl != null && product.imageUrl!.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.smallPadding),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with name and AI status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImage) ...[
                    _buildProductThumbnail(),
                    const SizedBox(width: AppConstants.smallPadding),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.barcode,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.grey[600],
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.smallPadding),
                  _buildAIStatusChip(context),
                ],
              ),

              const SizedBox(height: AppConstants.smallPadding),

              // Product details row
              Row(
                children: [
                  _buildCategoryChip(context),
                  const SizedBox(width: AppConstants.smallPadding),
                  if (product.price != null) ...[
                    _buildPriceChip(context),
                    const SizedBox(width: AppConstants.smallPadding),
                  ],
                  _buildQuantityChip(context),
                ],
              ),

              // AI Analysis results (if available)
              if (product.hasAiAnalysis) ...[
                const SizedBox(height: AppConstants.smallPadding),
                _buildAIAnalysisSection(context),
              ],

              const SizedBox(height: AppConstants.smallPadding),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onAnalyze != null)
                    IconButton(
                      icon: const Icon(Icons.psychology),
                      onPressed: onAnalyze,
                      tooltip: 'AI分析',
                      iconSize: 20,
                    ),
                  if (onPrint != null)
                    IconButton(
                      icon: const Icon(Icons.print),
                      onPressed: onPrint,
                      tooltip: 'タグ印刷',
                      iconSize: 20,
                    ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: onEdit,
                      tooltip: '編集',
                      iconSize: 20,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: onDelete,
                      tooltip: '削除',
                      iconSize: 20,
                      color: Colors.red[600],
                    ),
                ],
              ),

              // Timestamp
              Text(
                '登録: ${AppUtils.formatDateTime(product.createdAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductThumbnail() {
    final url = product.imageUrl!.trim();
    final uri = Uri.tryParse(url);
    final isRemote =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    final image = isRemote
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
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 64, height: 64, child: image),
    );
  }

  Widget _buildAIStatusChip(BuildContext context) {
    if (product.hasAiAnalysis) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.smallPadding,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: Colors.green[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: Colors.green[700]),
            const SizedBox(width: 4),
            Text(
              'AI分析済',
              style: TextStyle(
                fontSize: 10,
                color: Colors.green[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.smallPadding,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: Colors.orange[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pending, size: 12, color: Colors.orange[700]),
            const SizedBox(width: 4),
            Text(
              '未分析',
              style: TextStyle(
                fontSize: 10,
                color: Colors.orange[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildCategoryChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.smallPadding,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        product.category,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPriceChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.smallPadding,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[300]!),
      ),
      child: Text(
        product.displayPrice,
        style: TextStyle(
          fontSize: 12,
          color: Colors.blue[700],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildQuantityChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.smallPadding,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.purple[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple[300]!),
      ),
      child: Text(
        '数量: ${product.quantity}',
        style: TextStyle(
          fontSize: 12,
          color: Colors.purple[700],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAIAnalysisSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.smallPadding),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Moving decision
          Row(
            children: [
              Icon(
                _getMovingDecisionIcon(),
                size: 16,
                color: _getMovingDecisionColor(),
              ),
              const SizedBox(width: 4),
              Text(
                '判定: ${_getMovingDecisionLabel()}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _getMovingDecisionColor(),
                ),
              ),
              if (product.aiConfidence != null) ...[
                const Spacer(),
                Text(
                  '${(product.aiConfidence! * 100).toInt()}%',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ],
          ),

          // Storage location
          if (product.storageLocation != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '保管: ${product.storageLocation}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ],

          // Analysis notes
          if (product.analysisNotes != null) ...[
            const SizedBox(height: 4),
            Text(
              product.analysisNotes!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _getMovingDecisionLabel() {
    if (product.movingDecision == null) return '未判定';
    return AppConstants.movingDecisionLabels[product.movingDecision!] ??
        product.movingDecision!;
  }

  IconData _getMovingDecisionIcon() {
    switch (product.movingDecision) {
      case 'keep':
        return Icons.home;
      case 'parents_home':
        return Icons.family_restroom;
      case 'discard':
        return Icons.delete;
      case 'sell':
        return Icons.attach_money;
      default:
        return Icons.help;
    }
  }

  Color _getMovingDecisionColor() {
    switch (product.movingDecision) {
      case 'keep':
        return Colors.green[600]!;
      case 'parents_home':
        return Colors.brown[600]!;
      case 'discard':
        return Colors.red[600]!;
      case 'sell':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
  }
}
