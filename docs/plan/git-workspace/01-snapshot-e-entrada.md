# Git Workspace Visual com Assistente Local — Parte 1: Snapshot e Entrada

> **Objetivo da parte:** reconhecer com segurança a raiz Git, carregar um snapshot somente leitura e permitir alternar entre Chat e Git exibindo branch e estado do repositório.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** nenhuma

## Contexto

O pacote raiz já injeta runners para processos do Ollama, mas não possui cliente Git nem tipos para refs, commits ou worktree. No desktop, `DesktopView` coordena `WorkspaceCubit`, `ChatCubit` e `FileExplorerCubit`; a nova entrada deve seguir o mesmo padrão, sem Cubit referenciando outro diretamente.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/git.dart` | criar | Tipos imutáveis, `GitProcessRunner`, `GitClient`, parsing e erros Git |
| `lib/salvador_cli.dart` | modificar | Exportar o módulo Git pelo barrel público |
| `test/git_test.dart` | criar | Contrato do cliente/parsers com runner fake |
| `app/lib/config/error/app_exception.dart` | modificar | Classificar falhas Git como `GitFailureException` |
| `app/lib/domain/interfaces/git_repository.dart` | criar | Contrato de snapshot e refresh para a apresentação |
| `app/lib/data/datasources/git_datasource.dart` | criar | Adaptar `GitClient` à raiz ativa |
| `app/lib/data/repositories/git_repository_impl.dart` | criar | Converter falhas em `Result<T>`/`GitFailureException` |
| `app/lib/presentation/desktop/view_model/git_cubit.dart` | criar | Carregar, atualizar e limpar o snapshot por raiz |
| `app/lib/presentation/desktop/view_model/git_state.dart` | criar | Estado vazio, carregando, pronto, fora de escopo e erro apresentável |
| `app/lib/config/inject/app_injector.dart` | modificar | Registrar datasource, repository e `GitCubit` |
| `app/lib/presentation/desktop/widgets/workspace_rail.dart` | criar | Navegação permanente Chat/Git e abertura do painel de atividade |
| `app/lib/presentation/desktop/content/git_workspace.dart` | criar | Estado inicial do modo Git com resumo do snapshot |
| `app/lib/presentation/desktop/view/desktop_view.dart` | modificar | Orquestrar seção ativa e sincronizar raiz com `GitCubit` |

## Fases

### Fase 1 — Contratos e testes do núcleo Git

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Criar em `lib/src/git.dart` os contratos mínimos `GitSnapshot`, `GitRef`, `GitCommit`, `GitWorktreeEntry`, `GitRepositoryState`, `GitProcessRunner`, `GitClient` e `GitException`, com métodos ainda não implementados e tipos públicos imutáveis.
- [x] Exportar `lib/src/git.dart` em `lib/salvador_cli.dart` para que testes e desktop não importem `lib/src/` diretamente.
- [x] Criar `test/git_test.dart` com runner fake, cobrindo repositório válido, pasta sem Git, top-level acima da raiz, detached HEAD e falha de processo/código de saída.
- [x] Adicionar fixtures de `status --porcelain=v2 --branch -z`, `for-each-ref` e `log` com branch local/remota, tag, stash, merge com dois pais, caminho com espaço e mensagem Unicode.
- [x] Verificação: `dart test test/git_test.dart` compila e falha apenas por métodos ainda não implementados ou expectativas funcionais não atendidas.

### Fase 2 — Implementar snapshot Git somente leitura

- [x] Implementar `GitClient` em `lib/src/git.dart` com `Process.run('git', ['-C', root.path, ...])`, `runInShell: false`, timeout e normalização de stdout/stderr sem interpolar argumentos de usuário em shell.
- [x] Validar `rev-parse --show-toplevel` por caminhos resolvidos e distinguir `notRepository`, `repositoryOutsideRoot`, `detachedHead` e repositório válido.
- [x] Montar `GitSnapshot` a partir de status, upstream/ahead/behind, refs locais/remotas, tags, stashes, commits com pais e worktree staged/unstaged/untracked/conflicted.
- [x] Limitar o histórico inicial e o tamanho de patches/textos retornados; representar truncamento no tipo em vez de cortar silenciosamente.
- [x] Garantir que qualquer falha esperada vire `GitException` própria e que os parsers aceitem saída vazia sem lançar `FormatException` genérica.
- [x] Verificação: `dart test test/git_test.dart` passa, incluindo fixtures NUL-delimited e validação de confinamento.

### Fase 3 — Testes de Repository e Cubit antes da implementação

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Declarar as assinaturas mínimas de `GitRepository`, `GitRepositoryImpl`, `GitState` e `GitCubit` nos caminhos planejados, com corpos provisórios lançando `UnimplementedError`, para que os testes validem o contrato sem erro de importação.
- [x] Criar `app/test/data/git/fakes/fake_git_datasource.dart` e `app/test/data/git/git_repository_impl_test.dart` para sucesso, `GitException`, `ProcessException` e erro desconhecido preservando causa/stack trace.
- [x] Criar `app/test/presentation/desktop/fakes/fake_git_repository.dart` conforme o padrão dos fakes existentes.
- [x] Criar `app/test/presentation/desktop/git_cubit_test.dart` cobrindo `setRoot(null)`, carregamento bem-sucedido, refresh, troca de raiz durante requisição, fora de escopo e manutenção do snapshot anterior durante refresh.
- [x] Definir nos testes que um resultado atrasado da raiz antiga não pode sobrescrever a raiz atual.
- [x] Verificação: os dois arquivos de teste compilam e falham somente pela ausência da implementação funcional.

### Fase 4 — Implementar integração Git do app

- [x] Criar `GitRepository` em `app/lib/domain/interfaces/git_repository.dart` retornando `Result<GitSnapshot>` sem expor o datasource.
- [x] Implementar `GitDataSource` e `GitRepositoryImpl` nos caminhos planejados, reutilizando os tipos exportados por `package:salvador_cli/salvador_cli.dart` e classificando falhas em `GitFailureException`.
- [x] Implementar `GitState` imutável com `copyWith`, igualdade/hash consistentes e `toString()` informativo sem despejar commits ou diffs inteiros.
- [x] Implementar `GitCubit.setRoot`/`refresh` com token de requisição para descartar respostas obsoletas e preservar dados enquanto atualiza.
- [x] Registrar `GitDataSource`, `GitRepository` e `GitCubit` em `app/lib/config/inject/app_injector.dart` seguindo lazy singleton → repository → factory.
- [x] Verificação: `cd app && flutter test test/data/git/git_repository_impl_test.dart test/presentation/desktop/git_cubit_test.dart` passa.

### Fase 5 — Testes da entrada Chat/Git

> Os novos testes vão falhar inicialmente — isso é intencional.

- [ ] Atualizar o harness de `app/test/salvador_desktop_app_test.dart` para registrar `GitCubit` com repository fake, sem invocar um processo Git real.
- [ ] Testar que o rail permanece visível com Chat selecionado e que tocar `git-navigation-button` troca apenas a área central para `git-workspace`.
- [ ] Testar retorno ao Chat preservando mensagens, composer e estado dos painéis laterais.
- [ ] Testar os estados sem projeto, pasta sem Git, repositório fora da raiz, carregando e snapshot válido com branch/dirty/ahead/behind.
- [ ] Verificação: o arquivo compila e os novos testes falham porque os widgets e a navegação ainda não existem.

### Fase 6 — Implementar a entrada visual e fechar a parte

- [x] Criar `WorkspaceRail` em `app/lib/presentation/desktop/widgets/workspace_rail.dart` com botões Chat, Git e Atividade, tooltips, destaque coral, semântica de seleção e atalhos `Ctrl/Cmd+Shift+G` e `Ctrl/Cmd+Shift+C`.
- [x] Refatorar `app/lib/presentation/desktop/view/desktop_view.dart` para manter o rail de 50 px sempre visível, alternar a área central sem destruir `ChatCubit` e sincronizar mudanças de `WorkspaceState.root` com `GitCubit` pela View.
- [x] Criar o resumo inicial em `app/lib/presentation/desktop/content/git_workspace.dart` com branch/HEAD, clean/dirty, ahead/behind, contagens de refs/commits/alterações, botão Atualizar e mensagens acionáveis para estados inválidos.
- [x] Preservar `WorkspaceTopBar` e o painel direito de arquivos nos dois modos; o composer aparece apenas no modo Chat nesta parte.
- [x] Executar `dart format` nos Dart alterados, `dart analyze`, `dart test`, `cd app && flutter analyze` e `cd app && flutter test`, sem iniciar o app.
- [x] Verificação: todos os comandos passam e `salvador_desktop_app_test.dart` comprova alternância Chat/Git com o estado do chat preservado.
- [ ] Checkpoint: commit das mudanças da parte + resumo curto do snapshot e da navegação prontos, seguindo direto para a parte 2.

## Critérios de Sucesso

- [x] O cliente diferencia repositório válido, ausência de Git, detached HEAD e top-level fora da raiz sem processo real nos testes.
- [x] O snapshot inclui refs, commits com pais, upstream e estados staged/unstaged/untracked/conflicted.
- [x] O usuário consegue alternar Chat/Git sem perder a conversa atual.
- [x] `dart analyze` e `dart test` passam.
- [x] `cd app && flutter analyze && flutter test` passam.
- [ ] _(manual — feito pelo usuário)_ Confirmar que um projeto Git real mostra a branch e o resumo correto e que um diretório comum mostra o estado vazio.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Saída Git variar por locale | Média | Usar formatos explícitos/NUL e ambiente com locale estável no processo quando necessário |
| Refresh antigo sobrescrever nova raiz | Média | Token de requisição no `GitCubit` e teste com futures controlados |
| Refatoração do rail quebrar atividade | Média | Manter o callback de expansão e cobrir chat, atividade e arquivos no widget test existente |

## Notas de execução (drift confirmado do repositório)

- A suíte `salvador_desktop_app_test.dart` já falhava antes desta parte: o refactor `a33ced0` renomeou as chaves dos rails (`expand-panel-button` → `rail-sessions-button`, `expand-files-panel-button` → `right-rail-files-button`, `activity-rail` → `workspace-rail`) sem atualizar os testes, e os testes `menu de pasta`/`arvore` não seedavam `activeRoot`, deixando a raiz nula. Corrigido nesta parte, mantendo as chaves do `lib/` como verdade.
- Overflow pré-existente do `WorkspaceTopBar` e do `Composer` em janelas estreitas (acentuado pela fonte Ahem dos testes): corrigido com seção esquerda flexível no top bar, texto da pasta com limite em modo muito compacto, labels dos botões do composer com `maxWidth` + ellipsis, `Spacer` + `Flexible` no rodapé do composer e padding reduzido em larguras < 420 px.

## Rollback

Reverter o commit de checkpoint desta parte. Os módulos Git novos são isolados; remover o registro do `AppInjector`, a seção Git do shell e o export do barrel restaura o comportamento anterior.
