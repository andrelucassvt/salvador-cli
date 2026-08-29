---
generated_at: 2026-08-28
source_commit: ae9aaaa
source_state: dirty
verified_at: 2026-08-29
status: current
related_plans: ['docs/plan/salvador-desktop-clean-architecture/00-indice.md', 'docs/plan/attach-files-desktop.md']
---

# Flow: App Desktop do Salvador

> **Resumo:** Caminho ponta a ponta do app Flutter desktop: bootstrap do `AppInjector` (GetIt), restauração do estado persistido pelo `WorkspaceCubit`, conexão HTTP com o Ollama (`/api/tags` + `/api/ps`), seleção de modelo sem carga automática (o modelo só sobe pelo botão iniciar ou pelo primeiro envio de mensagem), conversa com o agente via `ChatCubit` com permissões configuráveis, registro de atividade/sessões no painel esquerdo e árvore de arquivos com preview seguro à direita via `FileExplorerCubit` — tudo persistido em JSON versionado no diretório de dados do sistema operacional.

## Visão Geral

O desktop segue Clean Architecture (Presentation → Domain ← Data) com injeção de dependências via GetIt (`AppInjector`). Quatro Cubits dividem a responsabilidade que antes vivia inteira em um único `DesktopController` (`ChangeNotifier`, removido nesta migração):

- **`WorkspaceCubit`** — coordenador: conexão com o Ollama, seleção/ciclo de vida do modelo, pasta raiz, parâmetros de inferência, permissões e histórico de sessões persistidas. Concentra essas responsabilidades porque `DesktopPreferencesEntity` é lida/gravada como uma unidade só.
- **`ChatCubit`** — mensagens, atividades de ferramentas emitidas pelo agente e envio.
- **`FileExplorerCubit`** — árvore de arquivos, filtro, preview e sugestões de menção `@arquivo`.
- **`SettingsCubit`** — estado local do formulário do diálogo de configurações (criado sob demanda, via `registerFactoryParam`, com os valores atuais do `WorkspaceState`).

Nenhum Cubit referencia outro diretamente: a sincronização entre eles acontece na View (`_ShellScreenState`, em `desktop_view.dart`), via `MultiBlocListener` — quando `WorkspaceCubit` emite uma nova raiz/modelo/permissões, a View aciona `FileExplorerCubit.setRoot(...)` e `ChatCubit.attachSession(...)`; quando `ChatCubit.newSession()` encerra uma sessão, ela recebe um callback (não uma referência a Cubit) que a View liga a `WorkspaceCubit.recordSession(...)`.

Na inicialização, `main.dart` chama `AppInjector.setupDependencies()` antes de `runApp`. O `WorkspaceCubit` restaura preferências, pasta, modelo, parâmetros de inferência, permissões, pastas recentes e resumos de sessões de um JSON versionado gravado no diretório de dados do SO (`Application Support` no macOS, `APPDATA` no Windows, `XDG_CONFIG_HOME`/`.config` no Linux). Em seguida, conecta ao servidor por HTTP — sem usar o binário `ollama` — consultando `/api/tags` e `/api/ps` para separar "servidor conectado" de "modelo carregado".

O shell tem quatro regiões: title bar customizada de 38 px no macOS, top bar de 62 px (logo, pasta, modelo, iniciar/encerrar, nova sessão, configurações), painel esquerdo escuro de atividade/sessões com rail de 50 px, e painel direito claro de árvore de arquivos com rail de 50 px. A área central alterna entre chat/estado vazio e o preview de arquivo. Tudo o que pode falhar (troca de pasta, de modelo, salvar configurações, testar servidor) só persiste após sucesso; o modelo é carregado antes de qualquer envio ao agente.

## Passo a Passo

1. **Bootstrap** — `app/lib/main.dart` → `main`
   `WidgetsFlutterBinding.ensureInitialized()`; `await AppInjector.setupDependencies()` registra services → datasources → repositories → cubits no GetIt. No macOS, inicializa o `window_manager` com `TitleBarStyle.hidden` (a janela fica sem title bar nativa e o app desenha a própria de 38 px). `runApp(const DesktopView())`.

