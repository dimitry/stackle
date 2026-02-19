import 'package:flutter/material.dart';

import '../models/category.dart';
import '../state/app_controller.dart';

class CategoryManagementDialog extends StatefulWidget {
  const CategoryManagementDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<CategoryManagementDialog> createState() =>
      _CategoryManagementDialogState();
}

class _CategoryManagementDialogState extends State<CategoryManagementDialog> {
  final TextEditingController _newCategoryController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.categories;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Manage Categories'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: categories.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isInbox = category.isInbox;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              category.name,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          if (isInbox)
                            Text(
                              'Required',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            )
                          else ...<Widget>[
                            TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => _renameCategory(category),
                              child: const Text('Rename'),
                            ),
                            TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => _deleteCategory(category),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (categories.length == 1)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Only Inbox exists right now. Add a category to organize focused views.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _newCategoryController,
                    enabled: !_submitting,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'New category',
                      hintText: 'Work',
                    ),
                    onSubmitted: (_) => _createCategory(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _submitting ? null : _createCategory,
                  child: const Text('Add'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _createCategory() async {
    final text = _newCategoryController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Category name cannot be empty.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.controller.createCategory(text);

    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      _error = error;
      if (error == null) {
        _newCategoryController.clear();
      }
    });
  }

  Future<void> _renameCategory(Category category) async {
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => _CategoryNameDialog(
        title: 'Rename category',
        initialValue: category.name,
      ),
    );

    if (nextName == null) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.controller.renameCategory(category, nextName);

    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  Future<void> _deleteCategory(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${category.name}?'),
        content: const Text('Todos in this category will move to Inbox.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3A1E1E),
              foregroundColor: const Color(0xFFFFD8D8),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.controller.deleteCategory(category);

    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      _error = error;
    });
  }
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({required this.title, required this.initialValue});

  final String title;
  final String initialValue;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Category name',
          isDense: true,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }
}
