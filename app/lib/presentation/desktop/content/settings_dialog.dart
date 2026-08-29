import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/config/inject/app_injector.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/settings_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/settings_state.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_state.dart';

Future<bool> _applySettings(
  WorkspaceCubit workspaceCubit, {
  required String hostText,
  required double temperature,
  required int? contextLength,
  required Duration? keepAlive,
  required Duration? timeout,
  required bool allowEdit,
  required bool allowCommands,
}) async {
  await workspaceCubit.saveSettings(
    hostText: hostText,
    temperature: temperature,
    contextLength: contextLength,
    keepAlive: keepAlive,
    timeout: timeout,
    allowEdit: allowEdit,
    allowCommands: allowCommands,
  );
  final state = workspaceCubit.state;
  return state is WorkspaceReady && state.errorKind == null;
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, required this.workspace});

  final WorkspaceReady workspace;

  @override
  Widget build(BuildContext context) {
    final workspaceCubit = context.read<WorkspaceCubit>();
    return BlocProvider<SettingsCubit>(
      create: (_) => AppInjector.inject<SettingsCubit>(
        param1: SettingsEditing(
          hostText: workspace.host.toString(),
          temperature: workspace.inference.temperature,
          contextText: workspace.inference.contextLength?.toString() ?? '',
          keepAlive: workspace.inference.keepAlive,
          timeout: workspace.inference.timeout,
          allowEdit: workspace.permissions.allowEdit,
          allowCommands: workspace.permissions.allowCommands,
        ),
      ),
      child: _SettingsDialogBody(workspaceCubit: workspaceCubit),
    );
  }
}

/// StatefulWidget porque os campos de texto livre (host/contexto) precisam
/// de um `TextEditingController` estavel: reconstrui-lo a cada emissao do
/// Cubit (como um `BlocBuilder` puro faria) jogaria o cursor para o fim do
/// campo a cada tecla digitada.
class _SettingsDialogBody extends StatefulWidget {
  const _SettingsDialogBody({required this.workspaceCubit});

  final WorkspaceCubit workspaceCubit;

  @override
  State<_SettingsDialogBody> createState() => _SettingsDialogBodyState();
}

class _SettingsDialogBodyState extends State<_SettingsDialogBody> {
  late final TextEditingController _hostController;
  late final TextEditingController _contextController;

