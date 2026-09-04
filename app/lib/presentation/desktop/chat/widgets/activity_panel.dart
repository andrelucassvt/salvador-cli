import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/common/utils/formatters.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_state.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_state.dart';

class ActivityPanel extends StatelessWidget {
  const ActivityPanel({super.key, required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, workspaceState) {
        final sessions = workspaceState is WorkspaceReady
            ? workspaceState.sessions
            : const <PersistedSessionSummaryEntity>[];
        return BlocBuilder<ChatCubit, ChatState>(
          builder: (context, chatState) {
            final activities = (chatState as ChatIdle).activities;
            final currentSession = chatState.currentSessionSummary;
            return Container(
              key: const Key('activity-panel'),
              decoration: const BoxDecoration(color: deepNavy),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _AzulejoPainter()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              key: const Key('collapse-panel-button'),
                              tooltip: 'Recolher painel',
                              onPressed: onCollapse,
                              icon: const Icon(
                                Icons.menu_open_rounded,
                                color: Colors.white70,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              'ATIVIDADE',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.3,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${activities.length}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: activities.isEmpty
                              ? const _NoActivity()
                              : ListView.separated(
                                  itemCount: activities.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 7),
                                  itemBuilder: (_, index) => _ActivityTile(
                                    activity: activities[index],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'SESSÕES',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: (sessions.isEmpty && currentSession == null)
                              ? const Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    'As sessões encerradas aparecerão aqui.',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                )
                              : ListView(
                                  children: [
                                    if (currentSession != null)
                                      _SessionTile(
                                        session: currentSession,
                                        current: true,
                                      ),
                                    ...sessions.map(
                                      (session) => _SessionTile(
                                        session: session,
                                        current: false,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.current});

  final PersistedSessionSummaryEntity session;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: current ? coral : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatSessionDate(session.startedAt)} · ${session.actionCount} ações',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
          if (current)
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: coral,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _NoActivity extends StatelessWidget {
  const _NoActivity();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'As leituras, edições e comandos aparecerão aqui.',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.45),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final ToolActivityEntity activity;

  ({String badge, String title, Color color}) get _style =>
      switch (activity.call.name) {
        'read_file' => (
          badge: 'R',
          title: 'Leitura',
          color: const Color(0xFF74C9D3),
        ),
        'write_file' => (
          badge: 'W',
          title: 'Gravação',
          color: const Color(0xFF7BD8B0),
        ),
        'replace_in_file' => (
          badge: 'E',
          title: 'Edição',
          color: const Color(0xFFFFCF70),
        ),
        'run_command' => (
          badge: '\$',
          title: 'Comando',
          color: const Color(0xFFF29E8E),
        ),
        _ => (badge: '?', title: activity.call.name, color: Colors.white54),
      };

  String get _detail {
    final result = activity.result;
    final measurable =
        result.startsWith('OK:') ||
        result.startsWith('ERRO:') ||
        result.contains('EXIT_CODE:');
    if (measurable) return result.split('\n').first;
    return activity.summary;
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              style.badge,
              style: TextStyle(
                color: style.color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      relativeTime(activity.happenedAt),
                      style: const TextStyle(
                        color: Color(0x75FFFFFF),
                        fontSize: 9,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x75FFFFFF),
                    fontSize: 9,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AzulejoPainter extends CustomPainter {
  const _AzulejoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .026)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const tile = 54.0;
    for (double y = -tile; y < size.height + tile; y += tile) {
      for (double x = -tile; x < size.width + tile; x += tile) {
        final center = Offset(x + tile / 2, y + tile / 2);
        final diamond = Path()
          ..moveTo(center.dx, center.dy - 13)
          ..lineTo(center.dx + 13, center.dy)
          ..lineTo(center.dx, center.dy + 13)
          ..lineTo(center.dx - 13, center.dy)
          ..close();
        canvas.drawPath(diamond, paint);
        canvas.drawCircle(center, 4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
