import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class LowStockAlert {
  final String name;
  final int quantity;
  final int minStock;
  final String category;
  final String severity;

  LowStockAlert({
    required this.name,
    required this.quantity,
    required this.minStock,
    required this.category,
    required this.severity,
  });
}

class AlertsScreen extends StatelessWidget {
  final List<LowStockAlert> alerts = [
    LowStockAlert(name: "Paracetamol 500mg", quantity: 12, minStock: 50, category: "Analgesics", severity: "urgent"),
    LowStockAlert(name: "Amoxicillin 250mg", quantity: 8, minStock: 30, category: "Antibiotics", severity: "critical"),
    LowStockAlert(name: "Ibuprofen 400mg", quantity: 15, minStock: 40, category: "Analgesics", severity: "urgent"),
    LowStockAlert(name: "Cetirizine 10mg", quantity: 22, minStock: 35, category: "Antihistamines", severity: "warning"),
    LowStockAlert(name: "Omeprazole 20mg", quantity: 5, minStock: 25, category: "Antacids", severity: "critical"),
    LowStockAlert(name: "Aspirin 100mg", quantity: 18, minStock: 45, category: "Analgesics", severity: "urgent"),
    LowStockAlert(name: "Metformin 500mg", quantity: 25, minStock: 50, category: "Antidiabetics", severity: "warning"),
    LowStockAlert(name: "Lisinopril 10mg", quantity: 10, minStock: 30, category: "Antihypertensives", severity: "critical"),
  ];

  AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final bool isDarkMode = settings.darkMode;

    final criticalCount = alerts.where((a) => a.severity == 'critical').length;
    final urgentCount = alerts.where((a) => a.severity == 'urgent').length;
    final warningCount = alerts.where((a) => a.severity == 'warning').length;

    final bgColor = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          _buildHeader(context, isDarkMode),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildSummaryCard(criticalCount.toString(), "Critical", [const Color(0xFFEF4444), const Color(0xFFB91C1C)]),
                      const SizedBox(width: 10),
                      _buildSummaryCard(urgentCount.toString(), "Urgent", [const Color(0xFFF97316), const Color(0xFFC2410C)]),
                      const SizedBox(width: 10),
                      _buildSummaryCard(warningCount.toString(), "Warning", [const Color(0xFFEAB308), const Color(0xFFA16207)]),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildListSection(context, isDarkMode, cardColor),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode
              ? [const Color(0xFFEA580C), const Color(0xFF9A3412)]
              : [const Color(0xFFF97316), const Color(0xFFEA580C)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Stock Alerts",
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          Text("Medicines below minimum levels",
              style: TextStyle(color: Color(0xFFFFEDD5), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String count, String label, List<Color> colors) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(color: colors[0].withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
            ]
        ),
        child: Column(
          children: [
            Text(count, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildListSection(BuildContext context, bool isDarkMode, Color cardColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: isDarkMode ? Border.all(color: Colors.white.withOpacity(0.05)) : null,
        boxShadow: isDarkMode ? [] : [const BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.alertTriangle, color: Color(0xFFF97316), size: 22),
              const SizedBox(width: 10),
              Text(
                  "Restock Required",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : const Color(0xFF1E293B)
                  )
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...alerts.map((alert) => _buildAlertItem(context, alert, isDarkMode)).toList(),
        ],
      ),
    );
  }

  Widget _buildAlertItem(BuildContext context, LowStockAlert alert, bool isDarkMode) {
    Color severityColor;
    Color itemBg;

    switch (alert.severity) {
      case "critical":
        severityColor = const Color(0xFFEF4444);
        itemBg = isDarkMode ? const Color(0xFFEF4444).withOpacity(0.1) : const Color(0xFFFEF2F2);
        break;
      case "urgent":
        severityColor = const Color(0xFFF97316);
        itemBg = isDarkMode ? const Color(0xFFF97316).withOpacity(0.1) : const Color(0xFFFFF7ED);
        break;
      case "warning":
        severityColor = const Color(0xFFEAB308);
        itemBg = isDarkMode ? const Color(0xFFEAB308).withOpacity(0.1) : const Color(0xFFFEFCE8);
        break;
      default:
        severityColor = Colors.grey;
        itemBg = isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.shade50;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: severityColor, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.name,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDarkMode ? Colors.white : const Color(0xFF1F2937)
                    )
                ),
                Text(alert.category,
                    style: TextStyle(
                        color: isDarkMode ? Colors.white38 : Colors.blueGrey,
                        fontSize: 13
                    )
                ),
                const SizedBox(height: 8),
                Text(
                  "Order: ${alert.minStock - alert.quantity} units to reach min.",
                  style: TextStyle(color: severityColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text("${alert.quantity}",
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : const Color(0xFF1F2937)
                  )
              ),
              const Text("left", style: TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}