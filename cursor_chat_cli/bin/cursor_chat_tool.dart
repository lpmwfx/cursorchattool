#!/usr/bin/env dart

// Request ID is the folder names in the workspaceStorage directory
// This is important to understand for correct display of chat data

import 'dart:io';
import 'package:args/args.dart';
import '../lib/chat_browser.dart';
import '../lib/chat_extractor.dart';
import '../lib/config.dart';
import '../lib/chat_model.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

/// Finds the path to Cursor's data folder based on the OS
String getCursorDataPath() {
  String home = '';
  
  if (Platform.environment.containsKey('HOME')) {
    home = Platform.environment['HOME']!;
  } else if (Platform.environment.containsKey('USERPROFILE')) {
    home = Platform.environment['USERPROFILE']!;
  } else {
    print('Could not find home directory');
    exit(1);
  }

  if (Platform.isMacOS) {
    return path.join(home, 'Library', 'Application Support', 'Cursor', 'User', 'workspaceStorage');
  } else if (Platform.isLinux) {
    return path.join(home, '.config', 'Cursor', 'User', 'workspaceStorage');
  } else if (Platform.isWindows) {
    return path.join(home, 'AppData', 'Roaming', 'Cursor', 'User', 'workspaceStorage');
  } else {
    print('Unsupported platform: ${Platform.operatingSystem}');
    exit(1);
  }
}

/// Finds a chat using the request ID and returns the full chat
Future<Chat?> findChatByRequestId(String requestId) async {
  final config = Config.load('~/.cursor_chat_tool.conf');
  final browser = ChatBrowser(config);
  final allChats = await browser.loadAllChats();
  
  // Find chat with matching requestId
  for (final chat in allChats) {
    if (chat.id == requestId || chat.id.contains(requestId) || 
        (chat.requestId.isNotEmpty && (chat.requestId == requestId || chat.requestId.contains(requestId)))) {
      return chat;
    }
  }
  
  print('Could not find chat with request ID: $requestId');
  return null;
}

/// Retrieves a full chat from the database via chat ID
Chat? getFullChatFromDb(Database db, int chatId, [String? requestId]) {
  try {
    // Get messages directly from chat_messages
    final messageResult = db.select(
      "SELECT content, role, timestamp FROM chat_messages WHERE folder_id = ? ORDER BY timestamp",
      [chatId]
    );
    
    if (messageResult.isEmpty) {
      // If folder_id doesn't work, try to get them all
      final allMessages = db.select(
        "SELECT content, role, timestamp FROM chat_messages ORDER BY timestamp"
      );
      
      if (allMessages.isEmpty) {
        print('No messages found in database');
        return null;
      }
      
      // If we have requestId, use it
      final rId = requestId ?? 'unavailable';
      final messages = <ChatMessage>[];
      
      for (final row in allMessages) {
        final content = row['content'] as String;
        final role = row['role'] as String;
        final timestamp = row['timestamp'] as int;
        
        messages.add(ChatMessage(
          content: content,
          role: role,
          timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
        ));
      }
      
      // Generate title from first message
      String title = rId;
      if (messages.isNotEmpty) {
        final firstMsg = messages.first;
        if (firstMsg.content.isNotEmpty) {
          title = firstMsg.content.substring(0, firstMsg.content.length.clamp(0, 50));
          title = title.replaceAll('\n', ' ');
        }
      }
      
      return Chat(
        id: rId,
        title: title,
        messages: messages,
        requestId: rId,
      );
    }
    
    // If we have results with folder_id
    final messages = <ChatMessage>[];
    String chatRequestId = requestId ?? 'unavailable';
    
    for (final row in messageResult) {
      final content = row['content'] as String;
      final role = row['role'] as String;
      final timestamp = row['timestamp'] as int;
      
      messages.add(ChatMessage(
        content: content,
        role: role,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      ));
    }
    
    // Generate title from first message
    String title = chatRequestId;
    if (messages.isNotEmpty) {
      final firstMsg = messages.first;
      if (firstMsg.content.isNotEmpty) {
        title = firstMsg.content.substring(0, firstMsg.content.length.clamp(0, 50));
        title = title.replaceAll('\n', ' ');
      }
    }
    
    return Chat(
      id: chatRequestId,
      title: title,
      messages: messages,
      requestId: chatRequestId,
    );
  } catch (e) {
    print('Error retrieving chat from db: $e');
    return null;
  }
}

