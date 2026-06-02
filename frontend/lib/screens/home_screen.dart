import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/db_service.dart';
import '../services/websocket_service.dart';
import 'chat_screen.dart';
import 'invite_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AegisUser> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshFriendsList();
  }

  void _refreshFriendsList() {
    final dbService = Provider.of<LocalDbService>(context, listen: false);
    setState(() {
      _friends = dbService.getFriends();
      _isLoading = false;
    });
  }

  Future<void> _logout() async {
    final dbService = Provider.of<LocalDbService>(context, listen: false);
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    wsService.disconnect();
    await dbService.clearAll();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<LocalDbService>(context);
    final wsService = Provider.of<WebSocketService>(context);
    final myUsername = dbService.getUsername() ?? 'Aegis User';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Container(
              width: 8.0,
              height: 8.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: wsService.isAuthenticated ? const Color(0xFF10B981) : Colors.orangeAccent,
              ),
            ),
            const SizedBox(width: 8.0),
            Text(
              myUsername,
              style: const TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _logout,
            tooltip: 'Logout',
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
          : _friends.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_alt_outlined, size: 64.0, color: const Color(0xFF334155)),
                        const SizedBox(height: 20.0),
                        const Text(
                          'Your Secure Roster is Empty',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8.0),
                        const Text(
                          'Aegis does not scan global contact networks. Click the button below to exchange invite QR codes with a friend.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13.0, height: 1.4),
                        ),
                        const SizedBox(height: 24.0),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const InviteScreen()),
                            );
                            _refreshFriendsList();
                          },
                          icon: const Icon(Icons.qr_code, color: Colors.white),
                          label: const Text('Add Friend', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final friend = _friends[index];
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF6366F1).withOpacity(0.15),
                          child: Text(
                            friend.username.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          friend.username,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Row(
                          children: const [
                            Icon(Icons.shield_outlined, size: 12.0, color: Color(0xFF94A3B8)),
                            SizedBox(width: 4.0),
                            Text('Secure Connection', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.0)),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF475569), size: 14.0),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(friend: friend),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4F46E5),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InviteScreen()),
          );
          _refreshFriendsList();
        },
        child: const Icon(Icons.person_add_alt_1, color: Colors.white),
      ),
    );
  }
}
