import 'dart:convert';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';

/// Estado persistido do desktop, sem conteudo de conversas.
class DesktopPersistedState {
  const DesktopPersistedState({
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
  final List<PersistedSessionSummary> sessions;
}

class PersistedSessionSummary {
  const PersistedSessionSummary({
    required this.title,
    required this.startedAt,
    required this.actionCount,
  });

  final String title;
  final DateTime startedAt;
  final int actionCount;
}

/// Persistencia local em JSON versionado, no diretorio de dados do sistema
/// operacional. Leitura defensiva devolve defaults e gravacao atomica evita
/// arquivo parcialmente escrito.
class DesktopStateStore {
  DesktopStateStore({File? file}) : file = file ?? defaultFile();

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

  Future<DesktopPersistedState> load() async {
    if (!await file.exists()) return const DesktopPersistedState();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != currentVersion) {
        return const DesktopPersistedState();
      }
      final json = decoded.cast<String, Object?>();
      return _fromJson(json);
    } on FormatException {
      return const DesktopPersistedState();
    }
  }

  Future<void> save(DesktopPersistedState state) async {
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

  DesktopPersistedState _fromJson(Map<String, Object?> json) {
    final host = json['host'];
    final sessions = json['sessions'];
    return DesktopPersistedState(
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
      activeRoot: json['active_root'] as String?,
      recentRoots: _stringList(json['recent_roots']),
      sessions: sessions is List
          ? sessions
                .whereType<Map>()
                .map(
                  (entry) => PersistedSessionSummary(
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

  Map<String, Object?> _toJson(DesktopPersistedState state) => {
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

  List<PersistedSessionSummary> _normalizeSessions(
    List<PersistedSessionSummary> sessions,
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