/// Retrieves a full chat from CLI via chat ID
Future<Chat?> getFullChatFromCli(String chatId) async {
  try {
    // Parse chatId as integer index
    int? index = int.tryParse(chatId);
    if (index != null) {
      // Load all chats and select by index
      final allChats = await getAllChats();
      
      if (allChats.isEmpty) {
        print('No chats found');
        return null;
      }
      
      if (index < 1 || index > allChats.length) {
        print('Invalid chat index: $index (should be between 1 and ${allChats.length})');
        return null;
      }
      
      return allChats[index - 1];
    }
    
    // If not an index, try to find chat by ID
    return await findChatByRequestId(chatId);
  } catch (e) {
    print('Error retrieving chat: $e');
    return null;
  }
}

/// Retrieves all chats (via ChatBrowser class)
Future<List<Chat>> getAllChats() async {
  final config = Config.load('~/.cursor_chat_tool.conf');
  final browser = ChatBrowser(config);
  return await browser.loadAllChats();
}

/// Shows a list of all chats
Future<void> printChatList() async {
  final allChats = await getAllChats();
  
  if (allChats.isEmpty) {
    print('No chat history found');
    return;
  }
  
  print('=== Cursor Chat History Browser ===');
  print('');
  print('ID | Title | Request ID | Count');
  print('----------------------------------------');
  
  for (var i = 0; i < allChats.length; i++) {
    final chat = allChats[i];
    final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
        ? chat.id
        : chat.title;
    
    // Use chat.id as fallback for requestId
    final requestIdDisplay = chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;
    
    print('${i + 1} | ${displayTitle} | $requestIdDisplay | ${chat.messages.length}');
  }
  
  print('');
  print('Found ${allChats.length} chat histories');
}

/// Main function
void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help')
    ..addFlag('list', abbr: 'l', negatable: false, help: 'List all chat histories')
    ..addFlag('tui', abbr: 't', negatable: false, help: 'Open TUI browser')
    ..addOption('extract', abbr: 'e', help: 'Extract a specific chat (id or all)')
    ..addOption('format', abbr: 'f', defaultsTo: 'text', help: 'Output format (text, markdown, html, json)')
    ..addOption('output', abbr: 'o', defaultsTo: './output', help: 'Output directory')
    ..addOption('config', abbr: 'c', defaultsTo: '~/.cursor_chat_tool.conf', help: 'Path to configuration file')
    ..addOption('request-id', abbr: 'r', help: 'Extract chat with specific request ID and save JSON to current directory')
    ..addOption('output-dir', abbr: 'd', help: 'Specific output directory for request-id command');

  try {
    ArgResults results;
    
    try {
      results = parser.parse(arguments);
    } catch (e) {
      // If parsing fails, check if the first argument could be a request ID
      if (arguments.isNotEmpty && !arguments[0].startsWith('-')) {
        final requestId = arguments[0];
        // Try to process the request ID directly
        await extractChatWithRequestId(requestId, Directory.current.path);
        return;
      } else {
        // If not a request ID, rethrow the error
        rethrow;
      }
    }
    
    // Load config
    final configPath = results['config'] as String;
    final config = Config.load(configPath);
    
    if (results['help'] as bool) {
      _printUsage(parser);
      return;
    }
    
    if (results['list'] as bool) {
      await printChatList();
      return;
    }
    
    if (results['tui'] as bool) {
      final browser = ChatBrowser(config);
      await browser.showTUI();
      return;
    }
    
    // Handle request-id parameter
    if (results.wasParsed('request-id')) {
      final requestId = results['request-id'] as String;
      
      // Determine output directory (current directory or user-specified)
      final outputDir = results.wasParsed('output-dir') 
          ? results['output-dir'] as String
          : Directory.current.path;
      
      await extractChatWithRequestId(requestId, outputDir);
      return;
    }
    
    if (results.wasParsed('extract')) {
      final chatId = results['extract'] as String;
      final format = results['format'] as String;
      final outputDir = results['output'] as String;
      
      // Create output directory if it doesn't exist
      final outputDirectory = Directory(outputDir);
      if (!outputDirectory.existsSync()) {
        outputDirectory.createSync(recursive: true);
      }
      
      if (chatId.toLowerCase() == 'alle' || chatId.toLowerCase() == 'all') {
        // Extract all chats
        final allChats = await getAllChats();
        
        if (allChats.isEmpty) {
          print('No chats found for extraction');
          return;
        }
        
        int counter = 0;
        for (final chat in allChats) {
          final outputFile = _getOutputFile(chat, outputDir, format);
          final formattedContent = _formatChat(chat, format);
          File(outputFile).writeAsStringSync(formattedContent);
          print('Extracted chat: ${chat.title} to ${path.basename(outputFile)}');
          counter++;
        }
        
        print('Extracted $counter chats to $outputDir');
      } else {
        // Extract a specific chat
        final specificChat = await getFullChatFromCli(chatId);
        
        if (specificChat == null) {
          print('No chats found for extraction');
          return;
        }
        
        final outputFile = _getOutputFile(specificChat, outputDir, format);
        final formattedContent = _formatChat(specificChat, format);
        File(outputFile).writeAsStringSync(formattedContent);
        
        print('Extracted chat "${specificChat.title}" to ${path.basename(outputFile)}');
      }
      return;
    }
    
    // If no options specified but there's a positional argument, assume it's a request ID
    if (results.rest.isNotEmpty) {
      final requestId = results.rest[0];
      await extractChatWithRequestId(requestId, Directory.current.path);
      return;
    }
    
    if (arguments.isEmpty) {
      _printUsage(parser);
    }
  } catch (e) {
    print('Error parsing arguments: $e');
    print('Use --help to see available commands');
    exit(1);
  }
}

