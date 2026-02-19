import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../models/category.dart';
import '../models/todo_item.dart';

class AppDatabaseException implements Exception {
  const AppDatabaseException(
    this.message, {
    this.isLocked = false,
    this.isMissing = false,
  });

  final String message;
  final bool isLocked;
  final bool isMissing;

  factory AppDatabaseException.missing(String path) {
    return AppDatabaseException(
      'Database file not found at $path',
      isMissing: true,
    );
  }

  factory AppDatabaseException.fromDatabaseException(
    DatabaseException exception,
  ) {
    final raw = exception.toString();
    final lower = raw.toLowerCase();
    if (lower.contains('database is locked') ||
        lower.contains('database table is locked')) {
      return AppDatabaseException(
        'The database is currently locked by another process.',
        isLocked: true,
      );
    }
    return AppDatabaseException(raw);
  }

  @override
  String toString() => message;
}

class AppDatabase {
  AppDatabase();

  static const String inboxName = 'Inbox';
  static const double orderStep = 1000.0;
  static final Uuid _uuid = const Uuid();

  Database? _db;
  String? _openedPath;
  bool _ffiInitialized = false;

  String? get openedPath => _openedPath;

  Future<void> openAtPath(String path, {required bool createIfMissing}) async {
    final file = File(path);
    if (!createIfMissing && !await file.exists()) {
      throw AppDatabaseException.missing(path);
    }

    if (createIfMissing && !await file.exists()) {
      await file.parent.create(recursive: true);
      await file.create();
    }

    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }

    if (_openedPath == path && _db != null) {
      return;
    }

    if (_db != null) {
      await _db!.close();
      _db = null;
    }

