class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    required this.categoryId,
    required this.categoryName,
    required this.sortOrder,
    required this.isCompleted,
    required this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String text;
  final String categoryId;
  final String categoryName;
  final double sortOrder;
  final bool isCompleted;
  final int? completedAt;
  final int createdAt;
  final int updatedAt;

  TodoItem copyWith({
    String? id,
    String? text,
    String? categoryId,
    String? categoryName,
    double? sortOrder,
    bool? isCompleted,
    int? completedAt,
    bool clearCompletedAt = false,
    int? createdAt,
    int? updatedAt,
  }) {
    return TodoItem(
      id: id ?? this.id,
      text: text ?? this.text,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      sortOrder: sortOrder ?? this.sortOrder,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory TodoItem.fromMap(Map<String, Object?> map) {
    return TodoItem(
      id: map['id']! as String,
      text: map['text']! as String,
      categoryId: map['category_id']! as String,
      categoryName: map['category_name']! as String,
      sortOrder: (map['sort_order']! as num).toDouble(),
      isCompleted: (map['is_completed']! as int) == 1,
      completedAt: map['completed_at'] as int?,
      createdAt: map['created_at']! as int,
      updatedAt: map['updated_at']! as int,
    );
  }
}