/// Extract a chat with a specific request ID and save as JSON in the specified directory
Future<void> extractChatWithRequestId(String requestId, String outputDir) async {
  final chat = await findChatByRequestId(requestId);
  
  if (chat == null) {
    print('No chat found with request ID: $requestId');
    return;
  }
  
  // Use a more descriptive filename
  final title = _sanitizeFilename(chat.title);
  final filename = '$title-${chat.id}.json';
  final outputFile = path.join(outputDir, filename);
  
  // Create full JSON with all messages
  final jsonContent = JsonEncoder.withIndent('  ').convert({
    'id': chat.id,
    'title': chat.title,
    'requestId': chat.requestId,
    'messages': chat.messages.map((msg) => {
      'role': msg.role,
      'content': msg.content,
      'timestamp': msg.timestamp.millisecondsSinceEpoch
    }).toList()
  });
  
  File(outputFile).writeAsStringSync(jsonContent);
  
  print('Chat with request ID "${chat.id}" saved as ${path.basename(outputFile)}');
}

// Help function
void _printUsage(ArgParser parser) {
  print('Cursor Chat Browser & Extractor\n');
  print('Usage: cursor_chat_tool [options] [request_id]\n');
  print('If a request_id is provided as a direct argument, the tool will save that chat as JSON in the current directory.\n');
  print(parser.usage);
  print('\nExamples:');
  print('  cursor_chat_tool --list             # List all chats');
  print('  cursor_chat_tool --tui              # Open the TUI browser');
  print('  cursor_chat_tool 1234abcd           # Extract chat with ID 1234abcd to current directory');
  print('  cursor_chat_tool --extract=all      # Extract all chats');
}