2. **Montagem do shell** — `app/lib/presentation/desktop/view/desktop_view.dart` → `DesktopView` / `_ShellScreenState.initState`
   `DesktopView` (StatelessWidget) monta o `MaterialApp` com o tema derivado dos tokens de `presentation/desktop/theme/desktop_theme.dart` e o shell privado `_ShellScreen`. `_ShellScreenState.initState` resolve `WorkspaceCubit`, `ChatCubit` e `FileExplorerCubit` via `AppInjector.inject<...>()`, registra os `MultiBlocListener`s de sincronização entre eles e agenda `_workspaceCubit.initialize()` no primeiro frame.

3. **Restauração do estado** — `app/lib/presentation/desktop/view_model/workspace_cubit.dart` → `WorkspaceCubit.initialize`
   Lê `DesktopStorageService.load()` (JSON versionado, leitura defensiva devolve defaults em arquivo ausente/corrompido/versão desconhecida) e aplica host, modelo, `InferenceOptions`, `AgentPermissions`, raiz ativa, recentes e sessões; valida a raiz no disco e chama `_connect()`.

4. **Conexão com o Ollama** — `workspace_cubit.dart` → `_connect`
   Chama `OllamaRepository.testConnection`/`listModels`/`listRunningModels` (implementados em `data/repositories/ollama_repository_impl.dart`, que encapsula `OllamaClient` via `data/datasources/ollama_remote_datasource.dart`); sem modelos instalados, emite `WorkspaceErrorKind.noModelsInstalled`. Seleciona o primeiro modelo se o persistido não existir e deriva `modelState` (parado/carregado) dos modelos em `/api/ps`.

5. **Sincronização entre Cubits** — `desktop_view.dart` → `_ShellScreenState.build` (`MultiBlocListener`)
   Ao `WorkspaceState` mudar de raiz/host/modelo/permissões (ou terminar uma reconexão), a View chama `FileExplorerCubit.setRoot(root)` e `ChatCubit.attachSession(host:, model:, options:, root:, permissions:)`. `WorkspaceState.root` é `Directory?`: sem projeto vinculado, `root` chega `null` aos dois — `FileExplorerCubit.setRoot(null)` limpa a árvore sem chamar o repositório, e `ChatCubit.attachSession(..., root: null, ...)` configura a sessão do agente sem nenhuma ferramenta de arquivo/comando (a prontidão do chat, ver passo 8, nunca dependeu de `root`). Ao `modelState`/`connecting` mudarem, chama `ChatCubit.updateReadiness(...)`, que substitui a checagem `connectionState == ready && modelState == running` do controlador antigo.

6. **Interações da top bar** — `presentation/desktop/content/workspace_top_bar.dart` + `presentation/desktop/widgets/folder_menu.dart` / `model_menu.dart` / `start_stop_button.dart`
   Pasta: menu lista `recentRoots` com marca da ativa, um item "Nenhum projeto" (chama `WorkspaceCubit.clearRoot`, desabilitado quando já não há raiz) e `file_selector.getDirectoryPath` para o picker nativo; seleção chama `WorkspaceCubit.selectRoot`, que valida a pasta, deduplica recentes e persiste. Modelo: menu mostra status, tamanho, quantização e contexto (`WorkspaceCubit.fetchModelContext` → `OllamaRepository.showModelContext` → `/api/show`); seleção chama `WorkspaceCubit.selectModel`, que só troca a seleção e persiste — **sem carregar o modelo** — derivando `modelState` dos `runningModels` já conhecidos. Iniciar/encerrar chama `startModel`/`stopModel` (`loadModel`/`unloadModel` → `/api/generate` com prompt vazio), sempre seguidos de atualização de `runningModels`.

7. **Configurações** — `presentation/desktop/content/settings_dialog.dart` (`SettingsDialog` + `SettingsCubit`)
   Modal que cria um `SettingsCubit` (via `registerFactoryParam`) com os valores atuais do `WorkspaceState`; os campos de texto livre (host/contexto) usam `TextEditingController`s locais no `_SettingsDialogBodyState`, não reconstruídos a cada emissão do Cubit. "Testar" chama `SettingsCubit.testHost` (sonda via `OllamaRepository`, sem mutar `WorkspaceState`). "Salvar e reconectar" chama `SettingsCubit.save`, cujo `onSave` callback delega a `WorkspaceCubit.saveSettings` — que valida o host e, se mudou, sonda o novo servidor antes de comitar qualquer valor. Permissões (editar/executar) viram `AgentPermissions` repassadas ao `ChatCubit.attachSession` pelo `MultiBlocListener`; acesso à rede fica desligado/indisponível com a explicação do shell sem sandbox.

