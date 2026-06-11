// lib/services/auth_service.dart
//
// Thin service wrapper used by MedicineRepository and SessionRepository
// to retrieve the currently logged-in user.
// Reads the userId persisted in SharedPreferences by AuthProvider,
// then fetches the user row from SQLite.
//
// This is intentionally lightweight — it is NOT a ChangeNotifier.
// UI-level auth state is handled by AuthProvider.

import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/user.dart';

class AuthService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Cached user for the duration of the app session
  User? _currentUser;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // ── Restore from SharedPreferences ────────────────────────────────────────
  /// Call this once at app start (after AuthProvider.restoreSession()).
  /// Repositories will then have a valid currentUser immediately.
  Future<void> restore() async {
    if (_currentUser != null) return; // already loaded
    final prefs = await SharedPreferences.getInstance();
    final int? userId = prefs.getInt('userId');
    if (userId == null) return;
    final db = await DatabaseHelper().database;
    final rows =
        await db.query('users', where: 'id = ?', whereArgs: [userId]);
    if (rows.isNotEmpty) {
      _currentUser = User.fromMap(rows.first);
    }
  }

  // ── Called by AuthProvider after login / register ─────────────────────────
  void setUser(User user) {
    _currentUser = user;
  }

  // ── Called by AuthProvider on logout ─────────────────────────────────────
  void clearUser() {
    _currentUser = null;
  }
}
