import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// Konfigurationsklasse til at håndtere indstillinger
class Config {
  /// Stien til mappen hvor Cursor gemmer workspaceStorage
  final String workspaceStoragePath;

  Config({required this.workspaceStoragePath});

  /// Indlæs konfiguration fra en angivet sti
  static Config load(String configPath) {
    final expandedPath = configPath.replaceFirst(
      '~',
      Platform.environment['HOME'] ?? '',
    );

    // Standardplaceringer af Cursor AI workspace storage baseret på OS
    String defaultWorkspacePath;
    if (Platform.isWindows) {
      defaultWorkspacePath = path.join(Platform.environment['APPDATA'] ?? '',
          'Cursor', 'User', 'workspaceStorage');
    } else if (Platform.isMacOS) {
      defaultWorkspacePath = path.join(
          Platform.environment['HOME'] ?? '',
          'Library',
          'Application Support',
          'Cursor',
          'User',
          'workspaceStorage');
    } else {
      // Linux
      defaultWorkspacePath = path.join(Platform.environment['HOME'] ?? '',
          '.config', 'Cursor', 'User', 'workspaceStorage');
    }

    try {
      final configFile = File(expandedPath);
      if (configFile.existsSync()) {
        final jsonData = jsonDecode(configFile.readAsStringSync());
        return Config(
          workspaceStoragePath:
              jsonData['workspaceStoragePath'] ?? defaultWorkspacePath,
        );
      }
    } catch (e) {
      print('Advarsel: Kunne ikke læse konfiguration fra $configPath: $e');
      print('Bruger standardværdier i stedet.');
    }

    // Returner standardkonfiguration
    return Config(workspaceStoragePath: defaultWorkspacePath);
  }

  /// Gem konfigurationen til fil
  void save(String configPath) {
    final expandedPath = configPath.replaceFirst(
      '~',
      Platform.environment['HOME'] ?? '',
    );

    final configFile = File(expandedPath);
    final configDir = path.dirname(expandedPath);

    if (!Directory(configDir).existsSync()) {
      Directory(configDir).createSync(recursive: true);
    }

    final jsonData = {
      'workspaceStoragePath': workspaceStoragePath,
    };

    configFile.writeAsStringSync(jsonEncode(jsonData));
  }
}
