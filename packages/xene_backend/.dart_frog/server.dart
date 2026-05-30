// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';


import '../routes/monitor.dart' as monitor;
import '../routes/user/saved/index.dart' as user_saved_index;
import '../routes/user/saved/export_sc.dart' as user_saved_export_sc;
import '../routes/user/saved/[id].dart' as user_saved_$id;
import '../routes/user/queue/sc_playlist.dart' as user_queue_sc_playlist;
import '../routes/user/queue/index.dart' as user_queue_index;
import '../routes/user/queue/[id].dart' as user_queue_$id;
import '../routes/user/history/index.dart' as user_history_index;
import '../routes/twitch/live.dart' as twitch_live;
import '../routes/soundcloud/track_search.dart' as soundcloud_track_search;
import '../routes/soundcloud/stream/[id].dart' as soundcloud_stream_$id;
import '../routes/publications/matches.dart' as publications_matches;
import '../routes/proxy/image.dart' as proxy_image;
import '../routes/press_scout/run.dart' as press_scout_run;
import '../routes/presets/magazine_cover.dart' as presets_magazine_cover;
import '../routes/presets/index.dart' as presets_index;
import '../routes/presets/custom_sources.dart' as presets_custom_sources;
import '../routes/presets/articles.dart' as presets_articles;
import '../routes/presets/templates/index.dart' as presets_templates_index;
import '../routes/presets/templates/[slug]/refresh_all.dart' as presets_templates_$slug_refresh_all;
import '../routes/presets/templates/[slug]/index.dart' as presets_templates_$slug_index;
import '../routes/presets/templates/[slug]/sources/youtube.dart' as presets_templates_$slug_sources_youtube;
import '../routes/presets/templates/[slug]/sources/index.dart' as presets_templates_$slug_sources_index;
import '../routes/presets/templates/[slug]/sources/[sourceId]/refresh_feed.dart' as presets_templates_$slug_sources_$source_id_refresh_feed;
import '../routes/presets/templates/[slug]/sources/[sourceId]/move.dart' as presets_templates_$slug_sources_$source_id_move;
import '../routes/presets/templates/[slug]/sources/[sourceId]/index.dart' as presets_templates_$slug_sources_$source_id_index;
import '../routes/presets/templates/[slug]/sources/[sourceId]/articles.dart' as presets_templates_$slug_sources_$source_id_articles;
import '../routes/game/profile/username.dart' as game_profile_username;
import '../routes/game/parties/index.dart' as game_parties_index;
import '../routes/game/parties/[partyId]/scores.dart' as game_parties_$party_id_scores;
import '../routes/game/parties/[partyId]/leave.dart' as game_parties_$party_id_leave;
import '../routes/game/parties/[partyId]/index.dart' as game_parties_$party_id_index;
import '../routes/game/parties/[partyId]/export_sc.dart' as game_parties_$party_id_export_sc;
import '../routes/game/parties/[partyId]/votes/index.dart' as game_parties_$party_id_votes_index;
import '../routes/game/parties/[partyId]/tracks/index.dart' as game_parties_$party_id_tracks_index;
import '../routes/game/parties/[partyId]/tracks/[trackId].dart' as game_parties_$party_id_tracks_$track_id;
import '../routes/game/join/[inviteCode].dart' as game_join_$invite_code;
import '../routes/feed/merged.dart' as feed_merged;
import '../routes/discovery/status.dart' as discovery_status;
import '../routes/discovery/sc_search.dart' as discovery_sc_search;
import '../routes/discovery/save_discovery.dart' as discovery_save_discovery;
import '../routes/discovery/graph.dart' as discovery_graph;
import '../routes/discovery/auto_discover.dart' as discovery_auto_discover;
import '../routes/connections/status.dart' as connections_status;
import '../routes/connections/soundcloud/following.dart' as connections_soundcloud_following;
import '../routes/connections/soundcloud/disconnect.dart' as connections_soundcloud_disconnect;
import '../routes/auth/soundcloud/nonce.dart' as auth_soundcloud_nonce;
import '../routes/auth/soundcloud/index.dart' as auth_soundcloud_index;
import '../routes/auth/soundcloud/done.dart' as auth_soundcloud_done;
import '../routes/auth/soundcloud/callback.dart' as auth_soundcloud_callback;
import '../routes/artists/index.dart' as artists_index;
import '../routes/artists/articles.dart' as artists_articles;
import '../routes/artists/[id]/index.dart' as artists_$id_index;
import '../routes/artists/[id]/articles.dart' as artists_$id_articles;
import '../routes/admin/poll.dart' as admin_poll;

