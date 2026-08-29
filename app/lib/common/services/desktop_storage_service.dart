import 'dart:convert';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/domain/entities/desktop_preferences_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';

/// Persistencia local em JSON versionado, no diretorio de dados do sistema
/// operacional. Leitura defensiva devolve defaults e gravacao atomica evita
/// arquivo parcialmente escrito.
class DesktopStorageService {
  DesktopStorageService({File? file}) : file = file ?? defaultFile();

  static const currentVersion = 1;
  static const maxRecentRoots = 8;
  static const maxSessions = 20;
  static const _stateFileName = 'salvador_state.json';

  final File file;

  static File defaultFile({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    final String base;
    if (Platform.isMacOS) {
      base = home == null
          ? 'Library/Application Support'
          : '$home/Library/Application Support';
    } else if (Platform.isWindows) {
      base = env['APPDATA'] ?? home ?? '.';
    } else {
      base =
          env['XDG_CONFIG_HOME'] ??
          (home == null ? '.config' : '$home/.config');
    }
    return File('$base/Salvador/$_stateFileName');
  }

  Future<DesktopPreferencesEntity> load() async {
    if (!await file.exists()) return const DesktopPreferencesEntity();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != currentVersion) {
        return const DesktopPreferencesEntity();
      }
      final json = decoded.cast<String, Object?>();
      return _fromJson(json);
    } on FormatException {
      return const DesktopPreferencesEntity();
    }
  }

  Future<void> save(DesktopPreferencesEntity state) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(_toJson(state)));
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (file.existsSync()) await file.delete();
      await temp.rename(file.path);
    }
  }

  DesktopPreferencesEntity _fromJson(Map<String, Object?> json) {
    final host = json['host'];
    final sessions = json['sessions'];
    return DesktopPreferencesEntity(
      host: host is String ? Uri.tryParse(host) : null,
      model: json['model'] as String?,
      inference: InferenceOptions(
        temperature: _double(json['temperature']) ?? 0.1,
        contextLength: _int(json['context_length']),
        keepAlive: _durationSeconds(json['keep_alive_seconds']),
        timeout: _durationSeconds(json['timeout_seconds']),
      ),
      permissions: AgentPermissions(
        allowEdit: json['allow_edit'] as bool? ?? true,
        allowCommands: json['allow_commands'] as bool? ?? true,
      ),
      contextFilesEnabled: json['context_files_enabled'] as bool? ?? true,
      activeRoot: json['active_root'] as String?,
      recentRoots: _stringList(json['recent_roots']),
      sessions: sessions is List
          ? sessions
                .whereType<Map>()
                .map(
                  (entry) => PersistedSessionSummaryEntity(
                    title: entry['title'] as String? ?? '',
                    startedAt:
                        _dateTime(entry['started_at']) ??
                        DateTime.fromMillisecondsSinceEpoch(0),
                    actionCount: _int(entry['action_count']) ?? 0,
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, Object?> _toJson(DesktopPreferencesEntity state) => {
    'version': currentVersion,
    if (state.host != null) 'host': state.host.toString(),
    if (state.model != null) 'model': state.model,
    'temperature': state.inference.temperature,
    if (state.inference.contextLength != null)
      'context_length': state.inference.contextLength,
    if (state.inference.keepAlive != null)
      'keep_alive_seconds': state.inference.keepAlive!.inSeconds,
    if (state.inference.timeout != null)
      'timeout_seconds': state.inference.timeout!.inSeconds,
    'allow_edit': state.permissions.allowEdit,
    'allow_commands': state.permissions.allowCommands,
    'context_files_enabled': state.contextFilesEnabled,
    if (state.activeRoot != null) 'active_root': state.activeRoot,
    'recent_roots': _normalizeRoots(state.recentRoots),
    'sessions': _normalizeSessions(state.sessions)
        .map(
          (session) => {
            'title': session.title,
            'started_at': session.startedAt.toIso8601String(),
            'action_count': session.actionCount,
          },
        )
        .toList(growable: false),
  };

  List<String> _normalizeRoots(List<String> roots) {
    final seen = <String>{};
    final unique = <String>[];
    for (final root in roots) {
      if (seen.add(root)) unique.add(root);
    }
    if (unique.length <= maxRecentRoots) return unique;
    return unique.sublist(0, maxRecentRoots);
  }

  List<PersistedSessionSummaryEntity> _normalizeSessions(
    List<PersistedSessionSummaryEntity> sessions,
  ) {
    final sorted = [...sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (sorted.length <= maxSessions) return sorted;
    return sorted.sublist(0, maxSessions);
  }

  List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  int? _int(Object? value) => value is num ? value.toInt() : null;

  double? _double(Object? value) => value is num ? value.toDouble() : null;

  Duration? _durationSeconds(Object? value) {
    final seconds = _int(value);
    return seconds == null ? null : Duration(seconds: seconds);
  }

  DateTime? _dateTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
