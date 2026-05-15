import 'package:dart_frog/dart_frog.dart';
import 'package:xene_backend/src/database.dart';

const _customSlot = {
  'slug': 'custom',
  'name': 'CUSTOM',
  'description': 'Your private source set.',
  'notchIndex': 0,
  'themeColor': '#222222',
  'isDefault': false,
  'isCustom': true,
  'enabled': true,
};

Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  switch (request.method) {
    case HttpMethod.get:
      return _getDial(context);
    case HttpMethod.post:
      return _saveSelection(context);
    default:
      return Response(statusCode: 405);
  }
}

Future<Response> _getDial(RequestContext context) async {
  final userId = context.request.headers['x-user-id'] ?? 'local_user';
  final db = context.read<DatabaseService>();

  final templates = await db.getPresetTemplates();
  Map<String, dynamic>? defaultTemplate;
  for (final template in templates) {
    if (template['is_default'] == true) {
      defaultTemplate = template;
      break;
    }
  }
  defaultTemplate ??= templates.isNotEmpty ? templates.first : null;
  final defaultSlug = defaultTemplate?['slug'] as String? ?? 'custom';
  final selectedSlug = await db.getUserPresetSelection(userId) ?? defaultSlug;

  return Response.json(
    body: {
      'defaultPresetSlug': defaultSlug,
      'activePresetSlug': selectedSlug,
      'slots': [_customSlot, ...templates.map(_templateToSlot)],
    },
  );
}

Future<Response> _saveSelection(RequestContext context) async {
  final userId = context.request.headers['x-user-id'];
  if (userId == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'X-User-Id header required'},
    );
  }

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid JSON body'});
  }

  final slug = body['activePresetSlug'] as String?;
  if (slug == null || slug.trim().isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'activePresetSlug is required'},
    );
  }

  final saved = await context.read<DatabaseService>().saveUserPresetSelection(
    userId,
    slug.trim(),
  );
  if (!saved) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Failed to save preset selection'},
    );
  }

  return Response.json(body: {'activePresetSlug': slug.trim()});
}

Map<String, dynamic> _templateToSlot(Map<String, dynamic> row) {
  return {
    'slug': row['slug'],
    'name': row['name'],
    'description': row['description'],
    'notchIndex': row['notch_index'],
    'themeColor': row['theme_color'],
    'isDefault': row['is_default'] == true,
    'isCustom': false,
    'enabled': row['enabled'] == true,
    'version': row['version'],
  };
}
