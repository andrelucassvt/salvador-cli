# Redesenho Desktop do Salvador — Parte 3: Top bar, configurações e atividade

> **Objetivo da parte:** substituir a sidebar de configuração pelo shell visual com top bar, seletor de modelo, modal de configurações e painel esquerdo de atividade/sessões.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** parte 2 concluída

## Contexto

Com os contratos e o estado prontos, esta parte entrega a primeira fatia observável do redesign. A UI continua importando somente `package:salvador_cli/salvador_cli.dart`; fontes entram como assets locais e o picker nativo fica restrito ao app Flutter.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/pubspec.yaml` | alterar | `file_selector`, `window_manager` e famílias tipográficas empacotadas |
| `app/pubspec.lock` | alterar | Versões resolvidas das dependências exclusivas do app |
| `app/lib/main.dart` | alterar | Inicialização das opções de janela sem editar runners nativos manualmente |
| `app/assets/fonts/Archivo-VariableFont_wdth,wght.ttf` | criar | Fonte principal da interface |
| `app/assets/fonts/JetBrainsMono-VariableFont_wght.ttf` | criar | Fonte de caminhos, modelos, código e números |
| `app/assets/fonts/OFL-Archivo.txt` | criar | Licença da fonte Archivo |
| `app/assets/fonts/OFL-JetBrains-Mono.txt` | criar | Licença da fonte JetBrains Mono |
| `app/lib/src/desktop/salvador_desktop_app.dart` | alterar | Tema, shell, top bar, menus, modal e painel esquerdo |
| `app/test/salvador_desktop_app_test.dart` | criar | Widget tests dos controles e estados visuais desta parte |

## Fases

### Fase 1 — Assets e tema

- [x] Adicionar `file_selector` e `window_manager` somente a `app/pubspec.yaml` e manter o `pubspec.yaml` raiz sem dependências de runtime.
- [x] Adicionar os dois arquivos de fonte e respectivas licenças em `app/assets/fonts/`, usando `google/fonts/ofl/archivo` e `google/fonts/ofl/jetbrainsmono` como fontes oficiais sob OFL.
- [x] Declarar `Archivo` e `JetBrains Mono` em `app/pubspec.yaml`, cobrindo os pesos usados no documento de referência.
- [x] Atualizar em `app/lib/src/desktop/salvador_desktop_app.dart` os tokens de cores, raios, tipografia e estados Material 3 conforme a especificação aprovada.
- [x] Inicializar `window_manager` em `app/lib/main.dart` com title bar oculta no macOS e opções padrão nas demais plataformas, sem editar `app/macos/`, `app/linux/` ou `app/windows/` manualmente.
- [x] Verificação: `cd app && flutter pub get && flutter analyze` reconhece dependência e assets sem alterar o manifesto raiz.

### Fase 2 — Top bar e menus

- [x] Criar em `app/lib/src/desktop/salvador_desktop_app.dart` a title bar arrastável de 38 px no macOS, respeitando a área dos controles nativos da janela.
- [x] Substituir `_TopBar` em `app/lib/src/desktop/salvador_desktop_app.dart` pela barra de 62 px com logo, pasta, modelo, iniciar/encerrar, configurações e nova sessão na ordem aprovada.
- [x] Implementar o menu de pasta com caminho curto, recentes persistidas, marca da pasta ativa e `file_selector.getDirectoryPath` para o picker nativo.
- [x] Implementar o menu de modelos com status, tamanho, contexto, RAM estimada/uso conhecido e RAM livre do sistema quando disponível.
- [x] Conectar seleção, início e encerramento aos métodos assíncronos do `DesktopController`, exibindo loading e impedindo ações concorrentes.
- [x] Manter “Nova sessão” habilitada conforme o estado do histórico e fazer a ação persistir o resumo antes de limpar mensagens/atividades.
- [x] Verificação: `cd app && flutter analyze` passa; `rg -n "class _SessionPanel" app/lib/src/desktop/salvador_desktop_app.dart` não encontra o painel antigo e `rg -n "class _WorkspaceTopBar|class _ActivityPanel" app/lib/src/desktop/salvador_desktop_app.dart` encontra o novo shell.

### Fase 3 — Modal de configurações

- [x] Substituir `_showSettings` em `app/lib/src/desktop/salvador_desktop_app.dart` por `showDialog` com overlay e card responsivo de até 560 px.
- [x] Implementar servidor + testar, contexto, temperatura, keep-alive e timeout com controllers locais que só gravam no `DesktopController` ao salvar.
- [x] Implementar toggles de editar arquivos e executar comandos; renderizar acesso à rede desligado/indisponível com explicação sobre o shell sem sandbox.
- [x] Exibir status, latência e contagem de modelos do último teste; manter o modal aberto e os valores editáveis em caso de falha.
- [x] Implementar cancelar/fechar sem mutar preferências e “Salvar e reconectar” com loading e mensagem de erro no próprio modal.
- [x] Verificação: `cd app && flutter analyze` passa e `rg -n "showModalBottomSheet" app/lib/src/desktop/salvador_desktop_app.dart` não retorna ocorrência.

### Fase 4 — Painel de atividade e sessões

- [x] Substituir `_SessionPanel` em `app/lib/src/desktop/salvador_desktop_app.dart` por painel escuro de 286 px dedicado a atividade e sessões.
- [x] Mapear `read_file`, `write_file`, `replace_in_file` e `run_command` para selo, título, detalhe e cor; usar o resultado concluído quando houver linha/alteração mensurável.
- [x] Exibir timestamps relativos atualizados durante rebuilds e contador de atividades no header.
- [x] Renderizar resumos persistidos com título, data, contagem de ações e barra coral na sessão atual, sem prometer reabertura do contexto.
- [x] Implementar rail esquerdo de 50 px com chevron, atividade + badge e sessões; qualquer ícone reexpande o painel.
- [x] Verificação: inspeção por chaves em widget test confirma ausência de campos de configuração no painel e presença dos dois modos expandido/rail.

### Fase 5 — Widget tests do shell

- [x] Criar `app/test/salvador_desktop_app_test.dart` com `DesktopController` injetável/fake e harness `MaterialApp` sem subir o app.
- [x] Testar top bar nos estados modelo carregado/parado/loading e callbacks de pasta, modelo, start/stop e nova sessão.
- [x] Testar abertura, cancelamento, erro de teste e salvamento do modal, incluindo o aviso de rede indisponível.
- [x] Testar painel esquerdo com atividade vazia/preenchida, sessões persistidas e alternância expandido/rail.
- [x] Testar constraints estreitas suficientes para provar que a top bar degrada sem overflow, preservando as ações essenciais.
- [x] Testar com `debugDefaultTargetPlatformOverride` que a title bar customizada aparece somente no macOS sem interferir nos callbacks da top bar.
- [x] Verificação: `cd app && flutter test test/salvador_desktop_app_test.dart` passa sem app, janela ou device.

### Fase 6 — Integridade da parte

- [x] Rodar `dart format app/lib/main.dart app/lib/src/desktop/salvador_desktop_app.dart app/test/salvador_desktop_app_test.dart`.
- [x] Rodar `cd app && flutter analyze && flutter test`.
- [x] Rodar `dart analyze && dart test` na raiz.
- [x] Checkpoint: commit das mudanças da parte + resumo curto do que ficou pronto, seguindo direto para a parte 4.

## Critérios de Sucesso

- [x] Configuração saiu completamente da sidebar e está acessível pela top bar/modal.
- [x] Pasta e modelo podem ser trocados e modelos podem ser carregados/descarregados pelos controles visuais.
- [x] Painel esquerdo contém somente atividade e histórico resumido de sessões, com rail funcional.
- [x] No macOS, a área cliente inclui a title bar escura de 38 px sem mudanças manuais no runner nativo.
- [x] Widget tests, testes unitários e análises estáticas passam.
- [ ] _(manual — feito pelo usuário)_ Fidelidade visual, foco, menus e picker nativo validados no app.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Download das fontes oficiais indisponível durante a execução | Baixa | Solicitar acesso apenas para os assets licenciados; não substituir silenciosamente por fonte remota em runtime |
| Popup/menu ficar fora da janela em largura reduzida | Média | Constraints máximas, âncora via `MenuAnchor`/overlay e widget tests em viewport estreita |

## Rollback

Reverter o commit restaura o shell anterior; o estado persistido da parte 2 continua válido e os assets/dependência deixam de ser referenciados.
