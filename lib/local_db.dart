import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDB {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'bloominous_local.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        // Table for inventory
        await db.execute('''
          CREATE TABLE inventory (
            id TEXT PRIMARY KEY,
            name TEXT,
            code TEXT,
            price REAL,
            stock INTEGER,
            category TEXT,
            model TEXT,
            image TEXT,
            branchId TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');

        // Table for orders
        await db.execute('''
          CREATE TABLE orders (
            id TEXT PRIMARY KEY,
            userId TEXT,
            customerEmail TEXT,
            customerName TEXT,
            items TEXT,
            totalAmount REAL,
            subtotal REAL,
            deliveryFee REAL,
            distanceKm REAL,
            deliveryAddress TEXT,
            recipientName TEXT,
            recipientPhone TEXT,
            deliveryNotes TEXT,
            orderType TEXT,
            occasion TEXT,
            paymentMethod TEXT,
            paymentStatus TEXT,
            checkoutUrl TEXT,
            status TEXT,
            createdAt TEXT,
            branchId TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');

        // Table for spoilage
        await db.execute('''
          CREATE TABLE spoilage (
            id TEXT PRIMARY KEY,
            product_id TEXT,
            flower_name TEXT,
            quantity INTEGER,
            loss_amount REAL,
            reason TEXT,
            reported_by TEXT,
            created_at TEXT,
            branchId TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');

        // Table for freshness analysis
        await db.execute('''
          CREATE TABLE freshness_analysis (
            id TEXT PRIMARY KEY,
            product_name TEXT,
            batch_code TEXT,
            freshness_score INTEGER,
            status TEXT,
            ai_recommendation TEXT,
            scanned_at TEXT,
            branchId TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Migration para sa mga delivery fields sa orders table
          final List<String> columns = [
            'customerName',
            'subtotal',
            'deliveryFee',
            'distanceKm',
            'deliveryAddress',
            'recipientName',
            'recipientPhone',
            'deliveryNotes',
            'occasion',
            'paymentMethod',
            'checkoutUrl'
          ];

          for (var column in columns) {
            try {
              await db.execute('ALTER TABLE orders ADD COLUMN $column TEXT');
            } catch (e) {
              // Ignore kung nage-exist na
            }
          }
        }

        if (oldVersion < 3) {
          // Migration para sa v3: Pagdagdag ng branchId columns sa lahat ng major tables
          final tables = [
            'inventory',
            'spoilage',
            'freshness_analysis',
            'orders'
          ];
          for (var table in tables) {
            try {
              await db.execute('ALTER TABLE $table ADD COLUMN branchId TEXT');
            } catch (e) {
              // Ignore kung nage-exist na
            }
          }
        }
      },
    );
  }

  // --- Generic Helpers para sa DB Operations ---
  static Future<void> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> query(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final db = await database;
    return await db.query(table, where: where, whereArgs: whereArgs);
  }

  static Future<void> update(
      String table, Map<String, dynamic> data, String id) async {
    final db = await database;
    await db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> delete(String table, String id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}
