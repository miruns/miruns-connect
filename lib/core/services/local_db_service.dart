import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/body_blog_entry.dart';
import '../models/body_blog_version.dart';
import '../models/capture_entry.dart';
import '../models/nutrition_log.dart';
import 'ble_source_provider.dart';

/// Snapshot of database metadata for the debug panel.
class DbInfo {
  final String path;
  final int schemaVersion;
  final int entryCount;
  final int captureCount;
  final String? oldestDate;
  final String? newestDate;

  const DbInfo({
    required this.path,
    required this.schemaVersion,
    required this.entryCount,
    this.captureCount = 0,
    this.oldestDate,
    this.newestDate,
  });
}

/// SQLite persistence layer for [BodyBlogEntry] and [CaptureEntry] records.
///
/// One row per calendar day (PK = ISO date string "yyyy-MM-dd") for body blog entries.
/// One row per capture (PK = capture ID) for captures.
/// Callers never interact with raw SQL — use the typed helpers below.
class LocalDbService {
  static const _dbName = 'miruns.db';
  static const _tableEntries = 'entries';
  static const _tableSettings = 'settings';
  static const _tableCaptures = 'captures';
  static const _tableVersions = 'body_blog_versions';
  static const _tableNutritionLogs = 'nutrition_logs';
  static const _schemaVersion = 13;

  /// All capture columns EXCEPT signal_session.
  /// Prevents Android CursorWindow overflow for rows with large signal data.
  static const _captureColumnsLight = [
    'id',
    'timestamp',
    'is_processed',
    'user_note',
    'user_mood',
    'tags',
    'health_data',
    'environment_data',
    'location_data',
    'calendar_events',
    'processed_at',
    'ai_insights',
    'source',
    'trigger',
    'execution_duration_ms',
    'errors',
    'battery_level',
    'ai_metadata',
    'ble_hr_session',
    'nutrition_data',
    'sync_status',
    'share_code',
  ];

