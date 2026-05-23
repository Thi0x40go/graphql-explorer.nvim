local M = {}

--- Retorna o diretório raiz do projeto atual
function M.get_project_root()
  local root_markers = { ".git", "package.json", "lazyvim.json", "Cargo.toml", "Makefile" }
  local current_buf = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buf)
  
  -- Se o buffer tiver arquivo associado, tenta achar o root a partir dele
  if current_file ~= "" then
    local root = vim.fs.root(current_file, root_markers)
    if root then
      return root
    end
  end
  
  -- Caso contrário, usa o diretório de trabalho atual (cwd)
  return vim.fn.getcwd()
end

--- Cria ou atualiza o graphql.config.json para apontar para o schema correto
function M.update_config(conn, schema_path)
  local root = M.get_project_root()
  local config_path = root .. "/graphql.config.json"
  
  -- Estrutura básica recomendada pela GraphQL Foundation
  local config_data = {
    schema = schema_path,
    documents = {
      "**/*.graphql",
      "**/*.gql"
    }
  }

  local file = io.open(config_path, "w")
  if file then
    local ok, json_str = pcall(vim.fn.json_encode, config_data)
    if ok then
      file:write(json_str)
      file:close()
      vim.notify(string.format("[GraphQL Explorer] LSP atualizado: graphql.config.json criado em %s", root), vim.log.levels.INFO)
      
      -- Tenta notificar o LSP do Neovim para recarregar a configuração se o servidor estiver ativo
      M.reload_graphql_lsp()
    end
  else
    vim.notify("[GraphQL Explorer] Não foi possível gravar o arquivo graphql.config.json na raiz do projeto.", vim.log.levels.WARN)
  end
end

--- Reinicia o cliente LSP do graphql para ler o novo arquivo de configuração
function M.reload_graphql_lsp()
  local active_clients = vim.lsp.get_clients({ name = "graphql" })
  for _, client in ipairs(active_clients) do
    vim.notify("[GraphQL Explorer] Reiniciando LSP do GraphQL para carregar novo schema...", vim.log.levels.INFO)
    vim.lsp.buf_detach_client(0, client.id)
    client.stop()
    -- Espera um pouco e reinicia
    vim.defer_fn(function()
      pcall(vim.cmd, "LspStart graphql")
    end, 500)
  end
end

return M
