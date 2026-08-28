# Migração do App Desktop para Clean Architecture — Índice

> **Objetivo:** Migrar `app/lib/` do `DesktopController` monolítico (`ChangeNotifier`) e da tela única de ~3100 linhas para a arquitetura de referência da skill `flutter-expert`: Presentation (View + Cubit/State) → Domain (Entities + Repository Interfaces) ← Data (Models/DataSources/RepositoryImpl), com injeção via GetIt (`AppInjector`), preservando 100% do comportamento documentado em `docs/flow/app-desktop.md`.
> **Design de origem:** reconstruído a partir do pedido do usuário (sem brainstorming prévio nesta conversa)
> **Flows relacionados:** `docs/flow/app-desktop.md` (será atualizado na última parte), `docs/flow/project-structure.md`

## Contexto

O app desktop hoje concentra em `app/lib/src/desktop/desktop_controller.dart` (877 linhas) a conexão HTTP com o Ollama, o ciclo de vida do modelo, a sessão de chat (`AgentSession` do pacote `salvador_cli`), a árvore de arquivos com preview e as configurações — tudo em um único `ChangeNotifier`. A UI vive inteira em `app/lib/src/desktop/salvador_desktop_app.dart` (~3100 linhas, ~35 widgets privados na mesma classe/arquivo). O usuário pediu explicitamente a migração estrutural completa para o padrão Cubit/BLoC + GetIt descrito na skill `flutter-expert`, não uma revisão nem uma feature nova. O pacote raiz (`lib/`) não é tocado: continua Dart puro, consumido só via `package:salvador_cli/salvador_cli.dart`, e suas classes imutáveis (`OllamaModelInfo`, `OllamaRunningModel`, `InferenceMetrics`, `InferenceOptions`, `AgentPermissions`, `ToolCall`, `AgentTurnResult`) tornam-se a "fonte externa" que a nova camada Data envolve.

## Design de Origem

- **Decisão aprovada:** aplicar Presentation/Domain/Data com GetIt em `app/lib/`, dividindo o `DesktopController` em três Cubits por responsabilidade real (não por campo isolado):
  - `WorkspaceCubit` — conexão Ollama, seleção/ciclo de vida do modelo, pasta raiz, parâmetros de inferência, permissões e histórico de sessões persistidas. Estas informações são lidas e gravadas atomicamente hoje em `DesktopPersistedState`/`_persist()`, então permanecem num único Cubit coordenador em vez de fragmentadas — fragmentar forçaria coordenação artificial entre Cubits para uma única escrita de arquivo.
  - `ChatCubit` — mensagens, atividades de ferramentas e envio ao agente.
  - `FileExplorerCubit` — árvore de arquivos, filtro, preview e sugestões de menção (`@arquivo`).
  - `SettingsCubit` — estado local do formulário do diálogo de configurações (campos em edição, teste de host), evitando que `WorkspaceCubit` acumule estado transitório de formulário.
  Comunicação entre Cubits acontece só na View, via `MultiBlocListener` (ex.: `WorkspaceCubit` muda a raiz → a View aciona `FileExplorerCubit.setRoot(...)`; `WorkspaceCubit` reconstrói a sessão → a View aciona `ChatCubit.attachSession(...)`) — nenhum Cubit referencia outro Cubit diretamente nem recebe `BuildContext`.
- **Alternativas descartadas:**
  - Um único Cubit espelhando o `DesktopController` inteiro — rejeitada por não separar concerns testáveis isoladamente, contrariando o pedido explícito de granularidade Cubit/BLoC.
  - Um Cubit por campo individual (`HostCubit`, `ModelCubit`, `RootCubit` etc.) — rejeitada por fragmentar um estado que hoje é persistido/lido como uma unidade só, criando mais acoplamento entre Cubits do que existe hoje entre métodos do controlador.
  - **GoRouter** — **rejeitada nesta migração.** O app tem uma única tela (`_ShellScreen`); o diálogo de configurações é um modal (`showDialog`, padrão explicitamente permitido pela própria skill em "Composição de View"); o preview de arquivo é uma troca de painel dentro do shell (estado, não navegação com back-stack). Introduzir GoRouter para uma única rota (`initialLocation: '/'` sem nenhum outro destino) seria a "camada especulativa" que a própria auditoria da skill `writing-plan` reprova (adicionar infraestrutura para quando precisarmos, sem uso real hoje). Esta decisão fica registrada aqui, como pediu o usuário, para aprovação explícita antes da execução — se o usuário preferir manter GoRouter mesmo assim, isso é uma parte adicional isolada (registrar `AppRoutes`/`AppRouter` com uma única rota) que pode ser inserida depois da Parte 5 sem impacto nas demais.
