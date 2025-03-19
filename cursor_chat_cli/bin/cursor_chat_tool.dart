#!/usr/bin/env dart

// Request ID er foldernavnene i workspaceStorage-mappen
// Dette er vigtigt at forstå for korrekt visning af chat-data

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

/// Finder stien til Cursor's data mappe baseret på OS
String getCursorDataPath() {
  String home = '';
  
  if (Platform.environment.containsKey('HOME')) {
    home = Platform.environment['HOME']!;
  } else if (Platform.environment.containsKey('USERPROFILE')) {
    home = Platform.environment['USERPROFILE']!;
  } else {
    print('Kunne ikke finde hjemmemappen');
    exit(1);
  }

  if (Platform.isMacOS) {
    return path.join(home, 'Library', 'Application Support', 'Cursor', 'User', 'workspaceStorage');
  } else if (Platform.isLinux) {
    return path.join(home, '.config', 'Cursor', 'User', 'workspaceStorage');
  } else if (Platform.isWindows) {
    return path.join(home, 'AppData', 'Roaming', 'Cursor', 'User', 'workspaceStorage');
  } else {
    print('Ikke-understøttet platform: ${Platform.operatingSystem}');
    exit(1);
  }
}

/// Finder chat ud fra request ID og returnerer den fulde chat
Future<Chat?> findChatByRequestId(String requestId) async {
  final config = Config.load('~/.cursor_chat_tool.conf');
  final browser = ChatBrowser(config);
  final allChats = await browser.loadAllChats();
  
  // Find chat med matching requestId
  for (final chat in allChats) {
    if (chat.id == requestId || chat.id.contains(requestId) || 
        (chat.requestId.isNotEmpty && (chat.requestId == requestId || chat.requestId.contains(requestId)))) {
      return chat;
    }
  }
  
  print('Kunne ikke finde chat med request ID: $requestId');
  return null;
}

/// Henter en fuld chat fra databasen via chat ID
Chat? getFullChatFromDb(Database db, int chatId, [String? requestId]) {
  try {
    // Hent meddelelser direkte fra chat_messages
    final messageResult = db.select(
      "SELECT content, role, timestamp FROM chat_messages WHERE folder_id = ? ORDER BY timestamp",
      [chatId]
    );
    
    if (messageResult.isEmpty) {
      // Hvis folder_id ikke virker, prøv at hente dem alle
      final allMessages = db.select(
        "SELECT content, role, timestamp FROM chat_messages ORDER BY timestamp"
      );
      
      if (allMessages.isEmpty) {
        print('Ingen beskeder fundet i databasen');
        return null;
      }
      
      // Hvis vi har requestId, brug det
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
      
      // Generer titel fra første besked
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
    
    // Hvis vi har resultater med folder_id
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
    
    // Generer titel fra første besked
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
    print('Fejl ved hentning af chat fra db: $e');
    return null;
  }
}

/// Henter en fuld chat fra CLI via chat ID
Future<Chat?> getFullChatFromCli(String chatId) async {
  try {
    // Parse chatId as integer index
    int? index = int.tryParse(chatId);
    if (index != null) {
      // Indlæs alle chats og vælg ud fra index
      final allChats = await getAllChats();
      
      if (allChats.isEmpty) {
        print('Ingen chats fundet');
        return null;
      }
      
      if (index < 1 || index > allChats.length) {
        print('Ugyldigt chat indeks: $index (skal være mellem 1 og ${allChats.length})');
        return null;
      }
      
      return allChats[index - 1];
    }
    
    // Hvis ikke et indeks, prøv at finde chat ud fra ID
    return await findChatByRequestId(chatId);
  } catch (e) {
    print('Fejl ved hentning af chat: $e');
    return null;
  }
}

/// Henter alle chats (via ChatBrowser klassen)
Future<List<Chat>> getAllChats() async {
  final config = Config.load('~/.cursor_chat_tool.conf');
  final browser = ChatBrowser(config);
  return await browser.loadAllChats();
}

/// Viser liste over alle chats
Future<void> printChatList() async {
  final allChats = await getAllChats();
  
  if (allChats.isEmpty) {
    print('Ingen chat historik fundet');
    return;
  }
  
  print('=== Cursor Chat Historik Browser ===');
  print('');
  print('ID | Titel | Request ID | Antal');
  print('----------------------------------------');
  
  for (var i = 0; i < allChats.length; i++) {
    final chat = allChats[i];
    final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
        ? chat.id
        : chat.title;
    
    // Brug chat.id som fallback for requestId
    final requestIdDisplay = chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;
    
    print('${i + 1} | ${displayTitle} | $requestIdDisplay | ${chat.messages.length}');
  }
  
  print('');
  print('Fandt ${allChats.length} chat historikker');
}

/// Main funktion
void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Vis hjælp')
    ..addFlag('list', abbr: 'l', negatable: false, help: 'List alle chat historikker')
    ..addFlag('tui', abbr: 't', negatable: false, help: 'Åben TUI browser')
    ..addOption('extract', abbr: 'e', help: 'Udtræk en specifik chat (id eller alle)')
    ..addOption('format', abbr: 'f', defaultsTo: 'text', help: 'Output format (text, markdown, html, json)')
    ..addOption('output', abbr: 'o', defaultsTo: './output', help: 'Output mappe')
    ..addOption('config', abbr: 'c', defaultsTo: '~/.cursor_chat_tool.conf', help: 'Sti til konfigurationsfil')
    ..addOption('request-id', abbr: 'r', help: 'Udtræk chat med specifik request ID og gem JSON i nuværende mappe')
    ..addOption('output-dir', abbr: 'd', help: 'Specifik output mappe for request-id kommandoen');

  try {
    final results = parser.parse(arguments);
    
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
    
    // Håndtér request-id parameter
    if (results.wasParsed('request-id')) {
      final requestId = results['request-id'] as String;
      
      // Bestem output-mappen (nuværende mappe eller brugerspecificeret)
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
      
      // Opret output mappe hvis den ikke eksisterer
      final outputDirectory = Directory(outputDir);
      if (!outputDirectory.existsSync()) {
        outputDirectory.createSync(recursive: true);
      }
      
      if (chatId.toLowerCase() == 'alle' || chatId.toLowerCase() == 'all') {
        // Udtræk alle chats
        final allChats = await getAllChats();
        
        if (allChats.isEmpty) {
          print('Ingen chats fundet til udtrækning');
          return;
        }
        
        int counter = 0;
        for (final chat in allChats) {
          final outputFile = _getOutputFile(chat, outputDir, format);
          final formattedContent = _formatChat(chat, format);
          File(outputFile).writeAsStringSync(formattedContent);
          print('Udtrak chat: ${chat.title} til ${path.basename(outputFile)}');
          counter++;
        }
        
        print('Udtrak $counter chats til $outputDir');
      } else {
        // Udtræk en specifik chat
        final specificChat = await getFullChatFromCli(chatId);
        
        if (specificChat == null) {
          print('Ingen chats fundet til udtrækning');
          return;
        }
        
        final outputFile = _getOutputFile(specificChat, outputDir, format);
        final formattedContent = _formatChat(specificChat, format);
        File(outputFile).writeAsStringSync(formattedContent);
        
        print('Udtrak chat "${specificChat.title}" til ${path.basename(outputFile)}');
      }
      return;
    }
    
    if (arguments.isEmpty) {
      _printUsage(parser);
    }
  } catch (e) {
    print('Fejl ved parsing af argumenter: $e');
    print('Brug --help for at se tilgængelige kommandoer');
    exit(1);
  }
}

