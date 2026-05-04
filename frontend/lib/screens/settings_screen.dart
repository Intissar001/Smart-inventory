import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: settings.darkMode
                ? [const Color(0xFF030303), const Color(0xFF0E0E0E)]
                : [const Color(0xFFE3F2FD), Colors.white],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 100,
              floating: false,
              pinned: true,
              backgroundColor: settings.darkMode ? const Color(0xFF0F172A) : const Color(0xFF2196F3),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Settings", style: TextStyle(color: Colors.white, fontSize: 18)),
                    Text("Configure your app", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildSectionCard(
                      settings: settings,
                      title: "Appearance",
                      icon: Icons.dark_mode_outlined,
                      iconColor: Colors.blue,
                      children: [
                        _buildSwitchTile(settings, "Dark Mode", "Use dark theme", settings.darkMode, (v) => settings.setDarkMode(v)),
                      ],
                    ),

                    _buildSectionCard(
                      settings: settings,
                      title: "Notifications",
                      icon: Icons.notifications_none_outlined,
                      iconColor: Colors.orange,
                      children: [
                        _buildSwitchTile(settings, "Push Notifications", "Get alerts for low stock", settings.notifications, (v) => settings.setNotifications(v)),
                      ],
                    ),

                    _buildSectionCard(
                      settings: settings,
                      title: "Aid Center",
                      icon: Icons.help_outline_rounded,
                      iconColor: Colors.redAccent,
                      children: [
                        _buildClickTile(settings, "Help Center", "Guides & FAQ", () {
                        }),
                        const Divider(height: 1),
                        _buildClickTile(settings, "Contact Support", "Talk to us", () {
                        }),
                      ],
                    ),

                    const SizedBox(height: 24),
                    _buildBrandingCard(settings),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required SettingsProvider settings, required String title, required IconData icon, required Color iconColor, required List<Widget> children}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: settings.darkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: settings.darkMode ? Colors.white10 : Colors.grey.shade100)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: settings.darkMode ? Colors.white : Colors.black)),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildBrandingCard(SettingsProvider settings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFD946EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          const Text(
            "Smart Inventory",
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "Version 1.0.0",
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "© 2026 Smart Inventory. All rights reserved.",
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(SettingsProvider settings, String title, String subtitle, bool value, Function(bool) onChanged) {
    return ListTile(
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: settings.darkMode ? Colors.white : Colors.black)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: Switch(
        value: value,
        activeColor: Colors.blue,
        onChanged: onChanged,
        inactiveThumbColor: settings.darkMode ? Colors.grey.shade400 : null,
      ),
    );
  }

  Widget _buildClickTile(SettingsProvider settings, String title, String trailing, VoidCallback onTap) {
    return ListTile(
      title: Text(title, style: TextStyle(fontSize: 14, color: settings.darkMode ? Colors.white : Colors.black)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(trailing, style: const TextStyle(color: Colors.blue, fontSize: 13)),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }
}