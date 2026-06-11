// Gère les opérations sur la table users (CRUD, authentification)
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import '../models/user.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class UserRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── Création ───────────────────────────────────────────────
  Future<User> createUser(User user) async {
    final db = await _dbHelper.database;
    final id = await db.insert('users', user.toMap());
    return user.copyWith(id: id);
  }

  // ── Lecture ────────────────────────────────────────────────
  Future<User?> getUserByEmail(String email) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email.toLowerCase().trim()],
    );
    return rows.isEmpty ? null : User.fromMap(rows.first);
  }

  Future<User?> getUserById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : User.fromMap(rows.first);
  }

  // ── Mise à jour ───────────────────────────────────────────
  Future<void> updateLastLogin(int userId) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      {'last_login': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> updateUser(User user) async {
    final db = await _dbHelper.database;
    await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  // ── Authentification ───────────────────────────────────────
  /// Vérifie les identifiants (à combiner avec un hash de mot de passe)
  /// Retourne l'utilisateur si succès, null sinon.
  /// Note : le hash doit être comparé avec un algorithme comme bcrypt.
  Future<User?> authenticate(String email, String passwordPlain) async {
    final user = await getUserByEmail(email);
    if (user == null) return null;
    // Ici on compare le mot de passe en clair avec le hash stocké.
    // Dans une vraie application, utiliser `bcrypt` ou `crypto`.
    // Exemple simplifié (à remplacer par bcrypt.check):
    final isValid = _verifyPassword(passwordPlain, user.passwordHash);
    if (isValid) {
      await updateLastLogin(user.id!);
      return user;
    }
    return null;
  }

  // Simulateur de vérification (à remplacer par bcrypt)
 // Remplace _verifyPassword (ligne ~68)
 bool _verifyPassword(String plain, String hash) {
   return _hashPassword(plain) == hash;
 }

 String _hashPassword(String plain) {
   final bytes = utf8.encode('SmartInventory_salt:$plain');
   return sha256.convert(bytes).toString();
 }

  /// Enregistre un nouvel utilisateur (hash du mot de passe)
  Future<User> register(String email, String password, {String? pharmacyName}) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();

    // Vérifier si un compte existe déjà
    final existing = await getUserByEmail(email);
    if (existing != null) throw Exception('Un compte existe déjà avec cet email');

    final user = User(
      email:        email.trim().toLowerCase(),
      passwordHash: _hashPassword(password),  // ← hashé ici
      pharmacyName: pharmacyName ?? 'Ma Pharmacie',
      createdAt:    now,
    );
    final id = await db.insert('users', user.toMap());
    return user.copyWith(id: id);
  }
  // Dans user_repository.dart
  Future<User?> findById(int id) async {
    final db = await DatabaseHelper().database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }
}