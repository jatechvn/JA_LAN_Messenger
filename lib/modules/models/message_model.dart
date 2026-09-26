enum MessageStatus { sending, sent, delivered, read, failed }

class FileAttachmentInfo {
  final String fileName;
  final int fileSize;
  final String? localPath;
  final String? checksum;
  final bool isTransferComplete;

  const FileAttachmentInfo({
    required this.fileName,
    required this.fileSize,
    this.localPath,
    this.checksum,
    this.isTransferComplete = false,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fileSize': fileSize,
    'localPath': localPath,
    'checksum': checksum,
    'isTransferComplete': isTransferComplete,
  };

  factory FileAttachmentInfo.fromJson(Map<String, dynamic> json) {
    return FileAttachmentInfo(
      fileName: json['fileName'] as String? ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      localPath: json['localPath'] as String?,
      checksum: json['checksum'] as String?,
      isTransferComplete: json['isTransferComplete'] as bool? ?? false,
    );
  }
}

class MessageModel {
  final String id;
  String senderId;
  final String senderName;
  String recipientId;
  String? sourceSession;
  String text;
  final DateTime timestamp;
  final bool isMine;
  MessageStatus status;
  // null denotes legacy history without per-recipient delivery bookkeeping.
  Set<String>? pendingRecipients;
  final FileAttachmentInfo? fileAttachment;
  bool isRevoked;
  DateTime? revokedAt;
  String? thinkingContent;
  bool isThinkingExpanded;
  String? aiModelTag;
  bool isStreaming;

  // Quote / Reply metadata
  final String? replyToId;
  final String? replyToSender;
  final String? replyToText;

  // Pin message in conversation
  bool isPinned;

  // Emoji reactions: emoji -> list of user names
  Map<String, List<String>> reactions;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.text,
    DateTime? timestamp,
    required this.isMine,
    this.status = MessageStatus.sent,
    this.pendingRecipients,
    this.sourceSession,
    this.fileAttachment,
    this.isRevoked = false,
    DateTime? revokedAt,
    this.thinkingContent,
    this.isThinkingExpanded = true,
    this.aiModelTag,
    this.isStreaming = false,
    this.replyToId,
    this.replyToSender,
    this.replyToText,
    this.isPinned = false,
    Map<String, List<String>>? reactions,
  }) : timestamp = (timestamp ?? DateTime.now()).toLocal(),
       revokedAt = revokedAt?.toLocal(),
       reactions = reactions ?? {};

  bool get hasAttachment => fileAttachment != null && !isRevoked;
  bool get isReply => replyToText != null && replyToText!.isNotEmpty;
  String get conversationId => isMine ? recipientId : senderId;

  bool hasUserReacted(String emoji, String username) {
    return reactions[emoji]?.contains(username) ?? false;
  }

  bool toggleReaction(String emoji, String username) {
    final list = reactions.putIfAbsent(emoji, () => <String>[]);
    if (list.contains(username)) {
      list.remove(username);
      if (list.isEmpty) {
        reactions.remove(emoji);
      }
      return false;
    } else {
      list.add(username);
      return true;
    }
  }

  void addReaction(String emoji, String username) {
    final list = reactions.putIfAbsent(emoji, () => <String>[]);
    if (!list.contains(username)) {
      list.add(username);
    }
  }

  void removeReaction(String emoji, String username) {
    if (reactions.containsKey(emoji)) {
      reactions[emoji]!.remove(username);
      if (reactions[emoji]!.isEmpty) {
        reactions.remove(emoji);
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    if (sourceSession != null) 'sourceSession': sourceSession,
    'senderName': senderName,
    'recipientId': recipientId,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'isMine': isMine,
    'status': status.name,
    if (pendingRecipients != null)
      'pendingRecipients': pendingRecipients!.toList(),
    if (fileAttachment != null) 'fileAttachment': fileAttachment!.toJson(),
    'isRevoked': isRevoked,
    if (revokedAt != null) 'revokedAt': revokedAt!.toIso8601String(),
    if (thinkingContent != null) 'thinkingContent': thinkingContent,
    'isThinkingExpanded': isThinkingExpanded,
    if (aiModelTag != null) 'aiModelTag': aiModelTag,
    if (replyToId != null) 'replyToId': replyToId,
    if (replyToSender != null) 'replyToSender': replyToSender,
    if (replyToText != null) 'replyToText': replyToText,
    'isPinned': isPinned,
    if (reactions.isNotEmpty)
      'reactions': reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
  };

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    MessageStatus parseStatus(String? name) {
      if (name == null) return MessageStatus.sent;
      try {
        return MessageStatus.values.byName(name);
      } catch (_) {
        return MessageStatus.sent;
      }
    }

    final ts = json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'] as String)?.toLocal() ??
              DateTime.now()
        : DateTime.now();
    final revAt = json['revokedAt'] != null
        ? DateTime.tryParse(json['revokedAt'] as String)?.toLocal()
        : null;

    final attachmentJson = json['fileAttachment'] as Map<String, dynamic>?;

    final reactionsMap = <String, List<String>>{};
    if (json['reactions'] is Map) {
      (json['reactions'] as Map).forEach((key, val) {
        if (val is List) {
          reactionsMap[key.toString()] = val.map((e) => e.toString()).toList();
        }
      });
    }

    return MessageModel(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      sourceSession: json['sourceSession'] as String?,
      senderName: json['senderName'] as String? ?? '',
      recipientId: json['recipientId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: ts,
      isMine: json['isMine'] as bool? ?? false,
      status: parseStatus(json['status'] as String?),
      pendingRecipients: (json['pendingRecipients'] as List?)
          ?.cast<String>()
          .toSet(),
      fileAttachment: attachmentJson != null
          ? FileAttachmentInfo.fromJson(attachmentJson)
          : null,
      isRevoked: json['isRevoked'] as bool? ?? false,
      revokedAt: revAt,
      thinkingContent: json['thinkingContent'] as String?,
      isThinkingExpanded: json['isThinkingExpanded'] as bool? ?? true,
      aiModelTag: json['aiModelTag'] as String?,
      isStreaming: false,
      replyToId: json['replyToId'] as String?,
      replyToSender: json['replyToSender'] as String?,
      replyToText: json['replyToText'] as String?,
      isPinned: json['isPinned'] as bool? ?? false,
      reactions: reactionsMap,
    );
  }
}
