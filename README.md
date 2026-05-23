# graphql-explorer.nvim

[Português (pt-br)](./README.pt-br.md)

A Neovim plugin written in Lua to execute GraphQL queries and visually explore schemas (similar to browser extensions), with automatic integration with **`graphql-lsp`**.

---

## ✨ Features

*   🔌 **Connection Manager:** Define multiple API profiles (endpoints and authentication headers).
*   🔍 **Sidebar Schema Explorer:** An interactive tree with Queries, Mutations, and Types from the endpoint. Press `<CR>` (Enter) to open a floating window with the type's documentation (fields, arguments, return types, descriptions).
*   🚀 **Query Executor:** Execute queries directly from your `.graphql` buffer and view formatted JSON results in a vertical split.
*   🧠 **Automatic LSP:** Dynamically creates the `graphql.config.json` file in the project root when selecting an endpoint, enabling autocompletion for the official GraphQL LSP (`graphql-lsp`) immediately.
*   ⚡ **Zero external dependencies:** Uses system native `curl` and Neovim 0.10+ asynchronous commands (`vim.system`).

---

## 📦 Installation (with Lazy.nvim)

Add the configuration below to your Neovim plugin structure (e.g., `lua/plugins/graphql-explorer.lua`):

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
            ["Authorization"] = "Bearer your-token-here"
          }
        }
      }
    },
    config = function(_, opts)
      require("graphql-explorer").setup(opts)
    end,
    keys = {
      { "<leader>gxs", "<cmd>GraphQLSelectConnection<cr>", desc = "Select GraphQL Connection" },
      { "<leader>gxe", "<cmd>GraphQLExplorerToggle<cr>", desc = "Toggle Schema Explorer" },
      { "<leader>gxr", "<cmd>GraphQLExecute<cr>", desc = "Execute GraphQL Query" },
      { "<leader>gxd", "<cmd>GraphQLDownloadSchema<cr>", desc = "Download Endpoint Schema" },
    }
  }
}
```

---

## 🎮 Available Commands

| Command | Description |
| :--- | :--- |
| `:GraphQLSelectConnection` | Opens an interactive list (`vim.ui.select`) to choose the active connection (including creating a custom one). |
| `:GraphQLSetEndpoint` | Dynamically updates the endpoint URL for the active connection. |
| `:GraphQLSetAuth` | Dynamically updates the Authorization header/token for the active connection. |
| `:GraphQLDownloadSchema` | Downloads (or updates) the active endpoint schema using Introspection. |
| `:GraphQLExplorerToggle` | Opens or closes the sidebar with the Schema Explorer. |
| `:GraphQLExecute` | Executes the GraphQL query from the current buffer and shows the JSON output in a vertical split. |

---

## 💡 Usage

### 1. Selecting a connection
1. Run `:GraphQLSelectConnection` and choose the API.
2. The plugin will download the schema automatically via Introspection.
3. If you are inside a project, a `graphql.config.json` will be created in the root directory to enable LSP autocompletion.

### 2. Exploring the Schema
1. Type `:GraphQLExplorerToggle` to open the left panel.
2. Navigate to the desired category (e.g., **Queries**, **Types**) and press `<CR>` (Enter) to expand/collapse.
3. On a Type (e.g., `Player`) or Field, press `<CR>` to open a popup containing the full documentation. Press `q` or `Esc` to close the popup.

### 3. Writing and executing Queries
1. Create or open a `.graphql` file (e.g., `test.graphql`).
2. Write your GraphQL Query.
3. If you want to send variables to the query:
   * **Method A:** Create a file with the same name and a `.json` extension in the same directory (e.g., `test.json`) and write the variables' JSON in it.
   * **Method B:** Add a comment on the first line of your `.graphql` file specifying the inline JSON:
     ```graphql
     # variables: { "id": "123" }
     query GetUser($id: ID!) {
       user(id: $id) {
         name
       }
     }
     ```
4. Run `:GraphQLExecute` (or shortcut `<leader>gxr`). The formatted result will open in a right vertical split.
