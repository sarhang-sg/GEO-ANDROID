abstract final class DownloadName {
  static String sanitize(String? proposed, {String fallback = 'nav-kurd-file'}) {
    final raw = (proposed ?? '').trim();
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\.+|\.+$'), '')
        .trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.length <= 120) return cleaned;

    final dot = cleaned.lastIndexOf('.');
    final extension = dot > 0 && cleaned.length - dot <= 12
        ? cleaned.substring(dot)
        : '';
    final stemLimit = 120 - extension.length;
    return '${cleaned.substring(0, stemLimit)}$extension';
  }
}
