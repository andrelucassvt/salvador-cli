---
generated_at: 2026-08-29
source_commit: 6df9edf
source_state: dirty
verified_at: 2026-08-29
status: current
related_plans: ['docs/plan/git-workspace/00-indice.md']
---

# Flow: Git Workspace Visual com Assistente Local

> **Resumo:** No desktop, o rail Chat/Git abre um workspace somente leitura do repositório da raiz (branches, grafo, inspector, worktree) e um assistente Ollama dedicado que consulta Git por ferramentas tipadas e só muta após revisão explícita — fetch, criar/trocar branch, stage, unstage, commit, merge e rebase; nunca `run_command`, push, reset hard, clean, delete ou force.

## Visão Geral

O usuário escolhe Git no rail esquerdo (`WorkspaceSection.git`). A View já vinculou a raiz ao `GitCubit`, que carrega um `GitSnapshot` via `GitClient` (`Process.run('git', ...)` com runner injetável, sem shell). O repositório só é aceito quando o top-level resolvido coincide com a raiz; pasta sem Git ou repositório acima dela viram estados apresentáveis, sem ações.

No workspace o usuário navega refs, commits e arquivos. “Pedir ao Salvador” abre um drawer com conversa independente do chat principal. O envio serializa só a seleção atual (`serializeGitContext`) e manda a uma `AgentSession` com `GitProfile`: consultas `git_status`/`git_log`/`git_diff`/`git_show` e `propose_git_action`. Mutações não executam no tool call — viram `GitActionProposal` para o `GitActionReviewDialog`. Confirmar chama `GitCubit.executeApproved` → `GitActionExecutor` com argumentos fixos; sucesso recarrega o snapshot, falha preserva os dados e mostra banner. Fetch do cabeçalho usa o mesmo dialog porque envolve rede.

## Passo a Passo

1. **Navegação Chat/Git** — `app/lib/presentation/desktop/widgets/workspace_rail.dart` → `WorkspaceRail`
   O rail permanente troca `_ShellScreenState._section` entre `WorkspaceSection.chat` e `.git`. A área central (`desktop_view.dart` → `_buildCenter`) monta `GitWorkspace` sem destruir o `ChatCubit`.

2. **Montagem e sincronização** — `app/lib/presentation/desktop/view/desktop_view.dart` → `_ShellScreenState.initState` / `MultiBlocListener`
   Resolve `GitCubit` e `GitAssistantCubit` no `AppInjector`. Mudança de raiz chama `GitCubit.setRoot`. Mudança de host/modelo/raiz/permissões chama `GitAssistantCubit.attachSession` (sessão própria, conversa zerada). `modelState`/`connecting` atualizam `GitAssistantCubit.updateReadiness` em paralelo ao chat.

3. **Descoberta e snapshot** — `app/lib/presentation/desktop/view_model/git_cubit.dart` → `GitCubit.setRoot`
   Emite `GitLoading` (preserva `GitLoaded` anterior). `GitRepository.loadSnapshot` → `GitDataSource` → `GitClient.loadSnapshot`. `GitClient.discover` compara `rev-parse --show-toplevel` com a raiz resolvida.

4. **Estados do repositório** — `git_cubit.dart` + `git_workspace.dart`
   `GitRepositoryKind.valid` → `GitLoaded` (seleções sobrevivem se a ref/commit/arquivo ainda existe). `notRepository` / `repositoryOutsideRoot` / erro → telas com “Tentar novamente”. Sem raiz → `GitEmpty`.

5. **Navegação visual** — `git_workspace.dart` + `git_branches_panel.dart` / `git_commit_graph.dart` / `git_commit_inspector.dart` / `git_worktree_panel.dart`
   Refs, grafo (histórico inicial limitado, `loadMore` pagina), inspector e worktree. Largura &lt; 900 recolhe branches e abre inspector como gaveta. Seleção (`selectRef`/`selectCommit`/`selectFile`) não dispara Git.

6. **Abrir o assistente** — `git_workspace.dart` → `_GitHeader` + `git_assistant_cubit.dart` → `openDrawer`
   “Pedir ao Salvador” só abre o drawer; a seleção Git permanece. Chips de branch/commit/arquivo escutam `GitCubit` e `GitAssistantCubit`.

