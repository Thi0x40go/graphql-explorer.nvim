local M = {}

local conn_mgr = require("graphql-explorer.connection")

-- Mantém uma referência ao buffer de resultados para reusá-lo se aberto
M.result_buf = nil
M.result_win = nil

--- Busca as variáveis associadas ao buffer atual
local function get_variables(filepath)
  -- 1. Tenta achar arquivo JSON companheiro (ex: query.graphql -> query.json ou query.variables.json)
  if filepath and filepath ~= "" then
    local base = filepath:match("(.+)%.%w+$")
    if base then
      local json_paths = { base .. ".json", base .. ".variables.json" }
      for _, path in ipairs(json_paths) do
        if vim.fn.filereadable(path) == 1 then
          local content = table.concat(vim.fn.readfile(path), "\n")
          local ok, decoded = pcall(vim.fn.json_decode, content)
          if ok then
            return decoded
          end
        end
      end
    end
  end

  -- 2. Tenta parsear metadados no início do buffer, ex: "# variables: { "id": 1 }"
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    local inline_vars = line:match("^#%s*variables:%s*(.+)$")
    if inline_vars then
      local ok, decoded = pcall(vim.fn.json_decode, inline_vars)
      if ok then
        return decoded
      end
    end
  end

  return nil
end

--- Exibe a resposta JSON formatada em uma janela split lateral
local function display_result(content, duration_ms, endpoint_name, success, error_msg)
  local formatted = ""
  if success and content then
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if ok then
      formatted = vim.fn.json_encode(decoded)
      -- Embeleza o JSON usando jq se disponível, ou fallback para Python/Lua
      if vim.fn.executable("jq") == 1 then
        formatted = vim.fn.system({"jq", "."}, content)
      elseif vim.fn.executable("python3") == 1 then
        formatted = vim.fn.system({"python3", "-m", "json.tool"}, content)
      end
    else
      formatted = content
    end
  else
    formatted = error_msg or "Unknown error during request."
  end

  -- Monta o cabeçalho de status da resposta em formato de comentário jsonc
  local header = {}
  if success then
    table.insert(header, string.format("// ⚡ Status: SUCCESS | ⏱️ Time: %dms | 🌐 Endpoint: %s", duration_ms, endpoint_name))
  else
    table.insert(header, string.format("// ❌ Status: ERROR | ⏱️ Time: %dms | 🌐 Endpoint: %s", duration_ms, endpoint_name))
  end
  table.insert(header, "// " .. string.rep("━", 55))
  table.insert(header, "")

  -- Verifica se o buffer de resultado existe e é válido, senão cria um novo
  if not M.result_buf or not vim.api.nvim_buf_is_valid(M.result_buf) then
    M.result_buf = vim.api.nvim_create_buf(false, true) -- nofile, scratch
    vim.api.nvim_set_option_value("filetype", "jsonc", { buf = M.result_buf }) -- jsonc para ignorar os comentários de cabeçalho
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.result_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = M.result_buf })
    vim.api.nvim_buf_set_name(M.result_buf, "GraphQL Result")
  else
    vim.api.nvim_set_option_value("filetype", "jsonc", { buf = M.result_buf })
  end

  -- Divide as linhas do conteúdo formatado
  local lines = {}
  for _, h_line in ipairs(header) do
    table.insert(lines, h_line)
  end
  for line in formatted:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  vim.api.nvim_buf_set_lines(M.result_buf, 0, -1, false, lines)

  -- Highlights no cabeçalho
  local ns = vim.api.nvim_create_namespace("graphql_result_header")
  vim.api.nvim_buf_clear_namespace(M.result_buf, ns, 0, -1)

  if success then
    vim.api.nvim_set_hl(0, "GraphQLResultSuccess", { fg = "#10b981", bold = true }) -- Green
    vim.api.nvim_buf_add_highlight(M.result_buf, ns, "GraphQLResultSuccess", 0, 3, 20)
  else
    vim.api.nvim_set_hl(0, "GraphQLResultError", { fg = "#ef4444", bold = true }) -- Red
    vim.api.nvim_buf_add_highlight(M.result_buf, ns, "GraphQLResultError", 0, 3, 17)
  end
  vim.api.nvim_set_hl(0, "GraphQLResultMeta", { fg = "#818cf8", italic = true }) -- Indigo/Purple light
  vim.api.nvim_buf_add_highlight(M.result_buf, ns, "GraphQLResultMeta", 0, 20, -1)

  -- Abre o split lateral se a janela não estiver ativa
  if not M.result_win or not vim.api.nvim_win_is_valid(M.result_win) then
    vim.cmd("vsplit")
    M.result_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.result_win, M.result_buf)
  else
    vim.api.nvim_win_set_buf(M.result_win, M.result_buf)
  end
end

--- Executa a query GraphQL do buffer atual
function M.execute_query()
  local conn = conn_mgr.get_active()
  if not conn then
    vim.notify("[GraphQL Explorer] No active connection. Use :GraphQLSelectConnection first.", vim.log.levels.WARN)
    return
  end

  -- Obtém todo o conteúdo do buffer (a query)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local query_lines = {}
  for _, line in ipairs(lines) do
    -- Ignora comentários ao concatenar a query
    if not line:match("^#") then
      table.insert(query_lines, line)
    end
  end
  local query = table.concat(query_lines, "\n")

  if query:gsub("%s+", "") == "" then
    vim.notify("[GraphQL Explorer] The current buffer is empty or contains only comments.", vim.log.levels.WARN)
    return
  end

  -- Busca variáveis
  local filepath = vim.api.nvim_buf_get_name(0)
  local variables = get_variables(filepath)

  -- Monta payload JSON
  local payload_data = {
    query = query,
    variables = variables or {}
  }
  local payload = vim.fn.json_encode(payload_data)

  vim.notify(string.format("[GraphQL Explorer] Sending request to '%s'...", conn.name), vim.log.levels.INFO)

  -- Prepara argumentos do curl
  local args = {
    "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", "@-",
    conn.url
  }

  -- Adiciona headers
  if conn.headers then
    for k, v in pairs(conn.headers) do
      table.insert(args, "-H")
      table.insert(args, string.format("%s: %s", k, v))
    end
  end

  local start_time = vim.uv.hrtime()

  -- Executa requisição assíncrona
  vim.system({"curl", unpack(args)}, {
    stdin = payload,
    text = true
  }, function(obj)
    local end_time = vim.uv.hrtime()
    local duration_ms = math.floor((end_time - start_time) / 1e6)

    vim.schedule(function()
      if obj.code ~= 0 then
        display_result(nil, duration_ms, conn.name, false, obj.stderr or ("Curl error: code " .. obj.code))
        return
      end
      display_result(obj.stdout, duration_ms, conn.name, true)
    end)
  end)
end

return M