8. **Envio ao agente** — `presentation/desktop/view/desktop_view.dart` → `_ShellScreenState._send` + `presentation/desktop/view_model/chat_cubit.dart` → `ChatCubit.send`
   Antes de chamar o agente, `_send` verifica o `WorkspaceState`: se o modelo selecionado estiver parado (e conectado), aguarda `WorkspaceCubit.startModel`; se a carga falhar, o texto digitado permanece no composer e o banner de erro mostra o motivo. Só então chama `ChatCubit.send`, que exige `_ready == true` (mantido por `updateReadiness`, ver passo 5). Antes de montar a mensagem do usuário, `send` lê cada `pendingAttachments` (arquivos escolhidos via `_attachFiles` → `openFiles()` do `file_selector`, sem confinamento de raiz — ao contrário da menção `@`) através de `FileAttachmentService.readContent` (`common/services/`), que devolve um de três resultados: texto (`AttachmentContent`, até 512 KiB) vira bloco `--- arquivo anexado: X ---` concatenado ao texto enviado a `ChatRepository.send`; imagem (`AttachmentImage`, extensão `.png/.jpg/.jpeg/.gif/.webp/.bmp`, até 8 MiB — limite próprio, maior que o de texto) vira base64 acumulado em `images` e repassado por `ChatRepository.send(message, images:)` → `ChatAgentDataSource.send` → `AgentSession.sendDetailed(images:)` → campo `images` de `AgentMessage`, enviado ao Ollama para modelos com suporte a visão; rejeição (arquivo inexistente/binário/UTF-8 inválido/acima do limite do seu tipo) vira aviso em `warnings` da própria mensagem do usuário, sem bloquear o envio. Em qualquer um dos três casos o nome entra em `ChatMessageEntity.attachedFiles`. `pendingAttachments` é limpo ao emitir a mensagem. Em seguida registra o primeiro prompt/data da sessão atual, adiciona a mensagem do usuário e chama `ChatRepository.send`. Tool calls concluídas chegam por um `Stream<ToolActivityEntity>` (adaptado do callback `onToolResult` da `AgentSession`) e viram `ToolActivityEntity` na lista de atividades.

9. **Atividade e sessões** — `presentation/desktop/widgets/activity_panel.dart`
   Painel escuro de 286 px lista atividades (do `ChatState.activities`) com selo/cor por ferramenta e timestamps relativos, e sessões (`WorkspaceState.sessions` + `ChatState.currentSessionSummary` para a sessão em andamento). "Nova sessão" chama `ChatCubit.newSession(onSessionEnded: ...)`, que calcula o resumo (título do primeiro prompt, data, contagem de atividades) e invoca o callback ligado a `WorkspaceCubit.recordSession`, que persiste antes de a sessão ser limpa.

