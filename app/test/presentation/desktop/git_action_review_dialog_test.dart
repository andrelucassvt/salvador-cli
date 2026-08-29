import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/content/git_action_review_dialog.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester, GitActionProposal proposal) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GitActionReviewDialog(proposal: proposal)),
        ),
      );

  testWidgets('acao normal mostra impacto local', (tester) async {
    await pumpDialog(
      tester,
      const GitActionProposal(type: GitActionType.commit, message: 'ajusta'),
    );

    expect(find.textContaining('local'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
  });

  for (final type in [
    GitActionType.fetch,
    GitActionType.pull,
    GitActionType.push,
    GitActionType.pushForce,
  ]) {
    testWidgets('$type mostra impacto de rede', (tester) async {
      await pumpDialog(tester, GitActionProposal(type: type));

      expect(find.textContaining('rede'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    });
  }

  for (final type in [
    GitActionType.resetHard,
    GitActionType.cleanForce,
    GitActionType.restoreFile,
    GitActionType.removeFile,
    GitActionType.deleteBranchForce,
    GitActionType.deleteTag,
    GitActionType.stashDrop,
    GitActionType.amendCommit,
  ]) {
    testWidgets('$type mostra impacto destrutivo', (tester) async {
      await pumpDialog(tester, GitActionProposal(type: type));

      expect(find.textContaining('destrutiva'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  }
}
