import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../db/database_helper.dart';

class AuthProvider extends ChangeNotifier {
  static final AuthProvider _instance = AuthProvider._internal();
  factory AuthProvider() => _instance;
  AuthProvider._internal();

  // The currently logged-in user row from the DB, or null if not logged in
  Map<String, dynamic>? _currentUser;

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // ── Password hashing (same salt as user_repository) ───────────────────────
  String _hashPassword(String plain) {
    final bytes = utf8.encode('SmartInventory_salt:$plain');
    return sha256.convert(bytes).toString();
  }

  // ── Restore session on app start ──────────────────────────────────────────
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    if (userId != null) {
      final db = await DatabaseHelper().database;
      final rows = await db.query('users', where: 'id = ?', whereArgs: [userId]);
      if (rows.isNotEmpty) {
        _currentUser = Map<String, dynamic>.from(rows.first);
        notifyListeners();
      }
    }
  }

  // ── Sign In ───────────────────────────────────────────────────────────────
  // Returns null on success, or an error message string on failure
  Future<String?> login(String email, String password) async {
    try {
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'users',
        where: 'email = ?',
        whereArgs: [email.trim().toLowerCase()],
      );

      if (rows.isEmpty) return 'Email or password is incorrect';

      final user = rows.first;
      final storedHash = user['password_hash'] as String;
      if (_hashPassword(password) != storedHash) {
        return 'Email or password is incorrect';
      }

      // Update last_login timestamp
      await db.update(
        'users',
        {'last_login': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [user['id']],
      );

      _currentUser = Map<String, dynamic>.from(user);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('userId', user['id'] as int);

      notifyListeners();
      return null; // success
    } catch (e) {
      debugPrint('Login error: $e');
      return 'Something went wrong. Please try again.';
    }
  }

  // ── Sign Up ───────────────────────────────────────────────────────────────
  // Returns null on success, or an error message string on failure
  Future<String?> register(String email, String password) async {
    try {
      final db = await DatabaseHelper().database;

      // Check if email already used
      final existing = await db.query(
        'users',
        where: 'email = ?',
        whereArgs: [email.trim().toLowerCase()],
      );
      if (existing.isNotEmpty) return 'An account with this email already exists';

      // Derive a display name from the email  (e.g. john.doe@... → "John Doe")
      final emailLocal = email.trim().split('@').first;
      final derivedName = emailLocal
          .replaceAll(RegExp(r'[._\-]'), ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');

      final now = DateTime.now().toIso8601String();

      final id = await db.insert('users', {
        'email':         email.trim().toLowerCase(),
        'password_hash': _hashPassword(password),
        'pharmacy_name': derivedName,
        'created_at':    now,
        'last_login':    now,
      });

      final rows = await db.query('users', where: 'id = ?', whereArgs: [id]);
      _currentUser = Map<String, dynamic>.from(rows.first);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('userId', id);

      notifyListeners();
      return null; // success
    } catch (e) {
      debugPrint('Register error: $e');
      return 'Something went wrong. Please try again.';
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    notifyListeners();
  }

  // ── Update pharmacy name (saved to DB + local state) ──────────────────────
  Future<void> updatePharmacyName(String newName) async {
    if (_currentUser == null) return;
    final db = await DatabaseHelper().database;
    await db.update(
      'users',
      {'pharmacy_name': newName},
      where: 'id = ?',
      whereArgs: [_currentUser!['id']],
    );
    _currentUser = {..._currentUser!, 'pharmacy_name': newName};
    notifyListeners();
  }
}