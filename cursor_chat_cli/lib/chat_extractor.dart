import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'config.dart';
import 'chat_model.dart';
import 'chat_browser.dart';

/// Klasse til at udtrække chats fra historik
class ChatExtractor {
  final Config config;
  final ChatBrowser browser;

  ChatExtractor(this.config) : browser = ChatBrowser(config);

  /// Udtræk en specifik chat eller alle chats
  Future<void> extract(String chatId, String outputPath, String format) async {
    List<Chat> chats = [];

    if (chatId.toLowerCase() == 'alle') {
      // Hent alle chats ved at kalde den offentlige metode
      chats = await browser.loadAllChats();
    } else {
      // Hent specifik chat med den offentlige metode
      final chat = await browser.getChat(chatId);
      if (chat != null) {
        chats = [chat];
      }
    }

    if (chats.isEmpty) {
      print('Ingen chats fundet til udtrækning.');
      return;
    }

    final outputDir = Directory(outputPath);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    for (final chat in chats) {
      final filename = '${_sanitizeFilename(chat.title)}_${chat.id}';
      final outputFile = _getOutputFile(outputPath, filename, format);
      final content = _formatChat(chat, format);

      await outputFile.writeAsString(content);
      print('Chat udtrukket til: ${outputFile.path}');
    }

    print(
        'Udtrækning fuldført! ${chats.length} chat(s) udtrukket til $outputPath');
  }

  /// Formatterer chat til det ønskede output format
  String _formatChat(Chat chat, String format) {
    switch (format.toLowerCase()) {
      case 'json':
        return JsonEncoder.withIndent('  ').convert(chat.toJson());

      case 'markdown':
      case 'md':
        return _formatChatAsMarkdown(chat);

      case 'html':
        return _formatChatAsHTML(chat);

      case 'text':
      default:
        return _formatChatAsText(chat);
    }
  }

  /// Formatterer chat som simpel tekst
  String _formatChatAsText(Chat chat) {
    final buffer = StringBuffer();

    buffer.writeln('=== ${chat.title} ===');
    buffer.writeln('Chat ID: ${chat.id}');
    buffer.writeln('Antal beskeder: ${chat.messages.length}');
    buffer.writeln('Sidst ændret: ${chat.lastMessageTime}');
    buffer.writeln('');

    for (final message in chat.messages) {
      final sender = message.isUser ? 'USER' : 'AI';
      buffer.writeln('[$sender - ${message.timestamp}]');
      buffer.writeln(message.content);
      buffer.writeln('');
    }

    return buffer.toString();
  }

  /// Formatterer chat som Markdown
  String _formatChatAsMarkdown(Chat chat) {
    final buffer = StringBuffer();

    buffer.writeln('# ${chat.title}');
    buffer.writeln('');
    buffer.writeln('**Chat ID:** ${chat.id}');
    buffer.writeln('**Antal beskeder:** ${chat.messages.length}');
    buffer.writeln('**Sidst ændret:** ${chat.lastMessageTime}');
    buffer.writeln('');

    for (final message in chat.messages) {
      final sender = message.isUser ? 'USER' : 'AI';
      buffer.writeln('### $sender - ${message.timestamp}');
      buffer.writeln('');
      buffer.writeln(message.content);
      buffer.writeln('');
      buffer.writeln('---');
      buffer.writeln('');
    }

    return buffer.toString();
  }

  /// Formatterer chat som HTML
  String _formatChatAsHTML(Chat chat) {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html>');
    buffer.writeln('<head>');
    buffer.writeln('  <meta charset="UTF-8">');
    buffer.writeln('  <title>${_escapeHtml(chat.title)}</title>');
    buffer.writeln('  <style>');
    buffer.writeln(
        '    body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }');
    buffer.writeln(
        '    .header { border-bottom: 1px solid #ddd; padding-bottom: 10px; margin-bottom: 20px; }');
    buffer.writeln(
        '    .message { margin-bottom: 20px; padding: 10px; border-radius: 5px; }');
    buffer
        .writeln('    .user { background-color: #f0f0f0; text-align: right; }');
    buffer.writeln('    .ai { background-color: #e6f7ff; }');
    buffer.writeln(
        '    .meta { color: #666; font-size: 0.8em; margin-bottom: 5px; }');
    buffer.writeln('    .content { white-space: pre-wrap; }');
    buffer.writeln('  </style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    buffer.writeln('  <div class="header">');
    buffer.writeln('    <h1>${_escapeHtml(chat.title)}</h1>');
    buffer.writeln('    <p>Chat ID: ${chat.id}</p>');
    buffer.writeln('    <p>Antal beskeder: ${chat.messages.length}</p>');
    buffer.writeln('    <p>Sidst ændret: ${chat.lastMessageTime}</p>');
    buffer.writeln('  </div>');

    for (final message in chat.messages) {
      final sender = message.isUser ? 'USER' : 'AI';
      final cssClass = message.isUser ? 'user' : 'ai';

      buffer.writeln('  <div class="message $cssClass">');
      buffer.writeln(
          '    <div class="meta">$sender - ${message.timestamp}</div>');
      buffer.writeln(
          '    <div class="content">${_escapeHtml(message.content)}</div>');
      buffer.writeln('  </div>');
    }

    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// Hjælpefunktion til at få output fil baseret på format
  File _getOutputFile(String outputPath, String filename, String format) {
    final extension = _getExtensionForFormat(format);
    return File(path.join(outputPath, '$filename.$extension'));
  }

  /// Hjælpefunktion til at få filendelse baseret på format
  String _getExtensionForFormat(String format) {
    switch (format.toLowerCase()) {
      case 'json':
        return 'json';
      case 'markdown':
      case 'md':
        return 'md';
      case 'html':
        return 'html';
      case 'text':
      default:
        return 'txt';
    }
  }

  /// Hjælpefunktion til at sanitize filnavne
  String _sanitizeFilename(String filename) {
    return filename
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  /// Hjælpefunktion til at escape HTML tegn
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
