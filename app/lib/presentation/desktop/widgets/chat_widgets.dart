import 'package:flutter/material.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/file_chip.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.ready,
    required this.rootPath,
    required this.onPrompt,
  });

  final bool ready;
  final String? rootPath;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: navy,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                ready
                    ? 'Pronto para trabalhar localmente.'
                    : 'Prepare sua bancada local.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ink,
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ready
                    ? (rootPath != null
                          ? 'O agente pode ler, editar e executar comandos somente em $rootPath.'
                          : 'Nenhum projeto vinculado — o agente responde sem acesso a arquivos ou comandos.')
                    : 'Confirme o servidor e o modelo para começar.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
              ),
              if (ready) ...[
                const SizedBox(height: 30),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _PromptCard(
                      label: 'Entender o projeto',
                      prompt:
                          'Analise este projeto e explique sua arquitetura.',
                      icon: Icons.account_tree_outlined,
                      onTap: onPrompt,
                    ),
                    _PromptCard(
                      label: 'Revisar um arquivo',
                      prompt: 'Revise @',
                      icon: Icons.fact_check_outlined,
                      onTap: onPrompt,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MessageCard extends StatelessWidget {
  const MessageCard({super.key, required this.entry});

  final ChatMessageEntity entry;

  @override
  Widget build(BuildContext context) {
    final user = entry.role == ChatRole.user;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: user ? 700 : 880),
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: user ? navy : paper,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(user ? 15 : 4),
            bottomRight: Radius.circular(user ? 4 : 15),
          ),
          border: user ? null : Border.all(color: line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user ? 'VOCÊ' : 'SALVADOR',
              style: TextStyle(
                color: user ? Colors.white60 : ocean,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              entry.content,
              style: TextStyle(
                color: user ? Colors.white : ink,
                fontSize: 14,
                height: 1.52,
              ),
            ),
            if (entry.mentionedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.mentionedFiles
                    .map((path) => FileChip(label: path))
                    .toList(growable: false),
              ),
            ],
            if (entry.attachedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.attachedFiles
                    .map((name) => FileChip(label: name, showAtPrefix: false))
                    .toList(growable: false),
              ),
            ],
            if (entry.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...entry.warnings.map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Aviso: $warning',
                    style: const TextStyle(color: coral, fontSize: 11),
                  ),
                ),
              ),
            ],
            if (entry.metrics != null) ...[
              const SizedBox(height: 14),
              _MetricsBar(metrics: entry.metrics!),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricsBar extends StatelessWidget {
  const _MetricsBar({required this.metrics});

  final InferenceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final rate = metrics.tokensPerSecond;
    final items = [
      (
        Icons.speed_rounded,
        rate == null ? 'n/d' : '${rate.toStringAsFixed(1)} tok/s',
      ),
      (Icons.north_east_rounded, '${metrics.generatedTokens} saída'),
      (Icons.south_west_rounded, '${metrics.promptTokens} entrada'),
      (
        Icons.timer_outlined,
        '${metrics.totalSeconds.toStringAsFixed(2)}s total',
      ),
      if (metrics.generations > 1)
        (Icons.repeat_rounded, '${metrics.generations} gerações'),
    ];
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: line)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items
            .map(
              (item) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.$1, size: 12, color: ocean),
                  const SizedBox(width: 4),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 10.5,
                      fontFamily: 'JetBrains Mono',
                      letterSpacing: .1,
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class ThinkingCard extends StatelessWidget {
  const ThinkingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: ocean),
            ),
            SizedBox(width: 10),
            Text('O agente está trabalhando…', style: TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: const Color(0xFFFFE9E5),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: coral, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: ink, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.label,
    required this.prompt,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String prompt;
  final IconData icon;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => onTap(prompt),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        backgroundColor: paper,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

