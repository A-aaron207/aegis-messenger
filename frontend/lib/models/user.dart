class AegisUser {
  final String userId;
  final String username;
  final String publicKey; // Base64
  final bool isFriend;

  AegisUser({
    required this.userId,
    required this.username,
    required this.publicKey,
    this.isFriend = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'publicKey': publicKey,
      'isFriend': isFriend ? 1 : 0,
    };
  }

  factory AegisUser.fromMap(Map<String, dynamic> map) {
    return AegisUser(
      userId: map['userId'] ?? '',
      username: map['username'] ?? '',
      publicKey: map['publicKey'] ?? '',
      isFriend: (map['isFriend'] ?? 0) == 1,
    );
  }
}
