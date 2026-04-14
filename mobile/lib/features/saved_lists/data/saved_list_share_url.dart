/// Deep link payload for saved list QR codes (opens the app when installed).
String savedListShareDeepLink(String shareToken) => 'woleh://saved-lists/$shareToken';

/// Parses a QR / pasted string into a share token (accepts raw token or full `woleh://` URL).
String? parseSavedListShareToken(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final u = Uri.tryParse(s);
  if (u != null &&
      u.scheme == 'woleh' &&
      u.host == 'saved-lists') {
    final seg = u.pathSegments.where((e) => e.isNotEmpty).toList();
    if (seg.isNotEmpty) return seg.first;
    if (u.path.length > 1 && u.path.startsWith('/')) {
      return u.path.substring(1);
    }
  }
  return s;
}
