import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Secrets (password, private key, passphrase) live in the platform keychain;
/// everything else in shared_preferences.
class Store {
  Store._(this._prefs);

  static Future<Store> open() async =>
      Store._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _secure = FlutterSecureStorage(
    // Legacy keychain so unsigned / ad-hoc signed macOS builds work.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const _kHost = 'conn.host',
      _kPort = 'conn.port',
      _kUser = 'conn.user',
      _sPassword = 'conn.password',
      _sKey = 'conn.privateKey',
      _sPassphrase = 'conn.passphrase',
      _kSources = 'sources',
      _kSelected = 'selected',
      _kRemote = 'dest.remote',
      _kRepoPath = 'dest.path',
      _kKeepLast = 'retention.keepLast',
      _kCleanup = 'retention.cleanup',
      _kCheck = 'options.check',
      _kHostKeys = 'hostKeys';

  // ---- connection ---------------------------------------------------------

  Future<ConnectionSettings> loadConnection() async {
    const d = ConnectionSettings();
    return ConnectionSettings(
      host: _prefs.getString(_kHost) ?? d.host,
      port: _prefs.getInt(_kPort) ?? d.port,
      username: _prefs.getString(_kUser) ?? d.username,
      password: await _readSecret(_sPassword),
      privateKey: await _readSecret(_sKey),
      passphrase: await _readSecret(_sPassphrase),
    );
  }

  Future<void> saveConnection(ConnectionSettings s) async {
    await _prefs.setString(_kHost, s.host.trim());
    await _prefs.setInt(_kPort, s.port);
    await _prefs.setString(_kUser, s.username.trim());
    await _writeSecret(_sPassword, s.password);
    await _writeSecret(_sKey, s.privateKey);
    await _writeSecret(_sPassphrase, s.passphrase);
  }

  Future<String> _readSecret(String key) async {
    try {
      return await _secure.read(key: key) ?? '';
    } catch (e) {
      debugPrint('secure storage read failed for $key: $e');
      return '';
    }
  }

  Future<void> _writeSecret(String key, String value) async {
    if (value.isEmpty) {
      await _secure.delete(key: key);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  // ---- sources ------------------------------------------------------------

  List<BackupSource>? loadSources() {
    final raw = _prefs.getString(_kSources);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BackupSource.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSources(List<BackupSource> sources) => _prefs.setString(
      _kSources, jsonEncode(sources.map((s) => s.toJson()).toList()));

  Set<String>? loadSelected() => _prefs.getStringList(_kSelected)?.toSet();
  Future<void> saveSelected(Set<String> ids) =>
      _prefs.setStringList(_kSelected, ids.toList());

  // ---- destination / retention / options ----------------------------------

  Destination? loadDestination() {
    final r = _prefs.getString(_kRemote), p = _prefs.getString(_kRepoPath);
    if (r == null || p == null) return null;
    return Destination(remote: r, path: p);
  }

  Future<void> saveDestination(Destination d) async {
    await _prefs.setString(_kRemote, d.remote);
    await _prefs.setString(_kRepoPath, d.path);
  }

  Retention? loadRetention() {
    final k = _prefs.getInt(_kKeepLast);
    if (k == null) return null;
    return Retention(keepLast: k, cleanup: _prefs.getBool(_kCleanup) ?? true);
  }

  Future<void> saveRetention(Retention r) async {
    await _prefs.setInt(_kKeepLast, r.keepLast);
    await _prefs.setBool(_kCleanup, r.cleanup);
  }

  bool get verifyAfterBackup => _prefs.getBool(_kCheck) ?? false;
  Future<void> setVerifyAfterBackup(bool v) => _prefs.setBool(_kCheck, v);

  // ---- host keys (trust on first use) ---------------------------------------

  Map<String, String> _hostKeys() {
    final raw = _prefs.getString(_kHostKeys);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  String? hostKey(String hostId) => _hostKeys()[hostId];

  Future<void> setHostKey(String hostId, String fingerprint) =>
      _prefs.setString(_kHostKeys, jsonEncode(_hostKeys()..[hostId] = fingerprint));

  Future<void> forgetHostKey(String hostId) =>
      _prefs.setString(_kHostKeys, jsonEncode(_hostKeys()..remove(hostId)));
}