import '../routes/_middleware.dart' as middleware;

void main() async {
  final address = InternetAddress.tryParse('') ?? InternetAddress.anyIPv6;
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  hotReload(() => createServer(address, port));
}

Future<HttpServer> createServer(InternetAddress address, int port) {
  final handler = Cascade().add(buildRootHandler()).handler;
  return serve(handler, address, port);
}

Handler buildRootHandler() {
  final pipeline = const Pipeline().addMiddleware(middleware.middleware);
  final router = Router()
    ..mount('/', (context) => buildHandler()(context))
    ..mount('/user/saved', (context) => buildUserSavedHandler()(context))
    ..mount('/user/queue', (context) => buildUserQueueHandler()(context))
    ..mount('/user/history', (context) => buildUserHistoryHandler()(context))
    ..mount('/twitch', (context) => buildTwitchHandler()(context))
    ..mount('/soundcloud', (context) => buildSoundcloudHandler()(context))
    ..mount('/soundcloud/stream', (context) => buildSoundcloudStreamHandler()(context))
    ..mount('/publications', (context) => buildPublicationsHandler()(context))
    ..mount('/proxy', (context) => buildProxyHandler()(context))
    ..mount('/press_scout', (context) => buildPressScoutHandler()(context))
    ..mount('/presets', (context) => buildPresetsHandler()(context))
    ..mount('/presets/templates', (context) => buildPresetsTemplatesHandler()(context))
    ..mount('/presets/templates/<slug>', (context,slug,) => buildPresetsTemplates$slugHandler(slug,)(context))
    ..mount('/presets/templates/<slug>/sources', (context,slug,) => buildPresetsTemplates$slugSourcesHandler(slug,)(context))
    ..mount('/presets/templates/<slug>/sources/<sourceId>', (context,slug,sourceId,) => buildPresetsTemplates$slugSources$sourceIdHandler(slug,sourceId,)(context))
    ..mount('/game/profile', (context) => buildGameProfileHandler()(context))
    ..mount('/game/parties', (context) => buildGamePartiesHandler()(context))
    ..mount('/game/parties/<partyId>', (context,partyId,) => buildGameParties$partyIdHandler(partyId,)(context))
    ..mount('/game/parties/<partyId>/votes', (context,partyId,) => buildGameParties$partyIdVotesHandler(partyId,)(context))
    ..mount('/game/parties/<partyId>/tracks', (context,partyId,) => buildGameParties$partyIdTracksHandler(partyId,)(context))
    ..mount('/game/join', (context) => buildGameJoinHandler()(context))
    ..mount('/feed', (context) => buildFeedHandler()(context))
    ..mount('/discovery', (context) => buildDiscoveryHandler()(context))
    ..mount('/connections', (context) => buildConnectionsHandler()(context))
    ..mount('/connections/soundcloud', (context) => buildConnectionsSoundcloudHandler()(context))
    ..mount('/auth/soundcloud', (context) => buildAuthSoundcloudHandler()(context))
    ..mount('/artists', (context) => buildArtistsHandler()(context))
    ..mount('/artists/<id>', (context,id,) => buildArtists$idHandler(id,)(context))
    ..mount('/admin', (context) => buildAdminHandler()(context));
  return pipeline.addHandler(router);
}

