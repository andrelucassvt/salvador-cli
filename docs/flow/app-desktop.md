---
generated_at: 2026-08-28
source_commit: 5b51277
source_state: dirty
verified_at: 2026-09-04
status: current
related_plans: ['docs/plan/salvador-desktop-clean-architecture/00-indice.md', 'docs/plan/attach-files-desktop.md', 'docs/plan/context-files-skills.md', 'docs/plan/git-workspace/00-indice.md', 'docs/plan/git-tool-operations/00-indice.md']
---

# Flow: App Desktop do Salvador

> **Resumo:** Caminho ponta a ponta do app Flutter desktop: bootstrap, estado persistido e conversa Ollama com anexos/contexto; com projeto vinculado, o chat principal oferece Git tipado junto de `run_command`, executa ações locais normais e revisa propostas arriscadas, enquanto o rail Git mantém sua sessão isolada.

## Visão Geral

O desktop segue Clean Architecture (Presentation → Domain ← Data) com injeção de dependências via GetIt (`AppInjector`). Seis Cubits dividem a responsabilidade que antes vivia inteira em um único `DesktopController` (`ChangeNotifier`, removido nesta migração):

- **`WorkspaceCubit`** — coordenador: conexão com o Ollama, seleção/ciclo de vida do modelo, pasta raiz, parâmetros de inferência, permissões e histórico de sessões persistidas. Concentra essas responsabilidades porque `DesktopPreferencesEntity` é lida/gravada como uma unidade só.
- **`ChatCubit`** — mensagens, atividades de ferramentas, envio e propostas Git pendentes do chat principal.
- **`FileExplorerCubit`** — árvore de arquivos, filtro, preview e sugestões de menção `@arquivo`.
- **`GitCubit`** — snapshot Git da raiz, seleção de ref/commit/arquivo, paginação do grafo e execução de ações já aprovadas.
- **`GitAssistantCubit`** — conversa Git independente do chat, propostas pendentes e drawer do assistente.
- **`SettingsCubit`** — estado local do formulário do diálogo de configurações (criado sob demanda, via `registerFactoryParam`, com os valores atuais do `WorkspaceState`).

Nenhum Cubit referencia outro diretamente: a sincronização entre eles acontece na View (`_ShellScreenState`, em `desktop_view.dart`), via `MultiBlocListener` — quando `WorkspaceCubit` emite uma nova raiz/modelo/permissões, a View aciona `FileExplorerCubit.setRoot(...)`, `ChatCubit.attachSession(...)`, `GitCubit.setRoot(...)` e `GitAssistantCubit.attachSession(...)`; quando `ChatCubit.newSession()` encerra uma sessão, ela recebe um callback (não uma referência a Cubit) que a View liga a `WorkspaceCubit.recordSession(...)`.

Na inicialização, `main.dart` chama `AppInjector.setupDependencies()` antes de `runApp`. O `WorkspaceCubit` restaura preferências, pasta, modelo, parâmetros de inferência, permissões, pastas recentes e resumos de sessões de um JSON versionado gravado no diretório de dados do SO (`Application Support` no macOS, `APPDATA` no Windows, `XDG_CONFIG_HOME`/`.config` no Linux). Em seguida, conecta ao servidor por HTTP — sem usar o binário `ollama` — consultando `/api/tags` e `/api/ps` para separar "servidor conectado" de "modelo carregado".

O shell tem quatro regiões: title bar customizada de 38 px no macOS, top bar de 62 px (logo, pasta, modelo, iniciar/encerrar, nova sessão, configurações), painel esquerdo escuro de atividade/sessões com rail de 50 px (navegação Chat/Git), e painel direito claro de árvore de arquivos com rail de 50 px. A área central alterna entre chat/estado vazio, preview de arquivo e o `GitWorkspace`. Tudo o que pode falhar (troca de pasta, de modelo, salvar configurações, testar servidor) só persiste após sucesso; o modelo é carregado antes de qualquer envio ao agente (chat ou assistente Git).

## Passo a Passo

