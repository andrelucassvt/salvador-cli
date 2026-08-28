import 'package:flutter/material.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/common/utils/formatters.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_state.dart';

class ModelMenu extends StatelessWidget {
  const ModelMenu({super.key, required this.state, required this.cubit});

  final WorkspaceReady state;
  final WorkspaceCubit cubit;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedModel;
    final isRunning = state.runningModels.any((model) => model.name == selected);
    return MenuAnchor(
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...state.models.map(
                (model) => _ModelMenuItem(
                  model: model,
                  selected: model.name == selected,
                  running: state.runningModels.any(
                    (runningModel) => runningModel.name == model.name,
                  ),
                  knownVram: state.runningModels
                      .where((runningModel) => runningModel.name == model.name)
                      .map((runningModel) => runningModel.sizeVramBytes)
                      .where((bytes) => bytes > 0)
                      .fold<int?>(null, (_, bytes) => bytes),
                  contextFuture: model.name == selected
                      ? cubit.fetchModelContext(model.name)
                      : null,
                  onTap: () => cubit.selectModel(model.name),
                ),
              ),
              const Divider(height: 1),
              FutureBuilder<int?>(
                future: cubit.availableMemory(),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Text(
                      bytes == null
                          ? 'RAM livre do sistema: indisponível'
                          : 'RAM livre do sistema: ${formatBytes(bytes)}',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
      builder: (context, menuController, _) => InkWell(
        key: const Key('model-menu'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => menuController.isOpen
            ? menuController.close()
            : menuController.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isRunning ? const Color(0xFF7BD8B0) : line,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  selected ?? 'Sem modelo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_drop_down_rounded,
                size: 17,
                color: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelMenuItem extends StatelessWidget {
  const _ModelMenuItem({
    required this.model,
    required this.selected,
    required this.running,
    required this.knownVram,
    required this.contextFuture,
    required this.onTap,
  });

  final OllamaModelInfo model;
  final bool selected;
  final bool running;
  final int? knownVram;
  final Future<int?>? contextFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('model-item-${model.name}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: selected ? ocean : line,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 12.5,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      StatusPill(running: running),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          '${formatBytes(model.sizeBytes)} · ${model.quantization ?? model.family ?? 'peso desconhecido'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 10,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (contextFuture != null)
                    FutureBuilder<int?>(
                      future: contextFuture,
                      builder: (context, snapshot) {
                        final contextLength = snapshot.data;
                        if (contextLength == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'contexto: $contextLength tokens',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 10,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (knownVram != null)
              Text(
                '${formatBytes(knownVram!)} em VRAM',
                style: const TextStyle(
                  color: muted,
                  fontSize: 10,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: running ? const Color(0xFFE2F5EC) : const Color(0xFFEFF2F0),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        running ? 'CARREGADO' : 'PARADO',
        style: TextStyle(
          color: running ? const Color(0xFF2E7D57) : muted,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .6,
        ),
      ),
    );
  }
}
