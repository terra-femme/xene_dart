/// Converts a snake_case key to camelCase.
/// Example: 'soundcloud_url' → 'soundcloudUrl'
String snakeToCamel(String key) {
  final parts = key.split('_');
  if (parts.length == 1) return key;
  return parts.first +
      parts
          .skip(1)
          .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
          .join('');
}

/// Converts all keys in a Supabase snake_case row to camelCase.
Map<String, dynamic> toApiRow(Map<String, dynamic> row) {
  return {for (final e in row.entries) snakeToCamel(e.key): e.value};
}
