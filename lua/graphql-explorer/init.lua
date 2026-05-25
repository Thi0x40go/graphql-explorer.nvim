local M = {}

local conn_mgr = require("graphql-explorer.connection")
local executor = require("graphql-explorer.executor")
local explorer = require("graphql-explorer.explorer")

-- Configurações padrões do plugin
local DEFAULT_OPTS = {
  connections = {},
}

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, opts or {})

  -- Configura as conexões
  conn_mgr.connections = opts.connections
  if #conn_mgr.connections > 0 then
    conn_mgr.active_index = 1 -- Define a primeira conexão como ativa por padrão
  end

  -- Registra comandos do Neovim
  vim.api.nvim_create_user_command("GraphQLSelectConnection", function()
    conn_mgr.select_connection(function(conn)
      -- Callback após mudar a conexão: atualiza o render do explorer se estiver aberto
      if explorer.win and vim.api.nvim_win_is_valid(explorer.win) then
        explorer.toggle() -- Fecha
        explorer.toggle() -- Abre com o novo schema
      end
    end)
  end, { desc = "Select active GraphQL Connection" })

  vim.api.nvim_create_user_command("GraphQLSetEndpoint", function()
    conn_mgr.set_active_endpoint(function(conn)
      if explorer.win and vim.api.nvim_win_is_valid(explorer.win) then
        explorer.toggle()
        explorer.toggle()
      end
    end)
  end, { desc = "Change Endpoint URL of the active connection" })

  vim.api.nvim_create_user_command("GraphQLSetAuth", function()
    conn_mgr.set_active_auth(function(conn)
      if explorer.win and vim.api.nvim_win_is_valid(explorer.win) then
        explorer.toggle()
        explorer.toggle()
      end
    end)
  end, { desc = "Change Authorization token of the active connection" })

  vim.api.nvim_create_user_command("GraphQLExecute", function()
    executor.execute_query()
  end, { desc = "Execute GraphQL Query from buffer" })

  vim.api.nvim_create_user_command("GraphQLExplorerToggle", function()
    explorer.toggle()
  end, { desc = "Open/Close GraphQL Schema Explorer" })

  vim.api.nvim_create_user_command("GraphQLDownloadSchema", function()
    local conn = conn_mgr.get_active()
    if conn then
      conn_mgr.download_schema(conn, function(success)
        if success and explorer.win and vim.api.nvim_win_is_valid(explorer.win) then
          explorer.render()
        end
      end)
    else
      vim.notify("[GraphQL Explorer] No active connection selected.", vim.log.levels.WARN)
    end
  end, { desc = "Manually download Schema from the active endpoint" })

  -- Configuração automática de sintaxe para arquivos .graphql
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = { "*.graphql", "*.gql" },
    callback = function()
      vim.api.nvim_set_option_value("filetype", "graphql", { buf = 0 })
    end
  })
end

return M
