# Git Workspace Visual com Assistente Local — Índice

> **Objetivo:** entregar um modo Git completo no desktop, com navegação por branches, grafo de commits, alterações locais e um assistente Ollama contextual que propõe ações Git tipadas para aprovação explícita.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/app-desktop.md`, `docs/flow/project-structure.md`
> **Skills para execução:** `flutter-expert`, `flutter-testing`, `custom-paint` e `flow` na fase documental final

## Contexto

O shell atual possui uma única área central de chat, um rail de atividade à esquerda e arquivos à direita. Não existe integração Git além da possibilidade genérica de executar comandos pelo `run_command`, que não fornece estado estruturado nem uma fronteira segura para ações propostas pela LLM. O novo modo deve continuar sem dependências de runtime no pacote raiz, respeitar a raiz selecionada e preservar o prompt enxuto para modelos pequenos.

## Design de Origem

- **Decisão aprovada:** criar um Git Workspace completo acessível pelo rail esquerdo, com branches locais/remotas, tags, stashes, grafo, alterações locais, detalhes de commit e assistente contextual no próprio modo.
- **Alternativas descartadas:** painel lateral Git — não oferece espaço suficiente para grafo, comparação, diff e interação com a LLM.
- **Tipo de mudança:** Logic

## Partes

| # | Arquivo | Entrega | Delegável | Depende de | Status |
|---|---------|---------|-----------|-----------|--------|
| 1 | `01-snapshot-e-entrada.md` | Núcleo Git somente leitura e entrada Chat/Git mostrando o resumo real do repositório | não — abre contratos consumidos pelas partes seguintes e altera o shell compartilhado | — | pendente |
| 2 | `02-workspace-visual.md` | Navegador de refs, grafo interativo, inspector e alterações locais responsivas | não — sobrepõe `GitCubit`, `DesktopView` e os testes de shell usados na parte 3 | 1 | pendente |
| 3 | `03-assistente-e-acoes.md` | Assistente Git contextual, propostas aprováveis e ações locais tipadas com atualização dos flows | não — integra contratos do núcleo, sessão do agente, estado e UI no mesmo fluxo | 1 e 2 | pendente |

## Regras Transversais

- Toda chamada usa `Process.run('git', argumentos)` com runner injetável, nunca `/bin/sh -lc` nem concatenação de entrada em uma linha de shell.
- O repositório só é aceito quando o top-level Git resolvido coincide com a raiz vinculada; um repositório acima dela produz estado orientando a abrir a raiz real.
- Ferramentas Git só entram na sessão dedicada do assistente Git. O chat normal mantém a superfície atual de ferramentas e o system prompt de sete linhas.
- Consultas Git podem executar automaticamente; mutações nunca são executadas durante o tool call da LLM, apenas viram propostas tipadas para revisão na UI.
- `reset --hard`, `clean`, exclusão de branch, push e qualquer variante de force não fazem parte do enum de ações da primeira versão.
- Nenhuma verificação executa o app, servidor, emulador ou dispositivo; usar apenas análise, build/compile e testes automatizados.

## Riscos e Mitigações (globais)

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Parsers quebrarem com nomes, mensagens ou caminhos incomuns | Média | Preferir formatos NUL-delimited e campos explícitos; cobrir espaços, Unicode, detached HEAD e saída vazia com fixtures |
| Grafo grande causar jank ou excesso de contexto | Média | Limitar histórico inicial, paginar carregamento, usar `ListView.builder`, `RepaintBoundary` e enviar só o contexto selecionado à LLM |
| LLM contornar aprovação usando shell | Alta | Sessão Git dedicada com `allowCommands: false`; mutações existem somente como `GitActionProposal` validada pela UI |
| Operação Git afetar conteúdo fora do workspace | Média | Comparar caminhos resolvidos do top-level e da raiz antes de habilitar repositório ou ações |
| Mudança no shell regredir chat, atividade ou arquivos | Média | Manter testes de widget do shell e cobrir alternância Chat/Git em larguras distintas |

## Rollback (global)

Reverter os commits de checkpoint em ordem inversa. Como cada parte termina com o pacote e o app íntegros, é possível remover primeiro o assistente, depois o workspace visual e por último o núcleo Git sem usar reset destrutivo nem apagar mudanças não relacionadas.