1. **Bootstrap** — `app/lib/main.dart` → `main`
   `WidgetsFlutterBinding.ensureInitialized()`; `await AppInjector.setupDependencies()` registra services → datasources → repositories → cubits no GetIt. No macOS, inicializa o `window_manager` com `TitleBarStyle.hidden` (a janela fica sem title bar nativa e o app desenha a própria de 38 px). `runApp(const DesktopView())`.

2. **Montagem do shell** — `app/lib/presentation/desktop/view/desktop_view.dart` → `DesktopView` / `_ShellScreenState.initState`
   `DesktopView` (StatelessWidget) monta o `MaterialApp` com o tema derivado dos tokens de `presentation/desktop/theme/desktop_theme.dart` e o shell privado `_ShellScreen`. `_ShellScreenState.initState` resolve `WorkspaceCubit`, `ChatCubit`, `FileExplorerCubit`, `GitCubit` e `GitAssistantCubit` via `AppInjector.inject<...>()`, registra os `MultiBlocListener`s de sincronização entre eles e agenda `_workspaceCubit.initialize()` no primeiro frame. O rail (`WorkspaceRail`) escolhe `WorkspaceSection.chat` ou `.git`; `_buildCenter` monta o chat/preview ou `GitWorkspace`.

3. **Restauração do estado** — `app/lib/presentation/desktop/shared/view_model/workspace_cubit.dart` → `WorkspaceCubit.initialize`
   Lê `DesktopStorageService.load()` (JSON versionado, leitura defensiva devolve defaults em arquivo ausente/corrompido/versão desconhecida) e aplica host, modelo, `InferenceOptions`, `AgentPermissions`, raiz ativa, recentes e sessões; valida a raiz no disco e chama `_connect()`.

4. **Conexão com o Ollama** — `workspace_cubit.dart` → `_connect`
   Chama `OllamaRepository.testConnection`/`listModels`/`listRunningModels` (implementados em `data/repositories/ollama_repository_impl.dart`, que encapsula `OllamaClient` via `data/datasources/ollama_remote_datasource.dart`); sem modelos instalados, emite `WorkspaceErrorKind.noModelsInstalled`. Seleciona o primeiro modelo se o persistido não existir e deriva `modelState` (parado/carregado) dos modelos em `/api/ps`.

5. **Sincronização entre Cubits** — `desktop_view.dart` → `_ShellScreenState.build` (`MultiBlocListener`)
   Ao `WorkspaceState` mudar de raiz/host/modelo/permissões/contexto (ou terminar uma reconexão), a View chama `FileExplorerCubit.setRoot(root)`, `ChatCubit.attachSession(host:, model:, options:, root:, permissions:, contextFilesEnabled:)` e `GitAssistantCubit.attachSession(...)` (sessão Git própria, conversa zerada). Mudança de raiz (ou fim de reconexão) também chama `GitCubit.setRoot(root)`. `WorkspaceState.root` é `Directory?`: sem projeto vinculado, `root` chega `null` — `FileExplorerCubit.setRoot(null)` limpa a árvore sem chamar o repositório, `ChatCubit.attachSession(..., root: null, ...)` configura a sessão do agente sem ferramentas, e `GitCubit.setRoot(null)` emite `GitEmpty`. Com raiz, o chat principal expõe arquivo, shell e Git tipado; a prontidão do chat e do assistente Git (passo 8) nunca dependeu de `root`. Ao `modelState`/`connecting` mudarem, chama `ChatCubit.updateReadiness(...)` e `GitAssistantCubit.updateReadiness(...)`.

