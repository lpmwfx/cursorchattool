import 'dart:io';
import 'package:dart_console/dart_console.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:collection/collection.dart';
import 'package:sqlite3/sqlite3.dart';
import 'config.dart';
import 'chat_model.dart';

/// Klasse til at browse og vise chat historikker
class ChatBrowser {
  final Config config;
  final console = Console();
  List<Chat> _chats = [];

  ChatBrowser(this.config);

  /// Indlæser alle chats fra workspace storage mapperne
  Future<List<Chat>> _loadChats() async {
    final storageDir = Directory(config.workspaceStoragePath);

    if (!storageDir.existsSync()) {
      print(
          'Advarsel: Workspace storage mappe ikke fundet: ${config.workspaceStoragePath}');
      return [];
    }

    final chats = <Chat>[];
    final skippedChats = <String>[];

    try {
      // Gennemgå alle md5 hash mapper (workspace storage)
      await for (final entity in storageDir.list()) {
        if (entity is Directory) {
          final dbFile = File(path.join(entity.path, 'state.vscdb'));

          // Tjek om der er en state.vscdb fil i mappen
          if (dbFile.existsSync()) {
            try {
              // Åbn SQLite database
              final db = sqlite3.open(dbFile.path);

              // Hent chat data fra databasen
              final result = db.select(
                  "SELECT rowid, [key], value FROM ItemTable WHERE [key] IN "
                  "('aiService.prompts', 'workbench.panel.aichat.view.aichat.chatdata')");

              // Behandl hver række
              for (final row in result) {
                final rowId = row['rowid'] as int;
                final key = row['key'] as String;
                final value = row['value'] as String;

                // Generer chat ID
                final chatId = '${entity.path.split(Platform.pathSeparator).last}_$rowId';
                
                // Forsøg at oprette en Chat fra værdien
                final chat = Chat.fromSqliteValue(chatId, value);
                
                // Validér chat og tilføj kun gyldige
                if (chat != null) {
                  if (Chat.isValidChat(chat)) {
                    chats.add(chat);
                  } else {
                    // Log at vi springer over en ugyldig chat
                    skippedChats.add(chatId);
                    print('Sprang over ugyldig chat: $chatId');
                  }
                }
              }

              // Luk databasen
              db.dispose();
            } catch (e) {
              print('Kunne ikke læse database ${dbFile.path}: $e');
            }
          }
        }
      }

      // Vis info om antal skippede chats
      if (skippedChats.isNotEmpty) {
        print('');
        print('Sprang over ${skippedChats.length} ugyldige chats');
      }

      // Sorter efter dato, nyeste først
      chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      return chats;
    } catch (e) {
      print('Fejl ved indlæsning af chats: $e');
      return [];
    }
  }

  /// Offentlig metode til at indlæse alle chats
  Future<List<Chat>> loadAllChats() async {
    return await _loadChats();
  }

  /// Viser liste over alle chats i konsollen
  Future<void> listChats() async {
    _chats = await _loadChats();

    if (_chats.isEmpty) {
      print('Ingen chat historikker fundet i ${config.workspaceStoragePath}');
      return;
    }

    print('=== Cursor Chat Historik Browser ===');
    print('');
    print('ID | Titel | Request ID | Antal');
    print('----------------------------------------');

    for (var i = 0; i < _chats.length; i++) {
      final chat = _chats[i];
      
      // Vis enten title eller ID baseret på format
      final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
          ? chat.id
          : chat.title;
      
      final requestIdDisplay = chat.requestId.isNotEmpty ? chat.requestId : 'N/A';
      
      print('${i + 1} | ${displayTitle} | $requestIdDisplay | ${chat.messages.length}');
    }
    
    print('');
    print('Fandt ${_chats.length} chat historikker');
  }

  /// Henter en specifik chat med ID
  Future<Chat?> getChat(String chatId) async {
    if (_chats.isEmpty) {
      _chats = await _loadChats();
    }

    // Prøv at parse chatId som et indeks
    final index = int.tryParse(chatId);
    if (index != null && index > 0 && index <= _chats.length) {
      final chat = _chats[index - 1];
      // Dobbelt-tjek at chat'en er gyldig
      if (Chat.isValidChat(chat)) {
        return chat;
      } else {
        print('Chat med indeks $index er ikke gyldig');
        return null;
      }
    }

    // Ellers søg efter matching ID
    final chat = _chats.firstWhereOrNull((chat) => chat.id == chatId);
    if (chat != null && Chat.isValidChat(chat)) {
      return chat;
    }
    
    print('Kunne ikke finde gyldig chat med ID: $chatId');
    return null;
  }

