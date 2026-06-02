import 'dart:convert';
import 'package:crypto/crypto.dart'; // Standard Dart library or fallback simple hash
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../crypto/crypto_helper.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/websocket_service.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      // 1. Pre-hash password on the client-side so server never sees plaintext
      final passwordHash = sha256.convert(utf8.encode(password)).toString();

      // 2. Generate E2EE cryptographic key pair locally on device
      final keyPair = await CryptoHelper.generateKeyPair();
      final publicKeyBase64 = await CryptoHelper.encodePublicKey(await keyPair.extractPublicKey());
      final privateKeyBase64 = await CryptoHelper.encodePrivateKey(keyPair);

      // 3. Post registration request to server
      final apiService = Provider.of<ApiService>(context, listen: false);
      final dbService = Provider.of<LocalDbService>(context, listen: false);
      final wsService = Provider.of<WebSocketService>(context, listen: false);

      final response = await apiService.register(
        username: username,
        passwordHash: passwordHash,
        publicKey: publicKeyBase64,
      );

      final userId = response['userId'];
      final token = response['token'];

      // 4. Persist keys & credentials locally
      await dbService.saveAuthCredentials(
        userId: userId,
        username: username,
        token: token,
      );
      await dbService.saveIdentityKeyPair(
        base64PrivateKey: privateKeyBase64,
        base64PublicKey: publicKeyBase64,
      );

      // 5. Fire WebSocket tunnel connection
      await wsService.connect();

      // 6. Push to Home Screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo/Brand Icon
              const Center(
                child: CircleAvatar(
                  radius: 40.0,
                  backgroundColor: Color(0xFF4F46E5),
                  child: Icon(Icons.shield_outlined, size: 48.0, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24.0),
              const Text(
                'Aegis',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32.0,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8.0),
              const Text(
                'Create your decentralized identity',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14.0,
                ),
              ),
              const SizedBox(height: 32.0),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13.0),
                  ),
                ),
                const SizedBox(height: 16.0),
              ],

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF64748B)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: const BorderSide(color: Color(0xFF4F46E5)),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a username';
                        }
                        if (value.trim().length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16.0),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF64748B)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: const BorderSide(color: Color(0xFF334155)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: const BorderSide(color: Color(0xFF4F46E5)),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),

              ElevatedButton(
                onPressed: _isLoading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20.0,
                        width: 20.0,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Generate Identity & Register',
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
              const SizedBox(height: 16.0),

              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Already have an identity? Login here',
                  style: TextStyle(color: Color(0xFF6366F1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
