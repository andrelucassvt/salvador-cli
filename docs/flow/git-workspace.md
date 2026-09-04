---
generated_at: 2026-08-29
source_commit: 718b3e9
source_state: dirty
verified_at: 2026-09-04
status: current
related_plans: ['docs/plan/git-workspace/00-indice.md', 'docs/plan/git-tool-operations/00-indice.md']
---

# Flow: Git Workspace Visual com Assistente Local

> **Resumo:** No desktop, o rail Chat/Git abre um workspace visual da raiz e um assistente Ollama dedicado com ferramentas Git tipadas: operações locais normais executam no turno, enquanto rede e operações destrutivas viram propostas revisáveis; a sessão nunca expõe `run_command`.

## Visão Geral

O usuário escolhe Git no rail esquerdo (`WorkspaceSection.git`). A View já vinculou a raiz ao `GitCubit`, que carrega um `GitSnapshot` via `GitClient` (`Process.run('git', ...)` com runner injetável, sem shell). O repositório só é aceito quando o top-level resolvido coincide com a raiz; pasta sem Git ou repositório acima dela viram estados apresentáveis, sem ações.

No workspace o usuário navega refs, commits e arquivos. O cabeçalho traz um botão preenchido “Pedir ao Salvador”, que abre um drawer com conversa independente do chat principal, e a branch atual abre um menu das demais branches locais. Clicar em um arquivo de alteração local mantém sua seleção no `GitCubit` e encaminha o caminho ao preview amplo compartilhado do shell, que usa a leitura confinada do workspace. Em largura compacta, o botão preserva o destaque visual e o tooltip, mas oculta seu rótulo para não causar overflow. Escolher uma branch no menu chama `GitCubit.checkoutBranch`, que só aceita ref local do snapshot atual e reaproveita a ação tipada `checkoutBranch` (`git checkout <branch>`).

O envio ao Salvador serializa só a seleção atual (`serializeGitContext`) e manda a uma `AgentSession` com `GitProfile`: consultas `git_status`/`git_log`/`git_diff`/`git_show` e a ferramenta única `git`. A ferramenta executa ações locais normais no turno e registra `GitActionProposal` para ações de rede ou destrutivas. O `GitActionReviewDialog` confirma estas últimas e chama `GitCubit.executeApproved` → `GitActionExecutor` com argumentos fixos; sucesso recarrega o snapshot, falha preserva os dados e mostra banner. Fetch do cabeçalho também entra no dialog porque envolve rede.

## Passo a Passo

1. **Navegação Chat/Git** — `app/lib/presentation/desktop/shared/widgets/workspace_rail.dart` → `WorkspaceRail`
   O rail permanente troca `_ShellScreenState._section` entre `WorkspaceSection.chat` e `.git`. A área central (`desktop_view.dart` → `_buildCenter`) monta `GitWorkspace` sem destruir o `ChatCubit`.

2. **Montagem e sincronização** — `app/lib/presentation/desktop/view/desktop_view.dart` → `_ShellScreenState.initState` / `MultiBlocListener`
   Resolve `GitCubit` e `GitAssistantCubit` no `AppInjector`. Mudança de raiz chama `GitCubit.setRoot`. Mudança de host/modelo/raiz/permissões chama `GitAssistantCubit.attachSession` (sessão própria, conversa zerada). `modelState`/`connecting` atualizam `GitAssistantCubit.updateReadiness` em paralelo ao chat.

3. **Descoberta e snapshot** — `app/lib/presentation/desktop/git/view_model/git_cubit.dart` → `GitCubit.setRoot`
   Emite `GitLoading` (preserva `GitLoaded` anterior). `GitRepository.loadSnapshot` → `GitDataSource` → `GitClient.loadSnapshot`. `GitClient.discover` compara `rev-parse --show-toplevel` com a raiz resolvida.

4. **Estados do repositório** — `git_cubit.dart` + `git_workspace.dart`
   `GitRepositoryKind.valid` → `GitLoaded` (seleções sobrevivem se a ref/commit/arquivo ainda existe). `notRepository` / `repositoryOutsideRoot` / erro → telas com “Tentar novamente”. Sem raiz → `GitEmpty`.

5. **Navegação visual, preview e troca de branch** — `git_workspace.dart` + `git_branches_panel.dart` / `git_commit_graph.dart` / `git_commit_inspector.dart` / `git_worktree_panel.dart`
   Refs, grafo (histórico inicial limitado, `loadMore` pagina), inspector e worktree. A área ampla reforça a hierarquia visual com barra “Histórico · Grafo”, painel “Detalhes” e “Mesa de trabalho”; o cabeçalho mantém status, branch, métricas, Fetch, Salvador e refresh. A branch atual abre somente as demais branches locais; a escolha chama `GitCubit.checkoutBranch`, que dispara a operação tipada normal e recarrega o snapshot no sucesso. Largura &lt; 840 recolhe branches e abre inspector como gaveta. O clique do worktree chama `GitCubit.selectFile` e o callback `onOpenFile` recebido do shell; `_ShellScreenState._openFilePreview` reutiliza `FileExplorerCubit.openPreview` e abre `FilePreviewDialog` com o conteúdo atual do arquivo. A seleção não dispara Git e o preview não usa shell nem `git show`.