  /// Viser Text User Interface (TUI) til at browse og se chats
  Future<void> showTUI() async {
    _chats = await _loadChats();

    if (_chats.isEmpty) {
      print('Ingen chat historikker fundet i ${config.workspaceStoragePath}');
      return;
    }

    console.clearScreen();
    var selectedIndex = 0;
    var viewingChat = false;
    var scrollOffset = 0;

    while (true) {
      console.clearScreen();
      console.resetCursorPosition();

      if (!viewingChat) {
        _drawChatList(selectedIndex);
      } else {
        _drawChatView(_chats[selectedIndex], scrollOffset);
      }

      final key = console.readKey();

      if (key.controlChar == ControlCharacter.ctrlC) {
        console.clearScreen();
        console.resetCursorPosition();
        return;
      }

      if (!viewingChat) {
        // Navigation i chat listen
        if (key.controlChar == ControlCharacter.arrowDown) {
          selectedIndex = (selectedIndex + 1) % _chats.length;
        } else if (key.controlChar == ControlCharacter.arrowUp) {
          selectedIndex = (selectedIndex - 1 + _chats.length) % _chats.length;
        } else if (key.controlChar == ControlCharacter.enter) {
          viewingChat = true;
          scrollOffset = 0;
        } else if (key.char == 'q') {
          console.clearScreen();
          console.resetCursorPosition();
          return;
        }
      } else {
        // Navigation i chat visning
        if (key.controlChar == ControlCharacter.arrowDown) {
          scrollOffset += 1;
        } else if (key.controlChar == ControlCharacter.arrowUp) {
          scrollOffset = (scrollOffset - 1).clamp(0, double.infinity).toInt();
        } else if (key.char == 'q' ||
            key.controlChar == ControlCharacter.escape) {
          viewingChat = false;
        }
      }
    }
  }

  /// Tegner chat listen
  void _drawChatList(int selectedIndex) {
    final width = console.windowWidth;

    console.writeLine(
      '=== Cursor Chat Historik Browser ==='.padRight(width),
      TextAlignment.center,
    );
    console.writeLine('');
    console.writeLine(
      'Tryk ↑/↓ for at navigere, Enter for at se chat, Q for at afslutte',
    );
    console.writeLine('');

    final titleWidth = 40;
    final requestIdWidth = 40;

    console.writeLine(
      'ID | ${_padTruncate('Titel', titleWidth)} | ${_padTruncate('Request ID', requestIdWidth)} | Antal',
    );
    console.writeLine(''.padRight(width, '-'));

    for (var i = 0; i < _chats.length; i++) {
      final chat = _chats[i];
      
      // Vis enten title eller ID baseret på format
      final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
          ? chat.id
          : chat.title;
      
      final requestIdDisplay = chat.requestId.isNotEmpty ? chat.requestId : 'N/A';
      
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
    console.writeLine('Fandt ${_chats.length} chat historikker');
  }

  /// Tegner chat visning
  void _drawChatView(Chat chat, int scrollOffset) {
    final width = console.windowWidth;
    final height = console.windowHeight - 5;

    console.writeLine(
      '=== ${chat.title} ==='.padRight(width),
      TextAlignment.center,
    );
    console.writeLine('');
    console.writeLine('Tryk ↑/↓ for at rulle, Q for at gå tilbage');
    console.writeLine(''.padRight(width, '-'));

    final visibleMessages = chat.messages.skip(scrollOffset).take(height);

    for (final message in visibleMessages) {
      final sender = message.isUser ? 'User' : 'AI';
      console.writeLine(
        '[$sender - ${DateFormat('HH:mm:ss').format(message.timestamp)}]',
      );

      // Del indholdet op i linjer der passer til skærmen
      final contentLines = _wrapText(message.content, width);
      for (final line in contentLines) {
        console.writeLine(line);
      }

      console.writeLine('');
    }

    console.writeLine(''.padRight(width, '-'));
    console.writeLine(
      'Besked ${scrollOffset + 1}-${(scrollOffset + visibleMessages.length).clamp(1, chat.messages.length)} af ${chat.messages.length}',
    );
  }

  /// Hjælpefunktion til at formattere tekst
  String _padTruncate(String text, int width) {
    if (text.length > width) {
      return text.substring(0, width - 3) + '...';
    }
    return text.padRight(width);
  }

  /// Hjælpefunktion til at wrappe tekst til en bestemt bredde
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
