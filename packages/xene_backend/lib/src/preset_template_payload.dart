class PresetTemplatePayload {
  const PresetTemplatePayload._(this.data, this.error);

  factory PresetTemplatePayload.data(Map<String, dynamic> data) {
    return PresetTemplatePayload._(data, null);
  }

  factory PresetTemplatePayload.error(String error) {
    return PresetTemplatePayload._(<String, dynamic>{}, error);
  }

  final Map<String, dynamic> data;
  final String? error;
}

PresetTemplatePayload presetTemplateDataFromBody(
  Map<String, dynamic> body, {
  required bool requireRequiredFields,
}) {
  final name = _stringValue(body, 'name');
  final slug = _stringValue(body, 'slug') ?? _slugFromName(name);
  final themeColor =
      _stringValue(body, 'themeColor') ?? _stringValue(body, 'theme_color');
  final notchIndexValue = body['notchIndex'] ?? body['notch_index'];
  final notchIndex = notchIndexValue is int
      ? notchIndexValue
      : int.tryParse(notchIndexValue?.toString() ?? '');

  if (requireRequiredFields) {
    if (name == null || name.isEmpty) {
      return PresetTemplatePayload.error('name is required');
    }
    if (slug == null || slug.isEmpty) {
      return PresetTemplatePayload.error('slug is required');
    }
    if (notchIndex == null) {
      return PresetTemplatePayload.error('notchIndex is required');
    }
  }

  final data = <String, dynamic>{};
  if (name != null) data['name'] = name;
  if (slug != null) data['slug'] = slug;
  if (body.containsKey('description'))
    data['description'] = body['description'];
  if (notchIndex != null) data['notch_index'] = notchIndex;
  if (themeColor != null) data['theme_color'] = themeColor;
  if (body.containsKey('isDefault') || body.containsKey('is_default')) {
    data['is_default'] =
        body['isDefault'] == true || body['is_default'] == true;
  }
  if (body.containsKey('enabled')) data['enabled'] = body['enabled'] != false;
  if (requireRequiredFields) {
    data['theme_color'] = data['theme_color'] ?? '#222222';
    data['is_public'] = true;
  }

  final effectiveSlug = data['slug'] as String?;
  if (effectiveSlug != null &&
      !RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(effectiveSlug)) {
    return PresetTemplatePayload.error(
      'slug must use lowercase letters, numbers, and dashes',
    );
  }
  final effectiveColor = data['theme_color'] as String?;
  if (effectiveColor != null &&
      !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(effectiveColor)) {
    return PresetTemplatePayload.error(
      'themeColor must be a 6-digit hex color',
    );
  }
  if (notchIndex != null && (notchIndex < 0 || notchIndex > 11)) {
    return PresetTemplatePayload.error('notchIndex must be between 0 and 11');
  }
  if (!requireRequiredFields && data.isEmpty) {
    return PresetTemplatePayload.error('No updatable fields provided');
  }

  return PresetTemplatePayload.data(data);
}

String? _stringValue(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _slugFromName(String? name) {
  if (name == null || name.isEmpty) return null;
  final lower = name.toLowerCase();
  final dashed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return dashed.replaceAll(RegExp(r'^-+|-+$'), '');
}
