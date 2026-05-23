# graphql-explorer.nvim

[English (en)](./README.md)

Um plugin Neovim escrito em Lua para executar queries GraphQL e explorar visualmente schemas (como nas extensões do navegador), com integração automática com o **`graphql-lsp`**.

---

## ✨ Funcionalidades

*   🔌 **Gerenciador de Conexões:** Defina múltiplos profiles de API (endpoints e headers de autenticação).
*   🔍 **Schema Explorer Lateral:** Uma árvore interativa com Queries, Mutations e Tipos do endpoint. Aperte `<CR>` (Enter) para abrir uma janela flutuante com a documentação do tipo (campos, argumentos, tipos de retorno, descrições).
*   🚀 **Query Executor:** Execute queries direto do seu buffer `.graphql` e veja os resultados JSON formatados em uma split lateral.
*   🧠 **LSP Automático:** Cria o arquivo `graphql.config.json` na raiz do projeto dinamicamente ao selecionar um endpoint, permitindo que a autocompletação do seu LSP oficial do GraphQL (`graphql-lsp`) funcione imediatamente.
*   ⚡ **Zero dependências externas:** Usa `curl` nativo do sistema e comandos assíncronos do Neovim 0.10+ (`vim.system`).

---

## 📦 Instalação (com Lazy.nvim)

Adicione as configurações abaixo na sua estrutura de plugins do Neovim (ex: `lua/plugins/graphql-explorer.lua`):

```lua
return {
  {
    "Thi0x40go/graphql-explorer.nvim",
    opts = {
      connections = {
        {
          name = "Countries API",
          url = "https://countries.trevorblades.com/",
          headers = {}
        },
        {
          name = "Local Dev",
          url = "http://localhost:4000/graphql",
          headers = {
            ["Authorization"] = "Bearer seu-token-aqui"
          }
        }
      }
    },
    config = function(_, opts)
      require("graphql-explorer").setup(opts)
    end,
    keys = {
      { "<leader>gxs", "<cmd>GraphQLSelectConnection<cr>", desc = "Selecionar Conexão GraphQL" },
      { "<leader>gxe", "<cmd>GraphQLExplorerToggle<cr>", desc = "Abrir/Fechar Schema Explorer" },
      { "<leader>gxr", "<cmd>GraphQLExecute<cr>", desc = "Executar Query GraphQL" },
      { "<leader>gxd", "<cmd>GraphQLDownloadSchema<cr>", desc = "Baixar Schema do Endpoint" },
    }
  }
}
```

---

## 🎮 Comandos Disponíveis

| Comando | Descrição |
| :--- | :--- |
| `:GraphQLSelectConnection` | Abre uma lista interativa (`vim.ui.select`) para escolher a conexão ativa (incluindo opção para criar conexão customizada). |
| `:GraphQLSetEndpoint` | Altera a URL do endpoint ativo dinamicamente. |
| `:GraphQLSetAuth` | Altera o token de autorização do endpoint ativo dinamicamente. |
| `:GraphQLDownloadSchema` | Baixa (ou atualiza) o schema do endpoint ativo usando Introspecção. |
| `:GraphQLExplorerToggle` | Abre ou fecha o painel lateral com o Schema Explorer. |
| `:GraphQLExecute` | Executa a query GraphQL do buffer atual e mostra o resultado JSON em um split vertical. |

---

## 💡 Como Usar

### 1. Selecionando uma conexão
1. Execute `:GraphQLSelectConnection` e escolha a API.
2. O plugin fará download do schema automaticamente via Introspecção.
3. Se você estiver dentro de um projeto, um `graphql.config.json` será criado na raiz para ligar o autocompletação do LSP.

### 2. Explorando o Schema
1. Digite `:GraphQLExplorerToggle` para abrir o painel esquerdo.
2. Navegue até a categoria desejada (ex: **Queries**, **Types**) e aperte `<CR>` (Enter) para abrir/recolher.
3. Em um Tipo (ex: `Player`) ou Campo, aperte `<CR>` para abrir um popup contendo a documentação completa. Aperte `q` ou `Esc` para fechar o popup.

### 3. Escrevendo e executando Queries
1. Crie ou abra um arquivo `.graphql` (ex: `teste.graphql`).
2. Digite sua Query GraphQL.
3. Se você quiser enviar variáveis para a query:
   * **Método A:** Crie um arquivo com o mesmo nome e extensão `.json` no mesmo diretório (ex: `teste.json`) e escreva o JSON das variáveis nele.
   * **Método B:** Adicione um comentário na primeira linha do seu arquivo `.graphql` informando o JSON inline:
     ```graphql
     # variables: { "id": "123" }
     query GetUser($id: ID!) {
       user(id: $id) {
         name
       }
     }
     ```
4. Execute `:GraphQLExecute` (ou atalho `<leader>gxr`). O resultado abrirá em uma janela lateral direita formatado.
