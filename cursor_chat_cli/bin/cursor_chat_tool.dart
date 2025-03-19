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

import '../lib/cli/chat_model.dart' as cli_model;

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
Chat? findChatByRequestId(String requestId) {
  final workspacePath = getCursorDataPath();
  final workspaceDir = Directory(workspacePath);
  
  if (!workspaceDir.existsSync()) {
    print('Workspace mappe findes ikke: $workspacePath');
    return null;
  }
  
  try {
    // Find alle mapper, der matcher request ID
    final matchingFolders = workspaceDir.listSync().where((entity) {
      if (entity is Directory) {
        final folderName = entity.path.split(Platform.pathSeparator).last;
        return folderName == requestId || folderName.contains(requestId);
      }
      return false;
    }).toList();
    
    if (matchingFolders.isEmpty) {
      print('Kunne ikke finde mappe med request ID: $requestId');
      return null;
    }
    
    // Brug det første match
    final exactRequestId = matchingFolders.first.path.split(Platform.pathSeparator).last;
    
    // I denne forenklede implementation bruger vi bare ID'et til både ID og titel
    // og returnerer en tom liste af beskeder
    return Chat(
      id: exactRequestId,
      title: exactRequestId,
      messages: [],
    );
  } catch (e) {
    print('Fejl ved søgning efter chat: $e');
    return null;
  }
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
    );
  } catch (e) {
    print('Fejl ved hentning af chat fra db: $e');
    return null;
  }
}

/// Henter en fuld chat fra CLI via chat ID
Chat? getFullChatFromCli(String chatId) {
  try {
    final workspacePath = getCursorDataPath();
    final workspaceDir = Directory(workspacePath);
    
    if (!workspaceDir.existsSync()) {
      print('Workspace mappe findes ikke: $workspacePath');
      return null;
    }
    
    // Parse chatId as integer index
    int? index = int.tryParse(chatId);
    if (index != null) {
      // Indlæs alle chats og vælg ud fra index
      final allChats = getAllChats();
      
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
    return findChatByRequestId(chatId);
  } catch (e) {
    print('Fejl ved hentning af chat: $e');
    return null;
  }
}

/// Henter alle chats - forenklet version der bare bruger mappenavnene
List<Chat> getAllChats() {
  final workspacePath = getCursorDataPath();
  final workspaceDir = Directory(workspacePath);
  final chats = <Chat>[];
  
  if (!workspaceDir.existsSync()) {
    print('Workspace mappe findes ikke: $workspacePath');
    return [];
  }
  
  try {
    for (final entity in workspaceDir.listSync()) {
      if (entity is Directory) {
        final requestId = entity.path.split(Platform.pathSeparator).last;
        
        // Simpel chat med kun ID og titel (som er det samme som ID)
        final chat = Chat(
          id: requestId,
          title: requestId,
          messages: [], // Tom liste af beskeder, da vi ikke har brug for dem til visning
        );
        
        chats.add(chat);
      }
    }
    
    return chats;
  } catch (e) {
    print('Fejl ved indlæsning af chats: $e');
    return [];
  }
}

/// Viser liste over alle chats
void printChatList() {
  final allChats = getAllChats();
  
  if (allChats.isEmpty) {
    print('Ingen chat historik fundet');
    return;
  }
  
  print('Fandt ${allChats.length} chat historikker:');
  print('');
  print('ID | Titel | Request ID | Antal beskeder');
  print('----------------------------------------');
  
  for (var i = 0; i < allChats.length; i++) {
    final chat = allChats[i];
    
    print('${i + 1} | ${chat.title} | ${chat.id} | ${chat.messages.length}');
  }
}

/// Main funktion
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Vis hjælp')
    ..addFlag('list', abbr: 'l', negatable: false, help: 'List alle chat historikker')
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
      printChatList();
      return;
    }
    
    // Håndtér request-id parameter
    if (results.wasParsed('request-id')) {
      final requestId = results['request-id'] as String;
      
      // Bestem output-mappen (nuværende mappe eller brugerspecificeret)
      final outputDir = results.wasParsed('output-dir') 
          ? results['output-dir'] as String
          : Directory.current.path;
      
      extractChatWithRequestId(requestId, outputDir);
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
        final allChats = getAllChats();
        
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
        final specificChat = getFullChatFromCli(chatId);
        
        if (specificChat == null) {
          print('Ingen chats fundet til udtrækning');
          return;
        }
        
        final outputFile = _getOutputFile(specificChat, outputDir, format);
        final formattedContent = _formatChat(specificChat, format);
        File(outputFile).writeAsStringSync(formattedContent);
        
        print('Udtrak chat "${specificChat.title}" til ${path.basename(outputFile)}');
      }
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
void extractChatWithRequestId(String requestId, String outputDir) {
  final chat = findChatByRequestId(requestId);
  
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
