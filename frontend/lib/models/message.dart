class AegisMessage {
  final String id;
  final String sender;
  final String recipient;
  final String plaintext;
  final DateTime timestamp;
  final bool isOutgoing;

  AegisMessage({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.plaintext,
    required this.timestamp,
    required this.isOutgoing,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender': sender,
      'recipient': recipient,
      'plaintext': plaintext,
      'timestamp': timestamp.toIso8601String(),
      'isOutgoing': isOutgoing ? 1 : 0,
    };
  }

  factory AegisMessage.fromMap(Map<String, dynamic> map) {
    return AegisMessage(
      id: map['id'] ?? '',
      sender: map['sender'] ?? '',
      recipient: map['recipient'] ?? '',
      plaintext: map['plaintext'] ?? '',
      timestamp: DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
      isOutgoing: (map['isOutgoing'] ?? 0) == 1,
    );
  }
}
