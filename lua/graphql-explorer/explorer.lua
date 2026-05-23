local M = {}

local conn_mgr = require("graphql-explorer.connection")

M.buf = nil
M.win = nil
M.schema = nil
M.types_by_name = {}

-- Estado de expansão: { [category_name] = true/false, [type_name] = true/false }
M.state = {
  expanded = {
    queries = false,
    mutations = false,
    objects = false,
    inputs = false,
    enums = false,
  }
}

-- Mapeia cada linha do buffer de volta para uma tabela de metadados
M.lines_meta = {}

-- Helper para formatar tipos GraphQL recursivamente
local function format_type(t)
  if not t then return "Unknown" end
  if t.kind == "NON_NULL" then
    return format_type(t.ofType) .. "!"
  elseif t.kind == "LIST" then
    return "[" .. format_type(t.ofType) .. "]"
  else
    return t.name or "Unknown"
  end
end

-- Helper para extrair o nome base de um tipo (removendo wrappers de LIST e NON_NULL)
local function get_base_type_name(t)
  if not t then return nil end
  if t.name then return t.name end
  return get_base_type_name(t.ofType)
end

-- Formata argumentos de um campo
local function format_args(args)
  if not args or #args == 0 then return "" end
  local formatted = {}
  for _, arg in ipairs(args) do
    table.insert(formatted, string.format("%s: %s", arg.name, format_type(arg.type)))
  end
  return "(" .. table.concat(formatted, ", ") .. ")"
end

-- Helper recursivo para remover valores nulos (vim.json.null/vim.NIL) da tabela decodificada
local function clean_nulls(tbl)
  if type(tbl) ~= "table" then return tbl end
  for k, v in pairs(tbl) do
    if v == vim.json.null or v == vim.NIL then
      tbl[k] = nil
    else
      clean_nulls(v)
    end
  end
  return tbl
end

--- Carrega e parseia o schema da conexão ativa
local function load_active_schema()
  local conn = conn_mgr.get_active()
  if not conn then return false end

  local path = conn_mgr.get_schema_path(conn)
  if vim.fn.filereadable(path) == 0 then
    return false
  end

  local content = table.concat(vim.fn.readfile(path), "\n")
  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data or not data.data or not data.data.__schema then
    return false
  end

  -- Limpa todos os valores nulos para que o código Lua lide com nil puro
  data = clean_nulls(data)

  M.schema = data.data.__schema
  M.types_by_name = {}
  for _, t in ipairs(M.schema.types) do
    M.types_by_name[t.name] = t
  end
  return true
end

--- Renderiza o buffer do Explorer com base no estado atual
function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  -- Habilita escrita temporariamente para atualizar
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.buf })

  local lines = {}
  M.lines_meta = {}

  local function add_line(text, meta)
    table.insert(lines, text)
    table.insert(M.lines_meta, meta or {})
  end

  local conn = conn_mgr.get_active()
  add_line("🔍 SCHEMA EXPLORER")
  add_line("Endpoint: " .. (conn and conn.name or "Nenhum"))
  add_line(string.rep("━", 30))
  add_line("")

  if not M.schema then
    add_line("Nenhum schema carregado.")
    add_line("Execute :GraphQLSelectConnection")
    add_line("ou :GraphQLDownloadSchema")
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })
    return
  end

  local schema = M.schema

  -- 1. QUERIES
  local query_type_name = schema.queryType and schema.queryType.name
  local query_type = query_type_name and M.types_by_name[query_type_name]
  if query_type and query_type.fields and #query_type.fields > 0 then
    local icon = M.state.expanded.queries and "▼" or "▶"
    add_line(string.format("%s 📂 Queries", icon), { type = "category", name = "queries" })
    if M.state.expanded.queries then
      for _, f in ipairs(query_type.fields) do
        local line = string.format("  • %s%s: %s", f.name, format_args(f.args), format_type(f.type))
        add_line(line, { type = "field", data = f })
      end
    end
    add_line("")
  end

  -- 2. MUTATIONS
  local mut_type_name = schema.mutationType and schema.mutationType.name
  local mut_type = mut_type_name and M.types_by_name[mut_type_name]
  if mut_type and mut_type.fields and #mut_type.fields > 0 then
    local icon = M.state.expanded.mutations and "▼" or "▶"
    add_line(string.format("%s 📂 Mutations", icon), { type = "category", name = "mutations" })
    if M.state.expanded.mutations then
      for _, f in ipairs(mut_type.fields) do
        local line = string.format("  • %s%s: %s", f.name, format_args(f.args), format_type(f.type))
        add_line(line, { type = "field", data = f })
      end
    end
    add_line("")
  end

  -- Filtra tipos gerais
  local objects = {}
  local inputs = {}
  local enums = {}

  for _, t in ipairs(schema.types) do
    if not t.name:match("^__") then -- Ignora tipos internos do GraphQL
      if t.name ~= query_type_name and (not mut_type or t.name ~= mut_type_name) then
        if t.kind == "OBJECT" then
          table.insert(objects, t)
        elseif t.kind == "INPUT_OBJECT" then
          table.insert(inputs, t)
        elseif t.kind == "ENUM" then
          table.insert(enums, t)
        end
      end
    end
  end

  -- Helper para ordenação alfabética
  local function sort_by_name(a, b) return a.name < b.name end
  table.sort(objects, sort_by_name)
  table.sort(inputs, sort_by_name)
  table.sort(enums, sort_by_name)

  -- 3. OBJECT TYPES
  if #objects > 0 then
    local icon = M.state.expanded.objects and "▼" or "▶"
    add_line(string.format("%s 📂 Types (Objects)", icon), { type = "category", name = "objects" })
    if M.state.expanded.objects then
      for _, t in ipairs(objects) do
        add_line("  ◽ " .. t.name, { type = "type_link", name = t.name })
      end
    end
    add_line("")
  end

  -- 4. INPUTS
  if #inputs > 0 then
    local icon = M.state.expanded.inputs and "▼" or "▶"
    add_line(string.format("%s 📂 Inputs", icon), { type = "category", name = "inputs" })
    if M.state.expanded.inputs then
      for _, t in ipairs(inputs) do
        add_line("  ◽ " .. t.name, { type = "type_link", name = t.name })
      end
    end
    add_line("")
  end

  -- 5. ENUMS
  if #enums > 0 then
    local icon = M.state.expanded.enums and "▼" or "▶"
    add_line(string.format("%s 📂 Enums", icon), { type = "category", name = "enums" })
    if M.state.expanded.enums then
      for _, t in ipairs(enums) do
        add_line("  ◽ " .. t.name, { type = "type_link", name = t.name })
      end
    end
    add_line("")
  end

  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })
