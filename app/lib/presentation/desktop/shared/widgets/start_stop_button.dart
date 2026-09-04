import 'package:flutter/material.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_state.dart';

class StartStopButton extends StatelessWidget {
  const StartStopButton({
    super.key,
    required this.state,
    required this.cubit,
    this.iconOnly = false,
  });

  final WorkspaceReady state;
  final WorkspaceCubit cubit;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final starting = state.modelState == WorkspaceModelState.starting;
    final running = state.modelState == WorkspaceModelState.running;
    final busy = starting;
    final enabled = !state.connecting && state.selectedModel != null && !busy;

    final Widget content;
    if (starting) {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: ocean),
          ),
          SizedBox(width: 8),
          Text('Aguarde…'),
        ],
      );
    } else if (running) {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stop_rounded, size: 16),
          SizedBox(width: 6),
          Text('Encerrar modelo'),
        ],
      );
    } else {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 17),
          SizedBox(width: 4),
          Text('Iniciar modelo'),
        ],
      );
    }

    if (iconOnly) {
      return Tooltip(
        message: running ? 'Encerrar modelo' : 'Iniciar modelo',
        child: OutlinedButton(
          key: const Key('start-stop-button'),
          onPressed: enabled
              ? () => running ? cubit.stopModel() : cubit.startModel()
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: navy,
            side: const BorderSide(color: line),
            padding: const EdgeInsets.all(9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: starting
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ocean,
                  ),
                )
              : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
        ),
      );
    }

    return OutlinedButton(
      key: const Key('start-stop-button'),
      onPressed: enabled
          ? () => running ? cubit.stopModel() : cubit.startModel()
          : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        side: const BorderSide(color: line),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: content,
    );
  }
}