/// Udtræk en chat med et specifikt request ID og gem som JSON i den specificerede mappe
Future<void> extractChatWithRequestId(String requestId, String outputDir) async {
  final chat = await findChatByRequestId(requestId);
  
  if (chat == null) {
    print('Ingen chat fundet med request ID: $requestId');
    return;
  }
  
  // Opret output-filen - her bruger vi kun request ID som filnavn
  final filename = '${chat.id}.json';
  final outputFile = path.join(outputDir, filename);
  
  // Lav en minimal JSON med ID
  final jsonContent = JsonEncoder.withIndent('  ').convert({
    'id': chat.id,
    'title': chat.title
  });
  
  File(outputFile).writeAsStringSync(jsonContent);
  
  print('Chat med request ID "${chat.id}" gemt som ${path.basename(outputFile)}');
}

// Hjælpefunktioner
void _printUsage(ArgParser parser) {
  print('Cursor Chat Browser & Extractor\n');
  print('Brug: cursor_chat_tool [options]\n');
  print(parser.usage);
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
        buffer.writeln('<div class="timestamp">Besked timestamp: ${timestamp}</div>');
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
      buffer.writeln('Titel: ${chat.title}');
      buffer.writeln('ID: ${chat.id}');
      buffer.writeln('Antal beskeder: ${chat.messages.length}\n');
      
      for (final msg in chat.messages) {
        final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSSSSS').format(msg.timestamp);
        buffer.writeln('--- ${msg.role} (${timestamp}) ---');
        buffer.writeln(msg.content);
        buffer.writeln('');
      }
      
      return buffer.toString();
  }
}

String _getOutputFile(Chat chat, String outputDir, String format) {
  final sanitizedTitle = _sanitizeFilename(chat.title);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final ext = _getExtensionForFormat(format);
  
  // Brug en kombination af titel og ID for unikhed
  return path.join(outputDir, '${sanitizedTitle}_${chat.id}_$timestamp$ext');
}

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
  
  // Begræns længden
  var sanitized = input.length > 50 ? input.substring(0, 50) : input;
  
  // Erstat ugyldige filnavnstegn
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

// Fælles funktion til at konvertere en database værdi til JSON
dynamic valueToJson(dynamic value) {
  if (value == null) return null;
  
  try {
    String jsonStr;
    if (value is Uint8List) {
      jsonStr = utf8.decode(value);
    } else if (value is String) {
      jsonStr = value;
    } else {
      print('Uventet værditype: ${value.runtimeType}');
      return null;
    }
    
    return jsonDecode(jsonStr);
  } catch (e) {
    print('Fejl ved konvertering af værdi til JSON: $e');
    return null;
  }
}
