import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';
import 'scanner_screen.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSession());
  }

  Future<void> _ensureSession() async {
    final auth     = context.read<AuthProvider>();
    final provider = context.read<SessionProvider>();
    final userId   = auth.currentUser?['id'] as int?;
    if (userId != null && provider.sessionId == null) {
      await provider.loadOrCreateSession(userId);
    }
  }

  Future<void> _addEmptyZone() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("New Zone"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "e.g. Shelf C, Zone 4…",
            labelText: "Zone name",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text("Add")),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<SessionProvider>().addEmptyZone(name);
  }

  Future<void> _rescanZone(String lockedZoneName) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const CameraScanScreen()),
    );
    if (result == null || !mounted) return;
    final lockedResult = Map<String, dynamic>.from(result)
      ..['zoneName'] = lockedZoneName;
    await context.read<SessionProvider>().handleScanResult(lockedResult);
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsProvider>().darkMode;
    final sp     = context.watch<SessionProvider>();

    if (sp.loading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(isDark, sp),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              children: [
                Text("Scanned Zones",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isDark ? Colors.white : const Color(0xFF1E293B))),
                const SizedBox(height: 16),
                if (sp.zones.isEmpty)
                  _buildEmptyState(isDark)
                else
                  ...sp.zones.asMap().entries
                      .map((e) => _buildZoneCard(e.value, e.key, isDark)),
                const SizedBox(height: 24),
                _buildActionButtons(isDark, sp),
                const SizedBox(height: 24),
                _buildSessionInfo(isDark, sp),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────

  Widget _buildHeader(bool isDark, SessionProvider sp) {
    final progress = sp.zones.isEmpty ? 0.0 : sp.doneZones / sp.zones.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFF3B82F6),
        borderRadius: const BorderRadius.only(
          bottomLeft:  Radius.circular(32),
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
                children: [
                  const Text("Inventory Session",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  Text(sp.formattedDate,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_rounded,
                    color: Colors.white, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withOpacity(0.6)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryItem(
                        "Total Boxes",
                        "${sp.totalBoxes}",
                        isDark ? const Color(0xFF818CF8) : const Color(0xFF2563EB),
                        isDark),
                    _summaryItem(
                        "Progress",
                        "${sp.doneZones}/${sp.zones.length}",
                        const Color(0xFF10B981),
                        isDark),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Completion",
                        style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text("${(progress * 100).round()}%",
                        style: TextStyle(
                            color: isDark
                                ? const Color(0xFF10B981)
                                : const Color(0xFF2563EB),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(0.05)
                        : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(isDark
                        ? const Color(0xFF10B981)
                        : const Color(0xFF3B82F6)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color, bool isDark) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black45,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 28, fontWeight: FontWeight.bold)),
      ]);

  // ── Empty state ─────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) => Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : const Color(0xFFE2E8F0)),
        ),
        child: Column(children: [
          Icon(Icons.inbox_outlined,
              size: 48,
              color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 12),
          Text("No zones scanned yet",
              style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('Tap "Scan Zone" or "Add Zone" to start',
              style: TextStyle(
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                  fontSize: 13)),
        ]),
      );

  // ── Zone card ───────────────────────────────────────────────

  static const List<Color> _zonePalette = [
    Color(0xFF6366F1), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFFEC4899), Color(0xFF8B5CF6),
    Color(0xFFF97316), Color(0xFF06B6D4),
  ];

  Widget _buildZoneCard(ZoneEntry zone, int zoneIndex, bool isDark) {
    final bool isDone = zone.status == 'Done';
    final Color accent = isDone
        ? _zonePalette[zoneIndex % _zonePalette.length]
        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDone
                ? accent.withOpacity(0.12)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // ── Card body ─────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : const Color(0xFFE8EDF2),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Zone header ───────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(zone.name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B))),
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(
                                  isDone
                                      ? Icons.check_circle_outline
                                      : Icons.hourglass_empty_rounded,
                                  size: 12,
                                  color: isDone ? accent : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isDone
                                      ? (zone.time.isNotEmpty
                                          ? 'Scanned at ${zone.time}'
                                          : 'Done')
                                      : 'Pending scan',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: isDone ? accent : Colors.grey,
                                      fontWeight: FontWeight.w500),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Box count badge
                        Column(children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(isDone ? 0.12 : 0.06),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              isDone ? '${zone.totalBoxes}' : '—',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: isDone ? accent : Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text('boxes',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isDone ? accent : Colors.grey,
                                  fontWeight: FontWeight.w500)),
                        ]),
                      ],
                    ),
                  ),

                  // ── Medicine rows ─────────────────────────
                  if (isDone && zone.meds.isNotEmpty) ...[
                    Divider(
                        height: 1,
                        thickness: 0.5,
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : const Color(0xFFF1F5F9)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Detected medicines",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black45)),
                          const SizedBox(height: 8),
                          ...zone.meds.map((med) =>
                              _buildMedRow(med, accent, isDark, zone.id)),
                        ],
                      ),
                    ),
                  ],

                  if (isDone && zone.meds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 14, 6),
                      child: Text('No medicines identified',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade400,
                              fontStyle: FontStyle.italic)),
                    ),

                  // ── Rescan / Scan button ───────────────────
                  Divider(
                      height: 1,
                      thickness: 0.5,
                      color: isDark
                          ? Colors.white.withOpacity(0.06)
                          : const Color(0xFFF1F5F9)),
                  InkWell(
                    onTap: () => _rescanZone(zone.name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.replay_rounded, size: 14, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            isDone ? "Rescan this zone" : "Scan this zone",
                            style: TextStyle(
                                fontSize: 12,
                                color: accent,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Accent left strip ──────────────────────────────
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topLeft:    Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Med row ─────────────────────────────────────────────────

  Widget _buildMedRow(ZoneMedEntry med, Color accent, bool isDark, int zoneId) {
    final hasDetail = med.dosage.isNotEmpty || med.form.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.medication_outlined, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name.isNotEmpty ? med.name : '—',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1E293B))),
                if (hasDetail)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      if (med.form.isNotEmpty)
                        _miniChip(med.form, const Color(0xFF0EA5E9)),
                      if (med.form.isNotEmpty && med.dosage.isNotEmpty)
                        const SizedBox(width: 5),
                      if (med.dosage.isNotEmpty)
                        _miniChip(med.dosage, const Color(0xFFF59E0B)),
                    ]),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('× ${med.count}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: accent)),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600)),
      );

  // ── Action buttons ──────────────────────────────────────────

  Widget _buildActionButtons(bool isDark, SessionProvider sp) {
    return Column(
      children: [
        // Row 1: Scan Zone + Add Zone
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(builder: (_) => const CameraScanScreen()),
                  );
                  if (result != null && mounted) {
                    await context
                        .read<SessionProvider>()
                        .handleScanResult(result);
                  }
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text("Scan Zone",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 60),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _addEmptyZone,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text("Add Zone",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: const Color(0xFF6366F1),
                minimumSize: const Size(0, 60),
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Row 2: Save + Exit
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await sp.saveSession();
                  if (!mounted) return;
                  final auth   = context.read<AuthProvider>();
                  final userId = auth.currentUser?['id'] as int?;
                  if (userId != null) {
                    await context
                        .read<SessionProvider>()
                        .loadOrCreateSession(userId);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Session saved successfully!"),
                      backgroundColor: Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.save_rounded, size: 20),
                label: const Text("Save"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, '/dashboard', (r) => false),
                icon: const Icon(Icons.close_rounded, size: 20),
                label: const Text("Exit"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Session info ────────────────────────────────────────────

  Widget _buildSessionInfo(bool isDark, SessionProvider sp) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _infoRow("Session ID", sp.sessionCode, isDark),
          const SizedBox(height: 12),
          _infoRow("Started", sp.formattedStart, isDark),
          const SizedBox(height: 12),
          _infoRow("Duration", sp.duration, isDark),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black45,
                  fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black)),
          ),
        ],
      );
}