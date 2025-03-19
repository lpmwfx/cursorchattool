import 'dart:io';
import 'package:dart_console/dart_console.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:collection/collection.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:convert';
import 'config.dart';
import 'chat_model.dart';

/// Class for browsing and displaying chat histories
class ChatBrowser {
  final Config config;
  final console = Console();
  List<Chat> _chats = [];

  ChatBrowser(this.config);

  /// Loads all chats from workspace storage folders
  Future<List<Chat>> _loadChats() async {
    final storageDir = Directory(config.workspaceStoragePath);

    if (!storageDir.existsSync()) {
      print(
          'Warning: Workspace storage folder not found: ${config.workspaceStoragePath}');
      return [];
    }

    final chats = <Chat>[];
    final skippedChats = <String>[];

    try {
      // Go through all md5 hash folders (workspace storage)
      await for (final entity in storageDir.list()) {
        if (entity is Directory) {
          final dbFile = File(path.join(entity.path, 'state.vscdb'));

          // Check if there's a state.vscdb file in the folder
          if (dbFile.existsSync()) {
            try {
              // Open SQLite database
              final db = sqlite3.open(dbFile.path);

              // Get chat data from database
              final result = db.select(
                  "SELECT rowid, [key], value FROM ItemTable WHERE [key] IN "
                  "('aiService.prompts', 'workbench.panel.aichat.view.aichat.chatdata')");

              // Process each row
              for (final row in result) {
                final rowId = row['rowid'] as int;
                final key = row['key'] as String;
                final value = row['value'] as String;

                // Generate chat ID
                final chatId = '${entity.path.split(Platform.pathSeparator).last}_$rowId';
                
                // Try to create a Chat from the value
                final chat = Chat.fromSqliteValue(chatId, value);
                
                // Validate chat and only add valid ones
                if (chat != null) {
                  if (Chat.isValidChat(chat)) {
                    chats.add(chat);
                  } else {
                    // Log that we're skipping an invalid chat
                    skippedChats.add(chatId);
                    print('Skipped invalid chat: $chatId');
                  }
                }
              }

              // Close the database
              db.dispose();
            } catch (e) {
              print('Could not read database ${dbFile.path}: $e');
            }
          }
        }
      }

      // Show info about number of skipped chats
      if (skippedChats.isNotEmpty) {
        print('');
        print('Skipped ${skippedChats.length} invalid chats');
      }

      // Sort by date, newest first
      chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      return chats;
    } catch (e) {
      print('Error loading chats: $e');
      return [];
    }
  }

  /// Public method to load all chats
  Future<List<Chat>> loadAllChats() async {
    return await _loadChats();
  }

  /// Shows a list of all chats in the console
  Future<void> listChats() async {
    _chats = await _loadChats();

    if (_chats.isEmpty) {
      print('No chat histories found in ${config.workspaceStoragePath}');
      return;
    }

    print('=== Cursor Chat History Browser ===');
    print('');
    print('ID | Title | Request ID | Count');
    print('----------------------------------------');

    for (var i = 0; i < _chats.length; i++) {
      final chat = _chats[i];
      
      // Show either title or ID based on format
      final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
          ? chat.id
          : chat.title;
      
      final requestIdDisplay = chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;
      
      print('${i + 1} | ${displayTitle} | $requestIdDisplay | ${chat.messages.length}');
    }
    
    print('');
    print('Found ${_chats.length} chat histories');
  }

  /// Retrieves a specific chat by ID
  Future<Chat?> getChat(String chatId) async {
    if (_chats.isEmpty) {
      _chats = await _loadChats();
    }

    // Try to parse chatId as an index
    final index = int.tryParse(chatId);
    if (index != null && index > 0 && index <= _chats.length) {
      final chat = _chats[index - 1];
      // Double-check that the chat is valid
      if (Chat.isValidChat(chat)) {
        return chat;
      } else {
        print('Chat with index $index is not valid');
        return null;
      }
    }

    // Otherwise search for matching ID
    final chat = _chats.firstWhereOrNull((chat) => chat.id == chatId);
    if (chat != null && Chat.isValidChat(chat)) {
      return chat;
    }
    
    print('Could not find valid chat with ID: $chatId');
    return null;
  }

  /// Shows Text User Interface (TUI) to browse and view chats
  Future<void> showTUI() async {
    _chats = await _loadChats();

    if (_chats.isEmpty) {
      print('No chat histories found in ${config.workspaceStoragePath}');
      return;
    }

    console.clearScreen();
    var selectedIndex = 0;
    var viewingChat = false;
    var scrollOffset = 0;
    var statusMessage = '';

    while (true) {
      console.clearScreen();
      console.resetCursorPosition();

      if (!viewingChat) {
        _drawChatList(selectedIndex);
      } else {
        _drawChatView(_chats[selectedIndex], scrollOffset, statusMessage);
        statusMessage = ''; // Reset status message after displaying
      }

      final key = console.readKey();

      if (key.controlChar == ControlCharacter.ctrlC) {
        console.clearScreen();
        console.resetCursorPosition();
        return;
      }

      if (!viewingChat) {
        // Navigation in chat list
        if (key.controlChar == ControlCharacter.arrowDown) {
          selectedIndex = (selectedIndex + 1) % _chats.length;
        } else if (key.controlChar == ControlCharacter.arrowUp) {
          selectedIndex = (selectedIndex - 1 + _chats.length) % _chats.length;
        } else if (key.controlChar == ControlCharacter.enter) {
          viewingChat = true;
          scrollOffset = 0;
        } else if (key.char == 'q' || key.controlChar == ControlCharacter.ctrlQ) {
          console.clearScreen();
          console.resetCursorPosition();
          return;
        }
      } else {
        // Navigation in chat view
        if (key.controlChar == ControlCharacter.arrowDown) {
          scrollOffset += 1;
        } else if (key.controlChar == ControlCharacter.arrowUp) {
          scrollOffset = (scrollOffset - 1).clamp(0, double.infinity).toInt();
        } else if (key.char == 'q' ||
            key.controlChar == ControlCharacter.escape) {
          viewingChat = false;
        } else if (key.char == 's') {
          // Save chat as JSON
          statusMessage = _saveCurrentChatAsJson(_chats[selectedIndex]);
        }
      }
    }
  }