7. **Envio contextual** — `git_assistant_drawer.dart` → `_send`
   Mesmo fluxo seguro de `_ShellScreenState._send`: se o modelo está parado, `WorkspaceCubit.startModel`; só envia se ficar `running`, e afirma readiness no Cubit. Serializa `serializeGitContext(snapshot, selectedRef, selectedCommitHash, selectedFilePath)` e chama `GitAssistantCubit.send`.

8. **Sessão Git da LLM** — `git_assistant_datasource.dart` → `configureSession` / `send`
   `AgentSession` com `GitProfile()`, `allowCommands: false` (mesmo se as permissões do chat permitem shell) e `allowEdit` copiado para resolver conflitos. O prompt é `contexto + input`. Consultas Git leem pelo `GitClient`; `propose_git_action` valida e acumula `GitActionProposal` em `AgentTurnResult.proposals`, devolvendo “Aguardando aprovacao na interface.” — zero `Process.run` de mutação.

9. **Revisão** — `git_action_review_dialog.dart` → `GitActionReviewDialog`
   Tipo, ref, caminhos, mensagem e impacto (local vs rede). Abrir o dialog não executa. Cancelar no chip ou no dialog chama `dismissProposal` e não toca `GitRepository.executeAction`.

10. **Execução e refresh** — `git_cubit.dart` → `executeApproved`
    Bloqueia concorrência (`executingAction`). `GitRepository.executeAction` → `GitActionExecutor.execute` (`git -C <raiz> <args fixos>`). Sucesso: limpa execução, `refresh()` recarrega branches/grafo/worktree/inspector. Falha: `actionError` no banner, snapshot intacto, drawer e proposta pendente permanecem. Fetch do cabeçalho constrói `GitActionProposal(type: fetch)` e entra no mesmo dialog.

### Caminhos alternativos

- **Sem raiz:** `GitEmpty` — “Selecione um projeto para ver o status Git.”
- **Não é repositório / top-level acima da raiz:** `GitNotRepository` / `GitRepositoryOutsideRoot` com o caminho real e botão de refresh; ações desabilitadas.
- **Falha de processo/parsing Git:** `GitFailure` com a mensagem de `GitFailureException`.
- **Modelo parado no envio do assistente:** `_send` tenta `startModel`; se falhar, o texto fica no composer e nada vai à LLM.
- **Sessão não pronta:** `GitAssistantCubit.send` emite `GitAssistantErrorKind.sessionNotReady` sem chamar o repositório.
- **Falha Ollama/agente no assistente:** `GitAssistantErrorKind.sendFailed`; mensagens anteriores permanecem.
- **Proposta inválida da LLM:** `ProposeGitActionTool` lança `ToolException` → `ERRO: <motivo>` para o modelo corrigir; nada aparece na UI.
- **Fetch/merge/rebase falha após confirmar:** banner `git-action-error-banner`; sem abort/reset automático.
- **Detached HEAD:** cabeçalho “HEAD desanexado”; snapshot continua válido.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Núcleo Git | `lib/src/git.dart` | `GitClient` (snapshot somente leitura), `GitActionType`/`GitActionProposal`, `GitActionExecutor`, `serializeGitContext` |
| Ferramentas | `lib/src/tools.dart` | `GitProfile`, consultas Git, `ProposeGitActionTool`; `run_command` omitido quando o perfil Git está ativo |
| Agente | `lib/src/agent.dart` | `AgentSession` com perfil Git opcional; `AgentTurnResult.proposals` |
| Domínio | `app/lib/domain/interfaces/git_repository.dart` | Snapshot, paginação e `executeAction` aprovada |
| Domínio | `app/lib/domain/interfaces/git_assistant_repository.dart` | Sessão dedicada: configure/send/clear + atividades |
| Dados | `app/lib/data/datasources/git_datasource.dart` | Adapta `GitClient`/`GitActionExecutor` à raiz |
| Dados | `app/lib/data/datasources/git_assistant_datasource.dart` | `AgentSession` própria, `allowCommands: false`, contexto concatenado |
| Dados | `app/lib/data/repositories/git_repository_impl.dart` | `GitException`/`ProcessException` → `GitFailureException` |
| Dados | `app/lib/data/repositories/git_assistant_repository_impl.dart` | Falhas do agente/Ollama/Git → `Result<T>` |
| Estado | `app/lib/presentation/desktop/view_model/git_{cubit,state}.dart` | Snapshot, seleção, paginação, `executeApproved` |
| Estado | `app/lib/presentation/desktop/view_model/git_assistant_{cubit,state}.dart` | Drawer, mensagens, propostas, readiness |
| Apresentação | `app/lib/presentation/desktop/content/git_workspace.dart` | Shell Git, Fetch, Pedir ao Salvador, banner de erro |
| Apresentação | `app/lib/presentation/desktop/widgets/git_assistant_drawer.dart` | Conversa, chips, composer, propostas |
| Apresentação | `app/lib/presentation/desktop/content/git_action_review_dialog.dart` | Revisão Cancelar/Confirmar |
| Configuração | `app/lib/config/inject/app_injector.dart` | Data sources/repos singleton; Cubits factory |
| Testes | `test/git_test.dart`, `test/salvador_cli_test.dart` | Args exatos, enum fechado, sessão sem `run_command` |
| Testes | `app/test/presentation/desktop/git_*_test.dart`, `app/test/salvador_desktop_app_test.dart` | Cubits, drawer, confirmação, conversas independentes |

