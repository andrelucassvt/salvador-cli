# Git Workspace Visual com Assistente Local — Parte 2: Workspace Visual

> **Objetivo da parte:** entregar a navegação visual completa por refs, grafo de commits, inspector e alterações locais, com seleção e layout responsivo testados.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** parte 1 concluída

## Contexto

A parte 1 já disponibiliza um `GitSnapshot` confiável e um modo Git básico. Esta parte transforma o resumo em um workspace visual sem adicionar dependência gráfica: o grafo usa `CustomPainter`, enquanto seleção e acessibilidade permanecem em widgets semânticos sobre cada linha.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/presentation/desktop/view_model/git_cubit.dart` | modificar | Filtro, seleção de ref/commit/arquivo e paginação do histórico |
| `app/lib/presentation/desktop/view_model/git_state.dart` | modificar | Estado visual derivado e seleções imutáveis |
| `app/lib/presentation/desktop/content/git_workspace.dart` | modificar | Compor cabeçalho, regiões e comportamento por largura |
| `app/lib/presentation/desktop/widgets/git_branches_panel.dart` | criar | Pesquisa e grupos atual, locais, remotas, tags e stashes |
| `app/lib/presentation/desktop/widgets/git_commit_graph.dart` | criar | Lista virtualizada, linhas semânticas e seleção de commits |
| `app/lib/presentation/desktop/widgets/git_graph_painter.dart` | criar | Desenhar lanes, nós e conexões do grafo |
| `app/lib/presentation/desktop/widgets/git_graph_layout.dart` | criar | Calcular lanes/segmentos de forma determinística e testável |
| `app/lib/presentation/desktop/widgets/git_commit_inspector.dart` | criar | Metadados, refs, pais e arquivos do commit selecionado |
| `app/lib/presentation/desktop/widgets/git_worktree_panel.dart` | criar | Grupos staged, unstaged, untracked e conflicted |
| `app/lib/presentation/desktop/theme/desktop_theme.dart` | modificar | Dimensões e cores semânticas específicas do Git |
| `app/test/presentation/desktop/git_workspace_test.dart` | criar | Widget tests isolados dos estados e interações do workspace |
| `app/test/presentation/desktop/git_graph_layout_test.dart` | criar | Topologias lineares, branches e merges |

## Fases

### Fase 1 — Testes de seleção, filtro e layout do grafo

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Declarar em `app/lib/presentation/desktop/widgets/git_graph_layout.dart` os tipos mínimos de lane, nó, segmento e a assinatura de `GitGraphLayout.calculate`, com corpo provisório, para o teste compilar antes da lógica.
- [ ] Estender `app/test/presentation/desktop/git_cubit_test.dart` para seleção de ref, commit e arquivo, filtro case-insensitive e limpeza de seleção quando o snapshot atualizado não contém mais o item.
- [ ] Criar `app/test/presentation/desktop/git_graph_layout_test.dart` com histórico linear, bifurcação, merge de dois pais, refs no mesmo commit e hash pai ausente por paginação.
- [ ] Definir nos testes que a ordem de lanes é determinística para o mesmo conjunto de commits e que cada nó produz posição e segmentos dentro de limites não negativos.
- [ ] Cobrir paginação: solicitar mais commits preserva seleção e concatena sem duplicar hashes.
- [ ] Verificação: testes compilam e falham pelas regras ainda não implementadas, não por fixtures ou sintaxe inválidas.

### Fase 2 — Implementar estado visual e desenho do grafo

- [ ] Implementar filtro, seleção e paginação em `git_cubit.dart`/`git_state.dart`, mantendo dados brutos no snapshot e expondo listas derivadas sem mutação.
- [ ] Implementar `GitGraphLayout` em `git_graph_layout.dart`, separado do painter, convertendo commits ordenados e pais em lanes/nós/segmentos testáveis.
- [ ] Implementar `GitGraphPainter` em arquivo próprio, com propriedades finais, `shouldRepaint` comparando apenas layout/cores relevantes, `Paint`/`Path` criados em `paint()` e sem `saveLayer`.
- [ ] Criar `GitCommitGraph` com `ListView.builder`, uma `RepaintBoundary` por linha ou bloco visível e `InkWell`/`Semantics` para seleção; o canvas desenha conexões, mas não concentra hit testing ou texto.
- [ ] Adicionar estado de “carregar mais” ao fim da lista e impedir chamadas concorrentes de paginação.
- [ ] Verificação: `cd app && flutter test test/presentation/desktop/git_cubit_test.dart test/presentation/desktop/git_graph_layout_test.dart` passa.

### Fase 3 — Testes de widget do workspace completo

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Criar `app/test/presentation/desktop/git_workspace_test.dart` com providers/fakes para snapshot válido, vazio, erro, detached HEAD e conflito.
- [ ] Testar pesquisa e expansão dos grupos Atual, Locais, Remotas, Tags e Stashes, incluindo branch remota com upstream/ahead/behind.
- [ ] Testar seleção de commit no grafo atualizando o inspector e seleção de arquivo exibindo resumo de diff disponível no snapshot.
- [ ] Testar grupos staged, unstaged, untracked e conflicted e a ausência de seções vazias.
- [ ] Testar largura ampla e largura compacta: no compacto, branches viram painel recolhível e inspector abre como drawer inferior sem overflow.
- [ ] Verificação: o teste compila e falha porque os painéis e a composição final ainda não existem.

### Fase 4 — Implementar branches, inspector e worktree

- [ ] Criar `GitBranchesPanel` com pesquisa, contagens, grupos recolhíveis e distinção visual/semântica entre atual, local, remote-tracking, tag e stash.
- [ ] Criar `GitCommitInspector` com hash abreviado copiável, autor/data, mensagem, pais, refs e arquivos alterados; mostrar truncamento de conteúdo de forma explícita.
- [ ] Criar `GitWorktreePanel` com grupos staged, unstaged, untracked e conflicted, seleção de arquivo e status acessível além da cor.
- [ ] Compor os widgets em `git_workspace.dart`: branches à esquerda, grafo expandido, inspector à direita e bandeja de alterações abaixo em largura ampla.
- [ ] Usar `LayoutBuilder` para o modo compacto, movendo branches para painel recolhível e inspector para drawer inferior; não decidir layout por sistema operacional.
- [ ] Adicionar em `desktop_theme.dart` apenas tokens reutilizados por mais de um widget Git, mantendo a paleta Salvador e contraste de nós/lanes.
- [ ] Verificação: `cd app && flutter test test/presentation/desktop/git_workspace_test.dart test/salvador_desktop_app_test.dart` passa sem overflow ou exceções de pintura.

### Fase 5 — Verificação e checkpoint visual

- [ ] Executar `dart format` nos Dart alterados e `git diff --check` para detectar whitespace inválido.
- [ ] Executar `dart analyze` e `dart test` para garantir que o pacote compartilhado permanece íntegro.
- [ ] Executar `cd app && flutter analyze` e `cd app && flutter test`, sem iniciar o app ou gerar screenshots.
- [ ] Confirmar por teste que `GitGraphPainter.shouldRepaint` retorna falso para dados equivalentes e verdadeiro quando layout ou cores mudam.
- [ ] Confirmar que os elementos desenhados possuem rótulos equivalentes em `Semantics` e que seleção funciona por teclado/tap nos widgets de linha.
- [ ] Verificação: todos os comandos passam e os testes cobrem topologias linear/branch/merge e layouts amplo/compacto.
- [ ] Checkpoint: commit das mudanças da parte + resumo curto do workspace visual pronto, seguindo direto para a parte 3.

## Critérios de Sucesso

- [ ] Branches locais/remotas, tags e stashes são pesquisáveis e agrupadas.
- [ ] O grafo representa histórico linear, bifurcações e merges sem pacote externo.
- [ ] Selecionar um commit atualiza metadados e arquivos no inspector.
- [ ] Alterações locais aparecem separadas por staged, unstaged, untracked e conflicted.
- [ ] Widget tests cobrem larguras ampla e compacta sem overflow.
- [ ] `dart analyze`, `dart test`, `cd app && flutter analyze` e `cd app && flutter test` passam.
- [ ] _(manual — feito pelo usuário)_ Validar legibilidade do grafo, navegação por teclado e comportamento dos painéis em janelas redimensionadas.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Algoritmo de lanes produzir cruzamentos confusos | Média | Separar layout do painter e cobrir topologias conhecidas com coordenadas determinísticas |
| Muitos commits causarem repaints caros | Média | Histórico limitado/paginado, lista virtualizada, `RepaintBoundary` e `shouldRepaint` seletivo |
| Informação depender apenas de cores | Baixa | Ícones, rótulos, tooltips e `Semantics` para status/ref/seleção |

## Rollback

Reverter o commit desta parte preserva o modo Git resumido da parte 1. Os widgets visuais são específicos da feature e não alteram contratos públicos do pacote.