6. **Abrir o assistente** — `git_workspace.dart` → `_GitHeader` + `git_assistant_cubit.dart` → `openDrawer`
   O botão preenchido “Pedir ao Salvador” só abre o drawer; a seleção Git permanece. Chips de branch/commit/arquivo escutam `GitCubit` e `GitAssistantCubit`.

7. **Envio contextual** — `git_assistant_drawer.dart` → `_send`
   Mesmo fluxo seguro de `_ShellScreenState._send`: se o modelo está parado, `WorkspaceCubit.startModel`; só envia se ficar `running`, e afirma readiness no Cubit. Serializa `serializeGitContext(snapshot, selectedRef, selectedCommitHash, selectedFilePath)` e chama `GitAssistantCubit.send`.

8. **Sessão Git da LLM** — `git_assistant_datasource.dart` → `configureSession` / `send`
   `AgentSession` com `GitProfile()`, `allowCommands: false` (mesmo se as permissões do chat permitem shell) e `allowEdit` copiado para resolver conflitos. O prompt é `contexto + input`. Consultas Git leem pelo `GitClient`; a ferramenta `git` valida os argumentos fixos, executa ações normais e registra em `AgentTurnResult.proposals` apenas ações arriscadas, devolvendo “Aguardando aprovacao na interface.” quando a revisão é necessária.

9. **Revisão** — `git_action_review_dialog.dart` → `GitActionReviewDialog`
   Tipo, ref, caminhos, mensagem e impacto por risco: normal é local; ações arriscadas `fetch`/`pull`/`push`/`pushForce` são de rede; as demais arriscadas são destrutivas. Abrir o dialog não executa. Cancelar no chip ou no dialog chama `dismissProposal` e não toca `GitRepository.executeAction`.

10. **Execução e refresh** — `git_cubit.dart` → `executeApproved`
    Bloqueia concorrência (`executingAction`). `GitRepository.executeAction` → `GitActionExecutor.execute` (`git -C <raiz> <args fixos>`). Sucesso: limpa execução, `refresh()` recarrega branches/grafo/worktree/inspector. Falha: `actionError` no banner, snapshot intacto, drawer e proposta pendente permanecem. Fetch do cabeçalho constrói `GitActionProposal(type: fetch)` e entra no mesmo dialog.

### Caminhos alternativos

- **Sem raiz:** `GitEmpty` — “Selecione um projeto para ver o status Git.”
- **Não é repositório / top-level acima da raiz:** `GitNotRepository` / `GitRepositoryOutsideRoot` com o caminho real e botão de refresh; ações desabilitadas.
- **Falha de processo/parsing Git:** `GitFailure` com a mensagem de `GitFailureException`.
- **Modelo parado no envio do assistente:** `_send` tenta `startModel`; se falhar, o texto fica no composer e nada vai à LLM.
- **Sessão não pronta:** `GitAssistantCubit.send` emite `GitAssistantErrorKind.sessionNotReady` sem chamar o repositório.
- **Falha Ollama/agente no assistente:** `GitAssistantErrorKind.sendFailed`; mensagens anteriores permanecem.
- **Ação Git inválida da LLM:** `GitActionTool` lança `ToolException` → `ERRO: <motivo>` para o modelo corrigir; nada aparece na UI.
- **Fetch/merge/rebase falha após confirmar:** banner `git-action-error-banner`; sem abort/reset automático.
- **Detached HEAD:** cabeçalho “HEAD desanexado”; snapshot continua válido.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Núcleo Git | `lib/src/git.dart` | `GitClient` (snapshot somente leitura), `GitActionType`/`GitActionProposal`, `GitActionExecutor`, `serializeGitContext` |
| Ferramentas | `lib/src/tools.dart` | `GitProfile`, consultas Git e ferramenta tipada `git`; `run_command` omitido quando o perfil Git está ativo |
| Agente | `lib/src/agent.dart` | `AgentSession` com perfil Git opcional; `AgentTurnResult.proposals` |
| Domínio | `app/lib/domain/interfaces/git_repository.dart` | Snapshot, paginação e `executeAction` aprovada |
| Domínio | `app/lib/domain/interfaces/git_assistant_repository.dart` | Sessão dedicada: configure/send/clear + atividades |
| Dados | `app/lib/data/datasources/git_datasource.dart` | Adapta `GitClient`/`GitActionExecutor` à raiz |
| Dados | `app/lib/data/datasources/git_assistant_datasource.dart` | `AgentSession` própria, `allowCommands: false`, contexto concatenado |
| Dados | `app/lib/data/repositories/git_repository_impl.dart` | `GitException`/`ProcessException` → `GitFailureException` |
| Dados | `app/lib/data/repositories/git_assistant_repository_impl.dart` | Falhas do agente/Ollama/Git → `Result<T>` |
| Estado | `app/lib/presentation/desktop/git/view_model/git_{cubit,state}.dart` | Snapshot, seleção, paginação, troca validada para branch local e `executeApproved` |
| Estado | `app/lib/presentation/desktop/git/view_model/git_assistant_{cubit,state}.dart` | Drawer, mensagens, propostas, readiness |
| Apresentação | `app/lib/presentation/desktop/git/content/git_workspace.dart` | Shell Git, cabeçalho de status/branch/métricas, seletor da branch local, Fetch, botão Pedir ao Salvador, banner de erro e callback de preview do worktree |
| Apresentação compartilhada | `app/lib/presentation/desktop/view/desktop_view.dart` + `chat/widgets/preview_pane.dart` | Lê o arquivo pelo `FileExplorerCubit` e exibe `FilePreviewDialog` ou erro sobre o workspace Git |
| Apresentação | `app/lib/presentation/desktop/git/widgets/git_assistant_drawer.dart` | Conversa, chips, composer, propostas |
| Apresentação | `app/lib/presentation/desktop/git/content/git_action_review_dialog.dart` | Revisão Cancelar/Confirmar |
| Configuração | `app/lib/config/inject/app_injector.dart` | Data sources/repos singleton; Cubits factory |
| Testes | `test/git_test.dart`, `test/salvador_cli_test.dart` | Args exatos, enum fechado, sessão sem `run_command` |
| Testes | `app/test/presentation/git/`, `app/test/salvador_desktop_app_test.dart` | Cubits, drawer, confirmação, conversas independentes e encaminhamento de arquivo Git ao preview compartilhado |