## Regras de Negócio Relevantes

- **Top-level tem que ser a raiz** — `lib/src/git.dart` (`GitClient.discover`): repositório acima da pasta vinculada não habilita o workspace nem ações.
- **Git sempre por argv, nunca shell** — `GitClient` e `GitActionExecutor` usam `Process.run('git', argumentos)` com `runInShell: false`.
- **Mutação só depois da UI** — `ProposeGitActionTool` valida e registra; `GitActionExecutor.execute` só roda em `GitCubit.executeApproved` após Confirmar.
- **Enum fechado da primeira versão** — `GitActionType`: fetch, createBranch, checkoutBranch, stage, unstage, commit, merge, rebase. Sem reset hard, clean, delete, push ou force.
- **Sessão Git sem `run_command`** — `ToolRegistry`: com `GitProfile`, comandos de shell não entram mesmo se `allowCommands` for true; `GitAssistantDataSource` força `allowCommands: false`.
- **Contexto é a seleção, não o snapshot** — `serializeGitContext` manda resumo + ref/commit/arquivo selecionados, com `[TRUNCADO]` / `[... mais N]`; o system prompt de sete linhas em `prompt.dart` não muda.
- **Refresh só no sucesso** — `GitCubit.executeApproved`: falha preserva `GitLoaded.snapshot` e preenche `actionError`.
- **Chat e Git são sessões distintas** — `ChatCubit` e `GitAssistantCubit` têm datasources/`AgentSession` próprios; alternar o rail não mistura mensagens.
- **Edição de arquivo no Git segue `allowEdit`** — write/replace ficam disponíveis na sessão Git só se as permissões do workspace permitirem (conflitos).

## Dependências Externas

- Binário `git` no PATH (`Process.run`).
- Servidor Ollama (mesmos endpoints do chat) só no assistente Git, não no snapshot.

## Observações

- **`GitDataSource.executeAction` instancia um `GitActionExecutor()` novo**, sem reutilizar o `GitClient` injetado no datasource; testes de execução precisam fakear o repositório/executor, não só o runner do client de snapshot.
- **Timeouts divergem:** `GitClient` usa 15 s nas leituras; `GitActionExecutor` usa 30 s nas mutações.
- **Merge/rebase que deixam conflitos não disparam abort/reset.** O snapshot (possivelmente sujo) é recarregado só se a ação retornar sucesso; falha mostra o stderr e mantém o estado anterior em memória.
- **`GitActionReviewDialog` vive em `content/`**, embora o plano listasse `widgets/`; o drawer e o Fetch do header reutilizam o mesmo dialog.
