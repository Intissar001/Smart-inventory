class Medicine {
  final int? id;
  final int userId;               // 👈 Nouveau champ
  final String name;
  final String? dosage;
  final String? form;
  final String? category;
  final String? manufacturer;
  final String? barcode;
  final int stock;
  final int minStock;
  final String unit;
  final String? notes;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Medicine({
    this.id,
    required this.userId,
    required this.name,
    this.dosage,
    this.form,
    this.category,
    this.manufacturer,
    this.barcode,
    this.stock = 0,
    this.minStock = 10,
    this.unit = 'box',
    this.notes,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
  });
  factory Medicine.fromMap(Map<String, dynamic> map) {
    return Medicine(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      name: map['name'] as String,
      dosage: map['dosage'] as String?,
      form: map['form'] as String?,
      category: map['category'] as String?,
      manufacturer: map['manufacturer'] as String?,
      barcode: map['barcode'] as String?,
      stock: map['stock'] as int,
      minStock: map['min_stock'] as int,
      unit: map['unit'] as String? ?? 'box',
      notes: map['notes'] as String?,
      imagePath: map['image_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine.fromMap(json);
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'dosage': dosage,
      'form': form,
      'category': category,
      'manufacturer': manufacturer,
      'barcode': barcode,
      'stock': stock,
      'min_stock': minStock,
      'unit': unit,
      'notes': notes,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Medicine copyWith({
    int? id,
    int? userId,
    String? name,
    String? dosage,
    String? form,
    String? category,
    String? manufacturer,
    String? barcode,
    int? stock,
    int? minStock,
    String? unit,
    String? notes,
    String? imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Medicine(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      form: form ?? this.form,
      category: category ?? this.category,
      manufacturer: manufacturer ?? this.manufacturer,
      barcode: barcode ?? this.barcode,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      unit: unit ?? this.unit,
      notes: notes ?? this.notes,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}