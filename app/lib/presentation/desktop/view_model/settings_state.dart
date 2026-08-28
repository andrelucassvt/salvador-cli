import 'package:flutter/foundation.dart';
import 'package:salvador_desktop/domain/entities/host_test_result_entity.dart';

enum SettingsErrorKind { invalidHost, saveFailed }

/// Estado unico do formulario: edicao local que so afeta `WorkspaceCubit`
/// quando `save()` e confirmado - mesmo padrao de `WorkspaceState`/`ChatState`.
@immutable
sealed class SettingsState {
  const SettingsState();

  @override
  String toString();
}

class SettingsEditing extends SettingsState {
  const SettingsEditing({
    required this.hostText,
    required this.temperature,
    required this.contextText,
    this.keepAlive,
    this.timeout,
    required this.allowEdit,
    required this.allowCommands,
    this.testing = false,
    this.testResult,
    this.saving = false,
    this.saved = false,
    this.errorKind,
    this.error,
  });

  final String hostText;
  final double temperature;
  final String contextText;
  final Duration? keepAlive;
  final Duration? timeout;
  final bool allowEdit;
  final bool allowCommands;
  final bool testing;
  final HostTestResultEntity? testResult;
  final bool saving;
  final bool saved;
  final SettingsErrorKind? errorKind;
  final Object? error;

  SettingsEditing copyWith({
    String? hostText,
    double? temperature,
    String? contextText,
    Duration? keepAlive,
    bool clearKeepAlive = false,
    Duration? timeout,
    bool clearTimeout = false,
    bool? allowEdit,
    bool? allowCommands,
    bool? testing,
    HostTestResultEntity? testResult,
    bool clearTestResult = false,
    bool? saving,
    bool? saved,
    SettingsErrorKind? errorKind,
    bool clearError = false,
    Object? error,
  }) {
    return SettingsEditing(
      hostText: hostText ?? this.hostText,
      temperature: temperature ?? this.temperature,
      contextText: contextText ?? this.contextText,
      keepAlive: clearKeepAlive ? null : (keepAlive ?? this.keepAlive),
      timeout: clearTimeout ? null : (timeout ?? this.timeout),
      allowEdit: allowEdit ?? this.allowEdit,
      allowCommands: allowCommands ?? this.allowCommands,
      testing: testing ?? this.testing,
      testResult: clearTestResult ? null : (testResult ?? this.testResult),
      saving: saving ?? this.saving,
      saved: saved ?? this.saved,
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  String toString() =>
      'SettingsEditing(hostText: $hostText, testing: $testing, '
      'saving: $saving, saved: $saved, errorKind: $errorKind, error: $error)';
}
