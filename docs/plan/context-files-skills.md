# Plano: Contexto de arquivos — skills e AGENTS.md

> **Objetivo:** O sistema passa a identificar skills em `.agents/skills/*/SKILL.md` (listadas ao digitar `/` no CLI e no app) e ler o `AGENTS.md` da raiz automaticamente (injetado no system prompt), com chamada manual (`/skill` no prompt) e automática (tool `use_skill` que o modelo decide invocar); tudo ligado por um toggle único — flag `--no-context` na CLI e switch persistido no app.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/app-desktop.md`

## Contexto

O pacote `salvador_cli` já tem o padrão exato deste recurso em `FileMentionService` (lib/src/file_mentions.dart): indexação de arquivos, sugestão e injeção de conteúdo via `MentionExpansion`. O `TerminalInput` já renderiza o menu `/` a partir de uma lista de `TerminalCommand`, e o app já faz sugestões no composer por `FileExplorerCubit` → `WorkspaceDataSource`. A novidade é a leitura de dois arquivos especiais (`AGENTS.md` na raiz e `SKILL.md` em `.agents/skills/`) e uma ferramenta nova no `ToolRegistry` para o modelo buscar skills sozinho.

## Design de Origem

- **Decisão aprovada:** módulo novo `ContextFilesService` no pacote + tool `use_skill` (chamada automática pelo modelo, descrição lista as skills disponíveis) + expansão manual `/skill` (mesma mecânica de `@arquivo`); AGENTS.md anexado ao system prompt pelo `AgentSession`; toggle único liga/desliga tudo — `--no-context` na CLI (padrão habilitado) e `contextFilesEnabled` persistido no app (default `true`).
- **Alternativas descartadas:** dois toggles separados (AGENTS.md × skills) — o pedido trata a leitura como uma coisa só.
- **Tipo de mudança:** Logic

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `test/context_files_test.dart` | criar | Contrato do serviço e da tool `use_skill` |
| `test/config_test.dart` | criar | Parsing de `--no-context` |
| `lib/src/context_files.dart` | criar | `SkillInfo(nome, descricao)` + `ContextFilesService(root)`: `discoverSkills()` (frontmatter `description:`, fallback nome, cache), `agentsMdContext()` (`AGENTS.md` da raiz com confinamento por symlink, cap 64 KiB, binário/UTF-8 inválido → `null`, rotulado), `expand(input)` → `MentionExpansion`, `skillContent(nome)` (trunca a 64 KiB com `[TRUNCADO]`, confinamento igual ao de `FileMentionService._safeFile`) |
| `lib/src/tools.dart` | alterar | `UseSkillTool` + `ToolRegistry(root, permissions, contextFiles:)` registra a tool só com serviço; `ERRO: skill nao encontrada: X. Skills disponiveis: ...` |
| `lib/src/agent.dart` | alterar | `AgentSession(contextFiles: ContextFilesService?)`: anexa `agentsMdContext()` à mensagem de sistema e repassa o serviço ao `ToolRegistry` |
| `lib/src/config.dart` | alterar | Flag `--no-context` → `CliConfig.contextFiles` (default `true`); `cliUsage` documenta a flag |
| `lib/salvador_cli.dart` | alterar | Exporta `context_files.dart` |
| `bin/salvador_cli.dart` | alterar | Cria o serviço quando habilitado; `TerminalCommand('/skill', descricao)` junto de `_chatCommands`; expande `/skill` antes de `sendDetailed` (comandos built-in primeiro); avisos em stderr |
| `app/lib/domain/entities/desktop_preferences_entity.dart` | alterar | Campo `contextFilesEnabled` (default `true`), `copyWith`, `==`, `hashCode` |
| `app/lib/common/services/desktop_storage_service.dart` | alterar | JSON `context_files_enabled` (leitura defensiva default `true`) |
| `app/lib/presentation/desktop/view_model/workspace_state.dart` | alterar | Campo `contextFilesEnabled` + `copyWith` |
| `app/lib/presentation/desktop/view_model/workspace_cubit.dart` | alterar | `initialize`/`saveSettings`/`_persist` carregam e gravam o campo |
| `app/lib/presentation/desktop/view_model/settings_state.dart` | alterar | Campo `contextFilesEnabled` + `copyWith` |
| `app/lib/presentation/desktop/view_model/settings_cubit.dart` | alterar | `updateContextFilesEnabled` + campo no `save` |
| `app/lib/presentation/desktop/content/settings_dialog.dart` | alterar | Seção "Contexto" com switch (`settings-context-files`) + `_applySettings` |
| `app/lib/domain/interfaces/chat_repository.dart` + `app/lib/data/repositories/chat_repository_impl.dart` | alterar | `configureSession` ganha `contextFilesEnabled` |
| `app/lib/presentation/desktop/view_model/chat_cubit.dart` | alterar | `attachSession` repassa o toggle |
| `app/lib/data/datasources/chat_agent_datasource.dart` | alterar | Cria `ContextFilesService` (root + toggle), passa ao `AgentSession`, `send` expande `/skill` e mescla avisos no `AgentTurnResult` |
| `app/lib/data/datasources/workspace_datasource.dart` | alterar | `ContextFilesService` cacheado por raiz; `skillSuggestions`/`insertSkill` |
| `app/lib/domain/interfaces/workspace_repository.dart` + `app/lib/data/repositories/workspace_repository_impl.dart` | alterar | Pass-through de `skillSuggestions`/`insertSkill` |
| `app/lib/presentation/desktop/view_model/file_explorer_cubit.dart` | alterar | `skillSuggestions`/`insertSkill` |
| `app/lib/presentation/desktop/view/desktop_view.dart` | alterar | `_updateSuggestions`/`_insertSuggestion` alternam arquivo × skill pelo prefixo `/` + toggle; listener passa `contextFilesEnabled` ao `attachSession` |
| `docs/flow/app-desktop.md` | alterar | Atualizar fluxo (ver Fase 6) |

## Fases

### Fase 1 — Testes do pacote (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Criar `test/context_files_test.dart` com diretório temporário:
  - `discoverSkills`: `.agents/skills/a/SKILL.md` e `b/SKILL.md` com frontmatter `description:` → 2 skills com descrições corretas; `SKILL.md` sem frontmatter → descrição vazia; pasta sem `SKILL.md` e arquivo solto em `.agents` → ignorados; sem `.agents/skills` → lista vazia
  - `agentsMdContext`: `AGENTS.md` presente → `null` rotulado com "Contexto do projeto (AGENTS.md)"; ausente → `null`; acima de 64 KiB → `null`; binário (byte NUL) → `null`
  - `expand`: `/flow como funciona o login` → conteúdo injetado no fim e texto preservado, sem avisos; `/naoexiste` → aviso e texto preservado; `/` sozinho → inalterado; sem `/` → inalterado; duas skills numa linha → ambas injetadas
  - `skillContent`: nome conhecido → conteúdo; desconhecido → `null`; `../` no nome → `null` (fora da raiz); arquivo acima de 64 KiB → truncado com `[TRUNCADO]`
- [x] Criar `test/config_test.dart`: `CliConfig.parse([])` → `contextFiles == true`; `CliConfig.parse(['--no-context'])` → `contextFiles == false`; `cliUsage` contém `--no-context`
- [x] Verificação: `dart test test/context_files_test.dart` compila e falha só por referências a `ContextFilesService`/`SkillInfo`/`CliConfig.contextFiles` ainda inexistentes (não por erro de sintaxe)

### Fase 2 — Implementação do pacote (fazer os testes passarem)

- [x] Criar `lib/src/context_files.dart` conforme o contrato da Fase 1 (confinamento de leitura com resolução de symlink, mesmo padrão de `FileMentionService._safeFile`)
- [x] Em `lib/src/tools.dart`: `UseSkillTool(root, contextFiles)` — definição `use_skill` com descrição dinâmica listando as skills disponíveis; execução via `skillContent`, `ToolException('skill nao encontrada: $name. Skills disponiveis: a, b, c')`; registrar em `ToolRegistry` só quando `contextFiles != null`
- [x] Em `lib/src/agent.dart`: `AgentSession` aceita `contextFiles` e anexa `contextFiles.agentsMdContext()` à mensagem de sistema (após a linha "Raiz: ...")
- [x] Em `lib/src/config.dart`: flag `--no-context` e linha no `cliUsage`
- [x] Em `lib/salvador_cli.dart`: export de `context_files.dart`
- [x] Verificação: `dart analyze` limpo e `dart test` passando (incluindo teste da tool via `ToolRegistry`: sucesso, nome inexistente com lista, argumento ausente, `ToolRegistry` sem serviço → `ERRO: ferramenta desconhecida`)

### Fase 3 — CLI

- [x] Em `bin/salvador_cli.dart`: criar `ContextFilesService(config.root)` quando `config.contextFiles`; montar `TerminalCommand('/nome', descricao)` das skills junto de `_chatCommands`; passar `contextFiles` ao `AgentSession`; atualizar o hint "Digite / para ver os comandos e skills"
- [x] No loop do chat: após checagens de `/clear`/`/exit`/`/quit`, quando o texto começar com `/`, chamar `contextFiles.expand` e imprimir os avisos em stderr antes do envio
- [x] Verificação: `dart analyze` limpo e `dart test` passando

### Fase 4 — Testes do app (contrato antes da implementação)

- [x] `app/test/domain/entities/desktop_preferences_entity_test.dart`: default `true`, `copyWith` para `false`/`true`, `==` distingue o campo
- [x] `app/test/common/services/desktop_storage_service_test.dart`: roundtrip grava/lê o campo; JSON sem o campo → `true`
- [x] `app/test/presentation/desktop/settings_cubit_test.dart`: `updateContextFilesEnabled` e o valor chega ao callback de `save`
- [x] `app/test/presentation/desktop/workspace_cubit_test.dart`: `initialize` restaura e `saveSettings` persiste o campo (via fake de storage)
- [x] Atualizar fakes para as novas assinaturas: `app/test/presentation/desktop/fakes/fake_chat_repository.dart`, `app/test/data/chat/fakes/fake_chat_agent_datasource.dart` (`contextFilesEnabled`), `app/test/data/workspace/fakes/fake_workspace_datasource.dart` e `app/test/presentation/desktop/fakes/fake_workspace_repository.dart` (`skillSuggestions`/`insertSkill`)
- [x] `app/test/presentation/desktop/file_explorer_cubit_test.dart`: `skillSuggestions` devolve nomes com `/` e `insertSkill` substitui do início ao cursor
- [x] Verificação: `cd app && flutter test` compila e falha por causa das referências novas (assinaturas/entidade), não por erro de sintaxe

### Fase 5 — Implementação do app

- [x] `desktop_preferences_entity.dart`, `desktop_storage_service.dart`, `workspace_state.dart`, `workspace_cubit.dart`, `settings_state.dart`, `settings_cubit.dart`: propagar `contextFilesEnabled`
- [x] `settings_dialog.dart`: seção "Contexto" com `SwitchListTile` (key `settings-context-files`, subtítulo explicando AGENTS.md + skills) e `_applySettings` repassando o campo
- [x] `chat_repository.dart`, `chat_repository_impl.dart`, `chat_cubit.dart`, `chat_agent_datasource.dart`: `configureSession(contextFilesEnabled:)`; datasource cria o serviço (root não nulo + toggle) e expande `/skill` no `send` mesclando avisos ao `AgentTurnResult`
- [x] `workspace_datasource.dart`, `workspace_repository.dart`, `workspace_repository_impl.dart`, `file_explorer_cubit.dart`: `skillSuggestions` (slash ativo: texto começa com `/` e sem espaço, igual à regra do `TerminalInput`) e `insertSkill` (substitui do início ao cursor por `/nome `)
- [x] `desktop_view.dart`: `_updateSuggestions`/`_insertSuggestion` alternam por prefixo `/` (arquivos quando não começa com `/` ou toggle desligado); listener do `WorkspaceCubit` passa `contextFilesEnabled` ao `attachSession` e o inclui no `listenWhen`
- [ ] Verificação: `cd app && flutter analyze` limpo e `flutter test` passando

> Execução: `flutter analyze` passou e os testes focados nesta alteração passaram. A suíte completa ainda falha em testes de widget/layout preexistentes em `salvador_desktop_app_test.dart` (rails/top bar/composer estreitos e controles de painel ausentes), já reproduzidos antes da implementação; não corrigidos por estarem fora deste plano.

### Fase 6 — Atualizar flow

- [x] Em `docs/flow/app-desktop.md`: resumo menciona contexto de arquivos; passo 5 (attachSession ganha `contextFilesEnabled`); passo 7 (switch "Contexto"); passo 8 (expansão `/skill` no datasource e tool `use_skill`); passo 10 (sugestões de skill); regra de negócio nova sobre o toggle; tabela "Arquivos Envolvidos" ganha `lib/src/context_files.dart`
- [x] Verificação: `grep -n 'contextFilesEnabled\|use_skill\|skillSuggestions' docs/flow/app-desktop.md` encontra os termos nas seções citadas (passos 5/7/8/10, regras e tabela)

## Critérios de Sucesso

- [ ] CLI com contexto habilitado: `/` lista skills, `/skill` injeta o SKILL.md, AGENTS.md entra no system prompt; `--no-context` desliga tudo
- [ ] App: switch em Configurações liga/desliga e persiste; `/` no composer lista skills; o modelo pode chamar `use_skill` sozinho
- [x] `dart analyze` e `dart test` sem erros
- [ ] `cd app && flutter analyze` e `flutter test` sem erros
- [ ] _(manual — feito pelo usuário)_ Validação funcional no CLI e no app

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Modelos pequenos não chamam `use_skill` espontaneamente (tool-calling frágil) | Média | O caminho manual `/skill` independe do modelo; descrição da tool curta e objetiva |
| System prompt e AGENTS.md somados estouram o contexto de modelos pequenos | Baixa | Cap de 64 KiB no AGENTS.md (skip silencioso) e no SKILL.md (trunca); prompt atual continua enxuto |
| JSON persistido antigo sem o campo | Média | Leitura defensiva default `true` (testada na Fase 4) |
| Scan de `.agents/skills/` a cada tecla no composer | Baixa | Cache por raiz no `WorkspaceDataSource` (padrão já usado para `FileMentionService`) |

## Rollback

- Pacote e CLI: reverter commits — mudanças em `lib/src/` e `bin/` são aditivas (`contextFiles: null` preserva o comportamento atual)
- App: reverter commits — o campo novo é aditivo; JSON persistido com `context_files_enabled` continua legível pelo código antigo (leitura defensiva ignora chaves desconhecidas)
