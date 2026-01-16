// lib/services/settings_service.dart

import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _keyBaseUrl = 'base_url';
  static const _keyAdminMode = 'admin_mode';
  
  Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  /// BASE URL
  Future<String> get baseUrl async {
    final p = await _prefs;
    return p.getString(_keyBaseUrl) ?? 'https://www.denta1.uz';
  }

  Future<void> setBaseUrl(String url) async {
    final p = await _prefs;
    await p.setString(_keyBaseUrl, url);
  }

  /// ADMIN MODE (local switch)
  Future<bool> get isAdminMode async {
    final p = await _prefs;
    return p.getBool(_keyAdminMode) ?? false;
  }

  Future<void> setAdminMode(bool value) async {
    final p = await _prefs;
    await p.setBool(_keyAdminMode, value);
  }
}
