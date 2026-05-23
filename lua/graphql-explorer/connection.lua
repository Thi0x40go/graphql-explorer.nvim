local M = {}

M.connections = {}
M.active_index = nil

-- Caminho padrão para salvar os schemas baixados
M.schema_dir = vim.fn.stdpath("cache") .. "/graphql-explorer"

-- Garante que o diretório de cache existe
if vim.fn.isdirectory(M.schema_dir) == 0 then
  vim.fn.mkdir(M.schema_dir, "p")
end

-- Query de introspecção compactada para obter todos os tipos, queries e mutations
local INTROSPECTION_QUERY = [[
query IntrospectionQuery {
  __schema {
    queryType { name }
    mutationType { name }
    subscriptionType { name }
    types {
      kind
      name
      description
      fields(includeDeprecated: true) {
        name
        description
        args {
          name
          description
          type {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                }
              }
            }
          }
          defaultValue
        }
        type {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
              }
            }
          }
        }
        isDeprecated
        deprecationReason
      }
      inputFields {
        name
        description
        type {
          kind
          name
          ofType {
            kind
            name
          }
        }
        defaultValue
      }
      interfaces {
        kind
        name
      }
      enumValues(includeDeprecated: true) {
        name
        description
        isDeprecated
        deprecationReason
      }
      possibleTypes {
        kind
        name
      }
    }
  }
}
]]

--- Retorna a conexão ativa
function M.get_active()
  if not M.active_index or not M.connections[M.active_index] then
    return nil
  end
  return M.connections[M.active_index]
end

--- Seleciona uma conexão ativa usando vim.ui.select
function M.select_connection(callback)
  if #M.connections == 0 then
    vim.notify("[GraphQL Explorer] Nenhuma conexão configurada. Adicione conexões no seu setup().", vim.log.levels.WARN)
    return
  end

  local options = {}
  for i, conn in ipairs(M.connections) do
    table.insert(options, string.format("%d: %s (%s)", i, conn.name, conn.url))
  end

  vim.ui.select(options, {
    prompt = "Selecione a Conexão GraphQL ativa:",
  }, function(choice, idx)
    if choice then
      M.active_index = idx
      local conn = M.connections[idx]
      vim.notify(string.format("[GraphQL Explorer] Conexão ativa alterada para: %s", conn.name), vim.log.levels.INFO)
      
      -- Ao selecionar, sincroniza o LSP e baixa o schema se necessário
      M.download_schema(conn, function(success)
        if success and callback then
          callback(conn)
        end
      end)
    end
  end)
end

--- Executa a query de introspecção no endpoint usando curl assincronamente via vim.system
function M.download_schema(conn, callback)
  local schema_path = M.schema_dir .. "/" .. conn.name .. ".json"
  
  vim.notify(string.format("[GraphQL Explorer] Baixando schema para '%s'...", conn.name), vim.log.levels.INFO)
  
  -- Monta o payload JSON
  local payload = vim.fn.json_encode({
    query = INTROSPECTION_QUERY
  })

  -- Prepara argumentos do curl
  local args = {
    "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", "@-",
    conn.url
  }

  -- Adiciona headers customizados da conexão
  if conn.headers then
    for k, v in pairs(conn.headers) do
      table.insert(args, "-H")
      table.insert(args, string.format("%s: %s", k, v))
    end
  end

  -- Escreve o payload e passa pro stdin do curl
  local stderr = {}
  local stdout = {}
  
  -- Usamos o vim.system (disponível no Neovim 0.10+)
  vim.system({"curl", unpack(args)}, {
    stdin = payload,
    text = true,
  }, function(obj)
    if obj.code ~= 0 then
      vim.schedule(function()
        vim.notify(string.format("[GraphQL Explorer] Falha ao baixar schema (Curl code %d):\n%s", obj.code, obj.stderr or ""), vim.log.levels.ERROR)
        if callback then callback(false) end
      end)
      return
    end

    -- Sanitiza sequências de escape inválidas comuns que quebram o json_decode do Neovim (como \` e \')
    local clean_stdout = obj.stdout:gsub("\\`", "`"):gsub("\\'", "'")

    -- Tenta parsear a resposta para validar se é um JSON GraphQL válido usando o parser Lua nativo
    local ok, data = pcall(vim.json.decode, clean_stdout)
    if not ok or not data or not data.data or not data.data.__schema then
      -- Salva um log de depuração
      local log_path = M.schema_dir .. "/debug_error.log"
      local log_file = io.open(log_path, "w")
      if log_file then
        log_file:write("STDOUT:\n" .. tostring(obj.stdout) .. "\n\nSTDERR:\n" .. tostring(obj.stderr) .. "\n\nERROR:\n" .. tostring(data))
        log_file:close()
      end
      vim.schedule(function()
        local err_msg = not ok and tostring(data) or "Estrutura 'data.data.__schema' ausente no JSON"
        vim.notify(string.format("[GraphQL Explorer] Falha no schema: %s", err_msg), vim.log.levels.ERROR)
        if callback then callback(false) end
      end)
      return
    end

    -- Salva o schema no arquivo de cache
    local file = io.open(schema_path, "w")
    if file then
      file:write(clean_stdout)
      file:close()
      vim.schedule(function()
        vim.notify(string.format("[GraphQL Explorer] Schema de '%s' salvo com sucesso!", conn.name), vim.log.levels.INFO)
        
        -- Atualiza o arquivo local para o LSP
        require("graphql-explorer.lsp").update_config(conn, schema_path)
        
        if callback then callback(true) end
      end)
    else
      vim.schedule(function()
        vim.notify("[GraphQL Explorer] Não foi possível salvar o arquivo de schema no cache.", vim.log.levels.ERROR)
        if callback then callback(false) end
      end)
    end
  end)
end

--- Retorna o caminho do schema em cache para uma conexão
function M.get_schema_path(conn)
  return M.schema_dir .. "/" .. conn.name .. ".json"
end

return M
