import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';

import 'persisted_session_summary_entity.dart';

@immutable
class DesktopPreferencesEntity {
  const DesktopPreferencesEntity({
    this.host,
    this.model,
    this.inference = const InferenceOptions(),
    this.permissions = const AgentPermissions(),
    this.activeRoot,
    this.recentRoots = const [],
    this.sessions = const [],
  });

  final Uri? host;
  final String? model;
  final InferenceOptions inference;
  final AgentPermissions permissions;
  final String? activeRoot;
  final List<String> recentRoots;
  final List<PersistedSessionSummaryEntity> sessions;

  DesktopPreferencesEntity copyWith({
    Uri? host,
    String? model,
    InferenceOptions? inference,
    AgentPermissions? permissions,
    String? activeRoot,
    List<String>? recentRoots,
    List<PersistedSessionSummaryEntity>? sessions,
  }) {
    return DesktopPreferencesEntity(
      host: host ?? this.host,
      model: model ?? this.model,
      inference: inference ?? this.inference,
      permissions: permissions ?? this.permissions,
      activeRoot: activeRoot ?? this.activeRoot,
      recentRoots: recentRoots ?? this.recentRoots,
      sessions: sessions ?? this.sessions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopPreferencesEntity &&
          host == other.host &&
          model == other.model &&
          inference == other.inference &&
          permissions == other.permissions &&
          activeRoot == other.activeRoot &&
          listEquals(recentRoots, other.recentRoots) &&
          listEquals(sessions, other.sessions);

  @override
  int get hashCode => Object.hash(
    host,
    model,
    inference,
    permissions,
    activeRoot,
    Object.hashAll(recentRoots),
    Object.hashAll(sessions),
  );

  @override
  String toString() =>
      'DesktopPreferencesEntity(host: $host, model: $model, '
      'activeRoot: $activeRoot, recentRoots: $recentRoots, '
      'sessions: ${sessions.length})';
}
