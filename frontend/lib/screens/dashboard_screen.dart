import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'scanner_screen.dart';
import 'session_screen.dart';
import 'catalog_screen.dart';
import '../providers/settings_provider.dart';
import 'alerts_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  void _onNavigateToSession() {
    setState(() {
      _currentIndex = 1;
    });
  }

  void _onNavigateToAlerts() {
    setState(() {
      _currentIndex = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<SettingsProvider, bool>((p) => p.darkMode);

    final List<Widget> _pages = [
      _HomeContent(
          onViewSession: _onNavigateToSession,
          onViewAlerts: _onNavigateToAlerts,
          isDark: isDark
      ),
      const SessionScreen(),
      const CatalogScreen(),
      AlertsScreen(),
      const ReportsScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildFab(isDark),
      bottomNavigationBar: _buildBottomAppBar(isDark),
    );
  }

  Widget _buildFab(bool isDark) {
    return Container(
      height: 64,
      width: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFD946EF)]),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(isDark ? 0.6 : 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const CameraScanScreen())),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildBottomAppBar(bool isDark) {
    return BottomAppBar(
      height: 75,
      notchMargin: 10,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const CircularNotchedRectangle(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Row(
            children: [
              _navItem(Icons.home_outlined, "Home", 0, isDark),
              _navItem(Icons.assignment_outlined, "Session", 1, isDark),
              _navItem(Icons.medication_outlined, "Catalog", 2, isDark),
            ],
          ),
          const SizedBox(width: 95),
          Row(
            children: [
              _navItem(Icons.notifications_none_outlined, "Alerts", 3, isDark),
              _navItem(Icons.bar_chart_outlined, "Report", 4, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index, bool isDark) {
    bool isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
                size: 24),
            Text(label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final VoidCallback onViewSession;
  final VoidCallback onViewAlerts;
  final bool isDark;
  const _HomeContent({required this.onViewSession, required this.onViewAlerts, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
              : [const Color(0xFFEEF2FF), const Color(0xFFFDF2F8)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const _DashboardLogo(),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Smart Inventory",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: isDark ? Colors.white : Colors.black)),
                        Text("AI-Powered System",
                            style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : Colors.grey,
                                fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    _CircleIconButton(
                      icon: Icons.settings_outlined,
                      onTap: () => Navigator.pushNamed(context, '/settings'),
                    ),
                    const SizedBox(width: 8),
                    _CircleIconButton(
                      icon: Icons.person_outline,
                      onTap: () => Navigator.pushNamed(context, '/profile'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const _HeroCard(),
                  const SizedBox(height: 16),
                  _LowStockAlertsCard(isDark: isDark, onViewAll: onViewAlerts),
                  const SizedBox(height: 16),
                  _RecentScanCard(isDark: isDark, onTap: onViewSession),
                  const SizedBox(height: 16),
                  _TipCard(isDark: isDark),
                  const SizedBox(height: 120),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockAlertsCard extends StatelessWidget {
  final bool isDark;
  final VoidCallback onViewAll;
  const _LowStockAlertsCard({required this.isDark, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey.withOpacity(0.1)),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    Text("Stock Alerts",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black)),
                  ],
                ),
                TextButton(
                  onPressed: onViewAll,
                  child: const Row(
                    children: [
                      Text("View All", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                      Icon(Icons.arrow_forward, color: Colors.orange, size: 16),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 10),
            _alertItem("Paracetamol 500mg", 12, 50, "Urgent", Colors.orange),
            _alertItem("Amoxicillin 250mg", 8, 30, "Critical", Colors.red),
            _alertItem("Ibuprofen 400mg", 15, 40, "Urgent", Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _alertItem(String name, int current, int minStock, String status, Color color) {
    double progress = current / minStock;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white10 : Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text("$current/$minStock", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentScanCard extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _RecentScanCard({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Recent Scan",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text("Completed",
                    style: TextStyle(
                        color: Color(0xFF16A34A), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medication_outlined, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("302 boxes counted",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Text("Today at 09:30 AM", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF3B82F6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text("View",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardLogo extends StatelessWidget {
  const _DashboardLogo();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (context) => const CameraScanScreen())),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFD946EF)]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(children: [
          const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Icon(Icons.bolt, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text("Quick Action", style: TextStyle(color: Colors.white70))
                ]),
                SizedBox(height: 8),
                Text("Start Scanning",
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                Text("Count medicines with AI", style: TextStyle(color: Colors.white70)),
              ]),
          Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 36))),
        ]),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final bool isDark;
  const _TipCard({required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(24),
        border: Border(left: BorderSide(color: Colors.amber.shade600, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("💡", style: TextStyle(fontSize: 14)),
                    SizedBox(width: 6),
                    Text("Quick Tip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  "Hold your phone steady for 2 seconds for best AI detection results!",
                  style: TextStyle(color: Color(0xFF92400E), fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = context.select<SettingsProvider, bool>((p) => p.darkMode);

    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22, color: isDark ? Colors.white : Colors.black),
      style: IconButton.styleFrom(
          backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.5),
          shape: const CircleBorder()),
    );
  }
}