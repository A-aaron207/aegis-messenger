import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final AegisMessage message;

  const ChatBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('hh:mm a');

    return Align(
      alignment: message.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
        decoration: BoxDecoration(
          // Outgoing message gets premium violet gradient; incoming gets elegant dark-grey glassmorphic design
          gradient: message.isOutgoing
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: message.isOutgoing ? null : const Color(0xFF1E293B),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16.0),
            topRight: const Radius.circular(16.0),
            bottomLeft: message.isOutgoing ? const Radius.circular(16.0) : const Radius.circular(4.0),
            bottomRight: message.isOutgoing ? const Radius.circular(4.0) : const Radius.circular(16.0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4.0,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.plaintext,
              style: TextStyle(
                color: message.isOutgoing ? Colors.white : const Color(0xFFF1F5F9),
                fontSize: 15.0,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              timeFormat.format(message.timestamp),
              style: TextStyle(
                color: message.isOutgoing
                    ? Colors.white.withOpacity(0.65)
                    : const Color(0xFF94A3B8),
                fontSize: 10.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
