import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cryptography/cryptography.dart';

import 'crypto/crypto_helper.dart';
import 'services/api_service.dart';
import 'services/db_service.dart';
import 'services/websocket_service.dart';
import 'models/message.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize storage registry
  final dbService = await LocalDbService.init();

  // 2. Setup REST client and WebSocket relay
  final apiService = ApiService(baseUrl: 'http://localhost:3000');
  final wsService = WebSocketService(
    wsUrl: 'ws://localhost:3000',
    dbService: dbService,
    apiService: apiService,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<LocalDbService>.value(value: dbService),
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider<WebSocketService>.value(value: wsService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aegis Hardened MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF6366F1),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ==========================================
// 1. HARDENED LOGIN & VAULT SCREEN
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isRegisterMode = true; // Toggle between register or vault unlock
  String? _error;

  void _toggleMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _error = null;
    });
  }

  Future<void> _processAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final username = _usernameController.text.trim().toLowerCase();
      final password = _passwordController.text;

      final apiService = Provider.of<ApiService>(context, listen: false);
      final dbService = Provider.of<LocalDbService>(context, listen: false);
      final wsService = Provider.of<WebSocketService>(context, listen: false);

      SimpleKeyPair activeKeyPair;

      if (_isRegisterMode) {
        // REGISTER FLOW:
        if (dbService.getEncryptedPrivateKey(username) != null) {
          throw Exception('An identity already exists on this device. Switch to Unlock Vault.');
        }

        // 1. Generate new identity keypair
        final keyPair = await CryptoHelper.generateKeyPair();
        final pubKeyStr = await CryptoHelper.encodePublicKey(await keyPair.extractPublicKey());

        // 2. Encrypt/wrap private key using PBKDF2 derived password key
        final vault = await CryptoHelper.wrapPrivateKey(
          keyPair: keyPair,
          password: password,
        );

        // 3. Save secure encrypted vault elements locally
        await dbService.saveSecureVault(
          username: username,
          encryptedPrivateKey: vault.encryptedPrivateKey,
          salt: vault.salt,
          iv: vault.iv,
          publicKey: pubKeyStr,
        );

        // 4. Register public key on the blind server
        await apiService.register(username: username, publicKey: pubKeyStr);

        activeKeyPair = keyPair;
      } else {
        // UNLOCK VAULT FLOW:
        final encPriv = dbService.getEncryptedPrivateKey(username);
        final salt = dbService.getSalt(username);
        final iv = dbService.getWrapIv(username);
        final pubKey = dbService.getPublicKey(username);

        if (encPriv == null || salt == null || iv == null || pubKey == null) {
          throw Exception('No key vault found for this username on this device.');
        }

        final vault = EncryptedVault(
          encryptedPrivateKey: encPriv,
          salt: salt,
          iv: iv,
        );

        // Decrypt / unwrap local private key using PBKDF2 derived key
        activeKeyPair = await CryptoHelper.unwrapPrivateKey(
          vault: vault,
          password: password,
          base64PublicKey: pubKey,
        );
      }

      // Save session references and load in-memory keys
      await dbService.setActiveSession(username);
      wsService.setSessionIdentity(activeKeyPair);

      // Connect socket relays
      await wsService.connect();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield_outlined, size: 64.0, color: Color(0xFF6366F1)),
                const SizedBox(height: 16.0),
                Text(
                  _isRegisterMode ? 'Aegis Registry' : 'Unlock Key Vault',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8.0),
                Text(
                  _isRegisterMode
                      ? 'Generate identities wrapped with key derivation'
                      : 'Enter password to unwrap private keys locally',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13.0),
                ),
                const SizedBox(height: 32.0),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8.0)),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                  const SizedBox(height: 16.0),
                ],
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter a username' : null,
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => (val == null || val.length < 6) ? 'Password must be >= 6 chars' : null,
                ),
                const SizedBox(height: 24.0),
                ElevatedButton(
                  onPressed: _isLoading ? null : _processAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20.0,
                          width: 20.0,
                          child: CircularProgressIndicator(strokeWidth: 2.0, valueColor: AlwaysStoppedAnimation(Colors.white)),
                        )
                      : Text(_isRegisterMode ? 'Generate E2EE Vault' : 'Unwrap Key & Login', style: const TextStyle(color: Colors.white, fontSize: 16.0)),
                ),
                const SizedBox(height: 16.0),
                TextButton(
                  onPressed: _isLoading ? null : _toggleMode,
                  child: Text(_isRegisterMode ? 'Already registered on this device? Unlock here' : 'Need a new identity? Register here'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. HOME SCREEN (CONTACTS LIST)
// ==========================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final dbService = Provider.of<LocalDbService>(context, listen: false);
      final list = await apiService.fetchUsers();
      final self = dbService.getActiveUser() ?? '';

      list.removeWhere((u) => u.toLowerCase() == self.toLowerCase());

      setState(() {
        _users = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<LocalDbService>(context);
    final wsService = Provider.of<WebSocketService>(context);
    final myUsername = dbService.getActiveUser() ?? 'Anonymous';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 8.0,
              height: 8.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: wsService.isConnected ? const Color(0xFF10B981) : Colors.orangeAccent,
              ),
            ),
            const SizedBox(width: 8.0),
            Text('$myUsername (E2EE Vault Active)'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchUsers),
          IconButton(
            icon: const Icon(Icons.lock, color: Colors.redAccent),
            onPressed: () async {
              wsService.disconnect();
              await dbService.clearSession();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('Waiting for other users to register...'))
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final peer = _users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
                        child: Text(peer.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(peer, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Tap to start persistent secure session'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14.0),
                      onTap: () async {
                        try {
                          final apiService = Provider.of<ApiService>(context, listen: false);
                          final pubKey = await apiService.fetchUserPublicKey(peer);
                          await dbService.savePeerPublicKey(peer, pubKey);

                          if (context.mounted) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(peer: peer, peerPublicKey: pubKey),
                              ),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to load contact: $e')),
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }
}

// ==========================================
// 3. PERSISTENT CHAT SCREEN (DYNAMIC DECRYPTION)
// ==========================================
class ChatScreen extends StatefulWidget {
  final String peer;
  final String peerPublicKey;

  const ChatScreen({Key? key, required this.peer, required this.peerPublicKey}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<AegisMessage> _messages = [];
  StreamSubscription<AegisMessage>? _sub;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAndDecryptHistory();
    _subscribe();
  }

  // Phase 1: Retrieve E2EE envelopes from persistent storage and decrypt in-memory
  Future<void> _loadAndDecryptHistory() async {
    final db = Provider.of<LocalDbService>(context, listen: false);
    final ws = Provider.of<WebSocketService>(context, listen: false);
    
    final myUsername = db.getActiveUser()!;
    final envelopes = db.getEncryptedHistory(myUsername, widget.peer);

    if (envelopes.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Derive session key in-memory using active credentials
      final sessionKey = await CryptoHelper.deriveSessionKey(
        myKeyPair: ws.myKeyPair!,
        peerBase64PublicKey: widget.peerPublicKey,
      );

      // 2. Decrypt each local envelope in-memory dynamically
      final List<AegisMessage> decryptedList = [];
      for (var envelopeJson in envelopes) {
        final envelope = EncryptedEnvelope(
          iv: envelopeJson['iv'],
          ciphertext: envelopeJson['ciphertext'],
        );

        final plaintext = await CryptoHelper.decrypt(
          envelope: envelope,
          sessionKey: sessionKey,
        );

        decryptedList.add(AegisMessage(
          id: UniqueKey().toString(),
          sender: envelopeJson['sender'],
          recipient: envelopeJson['recipient'],
          plaintext: plaintext,
          timestamp: DateTime.parse(envelopeJson['timestamp']),
          isOutgoing: envelopeJson['sender'].toLowerCase() == myUsername.toLowerCase(),
        ));
      }

      setState(() {
        _messages.addAll(decryptedList);
        _isLoading = false;
      });
      _scroll();
    } catch (e) {
      debugPrint("Failed to decrypt local logs: $e");
      setState(() => _isLoading = false);
    }
  }

  void _subscribe() {
    final ws = Provider.of<WebSocketService>(context, listen: false);
    final myName = Provider.of<LocalDbService>(context, listen: false).getActiveUser() ?? '';

    _sub = ws.messageStream.listen((msg) {
      if ((msg.sender.toLowerCase() == widget.peer.toLowerCase() && msg.recipient.toLowerCase() == myName.toLowerCase()) ||
          (msg.sender.toLowerCase() == myName.toLowerCase() && msg.recipient.toLowerCase() == widget.peer.toLowerCase())) {
        setState(() {
          _messages.add(msg);
        });
        _scroll();
      }
    });
  }

  void _scroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    try {
      final ws = Provider.of<WebSocketService>(context, listen: false);
      await ws.sendMessage(
        recipient: widget.peer,
        recipientPublicKey: widget.peerPublicKey,
        plaintext: text,
      );
      _scroll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Encryption error: $e')),
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peer),
            Row(
              children: const [
                Icon(Icons.lock, size: 10.0, color: Color(0xFF10B981)),
                SizedBox(width: 4.0),
                Text('Persistent E2EE active', style: TextStyle(fontSize: 10.0, color: Color(0xFF10B981))),
              ],
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      return Align(
                        alignment: m.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                          decoration: BoxDecoration(
                            color: m.isOutgoing ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(m.plaintext, style: const TextStyle(fontSize: 15.0)),
                              const SizedBox(height: 4.0),
                              Text(
                                DateFormat('hh:mm a').format(m.timestamp),
                                style: TextStyle(fontSize: 9.0, color: Colors.white.withOpacity(0.6)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    color: const Color(0xFF1E293B),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                              hintText: 'Type secure message...',
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Color(0xFF6366F1)),
                          onPressed: _send,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