10. **Árvore e preview** — `presentation/desktop/view_model/file_explorer_cubit.dart` + `data/datasources/workspace_datasource.dart`
    A árvore é indexada com `Directory.listSync(followLinks: false)` dentro de `WorkspaceDataSource.listTree`, ignorando `FileMentionService.ignoredDirectories` e symlinks, ordenada pastas-antes-de-arquivos; filtro case-insensitive achata a visão (`FileExplorerCubit._visibleEntries`). Sem projeto vinculado, `FileExplorerCubit.setRoot(null)` nunca chama o repositório e emite `FileExplorerLoaded` vazio direto; o painel de arquivos mostra "Nenhum projeto vinculado" no lugar da árvore e do rodapé de escopo. Abrir um arquivo (`FileExplorerCubit.openPreview`) lê pela ferramenta `read_file` de um `ToolRegistry` com `AgentPermissions.readOnly` (mesma resolução confinada das ferramentas, dentro de `WorkspaceDataSource`), produz `FilePreviewEntity` com linguagem, linhas e tamanho (calculado a partir do conteúdo lido, não de um cache da árvore), e o centro exibe o corpo numerado selecionável com highlight leve (`presentation/desktop/widgets/code_highlighter.dart`); binário, UTF-8 inválido, caminho fora da raiz, arquivo removido/sem permissão viram `previewError` apresentável. "Mencionar com @" insere o caminho no composer com a codificação de aspas para espaços.

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
| Domínio | `app/lib/domain/interfaces/{ollama,chat,workspace}_repository.dart` | Contratos de Repository |
| Dados | `app/lib/data/datasources/*.dart` | `OllamaRemoteDataSource`, `ChatAgentDataSource` (encapsula `AgentSession`, stateful), `WorkspaceDataSource` (árvore + `ToolRegistry`/`FileMentionService`) |
| Dados | `app/lib/data/repositories/*_repository_impl.dart` | Classificam falhas em `AppException`, convertem para `Result<T>` |
| Serviços | `app/lib/common/services/desktop_storage_service.dart` | JSON versionado no diretório de dados do SO, leitura defensiva e gravação atômica |
| Serviços | `app/lib/common/services/system_memory_service.dart` | RAM disponível por plataforma (`vm_stat`+`sysctl`, `/proc/meminfo`, CIM) para o menu de modelos |
| Serviços | `app/lib/common/services/file_attachment_service.dart` | Lê e valida (tamanho/binário/UTF-8, ou imagem por extensão com limite próprio) um anexo escolhido via `file_selector`, sem confinamento de raiz |
| Estado | `app/lib/presentation/desktop/view_model/workspace_{cubit,state}.dart` | Conexão, modelo, pasta, configurações, sessões persistidas |
| Estado | `app/lib/presentation/desktop/view_model/chat_{cubit,state}.dart` | Mensagens, atividades, envio, sessão em andamento |
| Estado | `app/lib/presentation/desktop/view_model/file_explorer_{cubit,state}.dart` | Árvore, filtro, preview, menções |
| Estado | `app/lib/presentation/desktop/view_model/settings_{cubit,state}.dart` | Formulário do diálogo de configurações |
| Apresentação | `app/lib/presentation/desktop/view/desktop_view.dart` | `DesktopView` (MaterialApp + tema) e shell `_ShellScreenState` (resolve Cubits, `MultiBlocListener`, composer, scroll, `/exit` e `/quit`) |
| Apresentação | `app/lib/presentation/desktop/theme/desktop_theme.dart` | Paleta (navy/ocean/coral/shell/paper/…) e dimensões do shell (title bar, top bar, rails, painéis) |
| Apresentação | `app/lib/presentation/desktop/content/{workspace_top_bar,settings_dialog,composer}.dart` | Blocos únicos da View (top bar, diálogo de configurações, composer) |
| Apresentação | `app/lib/presentation/desktop/widgets/*.dart` | Componentes reutilizados (menus, botões, painel/rail de atividade, painel/rail de arquivos, preview, cartões de chat, highlighter, `FileChip` de menção/anexo) |
| Utilitários | `app/lib/common/utils/formatters.dart` | `formatBytes`/`relativeTime`/`formatSessionDate` |
| Agente (pacote) | `lib/src/agent.dart` | `AgentSession` com `AgentPermissions` e observador `onToolResult` |
| Cliente Ollama (pacote) | `lib/src/ollama_client.dart` | `/api/chat`, `/api/tags`, `/api/ps`, `/api/show`, `/api/generate` (load/unload) e `/api/version` |
| Ferramentas (pacote) | `lib/src/tools.dart` | `ToolRegistry` filtrado por permissões; `read_file` rejeita binário/UTF-8 inválido |
| Menções (pacote) | `lib/src/file_mentions.dart` | Autocomplete de `@`, expansão de conteúdo e `ignoredDirectories` compartilhado com a árvore |
| Testes | `app/test/presentation/desktop/*_test.dart` | `blocTest` dos 4 Cubits com fakes de Repository |
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
- **Cubits não se referenciam entre si** — toda sincronização entre `WorkspaceCubit`/`ChatCubit`/`FileExplorerCubit` passa pela View (`MultiBlocListener` ou callback explícito como `onSessionEnded`), nunca por um Cubit segurando outro.
- **Chat funciona sem projeto vinculado** — `workspace_state.dart`/`agent.dart`: `WorkspaceState.root` é `Directory?`; `WorkspaceCubit.clearRoot()` desvincula o projeto (persiste `activeRoot: null`) sem afetar a prontidão do chat, que nunca dependeu de `root` (só de conexão + modelo, ver regra acima). Sem `root`, `AgentSession`/`ToolRegistry` (pacote `salvador_cli`) não expõem nenhuma ferramenta de arquivo/comando ao modelo e o system prompt omite a linha "Raiz: ...".

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