end

--- Exibe os detalhes de um tipo ou campo em uma janela flutuante
local function show_details_float(title, info_lines)
  local width = math.min(70, vim.o.columns - 10)
  local height = math.min(#info_lines + 4, vim.o.rows - 10)
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, info_lines)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.rows - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  
  -- Keymaps para fechar o float
  local close_keys = { "q", "<esc>", "<CR>" }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, silent = true })
  end
end

--- Exibe detalhes do tipo selecionado
local function show_type_details(type_name)
  local t = M.types_by_name[type_name]
  if not t then return end

  local lines = {}
  table.insert(lines, "# " .. t.name)
  if t.description and t.description ~= "" then
    table.insert(lines, "_" .. t.description .. "_")
  end
  table.insert(lines, "")

  if t.kind == "ENUM" then
    table.insert(lines, "## Valores:")
    for _, val in ipairs(t.enumValues or {}) do
      local desc = val.description and (" - " .. val.description) or ""
      table.insert(lines, string.format("* `%s`%s", val.name, desc))
    end
  elseif t.kind == "INPUT_OBJECT" then
    table.insert(lines, "## Campos de Entrada (Input Fields):")
    for _, field in ipairs(t.inputFields or {}) do
      local desc = field.description and (" - " .. field.description) or ""
      table.insert(lines, string.format("* **%s**: `%s` %s", field.name, format_type(field.type), desc))
    end
  else
    table.insert(lines, "## Campos (Fields):")
    for _, field in ipairs(t.fields or {}) do
      local desc = field.description and (" - " .. field.description) or ""
      table.insert(lines, string.format("* **%s**%s: `%s` %s", field.name, format_args(field.args), format_type(field.type), desc))
    end
  end

  show_details_float("GraphQL Tipo: " .. type_name, lines)
end

--- Ação de clique / Enter no explorer
function M.handle_action()
  local line_idx = vim.api.nvim_win_get_cursor(0)[1]
  local meta = M.lines_meta[line_idx]
  if not meta then return end

  if meta.type == "category" then
    M.state.expanded[meta.name] = not M.state.expanded[meta.name]
    M.render()
    vim.api.nvim_win_set_cursor(0, { line_idx, 0 })
  elseif meta.type == "type_link" then
    show_type_details(meta.name)
  elseif meta.type == "field" then
    -- Abre detalhes do tipo base daquele campo
    local base_type = get_base_type_name(meta.data.type)
    if base_type then
      show_type_details(base_type)
    end
  end
end

--- Abre ou fecha a janela do explorer lateral
function M.toggle()
  -- Se a janela estiver aberta e for válida, fecha-a
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
    return
  end

  -- Carrega o schema da conexão ativa
  load_active_schema()

  -- Cria buffer se não existir
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("filetype", "graphql-explorer", { buf = M.buf })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = M.buf })
    vim.api.nvim_buf_set_name(M.buf, "GraphQL Schema Explorer")

    -- Define keymaps para o explorer
    vim.keymap.set("n", "<CR>", M.handle_action, { buffer = M.buf, silent = true, desc = "Expandir / Detalhes" })
    vim.keymap.set("n", "q", M.toggle, { buffer = M.buf, silent = true, desc = "Fechar Explorer" })
  end

  -- Renderiza
  M.render()

  -- Abre split lateral esquerdo
  vim.cmd("topleft vsplit")
  vim.cmd("vertical resize 35")
  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)

  -- Configurações da janela do explorer
  vim.api.nvim_set_option_value("number", false, { win = M.win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = M.win })
  vim.api.nvim_set_option_value("winfixwidth", true, { win = M.win })
end

return M
