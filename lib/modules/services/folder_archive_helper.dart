import 'dart:io';

import 'package:flutter/foundation.dart';

/// Helper service for automatically archiving dropped folders into `.zip` files
/// before staging them as chat attachments.
class FolderArchiveHelper {
  FolderArchiveHelper._();

  /// Returns true if [filePath] exists on disk and is a directory.
  static bool isDirectory(String filePath) {
    if (filePath.trim().isEmpty) return false;
    try {
      return FileSystemEntity.isDirectorySync(filePath);
    } catch (_) {
      return false;
    }
  }

  /// Compresses [directoryPath] into a `.zip` archive inside [outputDir] (or a
  /// freshly created system temp folder) and returns the resulting `.zip` path.
  ///
  /// Returns `null` if [directoryPath] does not exist or archiving fails.
  static Future<String?> zipDirectory(
    String directoryPath, {
    Directory? outputDir,
  }) async {
    final sourceDir = Directory(directoryPath);
    if (!await sourceDir.exists()) {
      return null;
    }

    final normalizedPath = sourceDir.absolute.path.replaceAll(
      RegExp(r'[\\/]+$'),
      '',
    );
    final lastSep = normalizedPath.lastIndexOf(RegExp(r'[\\/]'));
    final parentPath = lastSep > 0
        ? normalizedPath.substring(0, lastSep)
        : sourceDir.parent.path;
    final rawFolderName = lastSep >= 0
        ? normalizedPath.substring(lastSep + 1)
        : 'folder';
    final safeFolderName = rawFolderName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim();
    final archiveBaseName = safeFolderName.isEmpty ? 'folder' : safeFolderName;

    final targetDir =
        outputDir ??
        await Directory.systemTemp.createTemp('ja_lan_folder_zip_');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final zipFilePath =
        '${targetDir.path}${Platform.pathSeparator}$archiveBaseName.zip';
    final zipFile = File(zipFilePath);
    if (await zipFile.exists()) {
      try {
        await zipFile.delete();
      } catch (_) {}
    }

    try {
      if (Platform.isWindows) {
        // Fast path: built-in Windows 10/11 bsdtar (tar.exe -a -c -f)
        final tarResult = await Process.run('tar.exe', [
          '-a',
          '-c',
          '-f',
          zipFilePath,
          '-C',
          parentPath,
          rawFolderName,
        ], runInShell: false);

        if (tarResult.exitCode == 0 && await zipFile.exists()) {
          debugPrint(
            '[FolderArchiveHelper] Archived folder "$rawFolderName" via tar.exe -> $zipFilePath',
          );
          return zipFilePath;
        }

        // Fallback: PowerShell Compress-Archive
        final escapedSource = normalizedPath.replaceAll("'", "''");
        final escapedDest = zipFilePath.replaceAll("'", "''");
        final psResult = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "Compress-Archive -LiteralPath '$escapedSource' -DestinationPath '$escapedDest' -Force",
        ], runInShell: false);

        if (psResult.exitCode == 0 && await zipFile.exists()) {
          debugPrint(
            '[FolderArchiveHelper] Archived folder "$rawFolderName" via PowerShell -> $zipFilePath',
          );
          return zipFilePath;
        }

        debugPrint(
          '[FolderArchiveHelper] Failed to archive folder "$directoryPath": tar(${tarResult.stderr}) / ps(${psResult.stderr})',
        );
        return null;
      } else {
        final zipResult = await Process.run('zip', [
          '-r',
          '-q',
          zipFilePath,
          rawFolderName,
        ], workingDirectory: parentPath);
        if (zipResult.exitCode == 0 && await zipFile.exists()) {
          return zipFilePath;
        }
        return null;
      }
    } catch (e, st) {
      debugPrint(
        '[FolderArchiveHelper] Error zipping directory "$directoryPath": $e\n$st',
      );
      return null;
    }
  }
}
