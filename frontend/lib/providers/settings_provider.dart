import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  SharedPreferences? _prefs;
  Timer? _debounceTimer;

  bool _darkMode = false;
  bool _notifications = true;

  bool get darkMode => _darkMode;
  bool get notifications => _notifications;

  SettingsProvider() { _init(); }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _darkMode = _prefs?.getBool('darkMode') ?? false;
    _notifications = _prefs?.getBool('notifications') ?? true;
    notifyListeners();
  }

  void setDarkMode(bool v) {
    if (_darkMode != v) {
      _darkMode = v;
      _prefs?.setBool('darkMode', v);

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 50), () {
        notifyListeners();
      });
    }
  }

  void setNotifications(bool v) {
    if (_notifications != v) {
      _notifications = v;
      _prefs?.setBool('notifications', v);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}