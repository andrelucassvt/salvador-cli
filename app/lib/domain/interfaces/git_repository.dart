import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';

/// Contrato de snapshot Git para a apresentacao, sem expor o datasource.
abstract interface class GitRepository {
  Future<Result<GitSnapshot>> loadSnapshot({
    required Directory root,
    int maxCommits = GitClient.maxCommitsDefault,
  });

  Future<Result<GitCommitPage>> loadMoreCommits({
    required Directory root,
    required int skip,
    required int count,
  });

  /// Executa uma acao ja aprovada pela interface; mutacoes nunca rodam por
  /// tool call da LLM.
  Future<Result<String>> executeAction({
    required Directory root,
    required GitActionProposal proposal,
  });
}
