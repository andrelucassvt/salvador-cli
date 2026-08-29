# Anexar Arquivos no App Desktop

> **Objetivo:** Permitir que o usuário anexe arquivos de qualquer local do disco (via `file_selector`) ao compor uma mensagem no app desktop; o conteúdo entra no prompt enviado ao agente e os nomes ficam registrados na mensagem do usuário no histórico.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/app-desktop.md` (seção "Envio ao agente", passo 8, e tabela "Arquivos Envolvidos")

## Contexto

O app já tem menção de arquivo com `@caminho` (`FileMentionService`, no pacote `salvador_cli`), mas ela só enxerga arquivos **dentro** da raiz do workspace — a expansão resolve o caminho e rejeita qualquer coisa fora de `root`. "Anexar" é uma ação distinta: o usuário escolhe explicitamente um arquivo de qualquer lugar do disco via picker nativo, sem depender da raiz vinculada nem de o modelo "conhecer" o caminho. Como é uma ação do usuário (não do modelo via tool call), o confinamento de `WorkspaceTool.resolveFile` não se aplica — o precedente já existe em `FileMentionService`, que também lê arquivos com `File(...)` diretamente fora do `ToolRegistry`.

## Design de Origem

- **Decisão aprovada:** Anexar arquivos via `file_selector` (picker nativo, sem confinamento de raiz); leitura e injeção do conteúdo no prompt acontecem inteiramente no app (`ChatCubit`), sem alterar o pacote `salvador_cli`.
- **Alternativas descartadas:** Expandir no pacote (`AgentSession.sendDetailed` com parâmetro `attachments: List<String>`) — motivo insuficiente para mexer no núcleo compartilhado com a CLI por uma feature exclusiva do app.
- **Tipo de mudança:** Logic

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/domain/entities/attached_file_entity.dart` | criar | Entidade imutável `{path, name}` de um anexo pendente |
| `app/lib/common/services/file_attachment_service.dart` | criar | Lê e valida o conteúdo de um caminho absoluto (tamanho, binário, UTF-8) — sem `Result`/`AppException`, leitura local efêmera |
| `app/lib/domain/entities/chat_message_entity.dart` | editar | Novo campo `attachedFiles: List<String>` (nomes), mesmo padrão de `mentionedFiles`/`warnings` |
| `app/lib/presentation/desktop/view_model/chat_state.dart` | editar | `ChatIdle.pendingAttachments: List<AttachedFileEntity>` |
| `app/lib/presentation/desktop/view_model/chat_cubit.dart` | editar | `addAttachments`/`removeAttachment`; `send()` lê, injeta no prompt e registra sucesso/rejeição na mensagem do usuário |
| `app/lib/config/inject/app_injector.dart` | editar | Registrar `FileAttachmentService` e injetar no `ChatCubit` |
| `app/lib/presentation/desktop/widgets/file_chip.dart` | criar | `FileChip` público (movido de `_FileChip` em `chat_widgets.dart`), com `onRemove` opcional |
| `app/lib/presentation/desktop/widgets/chat_widgets.dart` | editar | Usa `FileChip` importado; `MessageCard` renderiza `entry.attachedFiles` |
| `app/lib/presentation/desktop/content/composer.dart` | editar | Botão "Anexar", linha de `FileChip` removíveis para `pendingAttachments` |
| `app/lib/presentation/desktop/view/desktop_view.dart` | editar | `_attachFiles()` chama `openFiles()` do `file_selector` e liga o callback ao `Composer` |

## Fases

### Fase 1 — Testes: entidade e serviço de leitura (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Criar `app/test/domain/entities/attached_file_entity_test.dart`: `==`/`hashCode` por `path`+`name`, `toString()` legível
- [x] Criar `app/test/common/services/file_attachment_service_test.dart` cobrindo `FileAttachmentService.readContent`:
  - sucesso: arquivo texto pequeno devolve o conteúdo (`AttachmentContent`)
  - rejeição: arquivo inexistente (`AttachmentRejected` com motivo)
  - rejeição: acima do limite de tamanho (injetar `maxFileBytes` pequeno no construtor para não depender de arquivo grande real)
  - rejeição: conteúdo binário (bytes com `0x00`)
  - rejeição: conteúdo não é UTF-8 válido
- [x] Verificação: `cd app && flutter test test/domain/entities/attached_file_entity_test.dart test/common/services/file_attachment_service_test.dart` — compilou e falhou por classe/método inexistente (`AttachedFileEntity`, `FileAttachmentService`, `AttachmentContent`, `AttachmentRejected`), não por erro de sintaxe

### Fase 2 — Implementação: entidade e serviço