  Database? _db;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    return openDatabase(
      fullPath,
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableEntries (
        date         TEXT    PRIMARY KEY,
        headline     TEXT    NOT NULL,
        summary      TEXT    NOT NULL,
        full_body    TEXT    NOT NULL,
        mood         TEXT    NOT NULL,
        mood_emoji   TEXT    NOT NULL,
        tags         TEXT    NOT NULL DEFAULT '[]',
        user_note    TEXT,
        user_mood    TEXT,
        snapshot     TEXT    NOT NULL DEFAULT '{}',
        ai_generated INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE $_tableSettings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_tableCaptures (
        id               TEXT    PRIMARY KEY,
        timestamp        TEXT    NOT NULL,
        is_processed     INTEGER NOT NULL DEFAULT 0,
        user_note        TEXT,
        user_mood        TEXT,
        tags             TEXT    NOT NULL DEFAULT '[]',
        health_data      TEXT,
        environment_data TEXT,
        location_data    TEXT,
        calendar_events  TEXT    NOT NULL DEFAULT '[]',
        processed_at     TEXT,
        ai_insights      TEXT,
        source           TEXT    NOT NULL DEFAULT 'manual',
        trigger          TEXT,
        execution_duration_ms INTEGER,
        errors           TEXT    NOT NULL DEFAULT '[]',
        battery_level    INTEGER,
        ai_metadata      TEXT,
        ble_hr_session   TEXT,
        nutrition_data   TEXT,
        signal_session   TEXT,
        sync_status      TEXT    NOT NULL DEFAULT 'none',
        share_code       TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_captures_timestamp ON $_tableCaptures(timestamp DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_captures_processed ON $_tableCaptures(is_processed)
    ''');
    await db.execute('''
      CREATE TABLE $_tableVersions (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        date         TEXT    NOT NULL,
        generated_at TEXT    NOT NULL,
        trigger      TEXT    NOT NULL,
        headline     TEXT    NOT NULL,
        summary      TEXT    NOT NULL,
        full_body    TEXT    NOT NULL,
        mood         TEXT    NOT NULL,
        mood_emoji   TEXT    NOT NULL,
        tags         TEXT    NOT NULL DEFAULT '[]',
        ai_generated INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_versions_date ON $_tableVersions(date DESC)
    ''');
    await db.execute('''
      CREATE TABLE $_tableNutritionLogs (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        capture_id   TEXT,
        barcode      TEXT    NOT NULL,
        product_name TEXT    NOT NULL,
        brand        TEXT,
        nutri_score  TEXT,
        nova_group   INTEGER,
        per_100g     TEXT,
        serving_size TEXT,
        per_serving  TEXT,
        image_url    TEXT,
        scanned_at   TEXT    NOT NULL,
        quantity_note TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_nutrition_scanned ON $_tableNutritionLogs(scanned_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_nutrition_capture ON $_tableNutritionLogs(capture_id)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: add settings table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableSettings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      // v2 → v3: add user_mood column
      // Guard against duplicate-column errors if the column was already
      // present from a partially-applied migration or a hot-restart.
      try {
        await db.execute(
          'ALTER TABLE $_tableEntries ADD COLUMN user_mood TEXT',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
    if (oldVersion < 4) {
      // v3 → v4: add captures table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableCaptures (
          id               TEXT    PRIMARY KEY,
          timestamp        TEXT    NOT NULL,
          is_processed     INTEGER NOT NULL DEFAULT 0,
          user_note        TEXT,
          user_mood        TEXT,
          tags             TEXT    NOT NULL DEFAULT '[]',
          health_data      TEXT,
          environment_data TEXT,
          location_data    TEXT,
          calendar_events  TEXT    NOT NULL DEFAULT '[]',
          processed_at     TEXT,
          ai_insights      TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_captures_timestamp 
        ON $_tableCaptures(timestamp DESC)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_captures_processed 
        ON $_tableCaptures(is_processed)
      ''');
    }
    if (oldVersion < 5) {
      // v4 → v5: add background capture metadata columns
      final newCols = {
        'source': "TEXT NOT NULL DEFAULT 'manual'",
        'trigger': 'TEXT',
        'execution_duration_ms': 'INTEGER',
        'errors': "TEXT NOT NULL DEFAULT '[]'",
        'battery_level': 'INTEGER',
      };
      for (final entry in newCols.entries) {
        try {
          await db.execute(
            'ALTER TABLE $_tableCaptures ADD COLUMN ${entry.key} ${entry.value}',
          );
        } catch (e) {
          if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
        }
      }
    }
    if (oldVersion < 6) {
      // v5 → v6: add ai_generated column to entries table
      try {
        await db.execute(
          'ALTER TABLE $_tableEntries ADD COLUMN ai_generated INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
    if (oldVersion < 7) {
      // v6 → v7: add AI metadata column to captures table
      try {
        await db.execute(
          'ALTER TABLE $_tableCaptures ADD COLUMN ai_metadata TEXT',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
    if (oldVersion < 8) {
      // v7 → v8: add immutable version-history table for body blog entries

      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableVersions (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          date         TEXT    NOT NULL,
          generated_at TEXT    NOT NULL,
          trigger      TEXT    NOT NULL,
          headline     TEXT    NOT NULL,
          summary      TEXT    NOT NULL,
          full_body    TEXT    NOT NULL,
          mood         TEXT    NOT NULL,
          mood_emoji   TEXT    NOT NULL,
          tags         TEXT    NOT NULL DEFAULT '[]',
          ai_generated INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_versions_date
        ON $_tableVersions(date DESC)
      ''');
    }
    if (oldVersion < 9) {
      // v8 → v9: add BLE HR session column to captures
      try {
        await db.execute(
          'ALTER TABLE $_tableCaptures ADD COLUMN ble_hr_session TEXT',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
    if (oldVersion < 10) {
      // v9 → v10: add nutrition_data column to captures + nutrition_logs table
      try {
        await db.execute(
          'ALTER TABLE $_tableCaptures ADD COLUMN nutrition_data TEXT',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableNutritionLogs (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          capture_id   TEXT,
          barcode      TEXT    NOT NULL,
          product_name TEXT    NOT NULL,
          brand        TEXT,
          nutri_score  TEXT,
          nova_group   INTEGER,
          per_100g     TEXT,
          serving_size TEXT,
          per_serving  TEXT,
          image_url    TEXT,
          scanned_at   TEXT    NOT NULL,
          quantity_note TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_nutrition_scanned
        ON $_tableNutritionLogs(scanned_at DESC)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_nutrition_capture
        ON $_tableNutritionLogs(capture_id)
      ''');
    }
    if (oldVersion < 11) {
      // v10 → v11: add signal_session column to captures
      try {
        await db.execute(
          'ALTER TABLE $_tableCaptures ADD COLUMN signal_session TEXT',
        );
      } catch (e) {
        if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
      }
    }
    if (oldVersion < 12) {
      // v11 → v12: signal data now stored in external files.
      // Actual data migration happens lazily on first DB access
      // (see _migrateSignalDataLazily) to avoid CursorWindow issues
      // inside the onUpgrade transaction.
    }
    if (oldVersion < 13) {
      // v12 → v13: miruns-link sync columns
      for (final col in {
        'sync_status': "TEXT NOT NULL DEFAULT 'none'",
        'share_code': 'TEXT',
      }.entries) {
        try {
          await db.execute(
            'ALTER TABLE $_tableCaptures ADD COLUMN ${col.key} ${col.value}',
          );
        } catch (e) {
          if (!e.toString().toLowerCase().contains('duplicate column')) rethrow;
        }
      }
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── signal file helpers ───────────────────────────────────────────────────

  /// Directory for signal session files, created lazily.
  Future<Directory> _signalDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'signals'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Write signal session JSON to an external file.
  Future<void> _writeSignalFile(String captureId, String json) async {
    final dir = await _signalDir();
    final file = File(p.join(dir.path, '$captureId.json'));
    await file.writeAsString(json);
  }

  /// Delete the signal file for a capture (no-op if absent).
  Future<void> _deleteSignalFile(String captureId) async {
    final dir = await _signalDir();
    final file = File(p.join(dir.path, '$captureId.json'));
    if (await file.exists()) await file.delete();
  }

  /// Read the raw JSON string from the signal file for a capture.
  /// Returns null if the file doesn't exist.
  Future<String?> readSignalFileRaw(String captureId) async {
    final dir = await _signalDir();
    final file = File(p.join(dir.path, '$captureId.json'));
    if (await file.exists()) return file.readAsString();
    return null;
  }

  /// Load the full signal session for a capture.
  ///
  /// Tries the external file first (new format). Falls back to reading the
  /// DB column via SUBSTR chunks for pre-migration data, writing a file for
  /// next time.
  Future<SignalSession?> loadSignalSessionFromFile(String captureId) async {
    // 1. Try external file.
    final dir = await _signalDir();
    final file = File(p.join(dir.path, '$captureId.json'));
    if (await file.exists()) {
      final raw = await file.readAsString();
      return SignalSession.decode(raw);
    }

    // 2. Fallback: read from DB via SUBSTR chunks (CursorWindow-safe).
    final db = await _database;
    final lenResult = await db.rawQuery(
      'SELECT LENGTH(signal_session) as len FROM $_tableCaptures WHERE id = ?',
      [captureId],
    );
    final len = lenResult.firstOrNull?['len'] as int?;
    if (len == null || len == 0) return null;

    final buffer = StringBuffer();
    int offset = 1; // SUBSTR is 1-indexed
    const chunkSize = 900000;
    while (true) {
      final rows = await db.rawQuery(
        'SELECT SUBSTR(signal_session, ?, ?) as chunk '
        'FROM $_tableCaptures WHERE id = ?',
        [offset, chunkSize, captureId],
      );
      final chunk = rows.first['chunk'] as String?;
      if (chunk == null || chunk.isEmpty) break;
      buffer.write(chunk);
      if (chunk.length < chunkSize) break;
      offset += chunkSize;
    }

    final fullJson = buffer.toString();
    if (fullJson.isEmpty) return null;

    final session = SignalSession.decode(fullJson);
    if (session != null) {
      // Write to file so next load is instant & update DB to compact meta.
      try {
        await file.writeAsString(fullJson);
        await db.update(
          _tableCaptures,
          {'signal_session': session.encodeMeta()},
          where: 'id = ?',
          whereArgs: [captureId],
        );
      } catch (_) {}
    }
    return session;
  }

  /// Lazily migrate old signal_session data to external files.
  ///
  /// Call once after the DB is open (outside onUpgrade). Safe to call
  /// multiple times — already-migrated rows are skipped.
  Future<void> migrateSignalDataLazily() async {
    final db = await _database;
    // Find rows where signal_session is large (not yet migrated to meta).
    // Meta format is < 2000 chars; full format is typically > 100 000.
    final ids = await db.rawQuery(
      'SELECT id FROM $_tableCaptures '
      'WHERE signal_session IS NOT NULL AND LENGTH(signal_session) > 3000',
    );
    if (ids.isEmpty) return;
    debugPrint('[DB] Lazy-migrating ${ids.length} signal sessions to files...');

    for (final row in ids) {
      final captureId = row['id'] as String;
      try {
        await loadSignalSessionFromFile(captureId);
      } catch (e) {
        debugPrint('[DB] Lazy-migrate failed for $captureId: $e');
      }
    }
    debugPrint('[DB] Lazy migration complete.');
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// "yyyy-MM-dd" key used as primary key.
  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> _toRow(BodyBlogEntry e) {
    final json = e.toJson();
    // toJson already encodes date as ISO string; convert to date-only key
    return {
      'date': _dateKey(e.date),
      'headline': json['headline'],
      'summary': json['summary'],
      'full_body': json['full_body'],
      'mood': json['mood'],
      'mood_emoji': json['mood_emoji'],
      'ai_generated': json['ai_generated'],
      'tags': json['tags'],
      'user_note': json['user_note'],
      'user_mood': json['user_mood'],
      'snapshot': json['snapshot'],
    };
  }

  static BodyBlogEntry _fromRow(Map<String, dynamic> row) {
    return BodyBlogEntry.fromJson({
      ...row,
      // fromJson expects ISO8601 date
      'date': '${row['date']}T00:00:00.000',
    });
  }

  // ── public API ────────────────────────────────────────────────────────────

  /// Insert or replace an entry (upsert by date).
  Future<void> saveEntry(BodyBlogEntry entry) async {
    final db = await _database;
    await db.insert(
      _tableEntries,
      _toRow(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Append an immutable version snapshot for [entry] to the history table.
  ///
  /// The [trigger] should be one of the [BlogVersionTrigger] constants.
  /// This is a pure INSERT — existing rows are never modified or deleted.
  Future<void> appendVersion(BodyBlogEntry entry, String trigger) async {
    final db = await _database;
    await db.insert(_tableVersions, {
      'date': _dateKey(entry.date),
      'generated_at': DateTime.now().toIso8601String(),
      'trigger': trigger,
      'headline': entry.headline,
      'summary': entry.summary,
      'full_body': entry.fullBody,
      'mood': entry.mood,
      'mood_emoji': entry.moodEmoji,
      'tags': entry.toJson()['tags'],
      'ai_generated': entry.aiGenerated ? 1 : 0,
    });
  }

  /// Load all version snapshots for [date], newest first.
  Future<List<BodyBlogVersion>> loadVersionsForDate(DateTime date) async {
    final db = await _database;
    final rows = await db.query(
      _tableVersions,
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
      orderBy: 'generated_at DESC',
    );
    return rows.map(BodyBlogVersion.fromJson).toList();
  }

  /// Load entry for a specific date, or `null` if not stored yet.
  Future<BodyBlogEntry?> loadEntry(DateTime date) async {
    final db = await _database;
    final rows = await db.query(
      _tableEntries,
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Load all stored entries between [from] and [to] (inclusive), newest first.
  Future<List<BodyBlogEntry>> loadEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    final db = await _database;
    final rows = await db.query(
      _tableEntries,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [_dateKey(from), _dateKey(to)],
      orderBy: 'date DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Overwrite only the `user_note` and `user_mood` columns for a given date.
  /// Returns the updated entry, or `null` if the date does not exist.
  Future<BodyBlogEntry?> updateUserNote(
    DateTime date,
    String? note, {
    String? mood,
  }) async {
    final db = await _database;
    final count = await db.update(
      _tableEntries,
      {'user_note': note, 'user_mood': mood},
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
    );
    if (count == 0) return null;
    return loadEntry(date);
  }

  /// Returns true when at least one journal entry exists in the database.
  /// Used to detect a first-time install vs a returning user.
  Future<bool> hasAnyEntries() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableEntries LIMIT 1',
    );
    return (result.first['count'] as int? ?? 0) > 0;
  }

  /// Delete the persisted entry for [date] (no-op if absent).
  Future<void> deleteEntry(DateTime date) async {
    final db = await _database;
    await db.delete(
      _tableEntries,
      where: 'date = ?',
      whereArgs: [_dateKey(date)],
    );
  }

  /// Total number of stored entries.
  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableEntries',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Load the [n] most-recent entries, newest first.
  Future<List<BodyBlogEntry>> loadRecentEntries(int n) async {
    final db = await _database;
    final rows = await db.query(_tableEntries, orderBy: 'date DESC', limit: n);
    return rows.map(_fromRow).toList();
  }

  /// Filesystem path of the database file (useful for debug).
  Future<String> getDatabasePath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, _dbName);
  }

  /// Aggregate information about the database, used by the debug panel.
  Future<DbInfo> getDbInfo() async {
    final db = await _database;
    final entryCount =
        (await db.rawQuery(
              'SELECT COUNT(*) as c FROM $_tableEntries',
            )).first['c']
            as int? ??
        0;
    final captureCount =
        (await db.rawQuery(
              'SELECT COUNT(*) as c FROM $_tableCaptures',
            )).first['c']
            as int? ??
        0;
    final oldest =
        (await db.query(
              _tableEntries,
              orderBy: 'date ASC',
              limit: 1,
            )).firstOrNull?['date']
            as String?;
    final newest =
        (await db.query(
              _tableEntries,
              orderBy: 'date DESC',
              limit: 1,
            )).firstOrNull?['date']
            as String?;
    final dbPath = await getDatabasePath();
    return DbInfo(
      path: dbPath,
      schemaVersion: _schemaVersion,
      entryCount: entryCount,
      captureCount: captureCount,
      oldestDate: oldest,
      newestDate: newest,
    );
  }

  // ── settings ──────────────────────────────────────────────────────────────

  /// Persist an app-level setting.
  Future<void> setSetting(String key, String value) async {
    final db = await _database;
    await db.insert(_tableSettings, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retrieve a previously persisted setting, or `null` if not set.
  Future<String?> getSetting(String key) async {
    final db = await _database;
    final rows = await db.query(
      _tableSettings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  // ── debug ─────────────────────────────────────────────────────────────────

  /// Raw rows for the debug inspector — returns lightweight maps
  /// (excludes the large full_body and snapshot JSON columns).
  Future<List<Map<String, Object?>>> getDebugRows() async {
    final db = await _database;
    return db.query(
      _tableEntries,
      columns: ['date', 'mood', 'mood_emoji', 'tags', 'user_note', 'user_mood'],
      orderBy: 'date DESC',
    );
  }

  // ── captures ──────────────────────────────────────────────────────────────

  /// Save a capture entry (insert or replace).
  ///
  /// When the capture contains a [SignalSession], the full sample data is
  /// written to an external file and only compact metadata is stored in the
  /// DB column to stay within Android's 2 MB CursorWindow limit.
  Future<void> saveCapture(CaptureEntry capture) async {
    final db = await _database;
    final row = capture.toJson();

    if (capture.signalSession != null) {
      // Write full data to file and store only metadata in DB.
      final fullJson = await capture.signalSession!.encodeAsync();
      await _writeSignalFile(capture.id, fullJson);
      row['signal_session'] = capture.signalSession!.encodeMeta();
      await db.insert(
        _tableCaptures,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      // Use UPDATE to preserve existing signal_session column
      // (ConflictAlgorithm.replace does DELETE+INSERT which would wipe it).
      row.remove('signal_session');
      final count = await db.update(
        _tableCaptures,
        row,
        where: 'id = ?',
        whereArgs: [capture.id],
      );
      if (count == 0) {
        await db.insert(_tableCaptures, row);
      }
    }
  }

  /// Load a specific capture by ID (excludes signal_session to avoid
  /// CursorWindow overflow — use [loadSignalSessionFromFile] for signal data).
  Future<CaptureEntry?> loadCapture(String id) async {
    final db = await _database;
    final rows = await db.query(
      _tableCaptures,
      columns: _captureColumnsLight,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CaptureEntry.fromJson(rows.first);
  }

  /// Load captures, optionally filtered by processed status.
  /// Results are ordered by timestamp descending (newest first).
  Future<List<CaptureEntry>> loadCaptures({
    bool? isProcessed,
    int? limit,
  }) async {
    final db = await _database;

    String? where;
    List<Object?>? whereArgs;

    if (isProcessed != null) {
      where = 'is_processed = ?';
      whereArgs = [isProcessed ? 1 : 0];
    }

    final rows = await db.query(
      _tableCaptures,
      columns: _captureColumnsLight,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map((row) => CaptureEntry.fromJson(row)).toList();
  }

  /// Load all captures for a specific calendar date, ordered by timestamp ASC.
  ///
  /// Uses SQLite's `date()` function to match on the local calendar date
  /// of the stored ISO-8601 timestamp.
  Future<List<CaptureEntry>> loadCapturesForDate(DateTime date) async {
    final db = await _database;
    final dateStr = _dateKey(date);
    final rows = await db.query(
      _tableCaptures,
      columns: _captureColumnsLight,
      where: "date(timestamp) = ?",
      whereArgs: [dateStr],
      orderBy: 'timestamp ASC',
    );
    return rows.map((row) => CaptureEntry.fromJson(row)).toList();
  }

  /// Update only the [ai_metadata] column for an existing capture.
  ///
  /// More efficient than loading + re-saving a full [CaptureEntry] when the
  /// only thing that changed is the AI metadata.

  /// Update sync status and optional share code for a capture.
  Future<void> updateSyncStatus(
    String captureId,
    String syncStatus, {
    String? shareCode,
  }) async {
    final db = await _database;
    final values = <String, dynamic>{'sync_status': syncStatus};
    if (shareCode != null) values['share_code'] = shareCode;
    await db.update(
      _tableCaptures,
      values,
      where: 'id = ?',
      whereArgs: [captureId],
    );
  }

  /// Look up the share code for a capture, or null if never synced.
  Future<String?> getShareCode(String captureId) async {
    final db = await _database;
    final rows = await db.query(
      _tableCaptures,
      columns: ['share_code'],
      where: 'id = ?',
      whereArgs: [captureId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['share_code'] as String?;
  }

  /// Load sync_status for a capture.
  Future<String> getSyncStatus(String captureId) async {
    final db = await _database;
    final rows = await db.query(
      _tableCaptures,
      columns: ['sync_status'],
      where: 'id = ?',
      whereArgs: [captureId],
      limit: 1,
    );
    if (rows.isEmpty) return 'none';
    return (rows.first['sync_status'] as String?) ?? 'none';
  }

  Future<void> updateCaptureAiMetadata(
    String captureId,
    String aiMetadataJson,
  ) async {
    final db = await _database;
    await db.update(
      _tableCaptures,
      {'ai_metadata': aiMetadataJson},
      where: 'id = ?',
      whereArgs: [captureId],
    );
  }

  /// Delete a capture by ID (also removes the external signal file).
  Future<void> deleteCapture(String id) async {
    final db = await _database;
    await db.delete(_tableCaptures, where: 'id = ?', whereArgs: [id]);
    await _deleteSignalFile(id);
  }

  /// Load captures that have a signal session (EEG recordings).
  /// Results are ordered by timestamp descending (newest first).
  ///
  /// Uses SUBSTR to read only the first 2000 chars of signal_session,
  /// which is enough for compact metadata and safely under the 2 MB
  /// CursorWindow limit even for old un-migrated data.
  Future<List<CaptureEntry>> loadSignalSessions({int? limit}) async {
    final db = await _database;
    final cols = _captureColumnsLight.join(', ');
    final sql =
        'SELECT $cols, SUBSTR(signal_session, 1, 2000) as signal_session '
        'FROM $_tableCaptures '
        'WHERE signal_session IS NOT NULL '
        'ORDER BY timestamp DESC'
        '${limit != null ? ' LIMIT $limit' : ''}';
    final rows = await db.rawQuery(sql);
    return rows.map((row) => CaptureEntry.fromJson(row)).toList();
  }

  /// Get count of captures that have signal sessions.
  Future<int> countSignalSessions() async {
    final db = await _database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_tableCaptures WHERE signal_session IS NOT NULL',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get count of captures, optionally filtered by processed status.
  Future<int> countCaptures({bool? isProcessed}) async {
    final db = await _database;

    String? where;
    List<Object?>? whereArgs;

    if (isProcessed != null) {
      where = 'is_processed = ?';
      whereArgs = [isProcessed ? 1 : 0];
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableCaptures${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Load only **unprocessed** captures for a specific calendar date.
  ///
  /// These are captures that have not yet been consumed by the AI journal
  /// generation pipeline.
  Future<List<CaptureEntry>> loadUnprocessedCapturesForDate(
    DateTime date,
  ) async {
    final db = await _database;
    final dateStr = _dateKey(date);
    final rows = await db.query(
      _tableCaptures,
      columns: _captureColumnsLight,
      where: "date(timestamp) = ? AND is_processed = 0",
      whereArgs: [dateStr],
      orderBy: 'timestamp ASC',
    );
    return rows.map((row) => CaptureEntry.fromJson(row)).toList();
  }

  /// Mark a list of captures as processed by setting `is_processed = 1`
  /// and `processed_at` to the current time.
  ///
  /// Called after the AI successfully uses these captures to generate
  /// or update a journal entry.
  Future<void> markCapturesProcessed(List<String> captureIds) async {
    if (captureIds.isEmpty) return;
    final db = await _database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final id in captureIds) {
      batch.update(
        _tableCaptures,
        {'is_processed': 1, 'processed_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  // ── nutrition logs ──────────────────────────────────────────────────────────────

  Future<void> saveNutritionLog(NutritionLog log, {String? captureId}) async {
    final db = await _database;
    await db.insert(_tableNutritionLogs, {
      'capture_id': captureId,
      'barcode': log.barcode,
      'product_name': log.productName,
      'brand': log.brand,
      'nutri_score': log.nutriScore,
      'nova_group': log.novaGroup,
      'per_100g': log.per100g != null
          ? jsonEncode(log.per100g!.toJson())
          : null,
      'serving_size': log.servingSize,
      'per_serving': log.perServing != null
          ? jsonEncode(log.perServing!.toJson())
          : null,
      'image_url': log.imageUrl,
      'scanned_at': log.scannedAt.toIso8601String(),
      'quantity_note': log.quantityNote,
    });
  }

  Future<List<NutritionLog>> loadNutritionLogsForCapture(
    String captureId,
  ) async {
    final db = await _database;
    final rows = await db.query(
      _tableNutritionLogs,
      where: 'capture_id = ?',
      whereArgs: [captureId],
      orderBy: 'scanned_at DESC',
    );
    return rows.map(_nutritionLogFromRow).toList();
  }

  Future<List<NutritionLog>> loadRecentNutritionLogs({int limit = 20}) async {
    final db = await _database;
    final rows = await db.query(
      _tableNutritionLogs,
      orderBy: 'scanned_at DESC',
      limit: limit,
    );
    return rows.map(_nutritionLogFromRow).toList();
  }

  NutritionLog _nutritionLogFromRow(Map<String, dynamic> row) {
    return NutritionLog(
      barcode: row['barcode'] as String,
      productName: row['product_name'] as String? ?? 'Unknown',
      brand: row['brand'] as String?,
      nutriScore: row['nutri_score'] as String?,
      novaGroup: row['nova_group'] as int?,
      per100g: row['per_100g'] != null
          ? NutritionFacts.fromJson(
              jsonDecode(row['per_100g'] as String) as Map<String, dynamic>,
            )
          : null,
      servingSize: row['serving_size'] as String?,
      perServing: row['per_serving'] != null
          ? NutritionFacts.fromJson(
              jsonDecode(row['per_serving'] as String) as Map<String, dynamic>,
            )
          : null,
      imageUrl: row['image_url'] as String?,
      scannedAt: DateTime.parse(row['scanned_at'] as String),
      quantityNote: row['quantity_note'] as String?,
    );
  }
}
