import 'dart:io';

/// Reveals a file or opens a folder in macOS Finder, Windows Explorer, or Linux file manager.
Future<void> revealInDesktopExplorer(String targetPath) async {
  if (targetPath.trim().isEmpty) return;
  try {
    final isDir = await FileSystemEntity.isDirectory(targetPath);
    if (Platform.isMacOS) {
      await Process.run('open', isDir ? [targetPath] : ['-R', targetPath]);
    } else if (Platform.isWindows) {
      await Process.run(
        'explorer',
        isDir ? [targetPath] : ['/select,$targetPath'],
      );
    } else if (Platform.isLinux) {
      final folder = isDir ? targetPath : File(targetPath).parent.path;
      await Process.run('xdg-open', [folder]);
    }
  } catch (_) {}
}