- [x] Implementar `AttachedFileEntity` (`@immutable`, `path`, `name`, `copyWith`, `==`, `hashCode`, `toString()`) em `app/lib/domain/entities/attached_file_entity.dart`
- [x] Implementar `FileAttachmentService` em `app/lib/common/services/file_attachment_service.dart`: `readContent(String path)` retorna um tipo selado `AttachmentReadResult` (`AttachmentContent(content)` | `AttachmentRejected(reason)`); limite padrão `maxFileBytes = 512 * 1024`, mesmas checagens de `FileMentionService` (existência, tamanho, byte nulo para binário, `utf8.decode` para validade)
- [x] Registrar `FileAttachmentService` no `AppInjector` (`registerLazySingleton`)
- [x] Verificação: `cd app && flutter test test/domain/entities/attached_file_entity_test.dart test/common/services/file_attachment_service_test.dart` passa — 10/10 testes ok

### Fase 3 — Testes: `ChatMessageEntity`, `ChatState` e `ChatCubit`

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Estender `app/test/domain/entities/chat_message_entity_test.dart` (ou criar se não existir): `attachedFiles` participa de `==`/`hashCode`/`copyWith`
- [x] Estender `app/test/presentation/desktop/chat_cubit_test.dart` (reaproveitando `FakeChatRepository`):
  - `addAttachments` adiciona a `pendingAttachments` sem duplicar por `path`
  - `removeAttachment` remove pelo `path`
  - `send` com um anexo válido: `fakeRepository.lastMessage` contém o bloco `--- arquivo anexado: <nome> ---`; a mensagem do usuário emitida tem `attachedFiles` com o nome; `pendingAttachments` volta vazio após o envio
  - `send` com um anexo inválido (caminho inexistente): mensagem do usuário emitida tem `warnings` com o motivo; texto enviado ao repositório não inclui bloco desse arquivo
- [x] Verificação: `cd app && flutter test test/domain/entities/chat_message_entity_test.dart test/presentation/desktop/chat_cubit_test.dart` — compilou e falhou por membro inexistente (`attachedFiles`, `pendingAttachments`, `addAttachments`, `removeAttachment`, parâmetro `attachments`), não por erro de sintaxe

### Fase 4 — Implementação: `ChatMessageEntity`, `ChatState` e `ChatCubit`

- [x] Adicionar `attachedFiles: List<String>` a `ChatMessageEntity` (default `const []`), incluindo em `copyWith`/`==`/`hashCode`/`toString()`
- [x] Adicionar `pendingAttachments: List<AttachedFileEntity>` a `ChatIdle` (default `const []`), incluindo em `copyWith`/`toString()`
- [x] Em `ChatCubit`: injetar `FileAttachmentService` (parâmetro nomeado opcional no construtor, default `FileAttachmentService()`, seguindo o padrão de `clock`); implementar `addAttachments(List<String> paths)` (dedupe por `path`, deriva `name` de `File(path).uri.pathSegments.last`) e `removeAttachment(String path)`
- [x] Em `ChatCubit.send`: antes de montar `withUserMessage`, ler cada `pendingAttachments` via `_attachments.readContent(path)`; para sucesso, acumular bloco `\n\n--- arquivo anexado: $name ---\n$content\n--- fim do arquivo: $name ---` a ser concatenado ao `normalized` enviado ao repositório e o `name` em `attachedFiles` da mensagem do usuário; para rejeição, acumular `'$name ignorado: $reason.'` em `warnings` da mensagem do usuário; limpar `pendingAttachments` (`copyWith` com lista vazia) ao emitir `withUserMessage`
- [x] Atualizar `AppInjector` para passar `inject<FileAttachmentService>()` ao construir `ChatCubit`
- [x] Verificação: `cd app && flutter test test/domain/entities/chat_message_entity_test.dart test/presentation/desktop/chat_cubit_test.dart` passa — 17/17 testes ok (corrigido bug de avaliação dupla de `Iterable` lazy em `addAttachments`, que fazia o dedupe descartar os próprios anexos recém-adicionados)

### Fase 5 — UI: botão Anexar, chips e histórico