Handler buildHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/monitor', (context) => monitor.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildUserSavedHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/export_sc', (context) => user_saved_export_sc.onRequest(context,))..all('/<id>', (context,id,) => user_saved_$id.onRequest(context,id,))..all('/', (context) => user_saved_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildUserQueueHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/sc_playlist', (context) => user_queue_sc_playlist.onRequest(context,))..all('/<id>', (context,id,) => user_queue_$id.onRequest(context,id,))..all('/', (context) => user_queue_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildUserHistoryHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => user_history_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildTwitchHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/live', (context) => twitch_live.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildSoundcloudHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/track_search', (context) => soundcloud_track_search.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildSoundcloudStreamHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/<id>', (context,id,) => soundcloud_stream_$id.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildPublicationsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/matches', (context) => publications_matches.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildProxyHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/image', (context) => proxy_image.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildPressScoutHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/run', (context) => press_scout_run.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildPresetsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/articles', (context) => presets_articles.onRequest(context,))..all('/custom_sources', (context) => presets_custom_sources.onRequest(context,))..all('/magazine_cover', (context) => presets_magazine_cover.onRequest(context,))..all('/', (context) => presets_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildPresetsTemplatesHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => presets_templates_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildPresetsTemplates$slugHandler(String slug,) {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/refresh_all', (context) => presets_templates_$slug_refresh_all.onRequest(context,slug,))..all('/', (context) => presets_templates_$slug_index.onRequest(context,slug,));
  return pipeline.addHandler(router);
}

Handler buildPresetsTemplates$slugSourcesHandler(String slug,) {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/youtube', (context) => presets_templates_$slug_sources_youtube.onRequest(context,slug,))..all('/', (context) => presets_templates_$slug_sources_index.onRequest(context,slug,));
  return pipeline.addHandler(router);
}

Handler buildPresetsTemplates$slugSources$sourceIdHandler(String slug,String sourceId,) {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/articles', (context) => presets_templates_$slug_sources_$source_id_articles.onRequest(context,slug,sourceId,))..all('/move', (context) => presets_templates_$slug_sources_$source_id_move.onRequest(context,slug,sourceId,))..all('/refresh_feed', (context) => presets_templates_$slug_sources_$source_id_refresh_feed.onRequest(context,slug,sourceId,))..all('/', (context) => presets_templates_$slug_sources_$source_id_index.onRequest(context,slug,sourceId,));
  return pipeline.addHandler(router);
}

Handler buildGameProfileHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/username', (context) => game_profile_username.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildGamePartiesHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => game_parties_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildGameParties$partyIdHandler(String partyId,) {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/export_sc', (context) => game_parties_$party_id_export_sc.onRequest(context,partyId,))..all('/leave', (context) => game_parties_$party_id_leave.onRequest(context,partyId,))..all('/scores', (context) => game_parties_$party_id_scores.onRequest(context,partyId,))..all('/', (context) => game_parties_$party_id_index.onRequest(context,partyId,));
  return pipeline.addHandler(router);
}

Handler buildGameParties$partyIdVotesHandler(String partyId,) {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => game_parties_$party_id_votes_index.onRequest(context,partyId,));
  return pipeline.addHandler(router);
}

Handler buildGameParties$partyIdTracksHandler(String partyId,) {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/<trackId>', (context,trackId,) => game_parties_$party_id_tracks_$track_id.onRequest(context,partyId,trackId,))..all('/', (context) => game_parties_$party_id_tracks_index.onRequest(context,partyId,));
  return pipeline.addHandler(router);
}

Handler buildGameJoinHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/<inviteCode>', (context,inviteCode,) => game_join_$invite_code.onRequest(context,inviteCode,));
  return pipeline.addHandler(router);
}

Handler buildFeedHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/merged', (context) => feed_merged.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildDiscoveryHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/auto_discover', (context) => discovery_auto_discover.onRequest(context,))..all('/graph', (context) => discovery_graph.onRequest(context,))..all('/save_discovery', (context) => discovery_save_discovery.onRequest(context,))..all('/sc_search', (context) => discovery_sc_search.onRequest(context,))..all('/status', (context) => discovery_status.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildConnectionsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/status', (context) => connections_status.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildConnectionsSoundcloudHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/disconnect', (context) => connections_soundcloud_disconnect.onRequest(context,))..all('/following', (context) => connections_soundcloud_following.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAuthSoundcloudHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/callback', (context) => auth_soundcloud_callback.onRequest(context,))..all('/done', (context) => auth_soundcloud_done.onRequest(context,))..all('/nonce', (context) => auth_soundcloud_nonce.onRequest(context,))..all('/', (context) => auth_soundcloud_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildArtistsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/articles', (context) => artists_articles.onRequest(context,))..all('/', (context) => artists_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildArtists$idHandler(String id,) {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/articles', (context) => artists_$id_articles.onRequest(context,id,))..all('/', (context) => artists_$id_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildAdminHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/poll', (context) => admin_poll.onRequest(context,));
  return pipeline.addHandler(router);
}

