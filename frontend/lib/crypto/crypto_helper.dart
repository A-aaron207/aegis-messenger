import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoHelper {
  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);

  /// Generates a new X25519 identity keypair
  static Future<SimpleKeyPair> generateKeyPair() async {
    return await _x25519.newKeyPair();
  }

  /// Converts public key bytes to Base64 string
  static Future<String> encodePublicKey(SimplePublicKey publicKey) async {
    return base64Encode(publicKey.bytes);
  }

  /// Decodes Base64 string back to X25519 public key
  static SimplePublicKey decodePublicKey(String base64Key) {
    return SimplePublicKey(base64Decode(base64Key), type: KeyPairType.x25519);
  }

  /// Decodes Base64 strings to Keypair objects (restores them in-memory)
  static SimpleKeyPair decodeKeyPair({
    required String base64PrivateKey,
    required String base64PublicKey,
  }) {
    return SimpleKeyPairData(
      base64Decode(base64PrivateKey),
      publicKey: SimplePublicKey(base64Decode(base64PublicKey), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Derives consistent session key via ECDH + HKDF
  static Future<SecretKey> deriveSessionKey({
    required SimpleKeyPair myKeyPair,
    required String peerBase64PublicKey,
  }) async {
    final peerPubKey = decodePublicKey(peerBase64PublicKey);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPubKey,
    );

    final aesKeyBytes = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: [],
      info: utf8.encode('AegisSimpleE2EE'),
    );

    return SecretKey(aesKeyBytes);
  }

  // ==========================================
  // AUTH HARDENING: PBKDF2 PRIVATE KEY WRAPPING
  // ==========================================

  /// Derives a key wrapping key from a user's password using PBKDF2 (100,000 iterations)
  static Future<SecretKey> deriveWrappingKey({
    required String password,
    required List<int> salt,
  }) async {
    final pbkdf2 = Pbkdf2(
      mac: Hmac(Sha256()),
      iterations: 100000,
      bits: 256,
    );

    final secretKey = SecretKey(utf8.encode(password));
    final wrappingKeyBytes = await pbkdf2.deriveKey(
      secretKey: secretKey,
      nonce: salt,
    );

    return wrappingKeyBytes;
  }

  /// Encrypts (wraps) raw private key bytes using Derived wrapping key + AES-GCM
  static Future<EncryptedVault> wrapPrivateKey({
    required SimpleKeyPair keyPair,
    required String password,
  }) async {
    final rawPrivBytes = await keyPair.extractPrivateKeyBytes();

    // 1. Generate random salt (16 bytes)
    final salt = SecretBox.getRandomBytes(16);

    // 2. Derive wrapping key from password
    final wrappingKey = await deriveWrappingKey(password: password, salt: salt);

    // 3. Encrypt private key using AES-GCM
    final secretBox = await _aesGcm.encrypt(
      rawPrivBytes,
      secretKey: wrappingKey,
    );

    // Append ciphertext + tag
    final combinedCiphertext = [...secretBox.cipherText, ...secretBox.mac.bytes];

    return EncryptedVault(
      encryptedPrivateKey: base64Encode(combinedCiphertext),
      salt: base64Encode(salt),
      iv: base64Encode(secretBox.nonce),
    );
  }

  /// Decrypts (unwraps) and imports private key from secure vault
  static Future<SimpleKeyPair> unwrapPrivateKey({
    required EncryptedVault vault,
    required String password,
    required String base64PublicKey,
  }) async {
    final salt = base64Decode(vault.salt);
    final iv = base64Decode(vault.iv);
    final combinedBytes = base64Decode(vault.encryptedPrivateKey);

    if (combinedBytes.length < 16) {
      throw Exception('Vault payload too short.');
    }

    final ciphertextBytes = combinedBytes.sublist(0, combinedBytes.length - 16);
    final macBytes = combinedBytes.sublist(combinedBytes.length - 16);

    // 1. Derive wrapping key from password
    final wrappingKey = await deriveWrappingKey(password: password, salt: salt);

    // 2. Decrypt secret box
    final secretBox = SecretBox(
      ciphertextBytes,
      nonce: iv,
      mac: Mac(macBytes),
    );

    final decryptedPrivBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: wrappingKey,
    );

    // 3. Re-assemble keypair object in memory
    return decodeKeyPair(
      base64PrivateKey: base64Encode(decryptedPrivBytes),
      base64PublicKey: base64PublicKey,
    );
  }

  /// Encrypts plaintext message payload
  static Future<EncryptedEnvelope> encrypt({
    required String plaintext,
    required SecretKey sessionKey,
  }) async {
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: sessionKey,
    );
    final combinedCiphertext = [...secretBox.cipherText, ...secretBox.mac.bytes];

    return EncryptedEnvelope(
      iv: base64Encode(secretBox.nonce),
      ciphertext: base64Encode(combinedCiphertext),
    );
  }

  /// Decrypts envelope payload
  static Future<String> decrypt({
    required EncryptedEnvelope envelope,
    required SecretKey sessionKey,
  }) async {
    final combinedBytes = base64Decode(envelope.ciphertext);
    final ciphertextBytes = combinedBytes.sublist(0, combinedBytes.length - 16);
    final macBytes = combinedBytes.sublist(combinedBytes.length - 16);

    final secretBox = SecretBox(
      ciphertextBytes,
      nonce: base64Decode(envelope.iv),
      mac: Mac(macBytes),
    );

    final decrypted = await _aesGcm.decrypt(secretBox, secretKey: sessionKey);
    return utf8.decode(decrypted);
  }
}

class EncryptedVault {
  final String encryptedPrivateKey; // Base64
  final String salt;                // Base64
  final String iv;                  // Base64

  EncryptedVault({
    required this.encryptedPrivateKey,
    required this.salt,
    required this.iv,
  });
}

class EncryptedEnvelope {
  final String iv;         // Base64
  final String ciphertext; // Base64 (ciphertext + mac)

  EncryptedEnvelope({required this.iv, required this.ciphertext});
}