6. **Interações da top bar** — `presentation/desktop/shared/content/workspace_top_bar.dart` + `presentation/desktop/shared/widgets/folder_menu.dart` / `model_menu.dart` / `start_stop_button.dart`
   Pasta: menu lista `recentRoots` com marca da ativa, um item "Nenhum projeto" (chama `WorkspaceCubit.clearRoot`, desabilitado quando já não há raiz) e `file_selector.getDirectoryPath` para o picker nativo; seleção chama `WorkspaceCubit.selectRoot`, que valida a pasta, deduplica recentes e persiste. Modelo: menu mostra status, tamanho, quantização e contexto (`WorkspaceCubit.fetchModelContext` → `OllamaRepository.showModelContext` → `/api/show`); seleção chama `WorkspaceCubit.selectModel`, que só troca a seleção e persiste — **sem carregar o modelo** — derivando `modelState` dos `runningModels` já conhecidos. Iniciar/encerrar chama `startModel`/`stopModel` (`loadModel`/`unloadModel` → `/api/generate` com prompt vazio), sempre seguidos de atualização de `runningModels`.

7. **Configurações** — `presentation/desktop/shared/content/settings_dialog.dart` (`SettingsDialog` + `SettingsCubit`)
   Modal que cria um `SettingsCubit` (via `registerFactoryParam`) com os valores atuais do `WorkspaceState`; os campos de texto livre (host/contexto) usam `TextEditingController`s locais no `_SettingsDialogBodyState`, não reconstruídos a cada emissão do Cubit. "Testar" chama `SettingsCubit.testHost` (sonda via `OllamaRepository`, sem mutar `WorkspaceState`). "Salvar e reconectar" chama `SettingsCubit.save`, cujo `onSave` callback delega a `WorkspaceCubit.saveSettings` — que valida o host e, se mudou, sonda o novo servidor antes de comitar qualquer valor. Permissões (editar/executar) viram `AgentPermissions` repassadas ao `ChatCubit.attachSession` pelo `MultiBlocListener`; o switch "Contexto" persiste `contextFilesEnabled` e controla a leitura de `AGENTS.md` e skills; acesso à rede fica desligado/indisponível com a explicação do shell sem sandbox.

8. **Envio ao agente e propostas Git** — `presentation/desktop/view/desktop_view.dart` → `_ShellScreenState._send` + `presentation/desktop/chat/view_model/chat_cubit.dart` → `ChatCubit.send`
   Antes de chamar o agente, `_send` verifica o `WorkspaceState`: se o modelo selecionado estiver parado (e conectado), aguarda `WorkspaceCubit.startModel`; se a carga falhar, o texto digitado permanece no composer e o banner de erro mostra o motivo. Só então chama `ChatCubit.send`, que exige `_ready == true` (mantido por `updateReadiness`, ver passo 5). Com raiz, `ChatAgentDataSource` monta a `AgentSession` com `GitClient` e `GitProfile(replacesRunCommand: false)`: consultas e a ferramenta `git` ficam disponíveis sem remover `run_command`. O resultado do turno preserva `AgentTurnResult.proposals`; o Cubit acumula as propostas arriscadas em `ChatIdle.pendingProposals`, enquanto ações normais já foram executadas pelo tool call e aparecem em atividades. `ChatPendingProposals` renderiza chips com resumo e oferece Revisar/Cancelar; Revisar abre `GitActionReviewDialog` e só Confirmar chama `ChatCubit.executeProposal` → `GitRepository.executeAction`, removendo a proposta apenas após sucesso. Antes de montar a mensagem do usuário, `send` lê cada `pendingAttachments` (arquivos escolhidos via `_attachFiles` → `openFiles()` do `file_selector`, sem confinamento de raiz — ao contrário da menção `@`) através de `FileAttachmentService.readContent` (`common/services/`), que devolve um de três resultados: texto (`AttachmentContent`, até 512 KiB) vira bloco `--- arquivo anexado: X ---` concatenado ao texto enviado a `ChatRepository.send`; imagem (`AttachmentImage`, extensão `.png/.jpg/.jpeg/.gif/.webp/.bmp`, até 8 MiB — limite próprio, maior que o de texto) vira base64 acumulado em `images` e repassado por `ChatRepository.send(message, images:)` → `ChatAgentDataSource.send` → `AgentSession.sendDetailed(images:)` → campo `images` de `AgentMessage`, enviado ao Ollama para modelos com suporte a visão; rejeição (arquivo inexistente/binário/UTF-8 inválido/acima do limite do seu tipo) vira aviso em `warnings` da própria mensagem do usuário, sem bloquear o envio. Com `contextFilesEnabled`, `ChatAgentDataSource` cria `ContextFilesService`, injeta `AGENTS.md` no system prompt, expande `/skill` e expõe `use_skill` ao modelo; os avisos da expansão são mesclados no `AgentTurnResult`. Em qualquer um dos três casos o nome entra em `ChatMessageEntity.attachedFiles`. `pendingAttachments` é limpo ao emitir a mensagem. Em seguida registra o primeiro prompt/data da sessão atual, adiciona a mensagem do usuário e chama `ChatRepository.send`. Tool calls concluídas chegam por um `Stream<ToolActivityEntity>` (adaptado do callback `onToolResult` da `AgentSession`) e viram `ToolActivityEntity` na lista de atividades.

