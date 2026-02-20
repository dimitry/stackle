import 'package:flutter/material.dart';

import '../../models/todo_item.dart';
import '../../platform/main_window_sizing_coordinator.dart';
import '../../state/app_controller.dart';
import '../../ui/category_management_dialog.dart';
import '../../ui/shared/frosted_surface.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/todo_row.dart';
import 'main_screen_commands.dart';
import 'main_screen_view_model.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const double _dialogMinWindowHeight = 460;

  late final MainScreenViewModel _viewModel;
  late final MainWindowSizingCoordinator _windowSizingCoordinator;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _viewModel = MainScreenViewModel()..attachFocusTracking();
    _viewModel.addListener(_onViewModelChanged);
    _windowSizingCoordinator = MainWindowSizingCoordinator(
      onSetMainWindowHeight: _controller.setMainWindowHeight,
    );
  }

  @override
  void dispose() {
    _windowSizingCoordinator.dispose();
    _viewModel
      ..removeListener(_onViewModelChanged)
      ..detachFocusTracking()
      ..dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _windowSizingCoordinator.scheduleSync(
      routeIsCurrent: ModalRoute.of(context)?.isCurrent ?? true,
      mounted: mounted,
      todoCount: _controller.visibleTodos.length,
    );

    final selectedTodo = _viewModel.selectedTodo(
      _controller.selectedTodoId,
      _controller.visibleTodos,
    );

    return Shortcuts(
      shortcuts: MainScreenCommands.shortcuts(
        canUseSelectionShortcuts: _viewModel.canUseSelectionShortcuts,
      ),
      child: Actions(
        actions: MainScreenCommands.actions(
          MainScreenCommandConfig(
            canUseSelectionShortcuts: _viewModel.canUseSelectionShortcuts,
            selectedTodo: selectedTodo,
            onOpenQuickAdd: _controller.showQuickAddOverlay,
            onToggleWindow: _controller.toggleMainWindow,
            onDeleteSelected: _confirmDeleteSelectedTodo,
            onToggleSelected: (todo) {
              _controller.setTodoCompletion(todo, !todo.isCompleted);
            },
            onEscape: () {
              _viewModel.clearSelectionOrEdit(
                clearSelection: () => _controller.selectTodo(null),
              );
            },
            onBeginEdit: () {
              if (selectedTodo != null) {
                _viewModel.beginEdit(selectedTodo.id);
              }
            },
          ),
        ),
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: appMainSurfaceColor,
            body: Column(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: _buildTodoList(),
                  ),
                ),
                _FooterBar(
                  onOpenQuickAdd: _controller.showQuickAddOverlay,
                  onSelectCategory: _openCategoryPicker,
                  onOpenCategoryManagement: _openCategoryManagement,
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
      return EmptyState(selectedCategoryId: _controller.selectedCategoryId);
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      itemExtent: 62,
      itemCount: todos.length,
      onReorderStart: (_) => _viewModel.setReordering(true),
      onReorderEnd: (_) {},
      onReorder: (oldIndex, newIndex) async {
        await _controller.reorderVisibleTodos(oldIndex, newIndex);
        if (mounted) {
          _viewModel.setReordering(false);
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
              isEditing: _viewModel.isEditing(todo.id),
              onSelect: () => _controller.selectTodo(todo.id),
              onBeginEdit: () => _viewModel.beginEdit(todo.id),
              onToggleCompleted: (value) =>
                  _controller.setTodoCompletion(todo, value),
              priorityRank: index,
              isReordering: _viewModel.isReordering,
              onSubmitEdit: (nextText) async {
                _viewModel.cancelEdit();
                await _controller.updateTodoText(todo.id, nextText);
              },
              onCancelEdit: _viewModel.cancelEdit,
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

    await _viewModel.showDeleteSnackBar(
      context: context,
      todo: todo,
      onUndo: () => _controller.restoreTodo(todo),
    );
  }

  Future<void> _confirmDeleteSelectedTodo() async {
    final todo = _viewModel.selectedTodo(
      _controller.selectedTodoId,
      _controller.visibleTodos,
    );
    if (todo == null) {
      return;
    }

    await _deleteTodo(todo);
  }

  Future<void> _openCategoryManagement() async {
    await _windowSizingCoordinator.setTemporaryHeight(_dialogMinWindowHeight);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            CategoryManagementScreen(controller: _controller),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            child,
      ),
    );
    if (!mounted) {
      return;
    }
    _restoreMainWindowHeightAfterOverlay();
  }

  Future<void> _openCategoryPicker() async {
    const allValue = '__all__';
    final selected = await _showDialogWithExpandedWindow<String>(
      minWindowHeight: _dialogMinWindowHeight,
      restoreAfterDismiss: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: FrostedSurface(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280, maxHeight: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    CategoryOptionTile(
                      label: 'Todos',
                      selected: _controller.selectedCategoryId == null,
                      onTap: () => Navigator.of(context).pop(allValue),
                    ),
                    for (final category in _controller.categories)
                      CategoryOptionTile(
                        label: category.name,
                        selected: _controller.selectedCategoryId == category.id,
                        onTap: () => Navigator.of(context).pop(category.id),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }
    if (selected == null) {
      _restoreMainWindowHeightAfterOverlay();
      return;
    }

    await _controller.selectCategory(selected == allValue ? null : selected);
    if (!mounted) {
      return;
    }
    _restoreMainWindowHeightAfterOverlay();
  }

  Future<T?> _showDialogWithExpandedWindow<T>({
    required WidgetBuilder builder,
    required double minWindowHeight,
    bool restoreAfterDismiss = true,
    Color? barrierColor,
  }) async {
    await _windowSizingCoordinator.setTemporaryHeight(minWindowHeight);
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
    if (restoreAfterDismiss) {
      _restoreMainWindowHeightAfterOverlay();
    }
    return result;
  }

  void _restoreMainWindowHeightAfterOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _windowSizingCoordinator.restoreHeight(
        mounted: mounted,
        todoCount: _controller.visibleTodos.length,
      );
    });
  }
}

class FooterBar extends StatelessWidget {
  const FooterBar({
    super.key,
    required this.onOpenQuickAdd,
    required this.onSelectCategory,
    required this.onOpenCategoryManagement,
  });

  final VoidCallback onOpenQuickAdd;
  final VoidCallback onSelectCategory;
  final VoidCallback onOpenCategoryManagement;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Align(
        alignment: Alignment.topCenter,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _TopIconButton(
              onPressed: onSelectCategory,
              tooltip: 'Filter category',
              icon: Icons.tune_rounded,
              iconSize: 18,
            ),
            const SizedBox(width: 8),
            _TopIconButton(
              onPressed: onOpenQuickAdd,
              tooltip: 'Quick Add',
              icon: Icons.add_rounded,
              iconSize: 20,
            ),
            const SizedBox(width: 8),
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

class _FooterBar extends FooterBar {
  const _FooterBar({
    required super.onOpenQuickAdd,
    required super.onSelectCategory,
    required super.onOpenCategoryManagement,
  });
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
      width: 32,
      height: 32,
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

class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appMainSurfaceColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FrostedSurface(
            child: CategoryManagementDialog(controller: controller),
          ),
        ),
      ),
    );
  }
}

class CategoryOptionTile extends StatelessWidget {
  const CategoryOptionTile({
    super.key,
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

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.selectedCategoryId});

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