  @override
  void initState() {
    super.initState();
    final initial = context.read<SettingsCubit>().state as SettingsEditing;
    _hostController = TextEditingController(text: initial.hostText);
    _contextController = TextEditingController(text: initial.contextText);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceCubit = widget.workspaceCubit;
    return BlocConsumer<SettingsCubit, SettingsState>(
      listener: (context, state) {
        if (state is SettingsEditing && state.saved) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        final editing = state as SettingsEditing;
        final settingsCubit = context.read<SettingsCubit>();
        final viewport = MediaQuery.sizeOf(context);
        return Dialog(
          key: const Key('settings-dialog'),
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: viewport.height * .82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 24, 26, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Configurações',
                          style: TextStyle(
                            color: ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.3,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _DialogLabel('SERVIDOR OLLAMA'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('settings-host-field'),
                                onChanged: settingsCubit.updateHostText,
                                controller: _hostController,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'JetBrains Mono',
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'http://127.0.0.1:11434',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              key: const Key('test-host-button'),
                              onPressed: editing.testing
                                  ? null
                                  : settingsCubit.testHost,
                              icon: editing.testing
                                  ? const SizedBox.square(
                                      dimension: 13,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.wifi_tethering_rounded,
                                      size: 16,
                                    ),
                              label: const Text('Testar'),
                            ),
                          ],
                        ),
                        if (editing.testResult != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            editing.testResult!.ok
                                ? 'Servidor ok · ${editing.testResult!.latency!.inMilliseconds} ms · ${editing.testResult!.modelCount} modelo(s) instalado(s)'
                                : 'Falha no teste: ${editing.testResult!.error}',
                            key: const Key('host-test-result'),
                            style: TextStyle(
                              color: editing.testResult!.ok
                                  ? const Color(0xFF2E7D57)
                                  : coral,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const _DialogLabel('INFERÊNCIA'),
                        const SizedBox(height: 10),
                        _SliderSetting(
                          label: 'Temperatura',
                          value: editing.temperature,
                          onChanged: settingsCubit.updateTemperature,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('settings-context-field'),
                          onChanged: settingsCubit.updateContextText,
                          controller: _contextController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'JetBrains Mono',
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Tamanho do contexto',
                            hintText: 'Padrão do modelo',
                            suffixText: 'tokens',
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<Duration?>(
                          key: const Key('settings-keep-alive-field'),
                          initialValue: editing.keepAlive,
                          decoration: const InputDecoration(
                            labelText: 'Keep-alive',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: null,
                              child: Text('Padrão do Ollama (5 min)'),
                            ),
                            DropdownMenuItem(
                              value: Duration(minutes: 30),
                              child: Text('30 minutos'),
                            ),
                            DropdownMenuItem(
                              value: Duration(hours: 1),
                              child: Text('1 hora'),
                            ),
                            DropdownMenuItem(
                              value: Duration(hours: 4),
                              child: Text('4 horas'),
                            ),
                            DropdownMenuItem(
                              value: Duration(hours: 24),
                              child: Text('24 horas'),
                            ),
                          ],
                          onChanged: settingsCubit.updateKeepAlive,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<Duration?>(
                          key: const Key('settings-timeout-field'),
                          initialValue: editing.timeout,
                          decoration: const InputDecoration(
                            labelText: 'Timeout das requisições',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: null,
                              child: Text('Sem limite'),
                            ),
                            DropdownMenuItem(
                              value: Duration(seconds: 30),
                              child: Text('30 segundos'),
                            ),
                            DropdownMenuItem(
                              value: Duration(seconds: 60),
                              child: Text('60 segundos'),
                            ),
                            DropdownMenuItem(
                              value: Duration(seconds: 120),
                              child: Text('120 segundos'),
                            ),
                          ],
                          onChanged: settingsCubit.updateTimeout,
                        ),
                        const SizedBox(height: 20),
                        const _DialogLabel('PERMISSÕES'),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          key: const Key('settings-allow-edit'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Editar arquivos',
                            style: TextStyle(fontSize: 13.5),
                          ),
                          subtitle: const Text(
                            'Permite write_file e replace_in_file na pasta do projeto.',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: editing.allowEdit,
                          onChanged: settingsCubit.updateAllowEdit,
                        ),
                        SwitchListTile(
                          key: const Key('settings-allow-commands'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Executar comandos',
                            style: TextStyle(fontSize: 13.5),
                          ),
                          subtitle: const Text(
                            'Permite run_command na pasta do projeto.',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: editing.allowCommands,
                          onChanged: settingsCubit.updateAllowCommands,
                        ),
                        const SwitchListTile(
                          key: Key('settings-network-access'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Acesso à rede',
                            style: TextStyle(fontSize: 13.5),
                          ),
                          subtitle: Text(
                            'Desabilitado: run_command executa sem sandbox de rede, então o agente sempre pode alcançar a internet.',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: false,
                          onChanged: null,
                        ),
                        if (editing.errorKind != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            key: const Key('settings-error'),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE9E5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              editing.error?.toString() ??
                                  switch (editing.errorKind!) {
                                    SettingsErrorKind.invalidHost =>
                                      'Informe uma URL válida para o Ollama.',
                                    SettingsErrorKind.saveFailed =>
                                      'Não foi possível salvar as configurações.',
                                  },
                              style: const TextStyle(color: ink, fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const Key('settings-cancel-button'),
                        onPressed: editing.saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const Key('settings-save-button'),
                        onPressed: editing.saving
                            ? null
                            : () => settingsCubit.save(
                                onSave:
                                    ({
                                      required hostText,
                                      required temperature,
                                      required contextLength,
                                      required keepAlive,
                                      required timeout,
                                      required allowEdit,
                                      required allowCommands,
                                    }) => _applySettings(
                                      workspaceCubit,
                                      hostText: hostText,
                                      temperature: temperature,
                                      contextLength: contextLength,
                                      keepAlive: keepAlive,
                                      timeout: timeout,
                                      allowEdit: allowEdit,
                                      allowCommands: allowCommands,
                                    ),
                              ),
                        icon: editing.saving
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync_rounded, size: 16),
                        label: const Text('Salvar e reconectar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: ink, fontSize: 13.5),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, 1),
            min: 0,
            max: 1,
            divisions: 20,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: ink,
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ],
    );
  }
}
