import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../services/db_service.dart';
import '../services/websocket_service.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  final AegisUser friend;

  const ChatScreen({Key? key, required this.friend}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<AegisMessage> _messages = [];
  StreamSubscription<AegisMessage>? _streamSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _subscribeToIncomingMessages();
  }

  Future<void> _loadChatHistory() async {
    final dbService = Provider.of<LocalDbService>(context, listen: false);
    final history = dbService.getChatHistory(widget.friend.userId);
    
    setState(() {
      _messages.addAll(history);
      _isLoading = false;
    });

    _scrollToBottom();
  }

  void _subscribeToIncomingMessages() {
    final wsService = Provider.of<WebSocketService>(context, listen: false);
    _streamSubscription = wsService.messageStream.listen((msg) {
      // Catch real-time messages belong to this specific friend conversation
      if ((msg.senderId == widget.friend.userId && msg.recipientId == _getMyUserId()) ||
          (msg.senderId == _getMyUserId() && msg.recipientId == widget.friend.userId)) {
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();
      }
    });
  }

  String _getMyUserId() {
    return Provider.of<LocalDbService>(context, listen: false).getUserId() ?? '';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      final wsService = Provider.of<WebSocketService>(context, listen: false);
      await wsService.sendMessage(
        recipientId: widget.friend.userId,
        recipientPublicKey: widget.friend.publicKey,
        plaintext: text,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send encrypted message: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Deep rich black-blue
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
              child: Text(
                widget.friend.username.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12.0),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.friend.username,
                  style: const TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2.0),
                Row(
                  children: const [
                    Icon(Icons.lock, size: 10.0, color: Color(0xFF10B981)),
                    SizedBox(width: 4.0),
                    Text(
                      'End-to-End Encrypted',
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 10.0, fontWeight: FontWeight.w500),
                    ),
                  ],
                )
              ],
            )
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_person_outlined, size: 48.0, color: const Color(0xFF334155)),
                              const SizedBox(height: 16.0),
                              const Text(
                                'No Messages Yet',
                                style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6.0),
                              const Text(
                                'Messages are encrypted locally before leaving your device.',
                                style: TextStyle(color: Color(0xFF475569), fontSize: 12.0),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            return ChatBubble(message: _messages[index]);
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    border: Border(
                      top: BorderSide(color: Color(0xFF334155), width: 0.5),
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            style: const TextStyle(color: Colors.white),
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: 'Secure message...',
                              hintStyle: const TextStyle(color: Color(0xFF64748B)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        Material(
                          color: const Color(0xFF4F46E5),
                          borderRadius: BorderRadius.circular(24.0),
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white, size: 20.0),
                            onPressed: _sendMessage,
                          ),
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
    );
  }
}