String _formatChat(Chat chat, String format) {
  switch (format.toLowerCase()) {
    case 'json':
      final jsonMap = {
        'id': chat.id,
        'title': chat.title,
        'messages': chat.messages.map((msg) => {
          'role': msg.role,
          'content': msg.content,
          'timestamp': msg.timestamp.millisecondsSinceEpoch
        }).toList()
      };
      return JsonEncoder.withIndent('  ').convert(jsonMap);
    
    case 'markdown':
      final buffer = StringBuffer();
      buffer.writeln('# ${chat.title}\n');
      
      for (final msg in chat.messages) {
        final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSSSSS').format(msg.timestamp);
        buffer.writeln('## ${msg.role} (${timestamp})\n');
        buffer.writeln('${msg.content}\n');
      }
      
      return buffer.toString();
    
    case 'html':
      final buffer = StringBuffer();
      buffer.writeln('<!DOCTYPE html>');
      buffer.writeln('<html>');
      buffer.writeln('<head>');
      buffer.writeln('<meta charset="UTF-8">');
      buffer.writeln('<title>${_escapeHtml(chat.title)}</title>');
      buffer.writeln('<style>');
      buffer.writeln('body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }');
      buffer.writeln('h1 { color: #333; }');
      buffer.writeln('.message { margin-bottom: 20px; padding: 10px; border-radius: 5px; }');
      buffer.writeln('.user { background-color: #f0f0f0; }');
      buffer.writeln('.assistant { background-color: #e6f7ff; }');
      buffer.writeln('.timestamp { color: #666; font-size: 0.8em; margin-bottom: 5px; }');
      buffer.writeln('.content { white-space: pre-wrap; }');
      buffer.writeln('</style>');
      buffer.writeln('</head>');
      buffer.writeln('<body>');
      buffer.writeln('<h1>${_escapeHtml(chat.title)}</h1>');
      
      for (final msg in chat.messages) {
        final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSSSSS').format(msg.timestamp);
        final cssClass = msg.role == 'user' ? 'user' : 'assistant';
        
        buffer.writeln('<div class="message ${cssClass}">');
        buffer.writeln('<div class="timestamp">Message timestamp: ${timestamp}</div>');
        buffer.writeln('<div class="role">${_escapeHtml(msg.role)}</div>');
        buffer.writeln('<div class="content">${_escapeHtml(msg.content)}</div>');
        buffer.writeln('</div>');
      }
      
      buffer.writeln('</body>');
      buffer.writeln('</html>');
      
      return buffer.toString();
    
    case 'text':
    default:
      final buffer = StringBuffer();
      buffer.writeln('=== ${chat.title} ===');
      buffer.writeln('Chat ID: ${chat.id}');
      buffer.writeln('Request ID: ${chat.requestId}');
      buffer.writeln('Message count: ${chat.messages.length}');
      buffer.writeln('');
      
      for (final msg in chat.messages) {
        final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSSSSS').format(msg.timestamp);
        buffer.writeln('[${msg.role} - ${timestamp}]');
        buffer.writeln(msg.content);
        buffer.writeln('');
      }
      
      return buffer.toString();
  }
}

/// Gets the output file path
String _getOutputFile(Chat chat, String outputDir, String format) {
  final sanitizedTitle = _sanitizeFilename(chat.title);
  final extension = _getExtensionForFormat(format);
  return path.join(outputDir, '${sanitizedTitle}_${chat.id}$extension');
}

/// Gets the file extension for the given format
String _getExtensionForFormat(String format) {
  switch (format.toLowerCase()) {
    case 'json': return '.json';
    case 'markdown': return '.md';
    case 'html': return '.html';
    case 'text':
    default: return '.txt';
  }
}

String _sanitizeFilename(String input) {
  if (input.isEmpty) return 'untitled';
  
  // Limit length
  var sanitized = input.length > 50 ? input.substring(0, 50) : input;
  
  // Replace invalid filename characters
  sanitized = sanitized.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  sanitized = sanitized.replaceAll(RegExp(r'\s+'), '_');
  
  return sanitized;
}

String _escapeHtml(String text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

int min(int a, int b) => a < b ? a : b;

// Common function to convert a database value to JSON
dynamic valueToJson(dynamic value) {
  if (value == null) return null;
  
  try {
    String jsonStr;
    if (value is Uint8List) {
      jsonStr = utf8.decode(value);
    } else if (value is String) {
      jsonStr = value;
    } else {
      print('Unexpected value type: ${value.runtimeType}');
      return null;
    }
    
    return jsonDecode(jsonStr);
  } catch (e) {
    print('Error converting value to JSON: $e');
    return null;
  }
}
