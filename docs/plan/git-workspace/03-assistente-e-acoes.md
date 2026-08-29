# Git Workspace Visual com Assistente Local — Parte 3: Assistente e Ações Seguras

> **Objetivo da parte:** permitir pedir análises e operações Git à LLM dentro do workspace, convertendo mutações em propostas tipadas que só executam após revisão explícita.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** partes 1 e 2 concluídas

## Contexto

O agente atual executa imediatamente qualquer tool call exposta e pode oferecer `run_command`, portanto não serve como fronteira de aprovação para Git. A solução usa uma sessão dedicada: leitura/edição de arquivos respeita `AgentPermissions`, comandos de shell ficam sempre desligados, consultas Git são tipadas e mutações apenas geram propostas para o `GitCubit` executar após confirmação.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/git.dart` | modificar | `GitAction`, proposta validada, execução tipada e serialização de contexto |
| `lib/src/tools.dart` | modificar | Ferramentas de consulta Git e `propose_git_action` sem efeito colateral |
| `lib/src/agent.dart` | modificar | Habilitar perfil Git opcional e devolver propostas no resultado do turno |
| `test/git_test.dart` | modificar | Ações permitidas, argumentos exatos e bloqueio das operações ausentes |
| `test/salvador_cli_test.dart` | modificar | Superfície da sessão Git, propostas e ausência de `run_command` |
| `app/lib/domain/interfaces/git_repository.dart` | modificar | Executar ação aprovada e atualizar snapshot |
| `app/lib/domain/interfaces/git_assistant_repository.dart` | criar | Contrato da sessão dedicada do assistente Git |
| `app/lib/data/datasources/git_assistant_datasource.dart` | criar | `AgentSession` com perfil Git, contexto limitado e stream de atividades |
| `app/lib/data/repositories/git_assistant_repository_impl.dart` | criar | Adaptar falhas do agente para `Result<T>` |
| `app/lib/presentation/desktop/view_model/git_assistant_cubit.dart` | criar | Mensagens, envio contextual, propostas pendentes e estado do drawer |
| `app/lib/presentation/desktop/view_model/git_assistant_state.dart` | criar | Estado imutável da conversa Git e propostas |
| `app/lib/presentation/desktop/view_model/git_cubit.dart` | modificar | Executar proposta confirmada, refresh e erro preservando snapshot |
| `app/lib/presentation/desktop/widgets/git_assistant_drawer.dart` | criar | Conversa contextual e chips da seleção atual |
| `app/lib/presentation/desktop/widgets/git_action_review_dialog.dart` | criar | Revisão e confirmação de ação local/fetch |
| `app/lib/presentation/desktop/content/git_workspace.dart` | modificar | Botões Fetch/Pedir ao Salvador e integração drawer/dialog |
| `app/lib/config/inject/app_injector.dart` | modificar | Registrar sessão/repository/Cubit dedicados |
| `docs/flow/app-desktop.md` | modificar | Documentar navegação e sincronização Git no shell |
| `docs/flow/git-workspace.md` | criar | Flow ponta a ponta de snapshot, assistente, aprovação e refresh |

## Fases

### Fase 1 — Testes dos contratos de ferramentas e ações

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Declarar em `lib/src/git.dart`, `lib/src/tools.dart` e `lib/src/agent.dart` os enums, tipos de proposta e assinaturas opcionais do perfil Git com corpos provisórios, preservando defaults das sessões normais para que os testes compilem antes da lógica.
- [x] Estender `test/git_test.dart` para `GitAction` de fetch, criar/trocar branch, stage, unstage, commit, merge e rebase, verificando listas exatas de argumentos sem shell.
- [x] Testar validações de branch/ref/caminho/mensagem vazia, rejeição de caminho fora da raiz e impossibilidade de representar reset hard, clean, delete, push ou force no enum público.
- [x] Estender `test/salvador_cli_test.dart` para o perfil Git expor consultas estruturadas e `propose_git_action`, sem expor `run_command` mesmo quando as permissões normais permitem comandos.
- [x] Testar que `propose_git_action` só acumula `GitActionProposal` em `AgentTurnResult`, não chama o runner e devolve à LLM uma mensagem de aprovação pendente.
- [x] Testar que o perfil Git respeita `allowEdit` para `write_file`/`replace_in_file` durante resolução de conflitos.
- [x] Verificação: `dart test test/git_test.dart test/salvador_cli_test.dart` compila e falha somente pelas APIs ainda não implementadas.

### Fase 2 — Implementar ferramentas Git e execução tipada

- [x] Adicionar em `lib/src/git.dart` `GitActionType`, `GitActionProposal` e executor que converte somente variantes permitidas em argumentos fixos para `GitClient`.
- [x] Implementar validação de refs e caminhos relativos antes do processo; não adicionar flags destrutivas, push/pull ou comandos livres à API.
- [x] Adicionar em `lib/src/tools.dart` ferramentas enxutas de status/log/diff/show e `propose_git_action`, compartilhando `GitClient` e limites de saída.
- [x] Estender `ToolRegistry`/`AgentSession` em `lib/src/tools.dart` e `lib/src/agent.dart` com perfil Git opcional, mantendo as definições atuais inalteradas em sessões normais.
- [x] Acumular propostas no turno e retorná-las em `AgentTurnResult`; erros das ferramentas continuam como `ERRO: <motivo>` para a LLM corrigir argumentos.
- [x] Verificação: `dart test test/git_test.dart test/salvador_cli_test.dart` passa e confirma zero invocações do runner para propostas não aprovadas.

### Fase 3 — Testes da sessão dedicada e aprovação no app

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Declarar as assinaturas mínimas de `GitAssistantRepository`, `GitAssistantRepositoryImpl`, `GitAssistantState` e `GitAssistantCubit` nos caminhos planejados, com corpos provisórios, para os testes falharem por comportamento e não por símbolos ausentes.
- [x] Criar fakes e `app/test/data/git/git_assistant_repository_impl_test.dart` cobrindo configuração com raiz/modelo, contexto selecionado, resposta, proposta e falhas do agente/Ollama.
- [x] Criar `app/test/presentation/desktop/git_assistant_cubit_test.dart` para abrir/fechar drawer, enviar seleção contextual, impedir envio sem readiness, preservar mensagens e registrar propostas pendentes.
- [x] Estender `app/test/presentation/desktop/git_cubit_test.dart` para confirmação/cancelamento, sucesso com refresh, falha preservando snapshot e bloqueio de execução concorrente.
- [x] Definir no fake que cancelar nunca chama `GitRepository.execute`, e confirmar chama exatamente uma vez com a proposta exibida.
- [x] Testar serialização contextual limitada a ref/commit/arquivos selecionados, com marcador de truncamento para diff grande e sem despejar o snapshot inteiro.
- [x] Verificação: os testes compilam e falham apenas pela integração ainda ausente.

### Fase 4 — Implementar sessão, estado e DI do assistente

- [x] Criar `GitAssistantRepository` e implementação/data source nos caminhos planejados, com `AgentSession` próprio, `allowCommands: false`, ferramentas Git habilitadas e edição de arquivo conforme `AgentPermissions.allowEdit`.
- [x] Implementar `GitAssistantCubit/State` com mensagens independentes do chat principal, readiness, contexto selecionado, propostas pendentes, atividades e erros tipados.
- [x] Construir o prompt contextual no datasource a partir de `GitSnapshot` + seleção, com limites explícitos e sem alterar `lib/src/prompt.dart`.
- [x] Implementar `GitRepository.execute` e `GitCubit.executeApproved`, atualizando o snapshot somente após sucesso e mantendo erro apresentável sem descartar dados anteriores.
- [x] Registrar data source/repository/Cubit dedicados em `app_injector.dart`; a View continua responsável por sincronizar raiz, modelo, permissões e readiness entre Cubits.
- [x] Verificação: `cd app && flutter test test/data/git/git_assistant_repository_impl_test.dart test/presentation/desktop/git_assistant_cubit_test.dart test/presentation/desktop/git_cubit_test.dart` passa.

### Fase 5 — Implementar drawer, revisão e ações

- [x] Criar `GitAssistantDrawer` com histórico próprio, composer, chips de branch/commit/arquivo, atividades, propostas e estados modelo parado/enviando/erro.
- [x] Adicionar “Pedir ao Salvador” em `git_workspace.dart`; abrir o drawer sem remover a seleção e iniciar o modelo pelo mesmo fluxo seguro usado em `_ShellScreenState._send` antes de enviar.
- [x] Criar `GitActionReviewDialog` mostrando tipo, refs, caminhos, mensagem de commit, impacto local/rede e botões Cancelar/Confirmar; nenhuma proposta executa no callback de abertura.
- [x] Ligar confirmação a `GitCubit.executeApproved` e, após sucesso, atualizar branches, grafo, worktree e inspector; exibir falha no workspace sem fechar o contexto do assistente.
- [x] Implementar o botão Fetch como ação explícita com loading/erro; propostas de fetch passam pelo mesmo dialog por envolver rede.
- [x] Estender `app/test/presentation/desktop/git_workspace_test.dart` e `app/test/salvador_desktop_app_test.dart` para drawer, contexto, cancelamento, confirmação, refresh e preservação do chat principal.
- [x] Verificação: os widget tests confirmam que apenas Confirmar chama o repository e que Chat/Git mantêm conversas independentes.

### Fase 6 — Segurança, documentação e verificação final

- [x] Executar `dart format` nos Dart alterados e `git diff --check`.
- [x] Executar `dart analyze` e `dart test`, incluindo as asserções de ausência de shell, force/reset/clean/delete/push e confinamento da raiz.
- [x] Executar `cd app && flutter analyze` e `cd app && flutter test`, sem iniciar app, Ollama, servidor, emulador ou dispositivo.
- [x] Atualizar `docs/flow/app-desktop.md` nas seções de montagem do shell, sincronização entre Cubits, envio ao agente, arquivos envolvidos e regras de negócio.
- [x] Invocar a skill `flow` para criar `docs/flow/git-workspace.md` cobrindo raiz → snapshot → seleção → contexto LLM → proposta → revisão → execução → refresh, incluindo erros e limites.
- [x] Verificação: todos os comandos passam, os testes provam que propostas não executam sem confirmação e os dois flows descrevem os caminhos e regras novos.
- [x] Checkpoint: commit final do Git Workspace + resumo das três partes concluídas.

## Critérios de Sucesso

- [x] A LLM consulta Git por ferramentas estruturadas sem receber `run_command` na sessão dedicada.
- [x] Toda mutação proposta exige revisão explícita e cancelar produz zero efeitos.
- [x] Somente fetch, criar/trocar branch, stage, unstage, commit, merge e rebase são representáveis na primeira versão.
- [x] O contexto enviado contém apenas a seleção e marca truncamentos de forma visível.
- [x] Após uma ação aprovada, branches, grafo e worktree são recarregados.
- [x] Chat normal e assistente Git mantêm sessões independentes.
- [x] `dart analyze`, `dart test`, `cd app && flutter analyze` e `cd app && flutter test` passam.
- [ ] _(manual — feito pelo usuário)_ Testar pedir comparação de branches, explicar commit, criar/trocar branch, preparar commit e cancelar uma proposta.
- [ ] _(manual — feito pelo usuário)_ Testar resolução de conflito com edição habilitada, falha de merge/rebase, detached HEAD e Fetch sem rede.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Modelo emitir proposta inválida ou incompleta | Alta | Schema com enum fechado, validação antes de exibir e resultado `ERRO:` permitindo nova tentativa |
| Sessão Git interferir no chat principal | Média | Datasource/Cubit próprios e widget test alternando modos com mensagens em ambos |
| Commit/merge/rebase deixar repositório em estado intermediário | Média | Exibir resultado real, atualizar snapshot mesmo após falha e nunca executar abort/reset automaticamente |
| Diff grande consumir contexto do modelo pequeno | Alta | Seleção explícita, resumo estruturado, limites por campo e marcador de truncamento |

## Rollback

Reverter o commit desta parte remove sessão, tools mutáveis/propostas e UI de confirmação, preservando o Git Workspace somente leitura das partes 1 e 2. Não executar comandos Git de limpeza como parte do rollback.
