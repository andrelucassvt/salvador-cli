---
generated_at: 2026-08-28
source_commit: 9c08a3d
source_state: clean
verified_at: 2026-08-28
status: current
related_plans: ['docs/plan/salvador-desktop-redesign/00-indice.md']
---

# Flow: App Desktop do Salvador

> **Resumo:** Caminho ponta a ponta do app Flutter desktop: restauração do estado persistido, conexão HTTP com o Ollama (`/api/tags` + `/api/ps`), carga/descarga do modelo pela top bar, conversa com o agente com permissões configuráveis, registro de atividade/sessões no painel esquerdo e árvore de arquivos com preview seguro à direita — tudo persistido em JSON versionado no diretório de dados do sistema operacional.

## Visão Geral

O desktop é um shell em torno do mesmo `AgentSession` da CLI, com estado próprio no `DesktopController` (`ChangeNotifier`). Na inicialização, o controlador restaura preferências, pasta, modelo, parâmetros de inferência, permissões, pastas recentes e resumos de sessões de um JSON versionado gravado no diretório de dados do SO (`Application Support` no macOS, `APPDATA` no Windows, `XDG_CONFIG_HOME`/`.config` no Linux). Em seguida, conecta ao servidor por HTTP — sem usar o binário `ollama` — consultando `/api/tags` e `/api/ps` para separar "servidor conectado" de "modelo carregado".

O shell tem quatro regiões: title bar customizada de 38 px no macOS, top bar de 62 px (logo, pasta, modelo, iniciar/encerrar, nova sessão, configurações), painel esquerdo escuro de atividade/sessões com rail de 50 px, e painel direito claro de árvore de arquivos com rail de 50 px. A área central alterna entre chat/estado vazio e o preview de arquivo. Tudo o que pode falhar (troca de pasta, de modelo, salvar configurações, testar servidor) só persiste após sucesso; o modelo é carregado antes de qualquer envio ao agente.

## Passo a Passo

1. **Bootstrap** — `app/lib/main.dart` → `main`
   `WidgetsFlutterBinding.ensureInitialized()`; no macOS, inicializa o `window_manager` com `TitleBarStyle.hidden` (a janela fica sem title bar nativa e o app desenha a própria de 38 px). `runApp(SalvadorDesktopApp())`.

2. **Montagem do shell** — `app/lib/src/desktop/salvador_desktop_app.dart` → `SalvadorDesktopApp` / `_ShellScreenState.initState`
   Cria (ou recebe injetado, nos testes) o `DesktopController`, registra listener e, se dono do controlador, agenda `initialize()` no primeiro frame.

3. **Restauração do estado** — `app/lib/src/desktop/desktop_controller.dart` → `DesktopController.initialize`
   Lê `DesktopStateStore.load()` (JSON versionado, leitura defensiva devolve defaults em arquivo ausente/corrompido/versão desconhecida) e aplica host, modelo, `InferenceOptions`, `AgentPermissions`, raiz ativa, recentes e sessões; valida a raiz no disco e reconstrói menções, ferramentas de preview e árvore via `_resetWorkspaceContext()`.

4. **Conexão com o Ollama** — `desktop_controller.dart` → `_performConnect`
   Cria o `OllamaClient` pela factory injetável (modelo atual, host, opções de inferência), chama `testConnection()` (`/api/version`), `listModels()` (`/api/tags`) e `listRunningModels(installed: …)` (`/api/ps`); sem modelos instalados, falha com mensagem de `ollama pull`. Seleciona o primeiro modelo se o persistido não existir, reconstrói a sessão do agente e deriva `modelState` (parado/carregado) dos modelos em `/api/ps`.

