# 🤖 Salvador Desktop

Salvador Desktop é a interface gráfica (GUI) em Flutter para o agente local.
Este aplicativo reutiliza o `salvador_cli` como uma dependência local (`path: ..`),
permitindo que a interface gráfica seja mantida separada da lógica de implementação
e do executável de terminal.

## ✨ Recursos

*   **Gerenciamento de Modelos:** Descoberta e seleção de modelos instalados no Ollama.
*   **Configuração:** Configuração do host e da pasta permitida para o agente.
*   **Interação:** Chat com suporte a menções de arquivos (usando `@`).
*   **Ferramentas:** Suporte a ações de sistema como `read_file`, `write_file`, `replace_in_file` e `run_command`.
*   **Monitoramento:** Histórico visual de ferramentas, avisos e métricas de inferência.
*   **Controles:** Comandos de controle como `/clear`, `/exit` e `/quit`, além de controles equivalentes na interface.

## 🚀 Como Executar

Certifique-se de que o Ollama esteja ativo e execute os seguintes comandos a partir da raiz do repositório:

### 1. Instalação de Dependências
```sh
flutter pub get
```

### 2. Execução
Para rodar em desenvolvimento (exemplo para macOS):
```sh
flutter run -d macos
```
Substitua `macos` por `windows` ou `linux` conforme a plataforma desejada.

### 3. Construção (Build)
Para gerar uma versão distribuível, utilize:
*   `flutter build macos`
*   `flutter build windows`
*   `flutter build linux`

> **⚠️ Aviso de Segurança:** Assim como no CLI, o comando `run_command` executa processos com as permissões do usuário e **não constitui um sandbox**. Use com cautela.
