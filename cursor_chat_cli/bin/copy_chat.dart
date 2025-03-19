#!/usr/bin/env dart

import 'dart:io';
import 'package:path/path.dart' as path;

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    print('Brug: dart copy_chat.dart <request_id>');
    exit(1);
  }

  final requestId = arguments[0];
  final outputDir = '/Users/larsmathiasen/Repo/CursorTool/output'; // Absolut sti til output-mappen
  final currentDir = Directory.current.path;
  
  // Find filen med matchende request ID i output-mappen
  final outputDirectory = Directory(outputDir);
  
  if (!outputDirectory.existsSync()) {
    print('Output-mappen findes ikke: $outputDir');
    exit(1);
  }
  
  final files = outputDirectory.listSync().where((file) {
    if (file is File) {
      final fileName = path.basename(file.path);
      return fileName.contains(requestId);
    }
    return false;
  }).toList();
  
  if (files.isEmpty) {
    print('Ingen filer fundet med request ID: $requestId i $outputDir');
    exit(1);
  }
  
  final sourceFile = files.first as File;
  final targetFileName = '$requestId.json';
  final targetFile = File(path.join(currentDir, targetFileName));
  
  try {
    // Kopier filen
    sourceFile.copySync(targetFile.path);
    print('Kopieret ${path.basename(sourceFile.path)} til $targetFileName');
  } catch (e) {
    print('Fejl ved kopiering af fil: $e');
    exit(1);
  }
} 