# Operações Git do Agente — Parte 2: App Desktop

> **Objetivo da parte:** o workspace Git mantém o fluxo de proposta/revisão com impacto por risco, e o chat principal do app ganha ferramentas Git com propostas revisáveis no próprio chat.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** parte 1 concluída

## Contexto

A parte 1 entregou no pacote a ferramenta `git` (normais executam direto, riscos viram proposta/confirmação) e `GitActionType` expandido. No app, `GitAssistantDataSource` já passa `GitProfile()` (default: `replacesRunCommand: true`), então o workspace absorve a ferramenta nova sem mudança de datasource — falta o dialog refletir o impacto por risco e atualizar testes. O chat principal (`ChatAgentDataSource`/`ChatCubit`/`ChatIdle`) não expõe Git hoje: precisa de perfil Git (com `run_command` preservado), propostas pendentes, execução e widgets.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/presentation/desktop/content/git_action_review_dialog.dart` | modificar | Impacto por `GitActionProposal.risk` (local/rede/destrutivo) para os tipos novos |
| `app/lib/data/datasources/chat_agent_datasource.dart` | modificar | `configureSession` com `GitClient()`, `GitProfile(replacesRunCommand: false)` e `onProposal` |
| `app/lib/presentation/desktop/view_model/chat_state.dart` | modificar | `pendingProposals` no `ChatIdle` |
| `app/lib/presentation/desktop/view_model/chat_cubit.dart` | modificar | `executeProposal` (via `GitRepository.executeAction`) e `dismissProposal` |
| `app/lib/presentation/desktop/widgets/chat_widgets.dart` | modificar | Seção de propostas pendentes no chat com Revisar/Cancelar |
| `app/lib/config/inject/app_injector.dart` | modificar | `GitRepository` no `ChatCubit` |
| Testes em `app/test/` | modificar/criar | Dialog por risco, datasource/chat com propostas, widget test de Revisar/Confirmar/Cancelar |

## Fases

### Fase 1 — Testes do workspace Git (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Criar `app/test/presentation/desktop/git_action_review_dialog_test.dart` (arquivo ausente no repositório durante a execução): impacto correto por risco — normal (local), rede (`fetch`, `pull`, `push`, `pushForce`) e destrutivo (`resetHard`, `cleanForce`, `restoreFile`, `removeFile`, `deleteBranchForce`, `deleteTag`, `stashDrop`, `amendCommit`)
- [x] Confirmar que os testes do drawer/assistente (usam fakes com `GitActionProposal` direto, não a ferramenta) seguem passando sem mudança; o swap da ferramenta ocorreu no pacote na parte 1
- [x] Verificação: o novo teste falhou antes da implementação porque o switch antigo não cobria o enum expandido da parte 1; após a implementação, ele e os testes do drawer/assistente passaram

### Fase 2 — Implementar workspace

- [x] Em `git_action_review_dialog.dart`, usar `proposal.risk` para separar impacto local de arriscado e uma coleção centralizada dos quatro tipos de rede (`fetch`, `pull`, `push`, `pushForce`) para distinguir rede de destrutivo; ajuste mecânico porque o contrato da parte 1 fixa `GitActionRisk` em `normal`/`risky`, não três níveis; manter a exibição de refs/caminhos/mensagem
- [x] Verificação: testes da Fase 1 passam; `cd app && flutter analyze` limpo

### Fase 3 — Testes do chat principal (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Estender teste do datasource do chat (`app/test/data/`): `configureSession` com raiz expõe ferramentas git; `onProposal` propaga propostas de tipos riscosos
- [x] Estender `app/test/presentation/desktop/chat_cubit_test.dart`: propostas do turno entram em `ChatIdle.pendingProposals`; `dismissProposal` remove sem chamar o repository; `executeProposal` chama `GitRepository.executeAction` exatamente uma vez com a proposta exibida e remove da lista
- [x] Widget test do chat: propostas pendentes renderizam chips; Revisar abre `GitActionReviewDialog`; Confirmar executa; Cancelar apenas remove
- [x] Verificação: antes da implementação, os testes falharam pelos contratos ausentes (`pendingProposals`, métodos do Cubit, widget e ferramentas Git no datasource); após a implementação, passaram

### Fase 4 — Implementar chat principal

- [x] Em `chat_agent_datasource.dart`: retornar as propostas do `AgentTurnResult` e passar `gitClient`/`gitProfile` quando `root != null`; o `AgentSession` já coleta `onProposal` no resultado do turno, sem stream duplicado
- [x] Em `chat_state.dart`: campo `pendingProposals` com `copyWith`; em `chat_cubit.dart`: acumular propostas no resultado do turno, `executeProposal` (chamando `GitRepository.executeAction` e limpando a lista) e `dismissProposal`; injetar `GitRepository` no construtor
- [x] Em `chat_widgets.dart`: seção de propostas pendentes (chips com `summary` e botões Revisar/Cancelar) ligada ao `GitActionReviewDialog` e aos métodos do cubit
- [x] Em `app_injector.dart`: registrar `GitRepository` no `ChatCubit`
- [x] Verificação: testes da Fase 3 passam; `cd app && flutter analyze` limpo

### Fase 5 — Flows e verificação final

- [x] Atualizar `docs/flow/git-workspace.md`: ferramenta `git` única no lugar de `propose_git_action`, execução direta de operações normais, dialog por risco (rede/destrutivo), sessão sem `run_command` mantida
- [x] Atualizar `docs/flow/app-desktop.md`: chat principal com ferramentas Git, `pendingProposals` no `ChatIdle`, execução via `GitRepository.executeAction`
- [x] `dart format` nos arquivos alterados, `git diff --check`, `dart analyze` + `dart test` e `cd app && flutter analyze && flutter test` passam
- [x] Checkpoint: commit local da parte 2 — diálogo por impacto, chat principal com propostas Git, testes e flows atualizados

## Critérios de Sucesso

- [x] Workspace Git: dialog mostra impacto local/rede/destrutivo; normais executam direto (atividade no drawer), riscos propõem
- [x] Chat principal: agente consulta Git, executa normais e mostra propostas revisáveis para riscos; `run_command` continua disponível
- [x] `dart analyze`, `dart test`, `cd app && flutter analyze` e `cd app && flutter test` passam
- [ ] _(manual — feito pelo usuário)_ No chat do app: pedir status, um commit e um push (proposta → Revisar → Confirmar/Cancelar), e conferir o impacto no dialog

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Widget test do chat depender de detalhes de layout instáveis | Média | Asserções por comportamento (chips presentes, callbacks) em vez de geometria |
| Proposta duplicada entre datasource e cubit | Baixa | `onProposal` único por sessão; lista limpa no `executeProposal`/`dismissProposal` |

## Rollback

Reverter o commit desta parte remove as mudanças do app (dialog por risco, chat com propostas); o pacote da parte 1 permanece intacto e a CLI continua funcional.