## Regras de Negócio Relevantes

- **Top-level tem que ser a raiz** — `lib/src/git.dart` (`GitClient.discover`): repositório acima da pasta vinculada não habilita o workspace nem ações.
- **Git sempre por argv, nunca shell** — `GitClient` e `GitActionExecutor` usam `Process.run('git', argumentos)` com `runInShell: false`.
- **Risco é fixo no código** — `GitActionType.risk` não vem do modelo: operações normais executam pelo `GitActionTool`; operações arriscadas exigem proposta ou confirmação.
- **Troca restrita à branch local conhecida** — `git_cubit.dart`/`git_workspace.dart`: o menu omite a branch atual, refs remotas e tags; `checkoutBranch` rejeita qualquer nome que não corresponda a uma branch local do snapshot antes de executar `git checkout`.
- **Revisão por impacto** — `GitActionReviewDialog` deriva local/rede/destrutivo de `proposal.risk` e de uma coleção centralizada dos quatro tipos de rede, sem confiar em texto ou argumentos do modelo.
- **Enum fechado e expandido** — `GitActionType` aceita operações Git suportadas por argumentos fixos, incluindo push, reset, clean, tags, stashes, remotos e ações de recuperação.
- **Sessão Git sem `run_command`** — `ToolRegistry`: com `GitProfile`, comandos de shell não entram mesmo se `allowCommands` for true; `GitAssistantDataSource` força `allowCommands: false`.
- **Contexto é a seleção, não o snapshot** — `serializeGitContext` manda resumo + ref/commit/arquivo selecionados, com `[TRUNCADO]` / `[... mais N]`; o system prompt de sete linhas em `prompt.dart` não muda.
- **Refresh só no sucesso** — `GitCubit.executeApproved`: falha preserva `GitLoaded.snapshot` e preenche `actionError`.
- **Chat e Git são sessões distintas** — `ChatCubit` e `GitAssistantCubit` têm datasources/`AgentSession` próprios; alternar o rail não mistura mensagens.
- **Edição de arquivo no Git segue `allowEdit`** — write/replace ficam disponíveis na sessão Git só se as permissões do workspace permitirem (conflitos).
- **Conteúdo do worktree segue o leitor confinado do workspace** — `git_worktree_panel.dart` encaminha apenas o caminho; `desktop_view.dart` usa `FileExplorerCubit.openPreview`, portanto a leitura continua sob `ToolRegistry` com `AgentPermissions.readOnly` e erros aparecem no diálogo.

## Dependências Externas

- Binário `git` no PATH (`Process.run`).
- Servidor Ollama (mesmos endpoints do chat) só no assistente Git, não no snapshot.

## Observações

- **`GitDataSource.executeAction` instancia um `GitActionExecutor()` novo**, sem reutilizar o `GitClient` injetado no datasource; testes de execução precisam fakear o repositório/executor, não só o runner do client de snapshot.
- **Timeouts divergem:** `GitClient` usa 15 s nas leituras; `GitActionExecutor` usa 30 s nas mutações.
- **Merge/rebase que deixam conflitos não disparam abort/reset.** O snapshot (possivelmente sujo) é recarregado só se a ação retornar sucesso; falha mostra o stderr e mantém o estado anterior em memória.
- **`GitActionReviewDialog` vive em `git/content/`**, embora o plano listasse `widgets/`; o drawer e o Fetch do header reutilizam o mesmo dialog.
