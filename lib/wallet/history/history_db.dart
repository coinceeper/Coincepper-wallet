import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/transaction.dart' as app_tx;

class HistoryDb {
  HistoryDb._();
  static final HistoryDb instance = HistoryDb._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final base = await getDatabasesPath();
    _db = await openDatabase(
      join(base, 'coinceeper_tx_history.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            tx_hash TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            from_addr TEXT,
            to_addr TEXT,
            amount TEXT,
            token_symbol TEXT,
            direction TEXT,
            status TEXT,
            timestamp TEXT,
            blockchain_name TEXT,
            raw_json TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_tx_user ON transactions(user_id, timestamp DESC)',
        );
      },
    );
    return _db!;
  }

  Future<void> upsertMany(String userId, List<app_tx.Transaction> txs) async {
    final db = await database;
    final batch = db.batch();
    for (final tx in txs) {
      batch.insert(
        'transactions',
        {
          'tx_hash': tx.txHash.isEmpty ? '${tx.timestamp}_${tx.amount}' : tx.txHash,
          'user_id': userId,
          'from_addr': tx.from,
          'to_addr': tx.to,
          'amount': tx.amount,
          'token_symbol': tx.tokenSymbol,
          'direction': tx.direction,
          'status': tx.status,
          'timestamp': tx.timestamp,
          'blockchain_name': tx.blockchainName,
          'raw_json': tx.toJson().toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<app_tx.Transaction>> loadForUser(String userId, {String? tokenSymbol}) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: 500,
    );
    final list = rows.map(_rowToTx).toList();
    if (tokenSymbol == null || tokenSymbol.isEmpty) return list;
    return list
        .where((t) => t.tokenSymbol.toUpperCase() == tokenSymbol.toUpperCase())
        .toList();
  }

  app_tx.Transaction _rowToTx(Map<String, Object?> row) {
    return app_tx.Transaction(
      txHash: row['tx_hash'] as String? ?? '',
      from: row['from_addr'] as String? ?? '',
      to: row['to_addr'] as String? ?? '',
      amount: row['amount'] as String? ?? '0',
      tokenSymbol: row['token_symbol'] as String? ?? '',
      direction: row['direction'] as String? ?? 'unknown',
      status: row['status'] as String? ?? 'completed',
      timestamp: row['timestamp'] as String? ?? '',
      blockchainName: row['blockchain_name'] as String? ?? '',
    );
  }
}
