import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:xene_backend/src/services/analysis_service.dart';

final _logger = Logger('track.analysis');

Future<Response> onRequest(
  RequestContext context,
  String platform,
  String trackId,
) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  _logger.info('[analysis] GET platform=$platform trackId=$trackId');

  final analysis = context.read<AnalysisService>();
  final row = await analysis.getAnalysis(platform, trackId);

  if (row == null) {
    return Response.json(
      statusCode: HttpStatus.notFound,
      body: {
        'error': 'Analysis not found for platform=$platform trackId=$trackId',
      },
    );
  }

  return Response.json(body: row);
}
