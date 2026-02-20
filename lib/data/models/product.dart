class Product {
  final int? id;
  final String barcode;
  final String name;
  final String category;
  final double? price;
  final String? description;
  final String? imageUrl;
  final String? brand;
  final DateTime createdAt;
  final DateTime updatedAt;

  // AI Analysis Results
  final String? movingDecision; // 'keep', 'discard', 'sell'
  final String? storageLocation; // AI suggested storage location
  final String? analysisNotes; // AI analysis notes
  final double? aiConfidence; // AI confidence score (0-1)

  // Inventory Management
  final int quantity;
  final String? location; // Current physical location
  final bool isScanned;
  final String? notes; // User notes

  const Product({
    this.id,
    required this.barcode,
    required this.name,
    required this.category,
    this.price,
    this.description,
    this.imageUrl,
    this.brand,
    required this.createdAt,
    required this.updatedAt,
    this.movingDecision,
    this.storageLocation,
    this.analysisNotes,
    this.aiConfidence,
    this.quantity = 1,
    this.location,
    this.isScanned = true,
    this.notes,
  });

  Product copyWith({
    int? id,
    String? barcode,
    String? name,
    String? category,
    double? price,
    String? description,
    String? imageUrl,
    String? brand,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? movingDecision,
    String? storageLocation,
    String? analysisNotes,
    double? aiConfidence,
    int? quantity,
    String? location,
    bool? isScanned,
    String? notes,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      brand: brand ?? this.brand,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      movingDecision: movingDecision ?? this.movingDecision,
      storageLocation: storageLocation ?? this.storageLocation,
      analysisNotes: analysisNotes ?? this.analysisNotes,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      quantity: quantity ?? this.quantity,
      location: location ?? this.location,
      isScanned: isScanned ?? this.isScanned,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'category': category,
      'price': price,
      'description': description,
      'imageUrl': imageUrl,
      'brand': brand,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'movingDecision': movingDecision,
      'storageLocation': storageLocation,
      'analysisNotes': analysisNotes,
      'aiConfidence': aiConfidence,
      'quantity': quantity,
      'location': location,
      'isScanned': isScanned ? 1 : 0,
      'notes': notes,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toInt(),
      barcode: map['barcode'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      price: map['price']?.toDouble(),
      description: map['description'],
      imageUrl: map['imageUrl'],
      brand: map['brand'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt']),
      movingDecision: map['movingDecision'],
      storageLocation: map['storageLocation'],
      analysisNotes: map['analysisNotes'],
      aiConfidence: map['aiConfidence']?.toDouble(),
      quantity: map['quantity']?.toInt() ?? 1,
      location: map['location'],
      isScanned: map['isScanned'] == 1,
      notes: map['notes'],
    );
  }

  @override
  String toString() {
    return 'Product{id: $id, name: $name, barcode: $barcode, category: $category, movingDecision: $movingDecision}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          barcode == other.barcode;

  @override
  int get hashCode => id.hashCode ^ barcode.hashCode;

  // Helper methods
  bool get hasAiAnalysis => movingDecision != null;
  bool get shouldKeep => movingDecision == 'keep';
  bool get shouldStoreAtParents => movingDecision == 'parents_home';
  bool get shouldDiscard => movingDecision == 'discard';
  bool get shouldSell => movingDecision == 'sell';

  String get displayPrice =>
      price != null ? '¥${price!.toStringAsFixed(0)}' : '価格不明';
  String get statusText => hasAiAnalysis ? movingDecision! : '分析中';
}