9. **Atividade e sessões** — `presentation/desktop/chat/widgets/activity_panel.dart`
   Painel escuro de 286 px lista atividades (do `ChatState.activities`) com selo/cor por ferramenta e timestamps relativos, e sessões (`WorkspaceState.sessions` + `ChatState.currentSessionSummary` para a sessão em andamento). "Nova sessão" chama `ChatCubit.newSession(onSessionEnded: ...)`, que calcula o resumo (título do primeiro prompt, data, contagem de atividades) e invoca o callback ligado a `WorkspaceCubit.recordSession`, que persiste antes de a sessão ser limpa.

10. **Árvore e preview** — `presentation/desktop/shared/view_model/file_explorer_cubit.dart` + `data/datasources/workspace_datasource.dart`
    A árvore é indexada com `Directory.listSync(followLinks: false)` dentro de `WorkspaceDataSource.listTree`, ignorando `FileMentionService.ignoredDirectories` e symlinks, ordenada pastas-antes-de-arquivos; filtro case-insensitive achata a visão (`FileExplorerCubit._visibleEntries`). Sem projeto vinculado, `FileExplorerCubit.setRoot(null)` nunca chama o repositório e emite `FileExplorerLoaded` vazio direto; o painel de arquivos mostra "Nenhum projeto vinculado" no lugar da árvore e do rodapé de escopo. Abrir um arquivo (`FileExplorerCubit.openPreview`) lê pela ferramenta `read_file` de um `ToolRegistry` com `AgentPermissions.readOnly` (mesma resolução confinada das ferramentas, dentro de `WorkspaceDataSource`), produz `FilePreviewEntity` com linguagem, linhas e tamanho (calculado a partir do conteúdo lido, não de um cache da árvore), e o centro exibe o corpo numerado selecionável com highlight leve (`presentation/desktop/chat/widgets/code_highlighter.dart`); binário, UTF-8 inválido, caminho fora da raiz, arquivo removido/sem permissão viram `previewError` apresentável. "Mencionar com @" insere o caminho no composer com a codificação de aspas para espaços. Com `contextFilesEnabled`, o composer troca para `skillSuggestions` quando o texto começa com `/` sem espaço e `insertSkill` substitui o prefixo pelo nome escolhido.

11. **Persistência** — `workspace_cubit.dart` → `_persist` / `app/lib/common/services/desktop_storage_service.dart` → `save`
    Toda ação bem-sucedida que muda preferências grava `DesktopPreferencesEntity` com gravação atômica (arquivo temporário + rename); o service normaliza recentes (dedupe, máx. 8) e sessões (mais novas, máx. 20).

### Caminhos alternativos

