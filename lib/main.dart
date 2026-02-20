import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'src/models/todo_item.dart';
import 'src/state/app_controller.dart';
import 'src/ui/category_management_dialog.dart';
import 'src/ui/todo_row.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StackleApp());
}

class StackleApp extends StatefulWidget {
  const StackleApp({super.key});

  @override
  State<StackleApp> createState() => _StackleAppState();
}

class _StackleAppState extends State<StackleApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stackle',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Avenir Next',
        scaffoldBackgroundColor: const Color(0xFF0B0B0B),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF10B981),
              brightness: Brightness.dark,
            ).copyWith(
              primary: const Color(0xFFECECEC),
              secondary: const Color(0xFF8C8C8C),
              surface: const Color(0xFF0E0E0E),
              surfaceContainerHighest: const Color(0xFF1B1B1B),
              onSurface: Colors.white,
            ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF111111),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          menuPadding: EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            side: BorderSide(color: Color(0xFF2A2A2A)),
          ),
          textStyle: TextStyle(
            fontFamily: 'Avenir Next',
            color: Color(0xFFEAEAEA),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF101010),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: Color(0xFF2A2A2A)),
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'Avenir Next',
            color: Color(0xFFF0F0F0),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: TextStyle(
            fontFamily: 'Avenir Next',
            color: Color(0xFFD2D2D2),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF171717),
          hintStyle: TextStyle(
            fontFamily: 'Avenir Next',
            color: Color(0xFF8A8A8A),
            fontSize: 13,
          ),
          labelStyle: TextStyle(
            fontFamily: 'Avenir Next',
            color: Color(0xFFC8C8C8),
            fontSize: 13,
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2B2B2B)),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF3A3A3A)),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2B2B2B)),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFE7E7E7),
            textStyle: const TextStyle(
              fontFamily: 'Avenir Next',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF242424),
            foregroundColor: const Color(0xFFF4F4F4),
            textStyle: const TextStyle(
              fontFamily: 'Avenir Next',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFEAEAEA),
            side: const BorderSide(color: Color(0xFF333333)),
            textStyle: const TextStyle(
              fontFamily: 'Avenir Next',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF151515),
          contentTextStyle: const TextStyle(
            fontFamily: 'Avenir Next',
            color: Color(0xFFEDEDED),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          actionTextColor: const Color(0xFFC8E1FF),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
        ),
      ),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          switch (_controller.startupState) {
            case StartupState.loading:
              return const _LoadingScreen();
            case StartupState.needsDatabase:
              return _DatabaseSelectionScreen(
                title: 'Choose where your todos live',
                description:
                    'Select a SQLite file path for local-first storage. The file can be in iCloud Drive, Dropbox, or any folder you prefer.',
                primaryLabel: 'Create New Database',
                primaryAction: () {
                  _controller.createDatabaseWithPicker();
                },
                secondaryLabel: 'Locate Existing Database',
                secondaryAction: () {
                  _controller.locateExistingDatabaseWithPicker();
                },
                onQuit: () {
                  _controller.quitApplication();
                },
              );
            case StartupState.missingDatabase:
              return _DatabaseSelectionScreen(
                title: 'Database file not found',
                description:
                    'The last selected database is unavailable:\n${_controller.missingPath ?? 'Unknown path'}',
                primaryLabel: 'Locate Existing Database',
                primaryAction: () {
                  _controller.locateExistingDatabaseWithPicker();
                },
                secondaryLabel: 'Create New Database',
                secondaryAction: () {
                  _controller.createDatabaseWithPicker();
                },
                onQuit: () {
                  _controller.quitApplication();
                },
              );
            case StartupState.fatal:
              return _DatabaseSelectionScreen(
                title: 'Unable to open database',
                description:
                    _controller.fatalError ?? 'Unknown database error.',
                primaryLabel: 'Retry',
                primaryAction: () {
                  _controller.retryOpenSavedDatabase();
                },
                secondaryLabel: 'Locate Existing Database',
                secondaryAction: () {
                  _controller.locateExistingDatabaseWithPicker();
                },
                onQuit: () {
                  _controller.quitApplication();
                },
              );
            case StartupState.ready:
              return _MainScreen(controller: _controller);
          }
        },
      ),
    );
  }
}