- [x] Criar `app/lib/presentation/desktop/widgets/file_chip.dart` com `FileChip({required label, bool showAtPrefix = true, VoidCallback? onRemove})` (generalizado além do plano original: `label`/`showAtPrefix` em vez de só `path`, porque o chip agora também exibe nomes de anexo sem o prefixo `@` de menção) movendo o corpo de `_FileChip`; quando `onRemove != null`, ícone de fechar (`Icons.close_rounded`) que o chama
- [x] Em `chat_widgets.dart`: removido `_FileChip` privado, importado `FileChip`, usado em `mentionedFiles` (`showAtPrefix: true`, default) e no novo bloco `entry.attachedFiles` (`showAtPrefix: false`) dentro de `MessageCard`
- [x] Em `composer.dart`: adicionados parâmetros `pendingAttachments: List<AttachedFileEntity>`, `onAttach: VoidCallback`, `onRemoveAttachment: ValueChanged<String>`; `Wrap` de `FileChip` removíveis acima do campo de texto quando `pendingAttachments.isNotEmpty`; `TextButton.icon` "Anexar" (`Icons.attach_file_rounded`) ao lado do botão "Arquivo" existente, desabilitado quando `sending`
- [x] Em `desktop_view.dart`: implementado `_attachFiles()` chamando `openFiles()` do `file_selector` (sem `acceptedTypeGroups`, multi-seleção) e repassando os `.path` para `_chatCubit.addAttachments`; `onAttach: _attachFiles` e `onRemoveAttachment: _chatCubit.removeAttachment` conectados na chamada de `Composer`; `pendingAttachments: idle.pendingAttachments` lido do `BlocBuilder<ChatCubit, ChatState>` já existente
- [x] Verificação: `cd app && flutter analyze` limpo (0 issues). `cd app && flutter test` (suíte completa): 91 passando / 9 falhando — as 9 falhas são pré-existentes (overflow em `workspace_top_bar.dart` sob janela estreita/compacta em `salvador_desktop_app_test.dart`), confirmado reproduzindo o mesmo conjunto de falhas com `git stash` antes destas mudanças; nenhuma regressão introduzida pela feature de anexos — o fluxo de ponta a ponta (abrir picker, ver chip, enviar) é validação manual do usuário

### Fase 6 — Atualizar Flow

- [x] Em `docs/flow/app-desktop.md`, passo 8 ("Envio ao agente"): descrito que `ChatCubit.send` agora lê `pendingAttachments` via `FileAttachmentService` e injeta o conteúdo no texto enviado, registrando `attachedFiles`/`warnings` na mensagem do usuário
- [x] Na tabela "Arquivos Envolvidos": adicionadas linhas para `attached_file_entity.dart` (via entrada "AttachedFile" na linha de Domínio), `file_attachment_service.dart` e `file_chip.dart` (via linha de widgets reutilizados); `Dependências Externas` atualizada para citar `openFiles` do `file_selector`
- [x] Atualizado `verified_at` e `related_plans` (incluindo `docs/plan/attach-files-desktop.md`) do frontmatter do flow

## Critérios de Sucesso

- [x] Usuário consegue anexar um ou mais arquivos de qualquer pasta via botão "Anexar" e vê chips removíveis no composer — implementado; validação visual é manual (ver abaixo)
- [x] O conteúdo dos arquivos anexados chega ao agente junto com o texto digitado — coberto por `send_withValidAttachment_injectsContentAndClearsPending`
- [x] Anexo inválido (inexistente/binário/grande demais) não quebra o envio — aparece como aviso na própria mensagem do usuário — coberto por `send_withInvalidAttachment_addsWarningWithoutBlockingSend` e pelos 4 casos de rejeição em `file_attachment_service_test.dart`
- [x] Mensagens antigas no histórico mostram os arquivos que foram anexados a elas — `MessageCard` renderiza `entry.attachedFiles`; `flutter analyze` confirma a fiação sem erros de tipo
- [x] Build sem erros — `flutter analyze` (app) e `dart analyze` (pacote raiz): 0 issues
- [x] Todos os testes unitários passando — 27 testes novos/estendidos (10 entidade+serviço, 6 `ChatMessageEntity`, 11 `ChatCubit`) passam; suíte completa do app em 91/100, os 9 restantes são falhas pré-existentes de overflow em `workspace_top_bar.dart` (confirmado via `git stash`, não relacionadas a esta feature); `dart test` do pacote raiz: 37/37
- [ ] _(manual — feito pelo usuário)_ Validação funcional no app

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Prompt fica muito grande com vários anexos de 512 KiB cada, estourando contexto do modelo pequeno | Média | Mesmo limite por arquivo já usado em `FileMentionService`; nenhum limite adicional de quantidade é imposto nesta entrega — decisão consciente de manter simples, revisitar se virar problema real |
| Mover `_FileChip` para arquivo público pode quebrar import não previsto | Baixa | `flutter analyze` após a Fase 5 pega qualquer referência solta |

## Rollback

Reverter os commits desta feature; nenhuma migração de dados persistidos é criada (anexos vivem só em memória, `pendingAttachments` não é serializado pelo `DesktopStorageService`).