5. **Interações da top bar** — `salvador_desktop_app.dart` → `_WorkspaceTopBar` / `_FolderMenu` / `_ModelMenu` / `_StartStopButton`
   Pasta: menu lista `recentRoots` com marca da ativa e `file_selector.getDirectoryPath` para o picker nativo; seleção chama `selectRoot`, que valida a pasta, deduplica recentes, persiste e reindexa a árvore. Modelo: menu mostra status, tamanho, quantização e contexto (`fetchModelContext` → `/api/show`); seleção chama `selectModel`, que carrega o modelo (`loadModel` → `/api/generate` com prompt vazio), persiste a escolha e reconstrói a sessão. Iniciar/encerrar chama `startModel`/`stopModel` (mesma via `loadModel`/`unloadModel`, com `keep_alive`), sempre seguidos de `listRunningModels` para atualizar o estado.

6. **Configurações** — `salvador_desktop_app.dart` → `_SettingsDialog`
   Modal com controllers locais que só gravam ao salvar. “Testar” chama `DesktopController.testHost` (client probe em novo host + latência + contagem de modelos, sem mutar estado). “Salvar e reconectar” chama `saveSettings`, que valida o host, e, se mudou, valida o novo servidor por um client probe antes de comitar qualquer valor; erros propagam sem descartar o último estado válido. Permissões (editar/executar) viram `AgentPermissions` na sessão; acesso à rede fica desligado/indisponível com a explicação do shell sem sandbox.

7. **Envio ao agente** — `desktop_controller.dart` → `send`
   Exige `connectionState == ready`, `modelState == running` e sessão criada; registra o primeiro prompt/data da sessão atual, adiciona a mensagem do usuário e chama `AgentSession.sendDetailed`. Tool calls concluídas viram `ToolActivity` (com o resultado textual) via `onToolResult` e notificam o painel esquerdo.

8. **Atividade e sessões** — `salvador_desktop_app.dart` → `_ActivityPanel` / `_ActivityRail`
   Painel escuro de 286 px lista atividades com selo/cor por ferramenta e timestamps relativos, e sessões (atual com barra coral + resumos persistidos). “Nova sessão” chama `newSession`, que persiste o resumo (título do primeiro prompt, data, contagem de ações) antes de limpar.

9. **Árvore e preview** — `desktop_controller.dart` → `refreshTree` / `openPreview` e `salvador_desktop_app.dart` → `_FilesPanel` / `_PreviewPane`
   A árvore é indexada com `Directory.listSync(followLinks: false)`, ignorando `FileMentionService.ignoredDirectories` e symlinks, ordenada pastas-antes-de-arquivos; filtro case-insensitive achata a visão. Abrir um arquivo lê pela ferramenta `read_file` de um `ToolRegistry` com `AgentPermissions.readOnly` (mesma resolução confinada das ferramentas), produz `FilePreview` com linguagem, linhas e tamanho, e o centro exibe o corpo numerado selecionável com highlight leve; binário, UTF-8 inválido, caminho fora da raiz, arquivo removido/sem permissão viram `previewError` apresentável. “Mencionar com @” insere o caminho no composer com a codificação de aspas para espaços.

10. **Persistência** — `desktop_controller.dart` → `_persist` / `app/lib/src/desktop/desktop_state_store.dart` → `save`
    Toda ação bem-sucedida que muda preferências grava `DesktopPersistedState` com gravação atômica (arquivo temporário + rename); o store normaliza recentes (dedupe, máx. 8) e sessões (mais novas, máx. 20).

### Caminhos alternativos