    try {
      _db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON;');
            await db.execute('PRAGMA journal_mode = WAL;');
          },
          onCreate: (db, _) async {
            await _createSchema(db);
            await _ensureInbox(db);
          },
          onOpen: (db) async {
            await _ensureInbox(db);
          },
        ),
      );
      _openedPath = path;
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE todos (
        id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        category_id TEXT NOT NULL REFERENCES categories(id),
        sort_order REAL NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('CREATE INDEX idx_todos_sort_order ON todos(sort_order);');
    await db.execute(
      'CREATE INDEX idx_todos_category_id ON todos(category_id);',
    );
    await db.execute(
      'CREATE INDEX idx_todos_completed_at ON todos(completed_at);',
    );
  }

  Future<void> _ensureInbox(DatabaseExecutor executor) async {
    final existing = await executor.query(
      'categories',
      where: 'LOWER(name) = ?',
      whereArgs: [inboxName.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await executor.insert('categories', {
      'id': _uuid.v4(),
      'name': inboxName,
      'created_at': now,
      'updated_at': now,
    });
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw const AppDatabaseException('Database has not been opened yet.');
    }
    return db;
  }

  Future<List<Category>> fetchCategories() async {
    try {
      final rows = await _database.query(
        'categories',
        orderBy: 'LOWER(name) ASC',
      );
      return rows.map(Category.fromMap).toList(growable: false);
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<List<TodoItem>> fetchVisibleTodos({
    String? categoryId,
    required int cutoffMs,
  }) async {
    try {
      final where = <String>[
        '(t.is_completed = 0 OR (t.is_completed = 1 AND t.completed_at > ?))',
      ];
      final whereArgs = <Object>[cutoffMs];

      if (categoryId != null) {
        where.add('t.category_id = ?');
        whereArgs.add(categoryId);
      }

      final rows = await _database.rawQuery('''
        SELECT
          t.id,
          t.text,
          t.category_id,
          t.sort_order,
          t.is_completed,
          t.completed_at,
          t.created_at,
          t.updated_at,
          c.name AS category_name
        FROM todos t
        JOIN categories c ON c.id = t.category_id
        WHERE ${where.join(' AND ')}
        ORDER BY t.sort_order DESC, t.created_at DESC
        ''', whereArgs);

      return rows.map(TodoItem.fromMap).toList(growable: false);
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<List<TodoItem>> fetchAllTodosOrdered() async {
    try {
      final rows = await _database.rawQuery('''
        SELECT
          t.id,
          t.text,
          t.category_id,
          t.sort_order,
          t.is_completed,
          t.completed_at,
          t.created_at,
          t.updated_at,
          c.name AS category_name
        FROM todos t
        JOIN categories c ON c.id = t.category_id
        ORDER BY t.sort_order DESC, t.created_at DESC
      ''');
      return rows.map(TodoItem.fromMap).toList(growable: false);
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<double> _nextTopSortOrder() async {
    final rows = await _database.rawQuery(
      'SELECT MAX(sort_order) AS top FROM todos;',
    );
    if (rows.isEmpty || rows.first['top'] == null) {
      return orderStep;
    }
    return (rows.first['top']! as num).toDouble() + orderStep;
  }

  Future<void> addTodo({
    required String text,
    required String categoryId,
  }) async {
    try {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final topSort = await _nextTopSortOrder();
      await _database.insert('todos', {
        'id': _uuid.v4(),
        'text': trimmed,
        'category_id': categoryId,
        'sort_order': topSort,
        'is_completed': 0,
        'completed_at': null,
        'created_at': now,
        'updated_at': now,
      });
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> updateTodoText(String todoId, String text) async {
    try {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _database.update(
        'todos',
        {'text': trimmed, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [todoId],
      );
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> updateTodoCategory(String todoId, String categoryId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _database.update(
        'todos',
        {'category_id': categoryId, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [todoId],
      );
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> setTodoCompletion(String todoId, bool isCompleted) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _database.update(
        'todos',
        {
          'is_completed': isCompleted ? 1 : 0,
          'completed_at': isCompleted ? now : null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [todoId],
      );
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> deleteTodo(String todoId) async {
    try {
      await _database.delete('todos', where: 'id = ?', whereArgs: [todoId]);
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> updateTodoSortOrder(String todoId, double sortOrder) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _database.update(
        'todos',
        {'sort_order': sortOrder, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [todoId],
      );
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> rebalanceInGlobalOrder(List<String> orderedTodoIds) async {
    if (orderedTodoIds.isEmpty) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _database.transaction((txn) async {
        for (var i = 0; i < orderedTodoIds.length; i++) {
          final sortOrder = (orderedTodoIds.length - i) * orderStep;
          await txn.update(
            'todos',
            {'sort_order': sortOrder, 'updated_at': now},
            where: 'id = ?',
            whereArgs: [orderedTodoIds[i]],
          );
        }
      });
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<Category> createCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AppDatabaseException('Category name cannot be empty.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final category = Category(
      id: _uuid.v4(),
      name: trimmed,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _database.insert('categories', {
        'id': category.id,
        'name': category.name,
        'created_at': category.createdAt,
        'updated_at': category.updatedAt,
      });
      return category;
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> renameCategory(String categoryId, String nextName) async {
    final trimmed = nextName.trim();
    if (trimmed.isEmpty) {
      throw const AppDatabaseException('Category name cannot be empty.');
    }

    final inbox = await fetchInboxCategory();
    if (inbox.id == categoryId) {
      throw const AppDatabaseException('Inbox cannot be renamed in v1.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _database.update(
        'categories',
        {'name': trimmed, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [categoryId],
      );
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> deleteCategoryAndMoveTodosToInbox(String categoryId) async {
    final inbox = await fetchInboxCategory();
    if (categoryId == inbox.id) {
      throw const AppDatabaseException('Inbox cannot be deleted.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _database.transaction((txn) async {
        await txn.update(
          'todos',
          {'category_id': inbox.id, 'updated_at': now},
          where: 'category_id = ?',
          whereArgs: [categoryId],
        );

        await txn.delete(
          'categories',
          where: 'id = ?',
          whereArgs: [categoryId],
        );
      });
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<Category> fetchInboxCategory() async {
    try {
      final rows = await _database.query(
        'categories',
        where: 'LOWER(name) = ?',
        whereArgs: [inboxName.toLowerCase()],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const AppDatabaseException('Inbox category is missing.');
      }
      return Category.fromMap(rows.first);
    } on DatabaseException catch (error) {
      throw AppDatabaseException.fromDatabaseException(error);
    }
  }

  Future<void> close() async {
    if (_db == null) {
      return;
    }
    await _db!.close();
    _db = null;
    _openedPath = null;
  }
}
