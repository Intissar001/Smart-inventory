import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class Medicine {
  int id;
  String name;
  String manufacturer;
  int stock;
  int minStock;
  String category;

  Medicine({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.stock,
    required this.minStock,
    required this.category,
  });
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final List<Medicine> _medicines = [
    Medicine(id: 1, name: "Paracetamol 500mg", manufacturer: "PharmaCorp Inc.", stock: 145, minStock: 50, category: "Analgesic"),
    Medicine(id: 2, name: "Amoxicillin 250mg", manufacturer: "MediLife Pharma", stock: 98, minStock: 40, category: "Antibiotic"),
    Medicine(id: 3, name: "Ibuprofen 400mg", manufacturer: "HealthCare Ltd.", stock: 112, minStock: 30, category: "Analgesic"),
    Medicine(id: 4, name: "Vitamin C 1000mg", manufacturer: "VitaHealth", stock: 78, minStock: 20, category: "Vitamin"),
  ];

  String _searchQuery = "";

  void _showStyledToast(String message, IconData icon, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.only(bottom: 100, left: 20, right: 20),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _deleteMedicine(Medicine m) {
    final isDark = Provider.of<SettingsProvider>(context, listen: false).darkMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text("Delete Medicine?", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        content: Text("This will permanently remove ${m.name}.", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              setState(() {
                _medicines.removeWhere((item) => item.id == m.id);
              });
              Navigator.pop(context);
              _showStyledToast("Item Deleted Successfully", Icons.delete_forever, const Color(0xFFEF4444));
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addMedicine() {
    final isDark = Provider.of<SettingsProvider>(context, listen: false).darkMode;
    final nameController = TextEditingController();
    final manController = TextEditingController();
    final catController = TextEditingController();
    final stockController = TextEditingController();
    final minStockController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text("Add New Medicine", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPopupTextField(nameController, "Name", isDark),
              _buildPopupTextField(manController, "Manufacturer", isDark),
              _buildPopupTextField(catController, "Category", isDark),
              _buildPopupTextField(stockController, "Current Stock", isDark, isNumber: true),
              _buildPopupTextField(minStockController, "Minimum Required Stock", isDark, isNumber: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              setState(() {
                _medicines.add(Medicine(
                  id: DateTime.now().millisecondsSinceEpoch,
                  name: nameController.text,
                  manufacturer: manController.text,
                  stock: int.tryParse(stockController.text) ?? 0,
                  minStock: int.tryParse(minStockController.text) ?? 0,
                  category: catController.text,
                ));
              });
              Navigator.pop(context);
              _showStyledToast("Medicine Added!", Icons.check_circle, const Color(0xFF10B981));
            },
            child: const Text("Add Product", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildPopupTextField(TextEditingController controller, String label, bool isDark, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
          filled: true,
          fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF10B981))),
        ),
      ),
    );
  }

  void _editMedicine(Medicine m) {
    final isDark = Provider.of<SettingsProvider>(context, listen: false).darkMode;
    final nameController = TextEditingController(text: m.name);
    final manController = TextEditingController(text: m.manufacturer);
    final catController = TextEditingController(text: m.category);
    final stockController = TextEditingController(text: m.stock.toString());
    final minStockController = TextEditingController(text: m.minStock.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text("Edit ${m.name}", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPopupTextField(nameController, "Name", isDark),
              _buildPopupTextField(manController, "Manufacturer", isDark),
              _buildPopupTextField(catController, "Category", isDark),
              _buildPopupTextField(stockController, "Current Stock", isDark, isNumber: true),
              _buildPopupTextField(minStockController, "Minimum Required Stock", isDark, isNumber: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              setState(() {
                m.name = nameController.text;
                m.manufacturer = manController.text;
                m.category = catController.text;
                m.stock = int.tryParse(stockController.text) ?? m.stock;
                m.minStock = int.tryParse(minStockController.text) ?? m.minStock;
              });
              Navigator.pop(context);
              _showStyledToast("Changes Saved!", Icons.save, const Color(0xFF6366F1));
            },
            child: const Text("Update", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _viewDetails(Medicine m) {
    final isDark = Provider.of<SettingsProvider>(context, listen: false).darkMode;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.name,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black
                )
            ),
            const SizedBox(height: 10),
            Text("Manufacturer: ${m.manufacturer}", style: TextStyle(color: isDark ? Colors.white60 : Colors.black87)),
            Text("Category: ${m.category}", style: TextStyle(color: isDark ? Colors.white60 : Colors.black87)),
            const Divider(height: 30, color: Colors.white10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Available Stock:", style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                Text("${m.stock}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: m.stock < m.minStock ? Colors.red : const Color(0xFF10B981))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Minimum Required:", style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                Text("${m.minStock}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<SettingsProvider>(context).darkMode;
    final filteredMedicines = _medicines.where((m) {
      final query = _searchQuery.toLowerCase();
      return m.name.toLowerCase().contains(query) ||
          m.category.toLowerCase().contains(query);
    }).toList();

    return Container(
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: Column(
        children: [
          _buildHeader(isDark),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildActionButtons(isDark),
                const SizedBox(height: 16),
                ...filteredMedicines.map((m) => _buildMedicineCard(m, isDark)).toList(),
                if (filteredMedicines.isEmpty) _buildEmptyState(isDark),
                const SizedBox(height: 16),
                _buildSummaryCard(isDark),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFF10B981),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Medicine Catalog", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text("${_medicines.length} products total", style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 20),
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: "Search name or category...",
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _addMedicine,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add New Product"),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildMedicineCard(Medicine m, bool isDark) {
    bool isLowStock = m.stock < m.minStock;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLowStock ? Colors.red.withOpacity(0.3) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(m.category, style: const TextStyle(color: Color(0xFF6366F1), fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${m.stock}", style: TextStyle(fontSize: 22, color: isLowStock ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontWeight: FontWeight.bold)),
                      Text("min: ${m.minStock}", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    onPressed: () => _deleteMedicine(m),
                  )
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.business_rounded, m.manufacturer, isDark),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _editMedicine(m),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text("Edit", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _viewDetails(m),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text("Details", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: isDark ? Colors.white38 : Colors.grey),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(bool isDark) {
    int totalStock = _medicines.fold(0, (sum, item) => sum + item.stock);
    int lowStockCount = _medicines.where((m) => m.stock < m.minStock).length;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem("${_medicines.length}", "Products"),
          _summaryItem("$totalStock", "Total Stock"),
          _summaryItem("$lowStockCount", "Below Min"),
        ],
      ),
    );
  }

  Widget _summaryItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: isDark ? Colors.white10 : Colors.grey.shade200),
            const SizedBox(height: 16),
            Text("No medicines found", style: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}