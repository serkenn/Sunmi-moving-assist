import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../data/models/product.dart';
import '../constants/app_constants.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String path = join(
      await getDatabasesPath(),
      AppConstants.databaseName,
    );

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.productsTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        price REAL,
        description TEXT,
        imageUrl TEXT,
        brand TEXT,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        movingDecision TEXT,
        storageLocation TEXT,
        analysisNotes TEXT,
        aiConfidence REAL,
        quantity INTEGER NOT NULL DEFAULT 1,
        location TEXT,
        isScanned INTEGER NOT NULL DEFAULT 1,
        notes TEXT
      )
    ''');

    // Create index for better search performance
    await db.execute('''
      CREATE INDEX idx_products_barcode ON ${AppConstants.productsTable}(barcode)
    ''');

    await db.execute('''
      CREATE INDEX idx_products_name ON ${AppConstants.productsTable}(name)
    ''');

    await db.execute('''
      CREATE INDEX idx_products_category ON ${AppConstants.productsTable}(category)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here in future versions
    if (oldVersion < 2) {
      // Example upgrade logic for version 2
      // await db.execute('ALTER TABLE products ADD COLUMN newColumn TEXT');
    }
  }

  // Product CRUD Operations

  Future<int> insertProduct(Product product) async {
    final Database db = await database;

    try {
      return await db.insert(
        AppConstants.productsTable,
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw DatabaseException('Failed to insert product: $e');
    }
  }

  Future<Product?> getProductById(int id) async {
    final Database db = await database;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        AppConstants.productsTable,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return Product.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      throw DatabaseException('Failed to get product by id: $e');
    }
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final Database db = await database;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        AppConstants.productsTable,
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return Product.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      throw DatabaseException('Failed to get product by barcode: $e');
    }
  }

  Future<List<Product>> getAllProducts({
    String? category,
    String? searchQuery,
    String? movingDecision,
    int? limit,
    int? offset,
  }) async {
    final Database db = await database;

    try {
      String whereClause = '';
      List<dynamic> whereArgs = [];

      // Build where clause based on filters
      List<String> conditions = [];

      if (category != null && category.isNotEmpty) {
        conditions.add('category = ?');
        whereArgs.add(category);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        conditions.add('(name LIKE ? OR barcode LIKE ? OR description LIKE ?)');
        final searchPattern = '%$searchQuery%';
        whereArgs.addAll([searchPattern, searchPattern, searchPattern]);
      }

      if (movingDecision != null && movingDecision.isNotEmpty) {
        conditions.add('movingDecision = ?');
        whereArgs.add(movingDecision);
      }

      if (conditions.isNotEmpty) {
        whereClause = conditions.join(' AND ');
      }

      final List<Map<String, dynamic>> maps = await db.query(
        AppConstants.productsTable,
        where: whereClause.isNotEmpty ? whereClause : null,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'updatedAt DESC',
        limit: limit,
        offset: offset,
      );

      return maps.map((map) => Product.fromMap(map)).toList();
    } catch (e) {
      throw DatabaseException('Failed to get products: $e');
    }
  }

  Future<int> updateProduct(Product product) async {
    final Database db = await database;

    try {
      return await db.update(
        AppConstants.productsTable,
        product.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
    } catch (e) {
      throw DatabaseException('Failed to update product: $e');
    }
  }

  Future<int> deleteProduct(int id) async {
    final Database db = await database;

    try {
      return await db.delete(
        AppConstants.productsTable,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw DatabaseException('Failed to delete product: $e');
    }
  }

  Future<int> deleteAllProducts() async {
    final Database db = await database;

    try {
      return await db.delete(AppConstants.productsTable);
    } catch (e) {
      throw DatabaseException('Failed to delete all products: $e');
    }
  }

  // Statistics and Analytics

  Future<int> getProductCount({
    String? category,
    String? movingDecision,
  }) async {
    final Database db = await database;

    try {
      String whereClause = '';
      List<dynamic> whereArgs = [];

      List<String> conditions = [];

      if (category != null && category.isNotEmpty) {
        conditions.add('category = ?');
        whereArgs.add(category);
      }

      if (movingDecision != null && movingDecision.isNotEmpty) {
        conditions.add('movingDecision = ?');
        whereArgs.add(movingDecision);
      }

      if (conditions.isNotEmpty) {
        whereClause = 'WHERE ${conditions.join(' AND ')}';
      }

      final List<Map<String, dynamic>> result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM ${AppConstants.productsTable} $whereClause',
        whereArgs,
      );

      return result.first['count'] as int;
    } catch (e) {
      throw DatabaseException('Failed to get product count: $e');
    }
  }

  Future<Map<String, int>> getCategoryCounts() async {
    final Database db = await database;

    try {
      final List<Map<String, dynamic>> result = await db.rawQuery('''
        SELECT category, COUNT(*) as count
        FROM ${AppConstants.productsTable}
        GROUP BY category
        ORDER BY count DESC
      ''');

      final Map<String, int> counts = {};
      for (final row in result) {
        counts[row['category'] as String] = row['count'] as int;
      }

      return counts;
    } catch (e) {
      throw DatabaseException('Failed to get category counts: $e');
    }
  }

  Future<Map<String, int>> getMovingDecisionCounts() async {
    final Database db = await database;

    try {
      final List<Map<String, dynamic>> result = await db.rawQuery('''
        SELECT movingDecision, COUNT(*) as count
        FROM ${AppConstants.productsTable}
        WHERE movingDecision IS NOT NULL
        GROUP BY movingDecision
        ORDER BY count DESC
      ''');

      final Map<String, int> counts = {};
      for (final row in result) {
        counts[row['movingDecision'] as String] = row['count'] as int;
      }

      return counts;
    } catch (e) {
      throw DatabaseException('Failed to get moving decision counts: $e');
    }
  }

  // Batch operations

  Future<void> insertProductsBatch(List<Product> products) async {
    final Database db = await database;
    final Batch batch = db.batch();

    try {
      for (final product in products) {
        batch.insert(
          AppConstants.productsTable,
          product.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    } catch (e) {
      throw DatabaseException('Failed to insert products batch: $e');
    }
  }

  // Database utilities

  Future<void> closeDatabase() async {
    final Database db = await database;
    await db.close();
    _database = null;
  }

  Future<void> deleteDatabase() async {
    final String path = join(
      await getDatabasesPath(),
      AppConstants.databaseName,
    );
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }

  Future<bool> isDatabaseEmpty() async {
    final int count = await getProductCount();
    return count == 0;
  }
}

class DatabaseException implements Exception {
  final String message;

  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