class _MainScreen extends StatefulWidget {
  const _MainScreen({required this.controller});

  final AppController controller;

  @override
  State<_MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<_MainScreen> {
  static const double _topBarHeight = 48;
  static const double _listVerticalPadding = 16;
  static const double _todoRowExtent = 62;
  static const int _maxVisibleRows = 8;
  static const double _dialogMinWindowHeight = 460;

  String? _editingTodoId;
  bool _isReordering = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _activeDeleteSnackBar;
  double? _lastRequestedWindowHeight;
  int? _lastWindowHeightTodoCount;
  Timer? _windowHeightDebounce;

  AppController get _controller => widget.controller;

  @override
  void dispose() {
    _windowHeightDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleWindowHeightSync();
    final selectedTodo = _selectedTodo;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyN, meta: true): _NewTodoIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _OpenQuickAddIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true, shift: true):
            _OpenQuickAddIntent(),
        SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true):
            _ToggleWindowIntent(),
        SingleActivator(LogicalKeyboardKey.delete): _DeleteSelectedTodoIntent(),
        SingleActivator(LogicalKeyboardKey.backspace):
            _DeleteSelectedTodoIntent(),
        SingleActivator(LogicalKeyboardKey.space): _ToggleTodoIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _BeginEditIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NewTodoIntent: CallbackAction<_NewTodoIntent>(
            onInvoke: (_) {
              _controller.showQuickAddOverlay();
              return null;
            },
          ),
          _OpenQuickAddIntent: CallbackAction<_OpenQuickAddIntent>(
            onInvoke: (_) {
              _controller.showQuickAddOverlay();
              return null;
            },
          ),
          _ToggleWindowIntent: CallbackAction<_ToggleWindowIntent>(
            onInvoke: (_) {
              _controller.toggleMainWindow();
              return null;
            },
          ),
          _DeleteSelectedTodoIntent: CallbackAction<_DeleteSelectedTodoIntent>(
            onInvoke: (_) {
              if (_isTextInputFocused) {
                return null;
              }
              _confirmDeleteSelectedTodo();
              return null;
            },
          ),
          _ToggleTodoIntent: CallbackAction<_ToggleTodoIntent>(
            onInvoke: (_) {
              if (_isTextInputFocused) {
                return null;
              }
              final todo = _selectedTodo;
              if (todo != null) {
                _controller.setTodoCompletion(todo, !todo.isCompleted);
              }
              return null;
            },
          ),
          _EscapeIntent: CallbackAction<_EscapeIntent>(
            onInvoke: (_) {
              if (_editingTodoId != null) {
                setState(() => _editingTodoId = null);
              } else {
                _controller.selectTodo(null);
              }
              return null;
            },
          ),
          _BeginEditIntent: CallbackAction<_BeginEditIntent>(
            onInvoke: (_) {
              if (_isTextInputFocused || selectedTodo == null) {
                return null;
              }
              setState(() => _editingTodoId = selectedTodo.id);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFF0B0B0B),
            body: Column(
              children: <Widget>[
                _TopBar(
                  selectedCategoryName: _selectedCategoryName,
                  onOpenQuickAdd: () {
                    _controller.showQuickAddOverlay();
                  },
                  onSelectCategory: _openCategoryPicker,
                  onOpenCategoryManagement: () {
                    _openCategoryManagement();
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                    child: _buildTodoList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodoList() {
    final todos = _controller.visibleTodos;
    if (todos.isEmpty) {
      return _EmptyState(selectedCategoryId: _controller.selectedCategoryId);
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      itemExtent: _todoRowExtent,
      itemCount: todos.length,
      onReorderStart: (_) {
        if (!_isReordering) {
          setState(() => _isReordering = true);
        }
      },
      onReorderEnd: (_) {},
      onReorder: (oldIndex, newIndex) async {
        await _controller.reorderVisibleTodos(oldIndex, newIndex);
        if (mounted && _isReordering) {
          setState(() => _isReordering = false);
        }
      },
      proxyDecorator: (child, index, animation) {
        return Material(color: Colors.transparent, child: child);
      },
      itemBuilder: (context, index) {
        final todo = todos[index];
        return ReorderableDragStartListener(
          key: ValueKey(todo.id),
          index: index,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: TodoRow(
              todo: todo,
              categories: _controller.categories,
              isSelected: _controller.selectedTodoId == todo.id,
              isEditing: _editingTodoId == todo.id,
              onSelect: () => _controller.selectTodo(todo.id),
              onBeginEdit: () => setState(() => _editingTodoId = todo.id),
              onToggleCompleted: (value) =>
                  _controller.setTodoCompletion(todo, value),
              priorityRank: index,
              isReordering: _isReordering,
              onSubmitEdit: (nextText) async {
                setState(() => _editingTodoId = null);
                await _controller.updateTodoText(todo.id, nextText);
              },
              onCancelEdit: () => setState(() => _editingTodoId = null),
              onCategoryChanged: (categoryId) =>
                  _controller.updateTodoCategory(todo.id, categoryId),
              onDelete: () => _deleteTodo(todo),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteTodo(TodoItem todo) async {
    await _controller.deleteTodo(todo.id);
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
    final snackbarController = messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${todo.text}"'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _controller.restoreTodo(todo);
          },
        ),
      ),
    );
    _activeDeleteSnackBar = snackbarController;
    unawaited(
      snackbarController.closed.then((_) {
        if (_activeDeleteSnackBar == snackbarController) {
          _activeDeleteSnackBar = null;
        }
      }),
    );
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted) {
          return;
        }
        if (_activeDeleteSnackBar == snackbarController) {
          _activeDeleteSnackBar?.close();
        }
      }),
    );
  }

  Future<void> _confirmDeleteSelectedTodo() async {
    final todo = _selectedTodo;
    if (todo == null) {
      return;
    }

    await _deleteTodo(todo);
  }

  TodoItem? get _selectedTodo {
    final selectedId = _controller.selectedTodoId;
    if (selectedId == null) {
      return null;
    }

    for (final todo in _controller.visibleTodos) {
      if (todo.id == selectedId) {
        return todo;
      }
    }
    return null;
  }

  bool get _isTextInputFocused {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is EditableText;
  }

  Future<void> _openCategoryManagement() async {
    await _showDialogWithExpandedWindow<void>(
      minWindowHeight: _dialogMinWindowHeight,
      builder: (_) => CategoryManagementDialog(controller: _controller),
    );
  }

  void _scheduleWindowHeightSync() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }

    final todoCount = _controller.visibleTodos.length;
    if (_lastWindowHeightTodoCount == todoCount) {
      return;
    }
    _lastWindowHeightTodoCount = todoCount;

    _windowHeightDebounce?.cancel();
    _windowHeightDebounce = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) {
        return;
      }

      final targetHeight = _targetWindowHeightForTodoCount(todoCount);
      if (_lastRequestedWindowHeight != null &&
          (_lastRequestedWindowHeight! - targetHeight).abs() < 1) {
        return;
      }

      _lastRequestedWindowHeight = targetHeight;
      await _controller.setMainWindowHeight(targetHeight);
    });
  }

  double _targetWindowHeightForTodoCount(int count) {
    const emptyStateHeight = 140.0;
    const bottomSlack = -2.0;

    if (count <= 0) {
      return _topBarHeight + _listVerticalPadding + emptyStateHeight;
    }

    final visibleRows = count.clamp(1, _maxVisibleRows);
    return _topBarHeight +
        _listVerticalPadding +
        (visibleRows * _todoRowExtent) +
        bottomSlack;
  }

  String? get _selectedCategoryName {
    final categoryId = _controller.selectedCategoryId;
    if (categoryId == null) {
      return null;
    }
    for (final category in _controller.categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }
    return null;
  }

  Future<void> _openCategoryPicker() async {
    const allValue = '__all__';
    final selected = await _showDialogWithExpandedWindow<String>(
      minWindowHeight: _dialogMinWindowHeight,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF101010),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF272727)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  _CategoryOptionTile(
                    label: 'Todos',
                    selected: _controller.selectedCategoryId == null,
                    onTap: () => Navigator.of(context).pop(allValue),
                  ),
                  for (final category in _controller.categories)
                    _CategoryOptionTile(
                      label: category.name,
                      selected: _controller.selectedCategoryId == category.id,
                      onTap: () => Navigator.of(context).pop(category.id),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) {
      return;
    }
    await _controller.selectCategory(selected == allValue ? null : selected);
  }

  Future<T?> _showDialogWithExpandedWindow<T>({
    required WidgetBuilder builder,
    required double minWindowHeight,
    Color? barrierColor,
  }) async {
    await _controller.setMainWindowHeight(minWindowHeight);
    if (!mounted) {
      return null;
    }

    final result = await showDialog<T>(
      context: context,
      barrierColor: barrierColor,
      builder: builder,
    );

    if (!mounted) {
      return result;
    }

    _restoreMainWindowHeightAfterDialog();
    return result;
  }

  void _restoreMainWindowHeightAfterDialog() {
    _lastWindowHeightTodoCount = null;
    _windowHeightDebounce?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final targetHeight = _targetWindowHeightForTodoCount(
        _controller.visibleTodos.length,
      );
      _lastRequestedWindowHeight = targetHeight;
      await _controller.setMainWindowHeight(targetHeight);
    });
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selectedCategoryName,
    required this.onOpenQuickAdd,
    required this.onSelectCategory,
    required this.onOpenCategoryManagement,
  });

  final String? selectedCategoryName;
  final VoidCallback onOpenQuickAdd;
  final VoidCallback onSelectCategory;
  final VoidCallback onOpenCategoryManagement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        border: Border(bottom: BorderSide(color: const Color(0xFF1D1D1D))),
      ),
      child: Center(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              selectedCategoryName == null
                  ? 'Todos'
                  : '${selectedCategoryName!} Todos',
              textAlign: TextAlign.left,
              style: theme.textTheme.labelLarge?.copyWith(
                color: const Color(0xFFDADADA),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                height: 1.0,
              ),
            ),
            const Spacer(),
            _TopIconButton(
              onPressed: onSelectCategory,
              tooltip: 'Filter category',
              icon: Icons.tune_rounded,
              iconSize: 18,
            ),
            const SizedBox(width: 4),
            _TopIconButton(
              onPressed: onOpenQuickAdd,
              tooltip: 'Quick Add',
              icon: Icons.add_rounded,
              iconSize: 20,
            ),
            const SizedBox(width: 4),
            _TopIconButton(
              onPressed: onOpenCategoryManagement,
              tooltip: 'Manage categories',
              icon: Icons.category_outlined,
              iconSize: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    required this.iconSize,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: iconSize),
      ),
    );
  }
}

