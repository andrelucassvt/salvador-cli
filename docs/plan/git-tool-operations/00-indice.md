# Operações Git do Agente — Índice

> **Objetivo:** o agente executa todas as operações Git pedidas pelo usuário, no CLI e no app desktop: enum `GitActionType` expandido com classificação de risco, ferramenta única `git` que executa operações seguras direto no tool call e registra proposta para destrutivas/rede (dialog no app, y/N no CLI), e chat principal do app com propostas Git.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/git-workspace.md`, `docs/flow/app-desktop.md`

## Contexto

Hoje a mutação Git só existe no assistente do workspace Git do desktop, com `propose_git_action` e enum fechado de 8 operações (sem push, reset, clean, delete, force); o CLI não expõe nenhuma ferramenta Git (só `run_command` livre) e o chat principal do app também não. O usuário quer pedir qualquer operação ao agente nos dois frontends, com confirmação mais forte apenas para as arriscadas.

## Design de Origem

- **Decisão aprovada:** enum `GitActionType` expandido (~34 ops) com `GitActionRisk`; ferramenta única `git` (substitui `propose_git_action`) que executa operações normais direto via `GitActionExecutor` e registra proposta para operações riscosas; CLI confirma riscos inline via `TerminalInput` (y/N); app confirma via `GitActionReviewDialog` no workspace Git e no chat principal
- **Alternativas descartadas:** tool free-form com whitelist de subcomandos — args soltos de modelo pequeno, validação mais fraca, contraria a regra de "argumentos fixos" do flow
- **Tipo de mudança:** Logic

## Partes

| # | Arquivo | Entrega | Delegável | Depende de | Status |
|---|---------|---------|-----------|-----------|--------|
| 1 | `01-pacote-e-cli.md` | Pacote com enum expandido + risco, ferramenta `git`, `GitProfile.replacesRunCommand`, `onGitConfirm`, e CLI executando operações com confirmação inline | não — abre contrato (GitActionTool, `GitProfile.replacesRunCommand`, `onGitConfirm`) consumido pela parte 2 | — | concluída |
| 2 | `02-app-desktop.md` | App com dialog por risco no workspace e chat principal com propostas Git (estado, cubit, widgets, DI) | sim — auto-contida (consome API da parte 1 no código), arquivos só em `app/`, verificação 100% por `flutter analyze`/`flutter test`, decisões cobertas, não abre contrato para parte pendente | 1 | concluída |

## Riscos e Mitigações (globais)

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Modelo pequeno errar o valor do enum no schema da ferramenta | Alta | Schema com enum listado na descrição e `ERRO: tipo de acao invalido: X` devolvido para corrigir |
| Operações riscosas executarem sem confirmação por engano | Média | `GitActionRisk` fixo por tipo no código (não vem da LLM); sem `onGitConfirm`/`onProposal` a ferramenta devolve ERRO sem executar |
| Mudança de comportamento no workspace Git (normais executam direto, antes tudo passava pelo dialog) | Média | Decisão do design; testes cobrem execução direta e proposta para risco; dialog continua para riscos |
| Entrada inesperada durante confirmação y/N no CLI | Baixa | Ctrl+C vira `TerminalInputInterrupted` (saída padrão atual); recusa devolve `ERRO: operacao cancelada pelo usuario` |

## Rollback (global)

Reverter o commit da parte 1 remove enum expandido, ferramenta `git` e confirmação do CLI; reverter o commit da parte 2 remove as mudanças do app. Os dois commits são independentes: reverter na ordem inversa restaura o estado anterior sem comandos Git de limpeza.