  /// Save current chat as JSON in the current directory
  String _saveCurrentChatAsJson(Chat chat) {
    try {
      final title = _sanitizeFilename(chat.title);
      final reqId = chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;
      final filename = '$title-$reqId.json';
      
      // Convert chat to JSON
      final jsonData = {
        'id': chat.id,
        'title': chat.title,
        'requestId': reqId,
        'messages': chat.messages.map((msg) => {
          'role': msg.role,
          'content': msg.content,
          'timestamp': msg.timestamp.millisecondsSinceEpoch
        }).toList()
      };
      
      final jsonString = JsonEncoder.withIndent('  ').convert(jsonData);
      
      // Write to current directory
      final file = File(path.join(Directory.current.path, filename));
      file.writeAsStringSync(jsonString);
      
      return 'Chat saved to ${file.path}';
    } catch (e) {
      return 'Error saving chat: $e';
    }
  }

  /// Sanitize filename for safe file operations
  String _sanitizeFilename(String input) {
    if (input.isEmpty) return 'chat';
    
    // Limit length
    var sanitized = input.length > 30 ? input.substring(0, 30) : input;
    
    // Replace invalid filename characters
    sanitized = sanitized.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), '_');
    
    return sanitized;
  }

  /// Draws the chat list
  void _drawChatList(int selectedIndex) {
    final width = console.windowWidth;

    console.writeLine(
      '=== Cursor Chat History Browser ==='.padRight(width),
      TextAlignment.center,
    );
    console.writeLine('');
    console.writeLine(
      'Press ↑/↓ to navigate, Enter to view chat, q or Ctrl+Q to exit',
    );
    console.writeLine('');

    final titleWidth = 40;
    final requestIdWidth = 40;

    console.writeLine(
      'ID | ${_padTruncate('Title', titleWidth)} | ${_padTruncate('Request ID', requestIdWidth)} | Count',
    );
    console.writeLine(''.padRight(width, '-'));

    for (var i = 0; i < _chats.length; i++) {
      final chat = _chats[i];
      
      // Show either title or ID based on format
      final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
          ? chat.id
          : chat.title;
      
      // Use chat.id as fallback for requestId
      final requestIdDisplay = chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;
      
      final line = '${_padTruncate((i + 1).toString(), 3)} | '
          '${_padTruncate(displayTitle, titleWidth)} | '
          '${_padTruncate(requestIdDisplay, requestIdWidth)} | '
          '${chat.messages.length}';

      if (i == selectedIndex) {
        console.setForegroundColor(ConsoleColor.white);
        console.setBackgroundColor(ConsoleColor.blue);
        console.writeLine(line.padRight(width));
        console.resetColorAttributes();
      } else {
        console.writeLine(line);
      }
    }

    console.writeLine('');
    console.writeLine('Found ${_chats.length} chat histories');
  }

  /// Draws the chat view
  void _drawChatView(Chat chat, int scrollOffset, [String statusMessage = '']) {
    final width = console.windowWidth;
    final height = console.windowHeight - 7; // Reduced height to accommodate status and help lines

    console.writeLine(
      '=== ${chat.title} ==='.padRight(width),
      TextAlignment.center,
    );
    console.writeLine('');
    console.writeLine('Press ↑/↓ to scroll, q or ESC to go back, s to save as JSON');
    console.writeLine(''.padRight(width, '-'));

    final visibleMessages = chat.messages.skip(scrollOffset).take(height);

    for (final message in visibleMessages) {
      final sender = message.isUser ? 'User' : 'AI';
      console.writeLine(
        '[$sender - ${DateFormat('HH:mm:ss').format(message.timestamp)}]',
      );

      // Split content into lines that fit the screen width
      final contentLines = _wrapText(message.content, width);
      for (final line in contentLines) {
        console.writeLine(line);
      }

      console.writeLine('');
    }

    console.writeLine(''.padRight(width, '-'));
    
    // Show message position
    console.writeLine(
      'Message ${scrollOffset + 1}-${(scrollOffset + visibleMessages.length).clamp(1, chat.messages.length)} of ${chat.messages.length}',
    );
    
    // Show help text
    console.writeLine(
      '[q] Back  [ESC] Back  [s] Save JSON  [Ctrl+Q] Exit',
      TextAlignment.center
    );
    
    // Show status message if present
    if (statusMessage.isNotEmpty) {
      console.setForegroundColor(ConsoleColor.green);
      console.writeLine(statusMessage, TextAlignment.center);
      console.resetColorAttributes();
    }
  }

  /// Helper function to format text
  String _padTruncate(String text, int width) {
    if (text.length > width) {
      return text.substring(0, width - 3) + '...';
    }
    return text.padRight(width);
  }

  /// Helper function to wrap text to a specific width
  List<String> _wrapText(String text, int width) {
    final result = <String>[];
    final words = text.split(' ');

    String currentLine = '';
    for (final word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if (currentLine.length + word.length + 1 <= width) {
        currentLine += ' $word';
      } else {
        result.add(currentLine);
        currentLine = word;
      }
    }

    if (currentLine.isNotEmpty) {
      result.add(currentLine);
    }

    return result;
  }
}
