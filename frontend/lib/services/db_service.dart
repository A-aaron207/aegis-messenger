import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDbService {
  final SharedPreferences _prefs;

  LocalDbService._(this._prefs);

  static Future<LocalDbService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalDbService._(prefs);
  }

  // ==========================================
  // 1. SECURE VAULTPERSISTENCE
  // ==========================================

  Future<void> saveSecureVault({
    required String username,
    required String encryptedPrivateKey,
    required String salt,
    required String iv,
    required String publicKey,
  }) async {
    final normalized = username.trim().toLowerCase();
    await _prefs.setString('enc_priv_$normalized', encryptedPrivateKey);
    await _prefs.setString('salt_$normalized', salt);
    await _prefs.setString('wrap_iv_$normalized', iv);
    await _prefs.setString('pub_$normalized', publicKey);
  }

  String? getEncryptedPrivateKey(String username) =>
      _prefs.getString('enc_priv_${username.trim().toLowerCase()}');

  String? getSalt(String username) =>
      _prefs.getString('salt_${username.trim().toLowerCase()}');

  String? getWrapIv(String username) =>
      _prefs.getString('wrap_iv_${username.trim().toLowerCase()}');

  String? getPublicKey(String username) =>
      _prefs.getString('pub_${username.trim().toLowerCase()}');

  // Active Session state tracker
  Future<void> setActiveSession(String username) async {
    await _prefs.setString('active_user', username.trim().toLowerCase());
  }

  String? getActiveUser() => _prefs.getString('active_user');

  // ==========================================
  // 2. PEER KEY REGISTRY (ECDH caches)
  // ==========================================

  Future<void> savePeerPublicKey(String peer, String publicKey) async {
    final normalized = peer.trim().toLowerCase();
    await _prefs.setString('peer_key_$normalized', publicKey);
  }

  String? getPeerPublicKey(String peer) {
    final normalized = peer.trim().toLowerCase();
    return _prefs.getString('peer_key_$normalized');
  }

  // ==========================================
  // 3. PERSISTENT ENCRYPTED MESSAGE LOGS (Phase 1)
  // ==========================================

  Future<void> saveEncryptedEnvelope({
    required String chatOwner,
    required String peer,
    required Map<String, dynamic> envelopeJson,
  }) async {
    final normalizedOwner = chatOwner.trim().toLowerCase();
    final normalizedPeer = peer.trim().toLowerCase();
    final key = 'chat_${normalizedOwner}_$normalizedPeer';

    final history = getEncryptedHistory(normalizedOwner, normalizedPeer);
    history.add(envelopeJson);

    final List<String> encoded = history.map((e) => jsonEncode(e)).toList();
    await _prefs.setStringList(key, encoded);
  }

  List<Map<String, dynamic>> getEncryptedHistory(String chatOwner, String peer) {
    final normalizedOwner = chatOwner.trim().toLowerCase();
    final normalizedPeer = peer.trim().toLowerCase();
    final key = 'chat_${normalizedOwner}_$normalizedPeer';

    final raw = _prefs.getStringList(key) ?? [];
    return raw.map((r) => Map<String, dynamic>.from(jsonDecode(r))).toList();
  }

  Future<void> clearSession() async {
    await _prefs.remove('active_user');
  }
}
