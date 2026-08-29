import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';

enum WorkspaceModelState { stopped, starting, running }

enum WorkspaceErrorKind {
  invalidHost,
  folderNotFound,
  noModelsInstalled,
  connectionFailed,
  modelLoadFailed,
  saveSettingsFailed,
  generic,
}

/// Diferente do template Initial/Loading/Loaded/Error: aqui `connecting` e
/// `modelState` sao campos dentro do unico estado de conteudo, nao estados a
/// parte, porque a pasta/modelo/sessoes precisam continuar visiveis durante
/// reconexao ou falha - exatamente como `DesktopController` fazia com campos
/// sempre presentes independente de `connectionState`/`modelState`.
@immutable
sealed class WorkspaceState {
  const WorkspaceState();

  @override
  String toString();
}

class WorkspaceInitial extends WorkspaceState {
  const WorkspaceInitial();

  @override
  String toString() => 'WorkspaceInitial';
}

class WorkspaceReady extends WorkspaceState {
  const WorkspaceReady({
    required this.host,
    this.root,
    this.connecting = false,
    this.modelState = WorkspaceModelState.stopped,
    this.models = const [],
    this.runningModels = const [],
    this.selectedModel,
    this.inference = const InferenceOptions(),
    this.permissions = const AgentPermissions(),
    this.recentRoots = const [],
    this.sessions = const [],
    this.errorKind,
    this.error,
  });

  final Uri host;
  final Directory? root;
  final bool connecting;
  final WorkspaceModelState modelState;
  final List<OllamaModelInfo> models;
  final List<OllamaRunningModel> runningModels;
  final String? selectedModel;
  final InferenceOptions inference;
  final AgentPermissions permissions;
  final List<String> recentRoots;
  final List<PersistedSessionSummaryEntity> sessions;
  final WorkspaceErrorKind? errorKind;
  final Object? error;

  WorkspaceReady copyWith({
    Uri? host,
    Directory? root,
    bool clearRoot = false,
    bool? connecting,
    WorkspaceModelState? modelState,
    List<OllamaModelInfo>? models,
    List<OllamaRunningModel>? runningModels,
    String? selectedModel,
    bool clearSelectedModel = false,
    InferenceOptions? inference,
    AgentPermissions? permissions,
    List<String>? recentRoots,
    List<PersistedSessionSummaryEntity>? sessions,
    WorkspaceErrorKind? errorKind,
    bool clearError = false,
    Object? error,
  }) {
    return WorkspaceReady(
      host: host ?? this.host,
      root: clearRoot ? null : (root ?? this.root),
      connecting: connecting ?? this.connecting,
      modelState: modelState ?? this.modelState,
      models: models ?? this.models,
      runningModels: runningModels ?? this.runningModels,
      selectedModel: clearSelectedModel
          ? null
          : (selectedModel ?? this.selectedModel),
      inference: inference ?? this.inference,
      permissions: permissions ?? this.permissions,
      recentRoots: recentRoots ?? this.recentRoots,
      sessions: sessions ?? this.sessions,
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  String toString() =>
      'WorkspaceReady(host: $host, root: ${root?.path}, connecting: '
      '$connecting, modelState: $modelState, selectedModel: $selectedModel, '
      'errorKind: $errorKind, error: $error)';
}
