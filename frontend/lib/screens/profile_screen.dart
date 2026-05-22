import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isEditing = false;
  bool isEditingBusiness = false;
  String? _imagePath;
  final Map<String, TextEditingController> _controllers = {};
  final ImagePicker _picker = ImagePicker();

  Map<String, String> profile = {
    "name":     "",
    "email":    "",
    "phone":    "",
    "pharmacy": "",
    "address":  "",
    "joinDate": "",
  };

  @override
  void initState() {
    super.initState();
    profile.forEach((key, value) {
      _controllers[key] = TextEditingController(text: value);
    });
    _loadProfileData();
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "??";
    final names = name.trim().split(" ");
    if (names.length > 1) {
      return '${names[0][0]}${names[names.length - 1][0]}'.toUpperCase();
    }
    return names[0][0].toUpperCase();
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      const months = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return isoString;
    }
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final auth  = Provider.of<AuthProvider>(context, listen: false);
    final user  = auth.currentUser;

    if (user == null) return;

    // Derive a readable name from email if none stored in prefs yet
    final emailLocal  = (user['email'] as String).split('@').first;
    final derivedName = emailLocal
        .replaceAll(RegExp(r'[._\-]'), ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');

    setState(() {
      profile["name"]     = prefs.getString('profile_name')    ?? derivedName;
      profile["email"]    = user['email'] as String;
      profile["phone"]    = prefs.getString('profile_phone')   ?? '';
      profile["pharmacy"] = (user['pharmacy_name'] as String?) ?? derivedName;
      profile["address"]  = prefs.getString('profile_address') ?? '';
      profile["joinDate"] = _formatDate(user['created_at'] as String? ?? '');
      _imagePath          = prefs.getString('profile_image_path');
    });

    profile.forEach((key, value) {
      _controllers[key]?.text = value;
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
      if (pickedFile != null) {
        final prefs = await SharedPreferences.getInstance();
        setState(() => _imagePath = pickedFile.path);
        await prefs.setString('profile_image_path', pickedFile.path);
      }
    } catch (e) {
      debugPrint("Image picker error: $e");
    }
  }

  Future<void> _saveProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final auth  = Provider.of<AuthProvider>(context, listen: false);

    final newName     = _controllers['name']?.text     ?? '';
    final newPhone    = _controllers['phone']?.text    ?? '';
    final newAddress  = _controllers['address']?.text  ?? '';
    final newPharmacy = _controllers['pharmacy']?.text ?? '';

    // Save non-sensitive fields locally
    await prefs.setString('profile_name',    newName);
    await prefs.setString('profile_phone',   newPhone);
    await prefs.setString('profile_address', newAddress);

    // Save pharmacy name to the DB via AuthProvider
    if (newPharmacy.isNotEmpty) {
      await auth.updatePharmacyName(newPharmacy);
    }

    setState(() {
      profile["name"]     = newName;
      profile["phone"]    = newPhone;
      profile["address"]  = newAddress;
      profile["pharmacy"] = newPharmacy;
    });
  }

  Future<void> _signOut() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
    }
  }

  @override
  void dispose() {
    for (var c in _controllers.values) c.dispose();
    super.dispose();
  }

  Widget buildField(String label, String key, IconData icon,
      bool isDark, Color textColor, bool localEditing) {
    final Color fieldColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final Color iconColor  = isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5);
    // email and joinDate are always read-only
    final bool readOnly = key == "email" || key == "joinDate";

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          (localEditing && !readOnly)
              ? TextField(
                  controller: _controllers[key],
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: fieldColor,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: isDark ? Colors.white10 : Colors.transparent)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: iconColor)),
                  ),
                )
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: fieldColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark ? Colors.white10 : Colors.transparent),
                  ),
                  child: Text(profile[key] ?? '',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings    = Provider.of<SettingsProvider>(context);
    final isDark      = settings.darkMode;

    final Color bgColor    = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final Color cardColor  = isDark ? const Color(0xFF161E2F) : Colors.white;
    final Color textColor  = isDark ? Colors.white : const Color(0xFF1E293B);
    final Color accentColor = isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Profile",
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(children: [
              Center(
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 55,
                      backgroundColor:
                          isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                      backgroundImage:
                          (_imagePath != null && _imagePath!.isNotEmpty)
                              ? FileImage(File(_imagePath!))
                              : null,
                      child: (_imagePath == null || _imagePath!.isEmpty)
                          ? Text(_getInitials(profile["name"]!),
                              style: TextStyle(
                                  color: accentColor,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold))
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: accentColor,
                        child: const Icon(Icons.camera_alt,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text(profile["name"]!,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
              const SizedBox(height: 4),
              Text(profile["pharmacy"]!,
                  style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5)),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              sectionCard(
                title: "Personal Info",
                icon: Icons.person_outline_rounded,
                color: const Color(0xFF10B981),
                cardColor: cardColor,
                textColor: textColor,
                isDark: isDark,
                action: IconButton(
                  onPressed: () {
                    if (isEditing) _saveProfileData();
                    setState(() => isEditing = !isEditing);
                  },
                  icon: Icon(
                      isEditing ? Icons.check_circle : Icons.edit_note,
                      color: accentColor,
                      size: 28),
                ),
                children: [
                  buildField("Full Name", "name",
                      Icons.badge_outlined, isDark, textColor, isEditing),
                  buildField("Email Address", "email",
                      Icons.alternate_email_rounded, isDark, textColor, false),
                  buildField("Phone Number", "phone",
                      Icons.phone_android_rounded, isDark, textColor, isEditing),
                ],
              ),

              const SizedBox(height: 20),

              sectionCard(
                title: "Business Details",
                icon: Icons.storefront_outlined,
                color: accentColor,
                cardColor: cardColor,
                textColor: textColor,
                isDark: isDark,
                action: IconButton(
                  onPressed: () {
                    if (isEditingBusiness) _saveProfileData();
                    setState(() => isEditingBusiness = !isEditingBusiness);
                  },
                  icon: Icon(
                      isEditingBusiness ? Icons.check_circle : Icons.edit_note,
                      color: accentColor,
                      size: 28),
                ),
                children: [
                  buildField("Pharmacy Name", "pharmacy",
                      Icons.local_pharmacy_outlined, isDark, textColor, isEditingBusiness),
                  buildField("Location", "address",
                      Icons.map_outlined, isDark, textColor, isEditingBusiness),
                ],
              ),

              const SizedBox(height: 20),

              sectionCard(
                title: "Account Details",
                icon: Icons.calendar_month_outlined,
                color: Colors.orange,
                cardColor: cardColor,
                textColor: textColor,
                isDark: isDark,
                children: [
                  buildField("Member Since", "joinDate",
                      Icons.event_available, isDark, textColor, false),
                ],
              ),

              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
                icon: const Icon(Icons.settings_suggest_rounded, size: 20),
                label: const Text("Configure Preferences",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),

              const SizedBox(height: 16),

              TextButton(
                onPressed: _signOut,
                child: const Text("Sign Out of Account",
                    style: TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),

              const SizedBox(height: 40),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget sectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Color cardColor,
    required Color textColor,
    required bool isDark,
    List<Widget>? children,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent),
        boxShadow: [
          if (!isDark)
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 8))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
          ]),
          if (action != null) action,
        ]),
        const SizedBox(height: 20),
        ...?children,
      ]),
    );
  }
}