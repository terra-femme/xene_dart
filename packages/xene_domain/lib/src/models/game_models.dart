// Game feature models — plain immutable Dart classes (no Freezed/code-gen).
// These are only used in the game feature and don't require cross-package
// JSON serialization with Freezed's reflection approach.

class PartyPreview {
  const PartyPreview({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.memberCount,
    required this.myTrackCountThisWeek,
    required this.myScenarioSubmitted,
    required this.weekStart,
  });

  final String id;
  final String name;
  final String inviteCode;
  final int memberCount;
  final int myTrackCountThisWeek;

  /// True when the user has submitted their scene track for this week.
  final bool myScenarioSubmitted;
  final String weekStart;

  int get myDiscoveryCount =>
      (myTrackCountThisWeek - (myScenarioSubmitted ? 1 : 0)).clamp(0, 4);

  factory PartyPreview.fromJson(Map<String, dynamic> j) => PartyPreview(
    id: j['id'] as String,
    name: j['name'] as String,
    inviteCode: j['invite_code'] as String,
    memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
    myTrackCountThisWeek: (j['my_track_count_this_week'] as num?)?.toInt() ?? 0,
    myScenarioSubmitted: j['my_scenario_submitted'] as bool? ?? false,
    weekStart: j['week_start'] as String? ?? '',
  );
}

class PartyMember {
  const PartyMember({
    required this.userId,
    required this.username,
    required this.isMe,
    this.joinedAt,
  });

  final String userId;
  final String username;
  final bool isMe;
  final String? joinedAt;

  factory PartyMember.fromJson(Map<String, dynamic> j) => PartyMember(
    userId: j['user_id'] as String,
    username: j['username'] as String? ?? 'Unknown',
    isMe: j['is_me'] as bool? ?? false,
    joinedAt: j['joined_at'] as String?,
  );
}

class PartyDetail {
  const PartyDetail({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.members,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String inviteCode;
  final List<PartyMember> members;
  final String createdBy;

  factory PartyDetail.fromJson(Map<String, dynamic> j) => PartyDetail(
    id: j['id'] as String,
    name: j['name'] as String,
    inviteCode: j['invite_code'] as String,
    createdBy: j['created_by'] as String,
    members: (j['members'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(PartyMember.fromJson)
        .toList(),
  );
}

class PartyTrack {
  const PartyTrack({
    required this.id,
    required this.userId,
    required this.scTrackId,
    required this.scTrackUrl,
    required this.scTitle,
    this.scArtworkUrl,
    this.scDurationSeconds,
    required this.weekStart,
    required this.submittedAt,
    this.trackType = 'discovery',
  });

  final String id;
  final String userId;
  final String scTrackId;
  final String scTrackUrl;
  final String scTitle;
  final String? scArtworkUrl;
  final int? scDurationSeconds;
  final String weekStart;
  final String submittedAt;

  /// 'scenario' = the week's competitive track (voted on).
  /// 'discovery' = social share, no vote.
  final String trackType;

  bool get isScenario => trackType == 'scenario';
  bool get isDiscovery => trackType == 'discovery';

  factory PartyTrack.fromJson(Map<String, dynamic> j) => PartyTrack(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    scTrackId: j['sc_track_id'] as String,
    scTrackUrl: j['sc_track_url'] as String,
    scTitle: j['sc_title'] as String,
    scArtworkUrl: j['sc_artwork_url'] as String?,
    scDurationSeconds: (j['sc_duration_seconds'] as num?)?.toInt(),
    weekStart: j['week_start'] as String,
    submittedAt: j['submitted_at'] as String,
    trackType: j['track_type'] as String? ?? 'discovery',
  );
}

class MemberTracks {
  const MemberTracks({required this.member, required this.tracks});

  final PartyMember member;
  final List<PartyTrack> tracks;

  factory MemberTracks.fromJson(Map<String, dynamic> j) => MemberTracks(
    member: PartyMember.fromJson(j['member'] as Map<String, dynamic>),
    tracks: (j['tracks'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(PartyTrack.fromJson)
        .toList(),
  );
}

class WeekVotes {
  const WeekVotes({
    required this.weekStart,
    required this.isWeekClosed,
    required this.isResultsVisible,
    this.myVote,
    required this.hasVoted,
    this.tally,
  });

  final String weekStart;
  final bool isWeekClosed;
  final bool isResultsVisible;

  /// The userId this user voted for, or null if not yet voted.
  final String? myVote;

  /// Maps userId → whether they have cast a vote (hidden until results visible).
  final Map<String, bool> hasVoted;

  /// Non-null only after results become visible (Friday 21:05 UTC).
  final Map<String, int>? tally;

  int get totalVoters => hasVoted.values.where((v) => v).length;

  factory WeekVotes.fromJson(Map<String, dynamic> j) {
    final hasVotedRaw = j['has_voted'] as Map<String, dynamic>? ?? {};
    final tallyRaw = j['tally'] as Map<String, dynamic>?;
    return WeekVotes(
      weekStart: j['week_start'] as String? ?? '',
      isWeekClosed: j['is_week_closed'] as bool? ?? false,
      isResultsVisible: j['is_results_visible'] as bool? ?? false,
      myVote: j['my_vote'] as String?,
      hasVoted: {for (final e in hasVotedRaw.entries) e.key: e.value == true},
      tally: tallyRaw == null
          ? null
          : {for (final e in tallyRaw.entries) e.key: (e.value as num).toInt()},
    );
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.member,
    required this.totalVotes,
    required this.weekWins,
  });

  final PartyMember member;
  final int totalVotes;
  final int weekWins;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
    member: PartyMember.fromJson(j),
    totalVotes: (j['total_votes'] as num?)?.toInt() ?? 0,
    weekWins: (j['week_wins'] as num?)?.toInt() ?? 0,
  );
}

class WeekWinner {
  const WeekWinner({
    required this.weekStart,
    required this.winnerUserId,
    required this.winnerUsername,
  });

  final String weekStart;
  final String winnerUserId;
  final String winnerUsername;

  factory WeekWinner.fromJson(Map<String, dynamic> j) => WeekWinner(
    weekStart: j['week_start'] as String,
    winnerUserId: j['winner_user_id'] as String,
    winnerUsername: j['winner_username'] as String,
  );
}

class ScTrackResult {
  const ScTrackResult({
    required this.id,
    required this.title,
    required this.username,
    required this.permalinkUrl,
    this.artworkUrl,
    this.durationSeconds,
  });

  final String id;
  final String title;
  final String username;
  final String permalinkUrl;
  final String? artworkUrl;
  final int? durationSeconds;

  factory ScTrackResult.fromJson(Map<String, dynamic> j) => ScTrackResult(
    id: j['id'] as String,
    title: j['title'] as String,
    username: j['username'] as String? ?? 'Unknown',
    permalinkUrl: j['permalink_url'] as String,
    artworkUrl: j['artwork_url'] as String?,
    durationSeconds: (j['duration_seconds'] as num?)?.toInt(),
  );

  String get durationLabel {
    if (durationSeconds == null) return '';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
