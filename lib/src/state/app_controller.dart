import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../models/category.dart';
import '../models/todo_item.dart';
import '../platform/native_bridge.dart';

enum StartupState { loading, needsDatabase, missingDatabase, ready, fatal }

class AppController extends ChangeNotifier {
  AppController({AppDatabase? database, NativeBridge? nativeBridge})
    : _database = database ?? AppDatabase(),
      _nativeBridge = nativeBridge ?? NativeBridge();

  static const String _databasePathPrefKey = 'database_path';

  final AppDatabase _database;
  final NativeBridge _nativeBridge;

  SharedPreferences? _preferences;

  StartupState _startupState = StartupState.loading;
  String? _fatalError;
  String? _missingPath;
  String? _lockMessage;

  List<Category> _categories = const [];
  List<TodoItem> _visibleTodos = const [];

  String? _selectedCategoryId;
  String? _selectedTodoId;
  bool _isAccessibilityTrusted = true;
  final Map<String, int> _completionMutationVersions = <String, int>{};

  StartupState get startupState => _startupState;
  String? get fatalError => _fatalError;
  String? get missingPath => _missingPath;
  String? get lockMessage => _lockMessage;
  String? get openedDatabasePath => _database.openedPath;

  List<Category> get categories => _categories;
  List<TodoItem> get visibleTodos => _visibleTodos;

  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedTodoId => _selectedTodoId;
  bool get isAccessibilityTrusted => _isAccessibilityTrusted;

  bool get hasDatabaseLoaded => _startupState == StartupState.ready;

  Future<void> initialize() async {
    _startupState = StartupState.loading;
    notifyListeners();

    await _nativeBridge.initialize(onQuickAdd: addQuickTodo);
    _isAccessibilityTrusted = await _nativeBridge.isAccessibilityTrusted();
    _preferences = await SharedPreferences.getInstance();
    _selectedCategoryId = null;

    final path = _preferences?.getString(_databasePathPrefKey);
    if (path == null || path.isEmpty) {
      _startupState = StartupState.needsDatabase;
      notifyListeners();
      return;
    }

    await _openDatabase(path, createIfMissing: false, persistPath: false);
  }

  Future<void> createDatabaseWithPicker() async {
    try {
      final selectedPath = await _nativeBridge
          .selectDatabasePathForCreate()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      final resolvedPath =
          (selectedPath != null && selectedPath.trim().isNotEmpty)
          ? selectedPath
          : _defaultDatabasePath();

      await _openDatabase(
        resolvedPath,
        createIfMissing: true,
        persistPath: true,
      );
    } on PlatformException catch (error) {
      _fatalError =
          'Unable to open the save dialog. ${error.message ?? error.code}';
      _startupState = StartupState.fatal;
      notifyListeners();
    } on MissingPluginException {
      await _openDatabase(
        _defaultDatabasePath(),
        createIfMissing: true,
        persistPath: true,
      );
    }
  }

  Future<void> locateExistingDatabaseWithPicker() async {
    try {
      final selectedPath = await _nativeBridge
          .selectDatabasePathForOpen()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      String? resolvedPath;
      if (selectedPath != null && selectedPath.trim().isNotEmpty) {
        resolvedPath = selectedPath;
      } else {
        final defaultPath = _defaultDatabasePath();
        if (await File(defaultPath).exists()) {
          resolvedPath = defaultPath;
        }
      }

      if (resolvedPath == null) {
        _fatalError =
            'Could not open the file picker. Try "Create New Database" first.';
        _startupState = StartupState.fatal;
        notifyListeners();
        return;
      }

      await _openDatabase(
        resolvedPath,
        createIfMissing: false,
        persistPath: true,
      );
    } on PlatformException catch (error) {
      _fatalError =
          'Unable to open the file picker. ${error.message ?? error.code}';
      _startupState = StartupState.fatal;
      notifyListeners();
    } on MissingPluginException {
      _fatalError =
          'Could not open the file picker. Try "Create New Database" first.';
      _startupState = StartupState.fatal;
      notifyListeners();
    }
  }

