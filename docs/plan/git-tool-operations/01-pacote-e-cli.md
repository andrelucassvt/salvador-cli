# Operações Git do Agente — Parte 1: Núcleo, Ferramenta e CLI

> **Objetivo da parte:** o pacote expõe enum `GitActionType` expandido com `GitActionRisk`, a ferramenta `git` (executa normais, propõe/confirma riscos) e a CLI executa operações Git com confirmação inline para riscos, com `run_command` preservado.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** nenhuma

## Contexto

`lib/src/git.dart` tem `GitActionType` fechado em 8 valores e `GitActionExecutor` com args fixos; `lib/src/tools.dart` expõe `ProposeGitActionTool` (só propõe, nunca executa) e `GitProfile` que remove `run_command`. A CLI (`bin/salvador_cli.dart`) não usa perfil Git. Esta parte expande o modelo, troca a ferramenta e liga o CLI.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/git.dart` | modificar | `GitActionRisk`, novos valores de `GitActionType` (34), args fixos no executor, `_validRef` com `~`/`^` |
| `lib/src/tools.dart` | modificar | `GitActionTool` substitui `ProposeGitActionTool`; `GitProfile.replacesRunCommand`; `ToolRegistry` com `onGitConfirm` |
| `lib/src/agent.dart` | modificar | `AgentSession.onGitConfirm` repassado ao registry |
| `bin/salvador_cli.dart` | modificar | Sessão com `GitClient()` + `GitProfile(replacesRunCommand: false)` + confirmação y/N |
| `test/git_test.dart` | modificar | Args exatos, validação e risco dos tipos novos |
| `test/salvador_cli_test.dart` | modificar | Comportamentos da ferramenta `git` e flags do perfil |

## Fases

### Fase 1 — Testes do núcleo Git (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Estender `test/git_test.dart` com a lista exata de argumentos (sem shell) dos novos valores de `GitActionType`: rede — push `['push', remote?]`, pushForce `['push', '--force', remote?]`, pull `['pull']`, fetch `['fetch']`; destrutivos — resetHard `['reset', '--hard', ref?]`, cleanForce `['clean', '-fd']`, restoreFile `['restore', paths...]`, removeFile `['rm', paths...]`, deleteBranchForce `['branch', '-D', ref]`, deleteTag `['tag', '-d', nome]`, stashDrop `['stash', 'drop']`, amendCommit `['commit', '--amend', '-m', msg]`
- [x] Estender `test/git_test.dart` com os demais novos valores: resetSoft `['reset', '--soft', ref?]`, resetMixed `['reset', ref?]`, moveFile `['mv', origem, destino]` (exige 2 paths), deleteBranch `['branch', '-d', ref]`, createTag `['tag', nome]`, stashPush `['stash', 'push', ('-m', msg)?]`, stashPop `['stash', 'pop']`, stashApply `['stash', 'apply']`, cherryPick `['cherry-pick', commit]`, revert `['revert', '--no-edit', commit]`, mergeAbort `['merge', '--abort']`, rebaseAbort `['rebase', '--abort']`, rebaseContinue `['rebase', '--continue']`, remoteAdd (refName = nome, message = URL) e remoteRemove `['remote', 'remove', nome]`
- [x] Testar que os 12 valores riscosos (fetch, pull, push, pushForce, resetHard, cleanForce, restoreFile, removeFile, deleteBranchForce, deleteTag, stashDrop, amendCommit) devolvem `GitActionRisk.risky` e os demais `normal`; `GitActionProposal.risk` repassa o risco
- [x] Testar `_validRef` estendido: aceita `HEAD~1`, `HEAD^`, hash curto/completo e nomes com `v1.0.0`; rejeita `@{`, `..`, espaço e `-` inicial
- [x] Verificação: `dart test test/git_test.dart` compila e falha somente pelos símbolos novos ausentes

### Fase 2 — Implementar o núcleo Git

- [x] Adicionar `GitActionRisk { normal, risky }` em `lib/src/git.dart`; getter `risk` em `GitActionType` e `GitActionProposal`
- [x] Adicionar os valores novos do enum com a construção de argumentos de cada um em `GitActionExecutor._argumentsFor` (remoteAdd usa `refName` como nome e `message` como URL; ref opcional em reset valida como commit)
- [x] Estender `_validRef` para aceitar `~` e `^` (mantendo bloqueio de `@{`, `..`, espaços, `-` inicial)
- [x] Verificação: `dart test test/git_test.dart` passa e `dart analyze` não acusa erros novos

### Fase 3 — Testes da ferramenta `git` (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Estender `test/salvador_cli_test.dart`: `GitActionTool` com tipo normal executa via runner (runner chamado uma vez com args exatos) e devolve a saída ao modelo
- [x] Testar tipo risco com `onGitConfirm` retornando true executa; retornando false devolve `ERRO: operacao cancelada pelo usuario` sem chamar o runner
- [x] Testar tipo risco sem `onGitConfirm`: registra em `AgentTurnResult.proposals`, devolve "Aguardando aprovacao na interface." e zero invocações do runner
- [x] Testar tipo risco sem `onGitConfirm` e sem `onProposal`: devolve `ERRO: operacao destrutiva requer aprovacao` sem executar
- [x] Testar que tipo normal nunca gera proposta, mesmo com `onProposal` configurado
- [x] Testar `GitProfile(replacesRunCommand: false)` mantém `run_command` na sessão; default (`true`) remove; e que a ferramenta `git` não existe sem `GitClient`/`GitProfile`
- [x] Testar `AgentSession` repassa `onGitConfirm` ao registry (sessão com callback resolve risco sem proposta)
- [x] Verificação: testes compilam e falham pelos motivos certos (símbolos novos ausentes)

### Fase 4 — Implementar a ferramenta e o perfil

- [x] Criar `GitActionTool` em `lib/src/tools.dart` (schema `type/ref/paths/message`, descrição listando os valores válidos do enum) substituindo `ProposeGitActionTool`: normal executa via `GitActionExecutor` e devolve saída; risco chama `onGitConfirm` se presente, senão registra proposta (`onProposal`) e devolve "Aguardando aprovacao na interface."; sem via de confirmação devolve ERRO
- [x] Adicionar `replacesRunCommand` em `GitProfile` (default `true`) e ajustar a condição do `RunCommandTool` em `ToolRegistry`; adicionar `onGitConfirm` ao `ToolRegistry` e ao `AgentSession` (repassado ao registry)
- [x] Manter `GitException` convertida em `ERRO: <motivo>` na execução da ferramenta (padrão atual do `ToolRegistry.execute`)
- [x] Verificação: `dart test test/git_test.dart test/salvador_cli_test.dart` passa; `dart analyze` limpo

### Fase 5 — CLI com confirmação inline

- [x] Em `bin/salvador_cli.dart`, passar à `AgentSession`: `gitClient: GitClient()`, `gitProfile: const GitProfile(replacesRunCommand: false)` e `onGitConfirm` lendo `TerminalInput.readLine(prompt: 'Operacao <summary>. Confirmar? [s/N]: ')` aceitando s/S/sim
- [x] Tratar `TerminalInputInterrupted` e `null` (EOF) na confirmação como recusa (false)
- [x] Verificação: `dart analyze` e `dart test` passam; a CLI compila com `dart compile exe bin/salvador_cli.dart`
- [x] Checkpoint: commit `a733965` das mudanças da parte 1 — núcleo Git expandido, ferramenta `git` e confirmação inline na CLI

## Critérios de Sucesso

- [x] `GitActionType` com 34 valores, cada um com args fixos e risco correto (12 riscosos)
- [x] Ferramenta `git` executa normais direto; riscos só com confirmação (callback) ou proposta; nunca executa sem via de aprovação
- [x] `run_command` preservado no CLI e removido apenas no perfil default (workspace Git)
- [x] `dart analyze` e `dart test` passam
- [ ] _(manual — feito pelo usuário)_ Pedir no CLI um commit, um push (confirmação y/N) e cancelar uma confirmação

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Esquecer um valor do enum na ferramenta (schema vs enum) | Média | Testes varrem `GitActionType.values` contra a validação da ferramenta |
| Confirmação y/N quebrar o fluxo do turno no CLI | Baixa | Recusa e EOF devolvem ERRO ao modelo; Ctrl+C mantém o comportamento atual de saída |

## Rollback

Reverter o commit desta parte restaura o enum fechado, `propose_git_action` e a CLI sem perfil Git — nenhuma outra parte depende do estado anterior.
