# Leve CLI

O Leve CLI é um agente de código local feito em Dart. Ele conversa com modelos
servidos pelo [Ollama](https://ollama.com/) e pode trabalhar dentro de uma pasta
do projeto, lendo, alterando arquivos e executando comandos.

O mesmo núcleo é usado por duas interfaces:

- **CLI interativa** em `bin/`, para usar no terminal;
- **app desktop Flutter** em `app/`, com chat, arquivos, anexos, configurações
  e um espaço visual para Git.

Tudo roda localmente: o projeto não envia prompts ou arquivos para serviços na
nuvem por conta própria. O modelo escolhido é servido pelo seu Ollama.

## O que ele faz

- conversa com modelos que suportam tool calling;
- lê, cria, substitui e edita arquivos dentro da raiz do projeto escolhida;
- executa comandos do sistema quando essa permissão está ativa;
- entende menções `@arquivo` e inclui o conteúdo do arquivo no contexto;
- carrega instruções de `AGENTS.md` e skills de `.agents/skills/`;
- mostra métricas de inferência do Ollama;
- oferece consultas e ações Git tipadas, com confirmação para ações arriscadas.

> As ferramentas de arquivo são confinadas à raiz selecionada. Já
> `run_command` usa as permissões normais do usuário e **não é um sandbox**.

## Requisitos

- Dart 3.12 ou superior;
- Ollama instalado e em execução em `http://127.0.0.1:11434`;
- ao menos um modelo instalado que suporte tool calling.

Exemplo de modelo:

```sh
ollama pull qwen2.5-coder:3b
```

## Usar pelo terminal

```sh
dart pub get
dart run bin/salvador_cli.dart
```

Opções principais:

```text
--model NOME     escolhe o modelo sem abrir a seleção
--host URL       endereço do servidor Ollama
--root CAMINHO   pasta acessível ao agente
--no-context     desliga AGENTS.md e skills do projeto
```

Durante o chat, use `@` para procurar e mencionar arquivos. Use `/` para ver
os comandos e skills disponíveis; `/clear` limpa a conversa e `/exit` encerra
o programa.

## App desktop

O diretório [`app/`](app/) contém a interface desktop em Flutter. Ela usa a
mesma lógica do pacote principal e permite conectar ao Ollama, escolher um
projeto, conversar com o agente, anexar arquivos, navegar pelos arquivos e
acompanhar operações Git.

Para preparar o app:

```sh
cd app
flutter pub get
```

## Desenvolvimento

O pacote principal não tem dependências de runtime e fica em `lib/`. A CLI e o
app desktop consomem esse mesmo pacote, evitando diferenças de comportamento
entre as interfaces.

Valide as alterações com:

```sh
dart analyze
dart test
cd app && flutter analyze && flutter test
```
