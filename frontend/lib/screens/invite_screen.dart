import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({Key? key}) : super(key: key);

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _inviteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  Future<void> _addFriendByInvite() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _message = null;
      _isSuccess = false;
    });

    try {
      final inviteUsername = _inviteController.text.trim();

      final apiService = Provider.of<ApiService>(context, listen: false);
      final dbService = Provider.of<LocalDbService>(context, listen: false);
      final token = await dbService.getAuthToken();

      if (inviteUsername == dbService.getUsername()) {
        throw Exception('You cannot add yourself as a friend.');
      }

      // Fetch target user's public key from the blind server registry
      final response = await apiService.fetchUserPublicKey(
        username: inviteUsername,
        token: token!,
      );

      final friend = AegisUser(
        userId: response['userId'],
        username: response['username'],
        publicKey: response['publicKey'],
        isFriend: true,
      );

      // Save friend to secure local contacts roster
      await dbService.saveFriend(friend);

      setState(() {
        _isSuccess = true;
        _message = 'Successfully added ${friend.username} to your local contacts!';
        _inviteController.clear();
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Parses a scanned QR payload directly
  Future<void> _addFriendByScannedPayload(String scannedText) async {
    setState(() {
      _isLoading = true;
      _message = null;
      _isSuccess = false;
    });

    try {
      final data = jsonDecode(scannedText);
      final uId = data['i'];
      final uName = data['u'];
      final pubKey = data['k'];

      if (uId == null || uName == null || pubKey == null) {
        throw Exception('Invalid QR code format.');
      }

      final dbService = Provider.of<LocalDbService>(context, listen: false);
      if (uName == dbService.getUsername()) {
        throw Exception('You cannot add yourself as a friend.');
      }

      final friend = AegisUser(
        userId: uId,
        username: uName,
        publicKey: pubKey,
        isFriend: true,
      );

      await dbService.saveFriend(friend);

      setState(() {
        _isSuccess = true;
        _message = 'Scanned and successfully added ${friend.username}!';
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = 'QR Error: ${e.toString().replaceFirst('Exception: ', '')}';
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
    final dbService = Provider.of<LocalDbService>(context);
    final myUsername = dbService.getUsername() ?? 'Anonymous';
    final myPublicKey = dbService.getPublicKey() ?? '';
    final myUserId = dbService.getUserId() ?? '';

    // Compact QR data to keep QR density extremely scan-friendly
    final qrPayload = jsonEncode({
      'u': myUsername,
      'k': myPublicKey,
      'i': myUserId,
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Add Friends', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            labelColor: Color(0xFF6366F1),
            unselectedLabelColor: Color(0xFF94A3B8),
            indicatorColor: Color(0xFF6366F1),
            tabs: [
              Tab(icon: Icon(Icons.qr_code), text: 'My QR Code'),
              Tab(icon: Icon(Icons.person_add), text: 'Enter Invite'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: My QR Code
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Your Identity QR',
                    style: TextStyle(color: Colors.white, fontSize: 20.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  const Text(
                    'Let your friend scan this to exchange public keys instantly without server lookup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.0),
                  ),
                  const SizedBox(height: 32.0),
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.0),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withOpacity(0.2),
                          blurRadius: 20.0,
                          spreadRadius: 2.0,
                        )
                      ],
                    ),
                    child: QrImageView(
                      data: qrPayload,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  Text(
                    'Invite Code (Username): $myUsername',
                    style: const TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // TAB 2: Enter Invite Fallback Code
            SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Add Friend via Invite',
                    style: TextStyle(color: Colors.white, fontSize: 20.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  const Text(
                    'Enter your friend\'s exact username to lookup their public key on the server.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.0),
                  ),
                  const SizedBox(height: 24.0),

                  if (_message != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: _isSuccess ? Colors.green.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: _isSuccess ? Colors.green.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: _isSuccess ? Colors.green : Colors.redAccent,
                          fontSize: 13.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20.0),
                  ],

                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _inviteController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Friend\'s Username',
                        labelStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF64748B)),
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
                          return 'Please enter username';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 20.0),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _addFriendByInvite,
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
                            'Lookup & Add Friend',
                            style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold),
                          ),
                  ),

                  // Standard Simulator / testing utility (allows simulating a scanned QR payload easily!)
                  const SizedBox(height: 40.0),
                  const Divider(color: Color(0xFF334155)),
                  const SizedBox(height: 16.0),
                  const Text(
                    'Simulator QR Scanner Tool',
                    style: TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6.0),
                  const Text(
                    'Paste a scanned QR JSON payload below to simulate a real hardware camera scan.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12.0),
                  ),
                  const SizedBox(height: 12.0),
                  TextField(
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _addFriendByScannedPayload(val.trim());
                      }
                    },
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.0),
                    decoration: InputDecoration(
                      hintText: 'Paste QR JSON payload here & press Enter...',
                      hintStyle: const TextStyle(color: Color(0xFF475569)),
                      contentPadding: const EdgeInsets.all(12.0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
