// lib/models/catalog_medicine.dart
//
// Represents one entry in the global medicines catalog (from medicines2.json).
// The catalog itself (name, manufacturer, category) is shared across all users.
// Per-user data (stock, min_stock) lives in a separate table joined at query time.

class CatalogMedicine {
  final int    id;           // catalog_medicines.id (global)
  final String name;
  final String manufacturer;
  final String category;

  // Per-user fields (null when not yet personalised)
  final int userId;
  int stock;
  int minStock;

  CatalogMedicine({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.category,
    required this.userId,
    this.stock    = 0,
    this.minStock = 0,
  });

  // ── From a JOIN row returned by CatalogRepository ──────────
  factory CatalogMedicine.fromRow(Map<String, dynamic> row, int userId) {
    return CatalogMedicine(
      id:           row['id']           as int,
      name:         (row['name']         as String? ?? '').trim(),
      manufacturer: (row['manufacturer'] as String? ?? '').trim(),
      category:     (row['category']     as String? ?? '').trim(),
      userId:       userId,
      stock:        (row['stock']        as int?) ?? 0,
      minStock:     (row['min_stock']    as int?) ?? 0,
    );
  }

  bool get isLowStock => stock < minStock && minStock > 0;

  @override
  String toString() =>
      'CatalogMedicine(id: $id, name: $name, stock: $stock, min: $minStock)';
}
