# Redesenho Desktop do Salvador — Índice

> **Objetivo:** Entregar o app desktop com top bar operacional, painéis recolhíveis de atividade e arquivos, histórico persistente de sessões, configurações do Ollama e preview seguro de arquivos, conforme a referência visual aprovada.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/project-structure.md`; `docs/flow/app-desktop.md` será criado na última parte

## Contexto

O desktop atual concentra servidor, pasta, modelo e atividade em uma única sidebar e usa o centro apenas para chat. O redesenho distribui essas responsabilidades em quatro regiões e exige estado novo no controlador, chamadas adicionais ao Ollama, permissões configuráveis e persistência local. O pacote raiz deve continuar Dart puro e sem dependências de runtime; dependências visuais ou de integração nativa ficam restritas a `app/`.

## Design de Origem

- **Decisão aprovada:** implementar as quatro regiões da referência e persistir preferências, pastas recentes e resumos de sessões em JSON versionado no diretório de dados do sistema operacional.
- **Alternativas descartadas:** salvar o estado em `.salvador/` dentro do projeto, pois poluiria o workspace e misturaria dados locais com o escopo do agente.
- **Tipo de mudança:** Logic
- **Limites aprovados:** o histórico persistido contém título, data e contagem de ações, mas não reabre a conversa como contexto do agente; “Acesso à rede” permanece desligado e indisponível porque `run_command` não oferece sandbox de rede.

## Partes

| # | Arquivo | Entrega | Delegável | Depende de | Status |
|---|---------|---------|-----------|-----------|--------|
| 1 | `01-ollama-e-permissoes.md` | Cliente Ollama conhece modelos instalados/ativos, controla carga e aplica parâmetros e permissões | não — abre contratos consumidos pelo controlador na parte 2 | — | concluída |
| 2 | `02-estado-persistente.md` | Preferências, recentes e sessões sobrevivem ao reinício e o controlador expõe todo o estado do novo workspace | não — altera `DesktopController`, que será consumido e novamente integrado nas partes 3 e 4 | 1 | concluída |
| 3 | `03-topbar-configuracoes-e-atividade.md` | Top bar, modal, seletor de modelo e painel de atividade/sessões funcionam no shell redesenhado | não — compartilha `salvador_desktop_app.dart` com a parte 4 e inclui validação visual manual | 2 | concluída |
| 4 | `04-arquivos-preview-e-responsividade.md` | Árvore, filtro, preview, rails, composer e estado vazio completam o redesenho | não — envolve UI com validação funcional do usuário e atualização dos mesmos componentes da parte 3 | 3 | concluída |

## Riscos e Mitigações (globais)

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Respostas de `/api/tags`, `/api/ps` e `/api/show` variarem entre versões do Ollama | Média | Parsers tolerantes a campos ausentes, modelos imutáveis com defaults e testes HTTP por contrato |
| Arquivo persistido estar corrompido ou vir de versão anterior | Média | Schema versionado, leitura defensiva, defaults seguros e gravação por arquivo temporário + rename |
| “Acesso à rede” sugerir uma garantia que o shell não cumpre | Alta | Manter o toggle desligado/indisponível e exibir a limitação de `run_command` no modal |
| Fontes, picker ou controle da janela quebrarem o caráter local do pacote raiz | Baixa | Fontes empacotadas como assets e plugins `file_selector`/`window_manager` somente no `app/pubspec.yaml` |
| Painéis e composer estourarem em janelas estreitas ou baixas | Média | Rails de 50 px, `min-width/min-height` equivalentes em Flutter e widget tests com constraints reduzidas |

## Rollback (global)

Reverter os commits na ordem 4 → 1. O armazenamento usa um arquivo novo e versionado; versões antigas do app o ignoram, portanto não há migração destrutiva de dados nem alteração dos projetos nativos gerados.