- **Servidor indisponível:** falhas de conexão/HTTP viram `NetworkException`/`OllamaServerException` (`config/error/app_exception.dart`), classificadas pelo `OllamaRepositoryImpl`, e aparecem como `WorkspaceState.errorKind`/`error`; configurações e árvore continuam utilizáveis.
- **Modelo parado:** ao enviar, `_send` inicia o modelo antes de chamar `ChatCubit.send`; se a carga falhar, o texto digitado permanece no composer e o banner mostra o erro. `ChatCubit.send` recusa com `ChatErrorKind.sessionNotReady` quando `_ready == false` (conectando, iniciando ou sem modelo), sem descartar a mensagem digitada (o composer só limpa o texto após a chamada).
- **Erro no preview:** o resultado de erro do `WorkspaceRepository.readFile` (`FileSystemFailureException`, a partir do `ERRO:` da ferramenta de leitura) vira `previewError` e o centro exibe a mensagem com botão de fechar.
- **Estado corrompido/ausente:** `DesktopStorageService.load` devolve defaults e não sobrescreve o arquivo até um save válido.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Bootstrap | `app/lib/main.dart` | Inicialização do binding, `AppInjector.setupDependencies()` e do `window_manager` no macOS |
| DI | `app/lib/config/inject/app_injector.dart` | Registro de services, datasources, repositories e cubits no GetIt |
| Erros | `app/lib/config/error/{result_pattern,app_exception}.dart` | `Result<T>` (Ok/Error) e hierarquia `AppException` do app |
| Domínio | `app/lib/domain/entities/*.dart` | Entidades imutáveis (ChatMessage, ToolActivity, WorkspaceTreeEntry, FilePreview, PersistedSessionSummary, DesktopPreferences, HostTestResult, AttachedFile) |
| Domínio | `app/lib/domain/interfaces/{ollama,chat,workspace,git,git_assistant}_repository.dart` | Contratos de Repository |
| Dados | `app/lib/data/datasources/*.dart` | `OllamaRemoteDataSource`, `ChatAgentDataSource` (encapsula `AgentSession`, stateful), `WorkspaceDataSource` (árvore + `ToolRegistry`/`FileMentionService`), `GitDataSource` (`GitClient`), `GitAssistantDataSource` (sessão Git com `GitProfile`) |
| Dados | `app/lib/data/repositories/*_repository_impl.dart` | Classificam falhas em `AppException`, convertem para `Result<T>` |
| Serviços | `app/lib/common/services/desktop_storage_service.dart` | JSON versionado no diretório de dados do SO, leitura defensiva e gravação atômica |
| Serviços | `app/lib/common/services/system_memory_service.dart` | RAM disponível por plataforma (`vm_stat`+`sysctl`, `/proc/meminfo`, CIM) para o menu de modelos |
| Serviços | `app/lib/common/services/file_attachment_service.dart` | Lê e valida (tamanho/binário/UTF-8, ou imagem por extensão com limite próprio) um anexo escolhido via `file_selector`, sem confinamento de raiz |
| Estado compartilhado | `app/lib/presentation/desktop/shared/view_model/{workspace,file_explorer,settings}_{cubit,state}.dart` | Conexão, configurações, pasta, árvore, preview e sessões persistidas |
| Estado Chat | `app/lib/presentation/desktop/chat/view_model/chat_{cubit,state}.dart` | Mensagens, atividades, envio, sessão em andamento e propostas Git pendentes/executáveis |
| Estado Git | `app/lib/presentation/desktop/git/view_model/git_{cubit,state}.dart` | Snapshot Git, seleção, paginação e ações aprovadas |
| Estado Git | `app/lib/presentation/desktop/git/view_model/git_assistant_{cubit,state}.dart` | Conversa Git, drawer e propostas pendentes |
| Apresentação | `app/lib/presentation/desktop/view/desktop_view.dart` | `DesktopView` (MaterialApp + tema) e shell `_ShellScreenState` (resolve Cubits, `MultiBlocListener`, composer, scroll, Chat/Git, `/exit` e `/quit`) |
| Apresentação | `app/lib/presentation/desktop/theme/desktop_theme.dart` | Paleta (navy/ocean/coral/shell/paper/…) e dimensões do shell (title bar, top bar, rails, painéis) |
| Apresentação compartilhada | `app/lib/presentation/desktop/shared/{content,widgets}/` | Top bar, configurações, menus, rails e painel de arquivos do shell |
| Apresentação Chat | `app/lib/presentation/desktop/chat/{content,widgets}/` | Composer, atividade, preview, cartões, highlighter e `FileChip` |
| Apresentação Git | `app/lib/presentation/desktop/git/{content,widgets}/` | Workspace, revisão de ação, drawer, refs, grafo, inspector e worktree |
| Utilitários | `app/lib/common/utils/formatters.dart` | `formatBytes`/`relativeTime`/`formatSessionDate` |
| Agente (pacote) | `lib/src/agent.dart` | `AgentSession` com `AgentPermissions` e observador `onToolResult` |
| Contexto (pacote) | `lib/src/context_files.dart` | Descobre skills, anexa `AGENTS.md`, expande `/skill` e fornece conteudo para `use_skill` |
| Cliente Ollama (pacote) | `lib/src/ollama_client.dart` | `/api/chat`, `/api/tags`, `/api/ps`, `/api/show`, `/api/generate` (load/unload) e `/api/version` |
| Ferramentas (pacote) | `lib/src/tools.dart` | `ToolRegistry` filtrado por permissões e `GitProfile`; `read_file` rejeita binário/UTF-8 inválido |
| Git (pacote) | `lib/src/git.dart` | `GitClient` somente leitura, `GitActionProposal`/`GitActionExecutor`, `serializeGitContext` |
| Menções (pacote) | `lib/src/file_mentions.dart` | Autocomplete de `@`, expansão de conteúdo e `ignoredDirectories` compartilhado com a árvore |
| Testes | `app/test/presentation/{chat,git,shared}/` | `blocTest` dos Cubits com fakes de Repository; widget tests do workspace Git |
| Testes | `app/test/data/**/*_test.dart` | Testes de RepositoryImpl com fakes de DataSource |
| Testes | `app/test/domain/entities/*_test.dart`, `app/test/config/error/*_test.dart` | Entidades e `Result`/`AppException` |
| Testes | `app/test/common/services/*_test.dart` | `DesktopStorageService`/`SystemMemoryReader` |
| Testes | `app/test/salvador_desktop_app_test.dart` | Widget tests do shell: registra Cubits reais no `AppInjector`, fakeando só `OllamaClient` e `DesktopStorageService` |

