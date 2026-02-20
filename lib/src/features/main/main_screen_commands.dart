import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/todo_item.dart';

class NewTodoIntent extends Intent {
  const NewTodoIntent();
}

class DeleteSelectedTodoIntent extends Intent {
  const DeleteSelectedTodoIntent();
}

class ToggleTodoIntent extends Intent {
  const ToggleTodoIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

class BeginEditIntent extends Intent {
  const BeginEditIntent();
}

class OpenQuickAddIntent extends Intent {
  const OpenQuickAddIntent();
}

class ToggleWindowIntent extends Intent {
  const ToggleWindowIntent();
}

class MainScreenCommandConfig {
  const MainScreenCommandConfig({
    required this.canUseSelectionShortcuts,
    required this.selectedTodo,
    required this.onOpenQuickAdd,
    required this.onToggleWindow,
    required this.onDeleteSelected,
    required this.onToggleSelected,
    required this.onEscape,
    required this.onBeginEdit,
  });

  final bool canUseSelectionShortcuts;
  final TodoItem? selectedTodo;
  final VoidCallback onOpenQuickAdd;
  final VoidCallback onToggleWindow;
  final VoidCallback onDeleteSelected;
  final ValueChanged<TodoItem> onToggleSelected;
  final VoidCallback onEscape;
  final VoidCallback onBeginEdit;
}

class MainScreenCommands {
  static Map<ShortcutActivator, Intent> shortcuts({
    required bool canUseSelectionShortcuts,
  }) {
    final result = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
          const NewTodoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
          const OpenQuickAddIntent(),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true, shift: true):
          const OpenQuickAddIntent(),
      const SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true):
          const ToggleWindowIntent(),
      const SingleActivator(LogicalKeyboardKey.escape): const EscapeIntent(),
    };

    if (canUseSelectionShortcuts) {
      result.addAll(const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.delete): DeleteSelectedTodoIntent(),
        SingleActivator(LogicalKeyboardKey.backspace):
            DeleteSelectedTodoIntent(),
        SingleActivator(LogicalKeyboardKey.space): ToggleTodoIntent(),
        SingleActivator(LogicalKeyboardKey.enter): BeginEditIntent(),
      });
    }

    return result;
  }

  static Map<Type, Action<Intent>> actions(MainScreenCommandConfig config) {
    return <Type, Action<Intent>>{
      NewTodoIntent: CallbackAction<NewTodoIntent>(
        onInvoke: (_) {
          config.onOpenQuickAdd();
          return null;
        },
      ),
      OpenQuickAddIntent: CallbackAction<OpenQuickAddIntent>(
        onInvoke: (_) {
          config.onOpenQuickAdd();
          return null;
        },
      ),
      ToggleWindowIntent: CallbackAction<ToggleWindowIntent>(
        onInvoke: (_) {
          config.onToggleWindow();
          return null;
        },
      ),
      DeleteSelectedTodoIntent: CallbackAction<DeleteSelectedTodoIntent>(
        onInvoke: (_) {
          if (config.canUseSelectionShortcuts) {
            config.onDeleteSelected();
          }
          return null;
        },
      ),
      ToggleTodoIntent: CallbackAction<ToggleTodoIntent>(
        onInvoke: (_) {
          if (config.canUseSelectionShortcuts && config.selectedTodo != null) {
            config.onToggleSelected(config.selectedTodo!);
          }
          return null;
        },
      ),
      EscapeIntent: CallbackAction<EscapeIntent>(
        onInvoke: (_) {
          config.onEscape();
          return null;
        },
      ),
      BeginEditIntent: CallbackAction<BeginEditIntent>(
        onInvoke: (_) {
          if (config.canUseSelectionShortcuts && config.selectedTodo != null) {
            config.onBeginEdit();
          }
          return null;
        },
      ),
    };
  }
}