class _CategoryOptionTile extends StatelessWidget {
  const _CategoryOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? const Color(0xFF232323) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFE0E0E0),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.selectedCategoryId});

  final String? selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inCategoryView = selectedCategoryId != null;

    return Center(
      child: Text(
        inCategoryView ? 'No todos in this category.' : 'Add your first todo.',
        style: theme.textTheme.titleMedium?.copyWith(
          color: const Color(0xFFBEBEBE),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _DatabaseSelectionScreen extends StatelessWidget {
  const _DatabaseSelectionScreen({
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.primaryAction,
    required this.secondaryLabel,
    required this.secondaryAction,
    required this.onQuit,
  });

  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback primaryAction;
  final String secondaryLabel;
  final VoidCallback secondaryAction;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.secondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton(
                      onPressed: primaryAction,
                      child: Text(primaryLabel),
                    ),
                    FilledButton.tonal(
                      onPressed: secondaryAction,
                      child: Text(secondaryLabel),
                    ),
                    OutlinedButton(
                      onPressed: onQuit,
                      child: const Text('Quit'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading Stackle...'),
          ],
        ),
      ),
    );
  }
}

class _NewTodoIntent extends Intent {
  const _NewTodoIntent();
}

class _DeleteSelectedTodoIntent extends Intent {
  const _DeleteSelectedTodoIntent();
}

class _ToggleTodoIntent extends Intent {
  const _ToggleTodoIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _BeginEditIntent extends Intent {
  const _BeginEditIntent();
}

class _OpenQuickAddIntent extends Intent {
  const _OpenQuickAddIntent();
}

class _ToggleWindowIntent extends Intent {
  const _ToggleWindowIntent();
}