## Regras de Negócio Relevantes

- **Persistir só após sucesso** — `workspace_cubit.dart`: troca de modelo/pasta/host só grava o service depois de a ação validar; `saveSettings` valida o novo servidor por uma sondagem antes de comitar qualquer campo.
- **Servidor conectado ≠ modelo carregado** — `workspace_cubit.dart`/`chat_cubit.dart`: `WorkspaceState.connecting`/`errorKind` vêm do HTTP; `modelState` deriva de `/api/ps`. `ChatCubit._ready` (mantido por `updateReadiness`) exige conexão + modelo selecionado + modelo fora de `starting`; configurações funcionam com modelo parado.
- **Selecionar não inicia** — `workspace_cubit.dart` (`selectModel`): a escolha do modelo no menu só persiste a seleção e deriva o estado de `runningModels`; as únicas formas de iniciar o modelo são o botão iniciar (`startModel`) e o primeiro envio de mensagem com o modelo parado (`_send` em `desktop_view.dart`, que pula o start quando o modelo já roda).
- **Histórico sem contexto** — `chat_cubit.dart`: `currentSessionSummary` guarda título, data e contagem de atividades; mensagens nunca são serializadas nem restauradas na `AgentSession`.
- **Preview usa o confinamento das ferramentas** — `workspace_datasource.dart`: leitura do preview passa por `ToolRegistry` com `AgentPermissions.readOnly`, nunca `File(path)` direto; binário/UTF-8 inválido é erro apresentável.
- **Acesso à rede indisponível** — `settings_dialog.dart`: o toggle fica desligado e desabilitado porque `run_command` executa sem sandbox de rede.
- **Árvore não segue symlinks** — `workspace_datasource.dart`: indexação com `followLinks: false` e diretórios ignorados compartilhados com `FileMentionService`.
- **Cubits não se referenciam entre si** — toda sincronização entre `WorkspaceCubit`/`ChatCubit`/`FileExplorerCubit`/`GitCubit`/`GitAssistantCubit` passa pela View (`MultiBlocListener` ou callback explícito como `onSessionEnded`), nunca por um Cubit segurando outro.
- **Git do chat preserva o shell** — `chat_agent_datasource.dart`: com raiz, `GitProfile(replacesRunCommand: false)` expõe Git tipado sem retirar `run_command`; sem raiz, nenhuma ferramenta é exposta.
- **Propostas Git arriscadas exigem confirmação** — `chat_widgets.dart`/`chat_cubit.dart`: o chat executa ações normais no tool call e acumula as arriscadas em `pendingProposals`; Confirmar no `GitActionReviewDialog` chama `GitRepository.executeAction`, e Cancelar não toca o repositório. O assistente do rail Git mantém o mesmo padrão arriscado, mas sem shell; detalhe em `docs/flow/git-workspace.md`.
- **Chat funciona sem projeto vinculado** — `workspace_state.dart`/`agent.dart`: `WorkspaceState.root` é `Directory?`; `WorkspaceCubit.clearRoot()` desvincula o projeto (persiste `activeRoot: null`) sem afetar a prontidão do chat, que nunca dependeu de `root` (só de conexão + modelo, ver regra acima). Sem `root`, `AgentSession`/`ToolRegistry` (pacote `salvador_cli`) não expõem nenhuma ferramenta de arquivo/comando ao modelo e o system prompt omite a linha "Raiz: ...".
- **Contexto é um toggle único** — `workspace_cubit.dart`/`chat_agent_datasource.dart`: `contextFilesEnabled` persiste com default `true`; desligado, não cria `ContextFilesService`, não injeta `AGENTS.md`, não expõe `use_skill` e não oferece `skillSuggestions` no composer.

