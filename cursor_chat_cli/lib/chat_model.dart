import 'dart:convert';

/// Model klasser for chat historik

/// Repræsenterer en besked i en chat
class ChatMessage {
  final String content;
  final String role;
  final DateTime timestamp;

  ChatMessage({
    required this.content,
    required this.role,
    required this.timestamp,
  });

  /// Returnerer true hvis rollen er 'user'
  bool get isUser => role.toLowerCase() == 'user';

  /// Opret ChatMessage fra JSON objekt
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      content: json['content'] as String,
      role: json['role'] as String,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
    );
  }

  /// Konverter ChatMessage til JSON
  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'role': role,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

/// Repræsenterer en hel chat historik
class Chat {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final String requestId;

  Chat({
    required this.id,
    required this.title,
    required this.messages,
    this.requestId = '',
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'].toString(),
      title: json['title'] as String,
      messages: (json['messages'] as List)
          .map((msg) => ChatMessage.fromJson(msg as Map<String, dynamic>))
          .toList(),
      requestId: json['requestId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((msg) => msg.toJson()).toList(),
      'requestId': requestId,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# $title\n');
    
    for (var message in messages) {
      buffer.writeln('## ${message.role}');
      buffer.writeln(message.content);
      buffer.writeln();
    }
    
    return buffer.toString();
  }

  String toHtml() {
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html>');
    buffer.writeln('<head>');
    buffer.writeln('<title>$title</title>');
    buffer.writeln('<style>');
    buffer.writeln('body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; }');
    buffer.writeln('h1 { color: #333; }');
    buffer.writeln('h2 { color: #666; margin-top: 20px; }');
    buffer.writeln('pre { background: #f5f5f5; padding: 15px; border-radius: 5px; overflow-x: auto; }');
    buffer.writeln('code { font-family: "SF Mono", "Consolas", monospace; }');
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<h1>$title</h1>');
    
    for (var message in messages) {
      buffer.writeln('<h2>${message.role}</h2>');
      buffer.writeln('<div>${message.content}</div>');
    }
    
    buffer.writeln('</body>');
    buffer.writeln('</html>');
    
    return buffer.toString();
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Chat: $title');
    buffer.writeln('ID: $id');
    buffer.writeln('Antal beskeder: ${messages.length}\n');
    
    for (var message in messages) {
      buffer.writeln('${message.role}:');
      buffer.writeln(message.content);
      buffer.writeln();
    }
    
    return buffer.toString();
  }

  static Chat? fromSqliteValue(String chatId, String jsonValue) {
    try {
      final data = jsonDecode(jsonValue);
      String extractedRequestId = '';

      // Find requestId på forskellige steder i JSON-strukturen
      if (data is Map) {
        // Tjek for requestId direkte i data
        if (data.containsKey('requestId')) {
          extractedRequestId = data['requestId'].toString();
        } 
        // Tjek for requestId i metadata
        else if (data.containsKey('metadata') && data['metadata'] is Map) {
          final metadata = data['metadata'] as Map;
          if (metadata.containsKey('requestId')) {
            extractedRequestId = metadata['requestId'].toString();
          }
        } 
        // Tjek for requestId i conversation
        else if (data.containsKey('conversation') && data['conversation'] is Map) {
          final conversation = data['conversation'] as Map;
          if (conversation.containsKey('requestId')) {
            extractedRequestId = conversation['requestId'].toString();
          }
        }
        
        // Prøv at finde UUID format i ID eller andre steder
        if (extractedRequestId.isEmpty) {
          final uuidRegex = RegExp(r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', caseSensitive: false);
          final longHashRegex = RegExp(r'[a-f0-9_-]{30,}', caseSensitive: false);
          
          // Tjek ID
          if (uuidRegex.hasMatch(chatId)) {
            extractedRequestId = uuidRegex.firstMatch(chatId)!.group(0)!;
          } else if (longHashRegex.hasMatch(chatId)) {
            extractedRequestId = longHashRegex.firstMatch(chatId)!.group(0)!;
          }
        }
      }

      // Håndter forskellige JSON-formater
      if (data is List) {
        // Hvis det er et array, antag at det er beskeder
        final messages = <ChatMessage>[];
        
        for (var msgJson in data) {
          if (msgJson is Map<String, dynamic>) {
            messages.add(ChatMessage(
              content: msgJson['text'] ?? msgJson['content'] ?? '',
              role: msgJson['role'] ?? (msgJson['isUser'] == true ? 'user' : 'assistant'),
              timestamp: msgJson['timestamp'] != null
                ? DateTime.fromMillisecondsSinceEpoch(msgJson['timestamp'] as int)
                : (msgJson['date'] != null ? DateTime.parse(msgJson['date']) : DateTime.now()),
            ));
          }
        }

        final title = messages.isNotEmpty
            ? _generateTitle(messages.first.content)
            : 'Chat $chatId';

        return Chat(
          id: chatId,
          title: title,
          messages: messages,
          requestId: extractedRequestId,
        );
      } else if (data is Map) {
        // Hvis det er et objekt, undersøg strukturen
        if (data.containsKey('messages')) {
          // Antagelse: { messages: [...] }
          final List<dynamic> messagesJson = data['messages'] ?? [];
          final messages = <ChatMessage>[];
          
          for (var msgJson in messagesJson) {
            if (msgJson is Map<String, dynamic>) {
              messages.add(ChatMessage(
                content: msgJson['text'] ?? msgJson['content'] ?? '',
                role: msgJson['role'] ?? (msgJson['isUser'] == true ? 'user' : 'assistant'),
                timestamp: msgJson['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(msgJson['timestamp'] as int)
                  : (msgJson['date'] != null ? DateTime.parse(msgJson['date']) : DateTime.now()),
              ));
            }
          }

          final title = data['title'] ??
              (messages.isNotEmpty
                  ? _generateTitle(messages.first.content)
                  : 'Chat $chatId');

          return Chat(
            id: chatId,
            title: title,
            messages: messages,
            requestId: extractedRequestId,
          );
        } else if (data.containsKey('sessions')) {
          // Antagelse: { sessions: [{messages: [...]}] }
          final List<dynamic> sessionsJson = data['sessions'] ?? [];
          if (sessionsJson.isNotEmpty) {
            final sessionData = sessionsJson.last;
            final List<dynamic> messagesJson = sessionData['messages'] ?? [];

            final messages = <ChatMessage>[];
            
            for (var msgJson in messagesJson) {
              if (msgJson is Map<String, dynamic>) {
                messages.add(ChatMessage(
                  content: msgJson['text'] ?? msgJson['content'] ?? '',
                  role: msgJson['role'] ?? (msgJson['isUser'] == true ? 'user' : 'assistant'),
                  timestamp: msgJson['timestamp'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(msgJson['timestamp'] as int)
                    : (msgJson['date'] != null ? DateTime.parse(msgJson['date']) : DateTime.now()),
                ));
              }
            }

            final title = sessionData['title'] ??
                (messages.isNotEmpty
                    ? _generateTitle(messages.first.content)
                    : 'Chat $chatId');

            return Chat(
              id: chatId,
              title: title,
              messages: messages,
              requestId: extractedRequestId,
            );
          }
        } else if (data.containsKey('chats')) {
          // Antagelse: { chats: [{title, messages: [...]}] }
          final List<dynamic> chatsJson = data['chats'] ?? [];
          if (chatsJson.isNotEmpty) {
            final chatData = chatsJson.last;
            final List<dynamic> messagesJson = chatData['messages'] ?? [];

            final messages = <ChatMessage>[];
            
            for (var msgJson in messagesJson) {
              if (msgJson is Map<String, dynamic>) {
                messages.add(ChatMessage(
                  content: msgJson['text'] ?? msgJson['content'] ?? '',
                  role: msgJson['role'] ?? (msgJson['isUser'] == true ? 'user' : 'assistant'),
                  timestamp: msgJson['timestamp'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(msgJson['timestamp'] as int)
                    : (msgJson['date'] != null ? DateTime.parse(msgJson['date']) : DateTime.now()),
                ));
              }
            }

            final title = chatData['title'] ??
                (messages.isNotEmpty
                    ? _generateTitle(messages.first.content)
                    : 'Chat $chatId');

            return Chat(
              id: chatId,
              title: title,
              messages: messages,
              requestId: extractedRequestId,
            );
          }
        } else if (data.containsKey('chatData')) {
          // Antagelse: { chatData: {messages: [...]} }
          final chatData = data['chatData'] as Map<String, dynamic>?;
          if (chatData != null && chatData.containsKey('messages')) {
            final List<dynamic> messagesJson = chatData['messages'] ?? [];
            final messages = <ChatMessage>[];
            
            for (var msgJson in messagesJson) {
              if (msgJson is Map<String, dynamic>) {
                messages.add(ChatMessage(
                  content: msgJson['text'] ?? msgJson['content'] ?? '',
                  role: msgJson['role'] ?? (msgJson['isUser'] == true ? 'user' : 'assistant'),
                  timestamp: msgJson['timestamp'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(msgJson['timestamp'] as int)
                    : (msgJson['date'] != null ? DateTime.parse(msgJson['date']) : DateTime.now()),
                ));
              }
            }

            final title = chatData['title'] ??
                (messages.isNotEmpty
                    ? _generateTitle(messages.first.content)
                    : 'Chat $chatId');

            return Chat(
              id: chatId,
              title: title,
              messages: messages,
              requestId: extractedRequestId,
            );
          }
        }
      }

      // Hvis vi ikke kunne genkende formatet
      return null;
    } catch (e) {
      print('Fejl ved parsing af chat data: $e');
      return null;
    }
  }

  /// Generer en titel baseret på den første besked
  static String _generateTitle(String content) {
    // Begræns til de første 50 tegn
    final truncated =
        content.length > 50 ? '${content.substring(0, 47)}...' : content;

    // Fjern newlines
    return truncated.replaceAll('\n', ' ').trim();
  }

  static bool isValidChat(Chat chat) {
    return chat.messages.isNotEmpty;
  }

  DateTime get lastMessageTime {
    return messages.isNotEmpty ? messages.last.timestamp : DateTime.now();
  }
}
