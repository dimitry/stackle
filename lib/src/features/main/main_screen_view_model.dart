import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/todo_item.dart';

class MainScreenViewModel extends ChangeNotifier {
  String? _editingTodoId;
  bool _isReordering = false;
  bool _textInputFocused = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _activeDeleteSnackBar;

  String? get editingTodoId => _editingTodoId;
  bool get isReordering => _isReordering;
  bool get isTextInputFocused => _textInputFocused;

  bool get canUseSelectionShortcuts =>
      _editingTodoId == null && !_textInputFocused;

  void attachFocusTracking() {
    FocusManager.instance.addListener(_handleFocusChange);
    _textInputFocused = _computeIsTextInputFocused();
  }

  void detachFocusTracking() {
    FocusManager.instance.removeListener(_handleFocusChange);
  }

  bool isEditing(String todoId) => _editingTodoId == todoId;

  void beginEdit(String todoId) {
    if (_editingTodoId == todoId) {
      return;
    }
    _editingTodoId = todoId;
    notifyListeners();
  }

  void cancelEdit() {
    if (_editingTodoId == null) {
      return;
    }
    _editingTodoId = null;
    notifyListeners();
  }

  void setReordering(bool value) {
    if (_isReordering == value) {
      return;
    }
    _isReordering = value;
    notifyListeners();
  }

  TodoItem? selectedTodo(String? selectedTodoId, List<TodoItem> visibleTodos) {
    if (selectedTodoId == null) {
      return null;
    }
    for (final todo in visibleTodos) {
      if (todo.id == selectedTodoId) {
        return todo;
      }
    }
    return null;
  }

  Future<void> showDeleteSnackBar({
    required BuildContext context,
    required TodoItem todo,
    required Future<void> Function() onUndo,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);

    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${todo.text}"'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(onUndo());
          },
        ),
      ),
    );

    _activeDeleteSnackBar = controller;
    unawaited(
      controller.closed.then((_) {
        if (_activeDeleteSnackBar == controller) {
          _activeDeleteSnackBar = null;
        }
      }),
    );

    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (_activeDeleteSnackBar == controller) {
          _activeDeleteSnackBar?.close();
        }
      }),
    );
  }

  void clearSelectionOrEdit({required VoidCallback clearSelection}) {
    if (_editingTodoId != null) {
      cancelEdit();
      return;
    }
    clearSelection();
  }

  bool _computeIsTextInputFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    return focusedContext?.widget is EditableText;
  }

  void _handleFocusChange() {
    final next = _computeIsTextInputFocused();
    if (next != _textInputFocused) {
      _textInputFocused = next;
      notifyListeners();
    }
  }
}