- **Servidor indisponível:** falhas de conexão/HTTP viram `OllamaException`/`SocketException` no client e são convertidas em `connectionError` com `connectionState: failed`; configurações e árvore continuam utilizáveis.
- **Modelo parado:** `send` recusa com “O modelo selecionado esta parado. Inicie o modelo antes de enviar.”, sem descartar a mensagem digitada.
- **Erro no preview:** o resultado `ERRO:` da ferramenta de leitura vira `previewError` e o centro exibe a mensagem com botão de fechar.
- **Estado corrompido/ausente:** `DesktopStateStore.load` devolve defaults e não sobrescreve o arquivo até um save válido.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Apresentação | `app/lib/src/desktop/salvador_desktop_app.dart` | Shell: title bar, top bar, menus, modal de configurações, painéis/rails, chat, composer e preview |
| Estado | `app/lib/src/desktop/desktop_controller.dart` | Estado do workspace (conexão, modelo, configurações, atividades, sessões, árvore, preview) e orquestração das ações assíncronas |
| Persistência | `app/lib/src/desktop/desktop_state_store.dart` | JSON versionado no diretório de dados do SO, leitura defensiva e gravação atômica |
| Sistema | `app/lib/src/desktop/system_memory.dart` | RAM disponível por plataforma (`vm_stat`+`sysctl`, `/proc/meminfo`, CIM) para o menu de modelos |
| Bootstrap | `app/lib/main.dart` | Inicialização do binding e do `window_manager` no macOS |
| Agente (pacote) | `lib/src/agent.dart` | `AgentSession` com `AgentPermissions` e observador `onToolResult` |
| Cliente Ollama (pacote) | `lib/src/ollama_client.dart` | `/api/chat`, `/api/tags`, `/api/ps`, `/api/show`, `/api/generate` (load/unload) e `/api/version` |
| Ferramentas (pacote) | `lib/src/tools.dart` | `ToolRegistry` filtrado por permissões; `read_file` rejeita binário/UTF-8 inválido |
| Menções (pacote) | `lib/src/file_mentions.dart` | Autocomplete de `@`, expansão de conteúdo e `ignoredDirectories` compartilhado com a árvore |
| Testes | `app/test/desktop_controller_test.dart`, `app/test/desktop_state_store_test.dart`, `app/test/system_memory_test.dart`, `app/test/salvador_desktop_app_test.dart` | Contratos do controlador/store/memória e widget tests do shell |

## Regras de Negócio Relevantes

- **Persistir só após sucesso** — `desktop_controller.dart`: troca de modelo/pasta/host só grava o store depois de a ação validar; `saveSettings` valida o novo servidor por um client probe antes de comitar qualquer campo.
- **Servidor conectado ≠ modelo carregado** — `desktop_controller.dart`: `connectionState` vem do HTTP; `modelState` deriva de `/api/ps`. Envio ao agente exige os dois; configurações funcionam com modelo parado.
- **Histórico sem contexto** — `desktop_controller.dart`: resumos de sessão guardam título, data e contagem de ações; mensagens nunca são serializadas nem restauradas no `AgentSession`.
- **Preview usa o confinamento das ferramentas** — `desktop_controller.dart`: leitura do preview passa por `ToolRegistry` com `AgentPermissions.readOnly`, nunca `File(path)` direto; binário/UTF-8 inválido é erro apresentável.
- **Acesso à rede indisponível** — `salvador_desktop_app.dart`: o toggle fica desligado e desabilitado porque `run_command` executa sem sandbox de rede.
- **Árvore não segue symlinks** — `desktop_controller.dart`: indexação com `followLinks: false` e diretórios ignorados compartilhados com `FileMentionService`.

## Dependências Externas

- Servidor Ollama em `http://127.0.0.1:11434` (configurável), endpoints `/api/chat`, `/api/tags`, `/api/ps`, `/api/show`, `/api/generate`, `/api/version`.
- `file_selector` (picker nativo de pasta) e `window_manager` (title bar oculta no macOS), exclusivos de `app/pubspec.yaml`.
- Fontes Archivo e JetBrains Mono empacotadas como assets em `app/assets/fonts/`.

## Observações

- **A descoberta por CLI saiu do desktop.** O `OllamaDiscovery` e o runner de caminhos absolutos continuam apenas na CLI (`bin/`); o desktop resolve tudo por HTTP. A ressalva do AGENTS.md sobre `PATH` do app GUI perdeu o consumidor no fluxo desktop, mas segue valendo para a CLI.
- **A árvore é indexada de forma síncrona** (`listSync`), como o `FileMentionService` já fazia. A mitigação de "indexação assíncrona" do plano não foi necessária para os testes; em workspaces muito grandes o primeiro `refreshTree` pode pausar a UI.
- **O modal não fecha menus por conta própria:** selecionar o mesmo modelo (no-op) deixa o menu aberto, pois o fechamento ocorre via rebuild por notificação do controlador.