  String _defaultDatabasePath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.trim().isEmpty) {
      return 'todos.db';
    }
    return '$home/Documents/todos.db';
  }

  Future<void> retryOpenSavedDatabase() async {
    final path = _preferences?.getString(_databasePathPrefKey);
    if (path == null || path.isEmpty) {
      _startupState = StartupState.needsDatabase;
      notifyListeners();
      return;
    }

    await _openDatabase(path, createIfMissing: false, persistPath: false);
  }

  Future<void> _openDatabase(
    String path, {
    required bool createIfMissing,
    required bool persistPath,
  }) async {
    _startupState = StartupState.loading;
    _fatalError = null;
    _missingPath = null;
    _lockMessage = null;
    notifyListeners();

    try {
      await _database.openAtPath(path, createIfMissing: createIfMissing);
      if (persistPath) {
        await _preferences?.setString(_databasePathPrefKey, path);
      }
      await _refreshData();
      _startupState = StartupState.ready;
    } on AppDatabaseException catch (error) {
      if (error.isMissing) {
        _missingPath = path;
        _startupState = StartupState.missingDatabase;
      } else if (error.isLocked) {
        _fatalError = error.message;
        _startupState = StartupState.fatal;
      } else {
        _fatalError = error.message;
        _startupState = StartupState.fatal;
      }
    }
    notifyListeners();
  }

  Future<void> reloadVisibleData() async {
    if (!hasDatabaseLoaded) {
      return;
    }

    try {
      await _refreshData();
      _lockMessage = null;
    } on AppDatabaseException catch (error) {
      if (error.isLocked) {
        _lockMessage = error.message;
      } else {
        _fatalError = error.message;
        _startupState = StartupState.fatal;
      }
    }
    notifyListeners();
  }

  Future<void> _refreshData() async {
    final cutoffMs =
        DateTime.now().millisecondsSinceEpoch -
        const Duration(hours: 12).inMilliseconds;
    final categories = await _database.fetchCategories();

    if (_selectedCategoryId != null &&
        categories.every((c) => c.id != _selectedCategoryId)) {
      _selectedCategoryId = null;
    }

    final todos = await _database.fetchVisibleTodos(
      categoryId: _selectedCategoryId,
      cutoffMs: cutoffMs,
    );

    _categories = categories;
    _visibleTodos = todos;

    if (_selectedTodoId != null &&
        todos.every((todo) => todo.id != _selectedTodoId)) {
      _selectedTodoId = null;
    }
  }

  void clearLockMessage() {
    _lockMessage = null;
    notifyListeners();
  }

  Future<void> selectCategory(String? categoryId) async {
    _selectedCategoryId = categoryId;
    await reloadVisibleData();
  }

  void selectTodo(String? todoId) {
    _selectedTodoId = todoId;
    notifyListeners();
  }

  Future<void> addTodoFromMain(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    try {
      final categoryId = _selectedCategoryId ?? await _inboxCategoryId();
      await _database.addTodo(text: trimmed, categoryId: categoryId);
      await _refreshData();
      _lockMessage = null;
      notifyListeners();
    } on AppDatabaseException catch (error) {
      _handleOperationError(error);
    }
  }

  Future<void> addQuickTodo(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !hasDatabaseLoaded) {
      return;
    }

    try {
      final inboxId = await _inboxCategoryId();
      await _database.addTodo(text: trimmed, categoryId: inboxId);
      await _refreshData();
      _lockMessage = null;
      notifyListeners();
    } on AppDatabaseException catch (error) {
      _handleOperationError(error);
    }
  }

  Future<void> setTodoCompletion(TodoItem todo, bool isCompleted) async {
    final index = _visibleTodos.indexWhere((item) => item.id == todo.id);
    if (index < 0) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = _visibleTodos[index];
    final optimistic = previous.copyWith(
      isCompleted: isCompleted,
      completedAt: isCompleted ? now : null,
      clearCompletedAt: !isCompleted,
      updatedAt: now,
    );

    final nextTodos = List<TodoItem>.from(_visibleTodos);
    nextTodos[index] = optimistic;
    _visibleTodos = nextTodos;
    notifyListeners();

    final version = (_completionMutationVersions[todo.id] ?? 0) + 1;
    _completionMutationVersions[todo.id] = version;
    unawaited(
      _persistCompletion(
        todoId: todo.id,
        isCompleted: isCompleted,
        expectedVersion: version,
        rollbackValue: previous,
      ),
    );
  }

  Future<void> _persistCompletion({
    required String todoId,
    required bool isCompleted,
    required int expectedVersion,
    required TodoItem rollbackValue,
  }) async {
    try {
      await _database.setTodoCompletion(todoId, isCompleted);
      if (_completionMutationVersions[todoId] == expectedVersion) {
        _lockMessage = null;
        notifyListeners();
      }
    } on AppDatabaseException catch (error) {
      if (_completionMutationVersions[todoId] != expectedVersion) {
        return;
      }

      final rollback = List<TodoItem>.from(_visibleTodos);
      final rollbackIndex = rollback.indexWhere((item) => item.id == todoId);
      if (rollbackIndex >= 0) {
        rollback[rollbackIndex] = rollbackValue;
        _visibleTodos = rollback;
      }
      _handleOperationError(error);
    }
  }

  Future<void> updateTodoText(String todoId, String text) async {
    try {
      await _database.updateTodoText(todoId, text);
      await _refreshData();
      _lockMessage = null;
      notifyListeners();
    } on AppDatabaseException catch (error) {
      _handleOperationError(error);
    }
  }

  Future<void> updateTodoCategory(String todoId, String categoryId) async {
    try {
      await _database.updateTodoCategory(todoId, categoryId);
      await _refreshData();
      _lockMessage = null;
      notifyListeners();
    } on AppDatabaseException catch (error) {
      _handleOperationError(error);
    }
  }

  Future<void> deleteTodo(String todoId) async {
    try {
      await _database.deleteTodo(todoId);
      await _refreshData();
      _selectedTodoId = null;
      _lockMessage = null;
      notifyListeners();
    } on AppDatabaseException catch (error) {
      _handleOperationError(error);
    }
  }

  Future<void> reorderVisibleTodos(int oldIndex, int newIndex) async {
    if (_visibleTodos.length < 2) {
      return;
    }

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex || oldIndex < 0 || newIndex < 0) {
      return;
    }

    if (oldIndex >= _visibleTodos.length || newIndex >= _visibleTodos.length) {
      return;
    }

    final reordered = List<TodoItem>.from(_visibleTodos);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final previous = newIndex > 0 ? reordered[newIndex - 1] : null;
    final next = newIndex < reordered.length - 1
        ? reordered[newIndex + 1]
        : null;

    try {
      if (_canUseFractionalOrdering(previous: previous, next: next)) {
        final nextOrder = _computeSortOrder(previous: previous, next: next);
        await _database.updateTodoSortOrder(moved.id, nextOrder);
      } else {
        await _rebalanceAndPlace(
          movedId: moved.id,
          previousId: previous?.id,
          nextId: next?.id,
        );
      }

      await _refreshData();
      _lockMessage = null;
      notifyListeners();
    } on AppDatabaseException catch (error) {
      _handleOperationError(error);
    }
  }

  Future<void> _rebalanceAndPlace({
    required String movedId,
    String? previousId,
    String? nextId,
  }) async {
    final globalTodos = await _database.fetchAllTodosOrdered();
    final ids = globalTodos.map((todo) => todo.id).toList(growable: true);

    ids.remove(movedId);
    var insertAt = _resolveInsertIndex(
      ids,
      previousId: previousId,
      nextId: nextId,
    );

    if (insertAt < 0) {
      insertAt = 0;
    }
    if (insertAt > ids.length) {
      insertAt = ids.length;
    }

    ids.insert(insertAt, movedId);
    await _database.rebalanceInGlobalOrder(ids);
  }

  int _resolveInsertIndex(
    List<String> ids, {
    required String? previousId,
    required String? nextId,
  }) {
    if (previousId == null && nextId == null) {
      return 0;
    }

    if (previousId == null) {
      final nextIndex = ids.indexOf(nextId!);
      return nextIndex < 0 ? 0 : nextIndex;
    }

    if (nextId == null) {
      final previousIndex = ids.indexOf(previousId);
      return previousIndex < 0 ? ids.length : previousIndex + 1;
    }

    final previousIndex = ids.indexOf(previousId);
    final nextIndex = ids.indexOf(nextId);

    if (previousIndex >= 0 && nextIndex >= 0) {
      final candidate = previousIndex + 1;
      return candidate > nextIndex ? nextIndex : candidate;
    }

    if (previousIndex >= 0) {
      return previousIndex + 1;
    }

    if (nextIndex >= 0) {
      return nextIndex;
    }

    return 0;
  }

  bool _canUseFractionalOrdering({
    required TodoItem? previous,
    required TodoItem? next,
  }) {
    if (previous == null || next == null) {
      return true;
    }
    return (previous.sortOrder - next.sortOrder).abs() > 0.0001;
  }

  double _computeSortOrder({
    required TodoItem? previous,
    required TodoItem? next,
  }) {
    if (previous == null && next == null) {
      return AppDatabase.orderStep;
    }

    if (previous == null) {
      return next!.sortOrder + AppDatabase.orderStep;
    }

    if (next == null) {
      return previous.sortOrder - AppDatabase.orderStep;
    }

    return (previous.sortOrder + next.sortOrder) / 2;
  }

  Future<String?> createCategory(String name) async {
    try {
      await _database.createCategory(name);
      await _refreshData();
      notifyListeners();
      return null;
    } on AppDatabaseException catch (error) {
      return _userFacingError(error);
    }
  }

  Future<String?> renameCategory(Category category, String nextName) async {
    try {
      await _database.renameCategory(category.id, nextName);
      await _refreshData();
      notifyListeners();
      return null;
    } on AppDatabaseException catch (error) {
      return _userFacingError(error);
    }
  }

  Future<String?> deleteCategory(Category category) async {
    try {
      await _database.deleteCategoryAndMoveTodosToInbox(category.id);
      if (_selectedCategoryId == category.id) {
        _selectedCategoryId = null;
      }
      await _refreshData();
      notifyListeners();
      return null;
    } on AppDatabaseException catch (error) {
      return _userFacingError(error);
    }
  }

  Future<void> showQuickAddOverlay() async {
    await _nativeBridge.showQuickAddOverlay();
  }

  Future<void> hideMainWindow() async {
    await _nativeBridge.hideMainWindow();
  }

  Future<void> quitApplication() async {
    await _nativeBridge.quitApp();
  }

  Future<void> setMainWindowHeight(double height) async {
    await _nativeBridge.setMainWindowHeight(height);
  }

  Future<void> openAccessibilitySettings() async {
    await _nativeBridge.openAccessibilitySettings();
  }

  Future<void> refreshAccessibilityTrust() async {
    _isAccessibilityTrusted = await _nativeBridge.isAccessibilityTrusted();
    notifyListeners();
  }

  Future<String> _inboxCategoryId() async {
    final existing = _categories.where((category) => category.isInbox);
    if (existing.isNotEmpty) {
      return existing.first.id;
    }

    final inbox = await _database.fetchInboxCategory();
    return inbox.id;
  }

  void _handleOperationError(AppDatabaseException error) {
    if (error.isLocked) {
      _lockMessage = error.message;
    } else {
      _fatalError = error.message;
      _startupState = StartupState.fatal;
    }
    notifyListeners();
  }

  String _userFacingError(AppDatabaseException error) {
    final raw = error.message.toLowerCase();
    if (raw.contains('unique constraint') && raw.contains('categories.name')) {
      return 'Category names must be unique.';
    }
    return error.message;
  }

  @override
  void dispose() {
    _database.close();
    super.dispose();
  }
}
