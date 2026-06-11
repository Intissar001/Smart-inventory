// Modèle représentant un utilisateur (une pharmacie)
class User {
  final int? id;
  final String email;
  final String passwordHash; // hash du mot de passe (ex: bcrypt)
  final String? pharmacyName;
  final DateTime createdAt;
  final DateTime? lastLogin;

  User({
    this.id,
    required this.email,
    required this.passwordHash,
    this.pharmacyName,
    required this.createdAt,
    this.lastLogin,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      email: map['email'] as String,
      passwordHash: map['password_hash'] as String,
      pharmacyName: map['pharmacy_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastLogin: map['last_login'] != null
          ? DateTime.parse(map['last_login'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'password_hash': passwordHash,
      'pharmacy_name': pharmacyName,
      'created_at': createdAt.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
    };
  }

  User copyWith({
    int? id,
    String? email,
    String? passwordHash,
    String? pharmacyName,
    DateTime? createdAt,
    DateTime? lastLogin,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      pharmacyName: pharmacyName ?? this.pharmacyName,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }
}