## Dependências Externas

- Servidor Ollama em `http://127.0.0.1:11434` (configurável), endpoints `/api/chat`, `/api/tags`, `/api/ps`, `/api/show`, `/api/generate`, `/api/version`.
- `file_selector` (picker nativo de pasta via `getDirectoryPath` e de arquivos para anexo via `openFiles`) e `window_manager` (title bar oculta no macOS), exclusivos de `app/pubspec.yaml`.
- `flutter_bloc`/`get_it` (state management + DI) e `bloc_test`/`mocktail`/`checks` (dev, testes), adicionados nesta migração.
- Fontes Archivo e JetBrains Mono empacotadas como assets em `app/assets/fonts/`.

## Observações

- **A descoberta por CLI saiu do desktop.** O `OllamaDiscovery` e o runner de caminhos absolutos continuam apenas na CLI (`bin/`); o desktop resolve tudo por HTTP.
- **A árvore é indexada de forma síncrona** (`listSync`, dentro de `WorkspaceDataSource`). Em workspaces muito grandes o primeiro `setRoot` pode pausar a UI.
- **O modal não fecha menus por conta própria:** selecionar o mesmo modelo (no-op) deixa o menu aberto, pois o fechamento ocorre via rebuild por emissão do Cubit.
- **Sem GoRouter.** O app tem uma única tela (`_ShellScreen`); o diálogo de configurações é modal (`showDialog`) e o preview é uma troca de painel dentro do shell, não uma rota navegável. Introduzir GoRouter para um único destino seria infraestrutura sem uso real — decisão registrada em `docs/plan/salvador-desktop-clean-architecture/00-indice.md`.
- **`WorkspaceInitial` é hoje inatingível.** `WorkspaceCubit` inicia direto em `WorkspaceReady` com valores default (para simplificar os `BlocBuilder`s da View); o estado `WorkspaceInitial` existe no arquivo `workspace_state.dart` mas nunca é emitido. Não é um bug funcional, mas quem mexer em `workspace_state.dart` deve saber que essa classe é vestigial.
