import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/category.dart';
import '../models/todo_item.dart';

class _CategorySwatch {
  const _CategorySwatch({
    required this.background,
    required this.border,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color text;
}

const List<_CategorySwatch> _categorySwatches = <_CategorySwatch>[
  _CategorySwatch(
    background: Color(0xFF1D2530),
    border: Color(0xFF334155),
    text: Color(0xFFBFDBFE),
  ),
  _CategorySwatch(
    background: Color(0xFF2A1F29),
    border: Color(0xFF4A2D45),
    text: Color(0xFFF5C2E7),
  ),
  _CategorySwatch(
    background: Color(0xFF1F2A26),
    border: Color(0xFF2F4D43),
    text: Color(0xFFBDE7D5),
  ),
  _CategorySwatch(
    background: Color(0xFF2A241D),
    border: Color(0xFF4B3D2E),
    text: Color(0xFFF3D6B3),
  ),
  _CategorySwatch(
    background: Color(0xFF222232),
    border: Color(0xFF3A3C5A),
    text: Color(0xFFD2D7FF),
  ),
  _CategorySwatch(
    background: Color(0xFF2C1F21),
    border: Color(0xFF4F3034),
    text: Color(0xFFFFC5C5),
  ),
  _CategorySwatch(
    background: Color(0xFF1F2B2D),
    border: Color(0xFF345057),
    text: Color(0xFFBEEBF2),
  ),
  _CategorySwatch(
    background: Color(0xFF2A2620),
    border: Color(0xFF4A4233),
    text: Color(0xFFF0E1B8),
  ),
];

class TodoRow extends StatefulWidget {
  const TodoRow({
    super.key,
    required this.todo,
    required this.categories,
    required this.isSelected,
    required this.isEditing,
    required this.onSelect,
    required this.onBeginEdit,
    required this.onToggleCompleted,
    required this.onSubmitEdit,
    required this.onCancelEdit,
    required this.onCategoryChanged,
    required this.onDelete,
    required this.priorityRank,
    required this.isReordering,
  });

  final TodoItem todo;
  final List<Category> categories;
  final bool isSelected;
  final bool isEditing;
  final VoidCallback onSelect;
  final VoidCallback onBeginEdit;
  final ValueChanged<bool> onToggleCompleted;
  final ValueChanged<String> onSubmitEdit;
  final VoidCallback onCancelEdit;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onDelete;
  final int priorityRank;
  final bool isReordering;

  @override
  State<TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<TodoRow> {
  late final TextEditingController _controller;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.todo.text);
  }

  @override
  void didUpdateWidget(covariant TodoRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isEditing && oldWidget.todo.text != widget.todo.text) {
      _controller.text = widget.todo.text;
    }

    if (widget.isEditing && !oldWidget.isEditing) {
      _controller
        ..text = widget.todo.text
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.todo.text.length,
        );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color rowColor;
    if (widget.isSelected) {
      rowColor = const Color(0xFF242424);
    } else if (_hovered) {
      rowColor = const Color(0xFF1F1F1F);
    } else {
      rowColor = const Color(0xFF171717);
    }
    final isTopPriority = widget.priorityRank < 3;
    final accent = switch (widget.priorityRank) {
      0 => const Color(0xFF5C91E8),
      1 => const Color(0xFF52A88A),
      2 => const Color(0xFFB58A52),
      _ => const Color(0x00000000),
    };

    final showPriorityAccent = isTopPriority && !widget.isReordering;
    final rowDecoration = BoxDecoration(
      color: rowColor,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF2A2A2A)),
      boxShadow: showPriorityAccent
          ? <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 10,
                spreadRadius: 0.5,
              ),
            ]
          : null,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        onDoubleTap: widget.onBeginEdit,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: widget.todo.isCompleted ? 0.55 : 1,
          child: AnimatedContainer(
            duration: widget.isReordering
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: rowDecoration,
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: widget.isReordering
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 2,
                  height: 20,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: showPriorityAccent
                        ? accent.withValues(alpha: 0.92)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 1,
                    end: widget.todo.isCompleted ? 0.95 : 1,
                  ),
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Checkbox(
                    value: widget.todo.isCompleted,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (value) =>
                        widget.onToggleCompleted(value ?? false),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: _buildText(theme)),
                const SizedBox(width: 8),
                _buildCategoryMenu(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildText(ThemeData theme) {
    if (widget.isEditing) {
      return Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                widget.onCancelEdit();
                return null;
              },
            ),
          },
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 1,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            textInputAction: TextInputAction.done,
            onSubmitted: widget.onSubmitEdit,
            onTapOutside: (_) => widget.onSubmitEdit(_controller.text),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
              ),
            ),
          ),
        ),
      );
    }

    final style = theme.textTheme.bodyLarge?.copyWith(
      decoration: widget.todo.isCompleted
          ? TextDecoration.lineThrough
          : TextDecoration.none,
      decorationThickness: 2,
      color: theme.colorScheme.onSurface,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.12,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        widget.todo.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        strutStyle: const StrutStyle(forceStrutHeight: true, height: 1.15),
        style: style,
      ),
    );
  }

  Widget _buildCategoryMenu(ThemeData theme) {
    final categoryIndex = widget.categories.indexWhere(
      (category) => category.id == widget.todo.categoryId,
    );
    final swatchIndex = categoryIndex >= 0
        ? categoryIndex % _categorySwatches.length
        : widget.todo.categoryId.hashCode.abs() % _categorySwatches.length;
    final swatch = _categorySwatches[swatchIndex];

    return PopupMenuButton<String>(
      tooltip: '',
      onSelected: widget.onCategoryChanged,
      itemBuilder: (context) => widget.categories
          .map(
            (category) => PopupMenuItem<String>(
              value: category.id,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      category.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (category.id == widget.todo.categoryId)
                    const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Color(0xFFECECEC),
                    ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: swatch.background.withValues(alpha: _hovered ? 1 : 0.8),
          border: Border.all(
            color: swatch.border.withValues(alpha: _hovered ? 1 : 0.78),
          ),
        ),
        child: Text(
          widget.todo.categoryName,
          style: theme.textTheme.labelMedium?.copyWith(
            color: swatch.text,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset offset) async {
    widget.onSelect();
    final theme = Theme.of(context);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx,
        offset.dy,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Edit',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Delete',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF6B6B),
            ),
          ),
        ),
      ],
    );

    switch (result) {
      case 'edit':
        widget.onBeginEdit();
        break;
      case 'delete':
        widget.onDelete();
        break;
      default:
        break;
    }
  }
}
