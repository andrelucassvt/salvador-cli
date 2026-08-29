import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/host_test_result_entity.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/settings_state.dart';

typedef SaveSettingsCallback =
    Future<bool> Function({
      required String hostText,
      required double temperature,
      required int? contextLength,
      required Duration? keepAlive,
      required Duration? timeout,
      required bool allowEdit,
      required bool allowCommands,
    });

/// Estado local do formulario do dialogo de configuracoes. Diferente de
/// `WorkspaceCubit`, que persiste, este Cubit so edita em memoria; `save()`
/// delega a persistencia de fato a um callback fornecido pela View, ligado a
/// `WorkspaceCubit.saveSettings` - a View e quem decide se o resultado foi
/// sucesso (olhando o `WorkspaceState` resultante), porque
/// `WorkspaceCubit.saveSettings` nunca lanca excecao, sempre emite.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._ollamaRepository, {required SettingsEditing initial})
    : super(initial);

  final OllamaRepository _ollamaRepository;

  void updateHostText(String value) =>
      _update((s) => s.copyWith(hostText: value));

  void updateTemperature(double value) =>
      _update((s) => s.copyWith(temperature: value));

  void updateContextText(String value) =>
      _update((s) => s.copyWith(contextText: value));

  void updateKeepAlive(Duration? value) => _update(
    (s) => s.copyWith(keepAlive: value, clearKeepAlive: value == null),
  );

  void updateTimeout(Duration? value) =>
      _update((s) => s.copyWith(timeout: value, clearTimeout: value == null));

  void updateAllowEdit(bool value) =>
      _update((s) => s.copyWith(allowEdit: value));

  void updateAllowCommands(bool value) =>
      _update((s) => s.copyWith(allowCommands: value));

  Future<void> testHost() async {
    final current = state;
    if (current is! SettingsEditing) return;
    final parsed = Uri.tryParse(current.hostText.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      emit(
        current.copyWith(
          testResult: const HostTestResultEntity(
            ok: false,
            error: 'Informe uma URL válida para o Ollama.',
          ),
        ),
      );
      return;
    }

    emit(current.copyWith(testing: true, clearTestResult: true));
    final stopwatch = Stopwatch()..start();
    final connectionResult = await _ollamaRepository.testConnection(
      host: parsed,
    );
    switch (connectionResult) {
      case Error(:final error):
        stopwatch.stop();
        emit(
          (state as SettingsEditing).copyWith(
            testing: false,
            testResult: HostTestResultEntity(
              ok: false,
              latency: stopwatch.elapsed,
              error: error.message,
            ),
          ),
        );
        return;
      case Ok():
        break;
    }

    final modelsResult = await _ollamaRepository.listModels(host: parsed);
    stopwatch.stop();
    switch (modelsResult) {
      case Error(:final error):
        emit(
          (state as SettingsEditing).copyWith(
            testing: false,
            testResult: HostTestResultEntity(
              ok: false,
              latency: stopwatch.elapsed,
              error: error.message,
            ),
          ),
        );
      case Ok(:final value):
        emit(
          (state as SettingsEditing).copyWith(
            testing: false,
            testResult: HostTestResultEntity(
              ok: true,
              latency: stopwatch.elapsed,
              modelCount: value.length,
            ),
          ),
        );
    }
  }

  Future<void> save({required SaveSettingsCallback onSave}) async {
    final current = state;
    if (current is! SettingsEditing) return;
    final parsed = Uri.tryParse(current.hostText.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      emit(
        current.copyWith(
          errorKind: SettingsErrorKind.invalidHost,
          error: 'Informe uma URL válida para o Ollama.',
        ),
      );
      return;
    }

    emit(current.copyWith(saving: true, clearError: true));
    final success = await onSave(
      hostText: current.hostText,
      temperature: current.temperature,
      contextLength: int.tryParse(current.contextText.trim()),
      keepAlive: current.keepAlive,
      timeout: current.timeout,
      allowEdit: current.allowEdit,
      allowCommands: current.allowCommands,
    );
    if (success) {
      emit((state as SettingsEditing).copyWith(saving: false, saved: true));
    } else {
      emit(
        (state as SettingsEditing).copyWith(
          saving: false,
          errorKind: SettingsErrorKind.saveFailed,
        ),
      );
    }
  }

  void _update(SettingsEditing Function(SettingsEditing current) transform) {
    final current = state;
    if (current is! SettingsEditing) return;
    emit(transform(current));
  }
}
