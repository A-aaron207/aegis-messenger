import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cryptography/cryptography.dart';
import '../crypto/crypto_helper.dart';
import '../models/message.dart';
import 'api_service.dart';
import 'db_service.dart';

class WebSocketService extends ChangeNotifier {
  final String wsUrl;
  final LocalDbService dbService;
  final ApiService apiService;

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Active in-memory identity keypair (Wiped on logout)
  SimpleKeyPair? _myKeyPair;
  SimpleKeyPair? get myKeyPair => _myKeyPair;

  // Stream to notify UI of new incoming messages
  final _messageStreamController = StreamController<AegisMessage>.broadcast();
  Stream<AegisMessage> get messageStream => _messageStreamController.stream;

  Timer? _heartbeatTimer;

  WebSocketService({
    required this.wsUrl,
    required this.dbService,
    required this.apiService,
  });

  /// Configures active identity session keys in memory
  void setSessionIdentity(SimpleKeyPair keyPair) {
    _myKeyPair = keyPair;
  }

  /// Connects to WebSocket relay
  Future<void> connect() async {
    final myUsername = dbService.getUsername();
    if (myUsername == null || _myKeyPair == null) return;

    try {
      debugPrint('Connecting to WS: $wsUrl');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 1. Authenticate WebSocket association
      _channel!.sink.add(jsonEncode({
        'type': 'auth',
        'username': myUsername,
      }));

      // 2. Setup Heartbeat and Listeners
      _channel!.stream.listen(
        (data) => _handleIncomingPacket(data),
        onDone: () {
          _isConnected = false;
          _stopHeartbeat();
          notifyListeners();
          _retryConnection();
        },
        onError: (err) {
          _isConnected = false;
          _stopHeartbeat();
          notifyListeners();
          _retryConnection();
        },
      );
    } catch (e) {
      debugPrint('WS Setup error: $e');
      _retryConnection();
    }
  }

  /// Encrypts and transmits outgoing E2EE message
  Future<void> sendMessage({
    required String recipient,
    required String recipientPublicKey,
    required String plaintext,
  }) async {
    if (_channel == null || !_isConnected || _myKeyPair == null) {
      throw Exception('WS is offline or identity locked.');
    }

    final myUsername = dbService.getUsername()!;

    // 1. Derive AES Session Key (X25519 + HKDF)
    final sessionKey = await CryptoHelper.deriveSessionKey(
      myKeyPair: _myKeyPair!,
      peerBase64PublicKey: recipientPublicKey,
    );

    // 2. Encrypt Plaintext message
    final envelope = await CryptoHelper.encrypt(
      plaintext: plaintext,
      sessionKey: sessionKey,
    );

    // 3. Dispatch encrypted payload over WebSocket
    _channel!.sink.add(jsonEncode({
      'type': 'message',
      'recipient': recipient,
      'sender': myUsername,
      'iv': envelope.iv,
      'ciphertext': envelope.ciphertext,
    }));

    // 4. Save ENCRYPTED envelope locally (Phase 1 Message Persistence)
    final envelopeJson = {
      'sender': myUsername,
      'recipient': recipient,
      'iv': envelope.iv,
      'ciphertext': envelope.ciphertext,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await dbService.saveEncryptedEnvelope(
      chatOwner: myUsername,
      peer: recipient,
      envelopeJson: envelopeJson,
    );

    // 5. Broadcast plaintext message to UI
    final localMsg = AegisMessage(
      id: UniqueKey().toString(),
      sender: myUsername,
      recipient: recipient,
      plaintext: plaintext,
      timestamp: DateTime.now(),
      isOutgoing: true,
    );
    _messageStreamController.add(localMsg);
  }

  void _handleIncomingPacket(String raw) async {
    try {
      final packet = jsonDecode(raw);
      final type = packet['type'];

      if (type == 'auth_ok') {
        _isConnected = true;
        notifyListeners();
        _startHeartbeat();
        debugPrint('WebSocket authenticated successfully.');
        return;
      }

      if (type == 'pong') {
        // Heartbeat verification
        return;
      }

      if (type == 'message') {
        final sender = packet['sender'];
        final iv = packet['iv'];
        final ciphertext = packet['ciphertext'];
        final timestampStr = packet['timestamp'];

        final myUsername = dbService.getUsername()!;

        // 1. Save ENCRYPTED envelope locally first (Phase 1 Message Persistence)
        final envelopeJson = {
          'sender': sender,
          'recipient': myUsername,
          'iv': iv,
          'ciphertext': ciphertext,
          'timestamp': timestampStr,
        };

        await dbService.saveEncryptedEnvelope(
          chatOwner: myUsername,
          peer: sender,
          envelopeJson: envelopeJson,
        );

        // 2. Recover peer public key (from local DB or server fetch)
        var senderPubKey = dbService.getPeerPublicKey(sender);
        if (senderPubKey == null) {
          senderPubKey = await apiService.fetchUserPublicKey(sender);
          await dbService.savePeerPublicKey(sender, senderPubKey);
        }

        // 3. Derive symmetric key
        final sessionKey = await CryptoHelper.deriveSessionKey(
          myKeyPair: _myKeyPair!,
          peerBase64PublicKey: senderPubKey,
        );

        // 4. Decrypt in-memory immediately for active UI rendering
        final envelopeObj = EncryptedEnvelope(iv: iv, ciphertext: ciphertext);
        final plaintext = await CryptoHelper.decrypt(
          envelope: envelopeObj,
          sessionKey: sessionKey,
        );

        final message = AegisMessage(
          id: UniqueKey().toString(),
          sender: sender,
          recipient: myUsername,
          plaintext: plaintext,
          timestamp: DateTime.tryParse(timestampStr) ?? DateTime.now(),
          isOutgoing: false,
        );

        // Broadcast to active chat screens
        _messageStreamController.add(message);
      }
    } catch (e) {
      debugPrint('Incoming packet error: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_channel != null && _isConnected) {
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  void _retryConnection() {
    Timer(const Duration(seconds: 4), () {
      if (!_isConnected) connect();
    });
  }

  void disconnect() {
    _stopHeartbeat();
    _channel?.sink.close();
    _isConnected = false;
    _myKeyPair = null;
    _channel = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _messageStreamController.close();
    disconnect();
    super.dispose();
  }
}