- **Tipo de mudança:** Logic (estado/domínio/repositórios — TDD: testes antes da implementação em cada parte)

## Partes

| # | Arquivo | Entrega | Delegável | Depende de | Status |
|---|---------|---------|-----------|-----------|--------|
| 1 | `01-fundacao-erros-entidades.md` | `Result<T>`, hierarquia `AppException`, entidades de domínio e dependências (`flutter_bloc`, `get_it`, `bloc_test`, `mocktail`, `checks`) instaladas e testadas | não — abre os contratos (`Result`, `AppException`, Entities) que todas as partes seguintes consomem | — | concluída |
| 2 | `02-domain-data.md` | Interfaces de Repository e suas implementações (Ollama, Chat/Agente, Workspace) mais `DesktopStorageService`, todos testados com fakes | não — abre os contratos de Repository consumidos pelos Cubits na parte 3/4 | 1 | concluída |
| 3 | `03-workspace-cubit.md` | `WorkspaceCubit` funcional e testado (conexão, modelo, pasta raiz, configurações, persistência) registrado no `AppInjector` | não — expõe o contrato de estado que `ChatCubit`/`FileExplorerCubit` consomem via `MultiBlocListener` na parte 5/6 | 2 | pendente |
| 4 | `04-chat-e-explorer-cubits.md` | `ChatCubit` e `FileExplorerCubit` funcionais e testados, registrados no `AppInjector` | não — mesmo motivo: contrato de estado consumido pela View nas partes 5/6 | 3 | pendente |
| 5 | `05-view-shell-topbar-settings.md` | Shell, top bar, menus, painel/rail de atividade e diálogo de configurações migrados para os Cubits; `main.dart` inicializa o `AppInjector` | não — envolve UI com validação funcional do usuário e compartilha `salvador_desktop_app.dart` com a parte 6 | 4 | pendente |
| 6 | `06-view-arquivos-composer-limpeza.md` | Painel/rail de arquivos, preview, composer e área de chat migrados; `DesktopController` antigo removido; testes de widget adaptados; flow atualizado | não — mesmo arquivo/UI da parte 5, validação funcional do usuário, remoção de código legado | 5 | pendente |

## Riscos e Mitigações (globais)

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Acoplamento real entre conexão/modelo/pasta/sessão de chat (hoje resolvido por `_rebuildSession()` chamado de 4 pontos do controlador) vazar para dentro dos Cubits, violando "Cubit não acessa Cubit" | Média | Toda transição entre Cubits passa por `MultiBlocListener` na View (documentado nas partes 3–6); nenhum Cubit importa outro Cubit |
| `AgentSession` do pacote raiz é stateful (mantém histórico internamente) e não se encaixa no molde "Repository = requisição pura" do `data.md` | Alta | `ChatRepository` documentado na parte 2 assume explicitamente essa exceção: expõe `configureSession`/`send`/`clearSession` mais um `Stream<ToolActivityEntity>`, em vez de métodos stateless — decisão registrada na própria parte, não decidida silenciosamente durante a execução |
| Perda de comportamento sutil documentado no flow (ex.: "servidor conectado ≠ modelo carregado", "persistir só após sucesso") durante a reescrita | Média | Cada parte referencia a regra de negócio equivalente do `docs/flow/app-desktop.md`; a Parte 6 termina com atualização do flow, não criação do zero |
| Testes de widget existentes (`app/test/salvador_desktop_app_test.dart`, 515 linhas) dependerem de chaves/estrutura que mudam ao dividir os 35 widgets privados em arquivos | Média | Partes 5 e 6 preservam as `Key(...)` existentes ao mover cada widget; os testes só são adaptados para resolver os Cubits via `AppInjector` (padrão de `testing.md`), não reescritos do zero |
| Escopo de 6 partes ficar grande demais para uma sessão só de `executing-plan` | Baixa | Cada parte termina em checkpoint de commit com repositório íntegro (build + testes passando); a execução pode parar entre partes sem quebrar nada |

## Rollback (global)

Reverter os commits das partes na ordem 6 → 1. Nenhuma parte altera o pacote raiz (`lib/`) nem os projetos nativos gerados (`app/macos/`, `app/linux/`, `app/windows/`); o arquivo de estado persistido (`salvador_state.json`) mantém o mesmo formato e localização, então uma versão revertida do app continua lendo/gravando normalmente. `DesktopController` só é removido na Parte 6, então reverter até a Parte 5 (inclusive) deixa o controlador antigo ainda presente e funcional como rede de segurança.
