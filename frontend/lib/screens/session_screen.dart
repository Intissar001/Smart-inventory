import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'scanner_screen.dart';
import 'package:intl/intl.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final List<Map<String, dynamic>> zones = [
    {
      "name": "Shelf A - Top",
      "boxes": 45,
      "status": "Done",
      "time": "09:15 AM",
      "meds": ["Paracetamol", "Ibuprofen", "Amoxicillin"]
    },
    {
      "name": "Shelf A - Middle",
      "boxes": 52,
      "status": "Done",
      "time": "09:22 AM",
      "meds": ["Vitamin C", "Aspirin"]
    },
    {
      "name": "Shelf A - Bottom",
      "boxes": 38,
      "status": "Done",
      "time": "09:28 AM",
      "meds": ["Insulin", "Metformin"]
    },
    {"name": "Shelf B - Top", "boxes": 41, "status": "Done", "time": "09:35 AM", "meds": ["Cetirizine"]},
    {"name": "Drawer 1", "boxes": 28, "status": "Done", "time": "09:42 AM", "meds": ["Loperamide"]},
    {"name": "Drawer 2", "boxes": 0, "status": "Pending", "time": "", "meds": []},
    {"name": "Drawer 3", "boxes": 0, "status": "Pending", "time": "", "meds": []},
    {"name": "Storage Cabinet", "boxes": 0, "status": "Pending", "time": "", "meds": []},
  ];


  void _handleScanResult(Map<String, dynamic>? result) {
    if (result == null) return;

    setState(() {
      final String zoneName = result['zoneName'];
      final int boxCount = result['count'];
      final List<String> scannedMeds = result['meds'];
      final String currentTime = DateFormat('hh:mm a').format(DateTime.now());


      int index = zones.indexWhere((z) => z['name'].toLowerCase() == zoneName.toLowerCase());

      if (index != -1) {

        zones[index]['boxes'] = boxCount;
        zones[index]['meds'] = scannedMeds;
        zones[index]['status'] = "Done";
        zones[index]['time'] = currentTime;
      } else {

        zones.add({
          "name": zoneName,
          "boxes": boxCount,
          "status": "Done",
          "time": currentTime,
          "meds": scannedMeds,
        });
      }
    });
  }

  void _showEditMedDialog(int zoneIndex, int medIndex) {
    TextEditingController editController = TextEditingController(
        text: zones[zoneIndex]['meds'][medIndex]
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Medication"),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(labelText: "Medication Name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                zones[zoneIndex]['meds'][medIndex] = editController.text;
              });
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final bool isDark = settings.darkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(isDark),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              children: [
                Text(
                  "Scanned Zones",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : const Color(0xFF1E293B)
                  ),
                ),
                const SizedBox(height: 16),
                ...zones.asMap().entries.map((entry) => _buildZoneCard(entry.value, entry.key, isDark)).toList(),
                const SizedBox(height: 24),
                _buildActionButtons(isDark),
                const SizedBox(height: 24),
                _buildSessionInfo(isDark),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFF3B82F6),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Inventory Session",
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "May 03, 2026",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_rounded, color: Colors.white, size: 28),
              )
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A).withOpacity(0.6) : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)
                ]
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryItem("Total Boxes", "${zones.where((z) => z['status'] == "Done").fold(0, (sum, z) => sum + (z['boxes'] as int))}", isDark ? const Color(0xFF818CF8) : const Color(0xFF2563EB), isDark),
                    _summaryItem("Progress", "${zones.where((z) => z['status'] == "Done").length}/${zones.length}", const Color(0xFF10B981), isDark),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Completion", style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
                    Text("${((zones.where((z) => z['status'] == "Done").length / zones.length) * 100).round()}%", style: TextStyle(color: isDark ? const Color(0xFF10B981) : const Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: zones.where((z) => z['status'] == "Done").length / zones.length,
                    minHeight: 10,
                    backgroundColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(isDark ? const Color(0xFF10B981) : const Color(0xFF3B82F6)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12, fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildZoneCard(Map<String, dynamic> zone, int zoneIndex, bool isDark) {
    bool isDone = zone['status'] == "Done";
    List<String> meds = List<String>.from(zone['meds'] ?? []);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDone
                ? (isDark ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFBBF7D0))
                : (isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0)),
            width: 1.5
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zone['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : const Color(0xFF1E293B))),
                  if (isDone)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: isDark ? Colors.white38 : Colors.grey),
                          const SizedBox(width: 4),
                          Text(zone['time'], style: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                    zone['status'],
                    style: TextStyle(
                        color: isDone ? const Color(0xFF10B981) : (isDark ? Colors.white38 : Colors.grey),
                        fontWeight: FontWeight.bold,
                        fontSize: 11
                    )
                ),
              )
            ],
          ),

          if (isDone && meds.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Divider(height: 1, thickness: 0.5),
            ),
            ...meds.asMap().entries.map((medEntry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.medication_outlined, size: 16, color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        medEntry.value,
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.blue),
                      onPressed: () => _showEditMedDialog(zoneIndex, medEntry.key),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            }).toList(),
          ],

          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  isDone ? "${zone['boxes']} boxes" : "Pending Scan",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDone ? (isDark ? Colors.white : Colors.black87) : Colors.grey.shade500
                  )
              ),
              if (isDone)
                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () async {
            final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CameraScanScreen())
            );
            _handleScanResult(result);
          },
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text("Scan Next Zone", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Session saved successfully!"),
                      backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
                },
                icon: const Icon(Icons.save_rounded, size: 20),
                label: const Text("Save"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.5)),
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
                },
                icon: const Icon(Icons.close_rounded, size: 20),
                label: const Text("Exit"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.5)),
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildSessionInfo(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _infoRow("Session ID", "INV-2026-0316-001", isDark),
          const SizedBox(height: 12),
          _infoRow("Started", "09:15 AM", isDark),
          const SizedBox(height: 12),
          _infoRow("Duration", "27 minutes", isDark),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
      ],
    );
  }
}