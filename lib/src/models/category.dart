class Category {
  const Category({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;

  bool get isInbox => name.toLowerCase() == 'inbox';

  Category copyWith({
    String? id,
    String? name,
    int? createdAt,
    int? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Category.fromMap(Map<String, Object?> map) {
    return Category(
      id: map['id']! as String,
      name: map['name']! as String,
      createdAt: map['created_at']! as int,
      updatedAt: map['updated_at']! as int,
    );
  }
}
