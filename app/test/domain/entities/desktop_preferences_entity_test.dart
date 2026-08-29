import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/domain/entities/desktop_preferences_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';

void main() {
  group('DesktopPreferencesEntity', () {
    test('equals_whenSameValuesInDifferentListInstances_returnsTrue', () {
      final sessionA = PersistedSessionSummaryEntity(
        title: 'sessao 1',
        startedAt: DateTime(2026, 1, 1),
        actionCount: 3,
      );
      final sessionB = PersistedSessionSummaryEntity(
        title: 'sessao 1',
        startedAt: DateTime(2026, 1, 1),
        actionCount: 3,
      );

      final a = DesktopPreferencesEntity(
        activeRoot: '/tmp/projeto',
        recentRoots: ['/tmp/projeto', '/tmp/outro'],
        sessions: [sessionA],
      );
      final b = DesktopPreferencesEntity(
        activeRoot: '/tmp/projeto',
        recentRoots: ['/tmp/projeto', '/tmp/outro'],
        sessions: [sessionB],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equals_whenRecentRootsDiffer_returnsFalse', () {
      final a = DesktopPreferencesEntity(recentRoots: const ['/a']);
      final b = DesktopPreferencesEntity(recentRoots: const ['/b']);

      expect(a, isNot(equals(b)));
    });

    test('copyWith_whenActiveRootGiven_changesOnlyActiveRoot', () {
      const original = DesktopPreferencesEntity(activeRoot: '/tmp/projeto');

      final copy = original.copyWith(activeRoot: '/tmp/novo');

      expect(copy.activeRoot, '/tmp/novo');
      expect(copy.host, original.host);
      expect(copy.recentRoots, original.recentRoots);
    });

    test(
      'contextFilesEnabled defaults, copies and participates in equality',
      () {
        const original = DesktopPreferencesEntity();

        expect(original.contextFilesEnabled, isTrue);
        expect(
          original.copyWith(contextFilesEnabled: false).contextFilesEnabled,
          isFalse,
        );
        expect(
          original.copyWith(contextFilesEnabled: true).contextFilesEnabled,
          isTrue,
        );
        expect(
          original,
          isNot(
            equals(const DesktopPreferencesEntity(contextFilesEnabled: false)),
          ),
        );
      },
    );
  });
}
