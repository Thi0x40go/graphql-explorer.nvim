local M = {}

local conn_mgr = require("graphql-explorer.connection")

M.buf = nil
M.win = nil
M.schema = nil
M.types_by_name = {}
M.original_buf = nil
M.float_win = nil

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

-- Arte em Pixel Art de Boas-Vindas
local WELCOME_ART = {
  "       .       .        .       .       .      ",
  "   .       .       .        .       .       .  ",
  "                 ●                             ",
  "                / \\                            ",
  "               /   \\                           ",
  "        ●─────●     ●─────●                    ",
  "         \\   / \\   / \\   /                     ",
  "          \\ /   \\ /   \\ /                      ",
  "           ●     ●     ●                       ",
  "          / \\   / \\   / \\                      ",
  "         /   \\ /   \\ /   \\                     ",
  "        ●─────●     ●─────●                    ",
  "               \\   /                           ",
  "                \\ /                            ",
  "                 ●                             ",
  "",
  "         ✨ GRAPHQL EXPLORER ✨          ",
  "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
  "",
  "  No active schema loaded.",
  "",
  "  Useful commands to manage:",
  "  ▸ :GraphQLSelectConnection (switch connection)",
  "  ▸ :GraphQLDownloadSchema (download current)",
  "  ▸ :GraphQLSetEndpoint (change endpoint url)",
  "  ▸ :GraphQLSetAuth (change token/headers)",
}

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

-- Aplica destaques coloridos de Pixel Art nas linhas do buffer do Explorer
local function apply_line_highlights(buf, line_num, text)
  local ns = vim.api.nvim_create_namespace("graphql_explorer_pixelart")
  
  -- Definição dos grupos de destaque com cores vivas e harmoniosas
  vim.api.nvim_set_hl(0, "GraphQLWelcomeStars", { fg = "#f59e0b", bold = true }) -- Amarelo ouro
  vim.api.nvim_set_hl(0, "GraphQLWelcomeRocket", { fg = "#ec4899", bold = true }) -- Rosa GraphQL
  vim.api.nvim_set_hl(0, "GraphQLWelcomeBorder", { fg = "#475569" }) -- Slate escuro para bordas
  vim.api.nvim_set_hl(0, "GraphQLWelcomeFire", { fg = "#f97316", bold = true }) -- Laranja fogo
  vim.api.nvim_set_hl(0, "GraphQLWelcomeTitle", { fg = "#f472b6", bold = true }) -- Rosa brilhante
  vim.api.nvim_set_hl(0, "GraphQLWelcomeBullets", { fg = "#a855f7" }) -- Roxo para setas e ícones
  
  if text:match("GRAPHQL EXPLORER") then
    local start_col = text:find("GRAPHQL EXPLORER") - 1
    local end_col = start_col + 16
    vim.api.nvim_buf_add_highlight(buf, ns, "GraphQLWelcomeTitle", line_num, start_col, end_col)
  end

  local byte_idx = 0
  while byte_idx < #text do
    local byte = string.byte(text, byte_idx + 1)
    local len = 1
    if byte >= 240 then len = 4
    elseif byte >= 224 then len = 3
    elseif byte >= 192 then len = 2
    end
    
    local char = text:sub(byte_idx + 1, byte_idx + len)
    
    local hl_group = nil
    if char == "." or char == "*" then
      hl_group = "GraphQLWelcomeStars"
    elseif char == "●" or char == "█" or char == "▀" or char == "▲" or char == "│" then
      hl_group = "GraphQLWelcomeRocket"
    elseif char == "/" or char == "\\" or char == "─" or char == "┌" or char == "┐" or char == "┘" or char == "└" or char == "┴" or char == "━" then
      hl_group = "GraphQLWelcomeBorder"
    elseif char == "(" or char == ")" or char == "🔥" then
      hl_group = "GraphQLWelcomeFire"
    elseif char == "▸" or char == "•" or char == "◽" then
      hl_group = "GraphQLWelcomeBullets"
    end
    
    if hl_group then
      vim.api.nvim_buf_add_highlight(buf, ns, hl_group, line_num, byte_idx, byte_idx + len)
    end
    
    byte_idx = byte_idx + len
  end
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

  -- Se não houver schema, exibe tela de boas-vindas com Pixel Art
  if not M.schema then
    for _, art_line in ipairs(WELCOME_ART) do
      add_line(art_line)
    end
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    
    -- Aplica os realces de Pixel Art
    local buf_lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
    for idx, text in ipairs(buf_lines) do
      apply_line_highlights(M.buf, idx - 1, text)
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })
    return
  end

  -- Se houver schema, adiciona cabeçalho com o logo compacto do GraphQL
  add_line("         ●         ")
  add_line("        / \\        ")
  add_line("    ●───●─●───●    ")
  add_line("     \\ /   \\ /     ")
  add_line("      ●     ●      ")
  add_line(" 🔍 SCHEMA EXPLORER ")
  add_line(" Endpoint: " .. (conn and conn.name or "None"))
  add_line(string.rep("━", 30))
  add_line("")

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
        add_line(line, { type = "field", data = f, category = "queries" })
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
        add_line(line, { type = "field", data = f, category = "mutations" })
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
  
  -- Aplica os realces de Pixel Art nas linhas do topo
  local buf_lines = vim.api.nvim_buf_get_lines(M.buf, 0, -1, false)
  for idx, text in ipairs(buf_lines) do
    apply_line_highlights(M.buf, idx - 1, text)
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })
end

-- Gera um fragmento de exemplo de campos para um tipo OBJECT
local function generate_sample_fragment(type_name)
  local t = M.types_by_name[type_name]
  if not t or not t.fields then return nil end

  local lines = {}
  table.insert(lines, string.format("fragment %sFields on %s {", type_name, type_name))
  local count = 0
  for _, field in ipairs(t.fields) do
    local base_name = get_base_type_name(field.type)
    local is_scalar = false
    if base_name then
      local field_t = M.types_by_name[base_name]
      if field_t then
        is_scalar = (field_t.kind == "SCALAR" or field_t.kind == "ENUM" or base_name == "ID" or base_name == "String" or base_name == "Int" or base_name == "Float" or base_name == "Boolean")
      end
    end
    
    if is_scalar then
      table.insert(lines, "  " .. field.name)
      count = count + 1
    else
      table.insert(lines, string.format("  %s {", field.name))
      table.insert(lines, "    id")
      table.insert(lines, "  }")
      count = count + 1
    end
    if count >= 6 then break end
  end
  table.insert(lines, "}")
  return table.concat(lines, "\n")
end

-- Gera um JSON de variáveis de exemplo para um INPUT_OBJECT
local function generate_sample_input_json(type_name)
  local t = M.types_by_name[type_name]
  if not t or not t.inputFields then return nil end

  local lines = {}
  table.insert(lines, "{")
  for _, field in ipairs(t.inputFields) do
    local base_name = get_base_type_name(field.type)
    local default_val = "null"
    if base_name == "String" then
      default_val = '"valor"'
    elseif base_name == "Int" or base_name == "Float" then
      default_val = "0"
    elseif base_name == "Boolean" then
      default_val = "false"
    elseif base_name == "ID" then
      default_val = '"id"'
    end
    table.insert(lines, string.format('  "%s": %s,', field.name, default_val))
  end
  table.insert(lines, "}")
  
  if #lines > 2 then
    lines[#lines - 1] = lines[#lines - 1]:gsub(",$", "")
  end
  return table.concat(lines, "\n")
end

-- Gera lista comentada de possíveis valores para ENUM
local function generate_sample_enum(t)
  local lines = {}
  table.insert(lines, string.format("# Valid values for ENUM %s:", t.name))
  for _, val in ipairs(t.enumValues or {}) do
    table.insert(lines, string.format("# - %s", val.name))
  end
  return table.concat(lines, "\n")
end

-- Gera uma query ou mutation completa baseada no campo
local function generate_sample_query_or_mutation(field, is_mutation)
  local name = field.name
  local op_type = is_mutation and "mutation" or "query"
  local op_name = name:sub(1,1):upper() .. name:sub(2)

  local var_decls = {}
  local arg_calls = {}
  if field.args and #field.args > 0 then
    for _, arg in ipairs(field.args) do
      table.insert(var_decls, string.format("$%s: %s", arg.name, format_type(arg.type)))
      table.insert(arg_calls, string.format("%s: $%s", arg.name, arg.name))
    end
  end

  local vars_str = #var_decls > 0 and ("(" .. table.concat(var_decls, ", ") .. ")") or ""
  local args_str = #arg_calls > 0 and ("(" .. table.concat(arg_calls, ", ") .. ")") or ""

  local lines = {}
  table.insert(lines, string.format("%s %s%s {", op_type, op_name, vars_str))
  table.insert(lines, string.format("  %s%s {", name, args_str))

  local ret_type_name = get_base_type_name(field.type)
  if ret_type_name then
    local ret_t = M.types_by_name[ret_type_name]
    if ret_t and ret_t.fields then
      local count = 0
      for _, f in ipairs(ret_t.fields) do
        local base_t = M.types_by_name[get_base_type_name(f.type)]
        local is_scalar = false
        if base_t then
          is_scalar = (base_t.kind == "SCALAR" or base_t.kind == "ENUM" or base_t.name == "ID" or base_t.name == "String" or base_t.name == "Int" or base_t.name == "Float" or base_t.name == "Boolean")
        else
          local bn = get_base_type_name(f.type)
          is_scalar = (bn == "ID" or bn == "String" or bn == "Int" or bn == "Float" or bn == "Boolean")
        end
        if is_scalar then
          table.insert(lines, "    " .. f.name)
          count = count + 1
        end
        if count >= 5 then break end
      end
      if count == 0 then
        table.insert(lines, "    id")
      end
    else
      table.insert(lines, "    # (scalar return type)")
    end
  else
    table.insert(lines, "    id")
  end

  table.insert(lines, "  }")
  table.insert(lines, "}")
  return table.concat(lines, "\n")
end

--- Exibe os detalhes de um tipo ou campo em uma janela flutuante
local function show_details_float(title, info_lines, example_code)
  -- Se já houver um float aberto, fecha antes de abrir o novo
  if M.float_win and vim.api.nvim_win_is_valid(M.float_win) then
    pcall(vim.api.nvim_win_close, M.float_win, true)
    M.float_win = nil
  end

  local width = math.min(80, vim.o.columns - 10)
  local height = math.min(#info_lines + 4, vim.o.lines - 10)
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, info_lines)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  M.float_win = win
  
  -- Keymaps para fechar o float
  local close_keys = { "q", "<esc>", "<CR>" }
  for _, key in ipairs(close_keys) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
      if M.float_win == win then
        M.float_win = nil
      end
    end, { buffer = buf, silent = true })
  end

  if example_code then
    -- 'y' para copiar o código de exemplo para o clipboard
    vim.keymap.set("n", "y", function()
      vim.fn.setreg("+", example_code)
      vim.notify("[GraphQL Explorer] Example copied to clipboard!", vim.log.levels.INFO)
    end, { buffer = buf, silent = true, desc = "Copy example" })

    -- 'i' para inserir o código de exemplo no buffer original (de onde o explorer foi aberto)
    vim.keymap.set("n", "i", function()
      local target_buf = M.original_buf
      if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
        -- Fecha a janela float
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
        if M.float_win == win then
          M.float_win = nil
        end
        -- Insere as linhas
        local lines = {}
        for line in example_code:gmatch("[^\r\n]+") do
          table.insert(lines, line)
        end
        
        local wins = vim.fn.win_findbuf(target_buf)
        if #wins > 0 then
          vim.api.nvim_set_current_win(wins[1])
          local cursor = vim.api.nvim_win_get_cursor(0)
          vim.api.nvim_buf_set_lines(target_buf, cursor[1], cursor[1], false, lines)
          vim.notify("[GraphQL Explorer] Example inserted in buffer at cursor line!", vim.log.levels.INFO)
        else
          vim.api.nvim_buf_set_lines(target_buf, 0, 0, false, lines)
          vim.notify("[GraphQL Explorer] Example inserted at the beginning of the buffer!", vim.log.levels.INFO)
        end
      else
        vim.notify("[GraphQL Explorer] Original buffer not found for insertion.", vim.log.levels.WARN)
      end
    end, { buffer = buf, silent = true, desc = "Insert example into buffer" })
  end
end

--- Exibe detalhes do tipo selecionado
local function show_type_details(type_name)
  local t = M.types_by_name[type_name]
  if not t then return end

  local lines = {}
  table.insert(lines, "# GraphQL Type: " .. t.name)
  if t.description and t.description ~= "" then
    table.insert(lines, "> " .. t.description)
  end
  table.insert(lines, "")

  local example = nil
  if t.kind == "ENUM" then
    table.insert(lines, "### Values:")
    for _, val in ipairs(t.enumValues or {}) do
      local desc = val.description and (" - " .. val.description) or ""
      table.insert(lines, string.format("* `%s` %s", val.name, desc))
    end
    example = generate_sample_enum(t)
  elseif t.kind == "INPUT_OBJECT" then
    table.insert(lines, "### Input Fields:")
    for _, field in ipairs(t.inputFields or {}) do
      local desc = field.description and (" - " .. field.description) or ""
      table.insert(lines, string.format("* **%s**: `%s` %s", field.name, format_type(field.type), desc))
    end
    example = generate_sample_input_json(type_name)
  else
    table.insert(lines, "### Fields:")
    for _, field in ipairs(t.fields or {}) do
      local desc = field.description and (" - " .. field.description) or ""
      table.insert(lines, string.format("* **%s**%s: `%s` %s", field.name, format_args(field.args), format_type(field.type), desc))
    end
    example = generate_sample_fragment(type_name)
  end

  if example then
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "### Example Usage:")
    table.insert(lines, "> 💡 Press **`y`** to copy this example code, or **`i`** to insert it into the active file.")
    table.insert(lines, "")
    local lang = (t.kind == "INPUT_OBJECT") and "json" or "graphql"
    table.insert(lines, "```" .. lang)
    for ex_line in example:gmatch("[^\r\n]+") do
      table.insert(lines, ex_line)
    end
    table.insert(lines, "```")
  end

  show_details_float("GraphQL Type: " .. type_name, lines, example)
end

--- Exibe detalhes de um campo de Query ou Mutation
local function show_field_details(field, is_mutation)
  local lines = {}
  local label = is_mutation and "Mutation" or "Query"
  table.insert(lines, string.format("# %s: %s", label, field.name))
  if field.description and field.description ~= "" then
    table.insert(lines, "> " .. field.description)
  end
  table.insert(lines, "")
  table.insert(lines, string.format("* **Return Type**: `%s`", format_type(field.type)))
  
  if field.args and #field.args > 0 then
    table.insert(lines, "")
    table.insert(lines, "### Arguments:")
    for _, arg in ipairs(field.args) do
      local desc = arg.description and (" - " .. arg.description) or ""
      table.insert(lines, string.format("* **%s**: `%s` %s", arg.name, format_type(arg.type), desc))
    end
  end

  local example = generate_sample_query_or_mutation(field, is_mutation)
  if example then
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "### Example Request:")
    table.insert(lines, "> 💡 Press **`y`** to copy this query example, or **`i`** to insert it into the active file.")
    table.insert(lines, "")
    table.insert(lines, "```graphql")
    for ex_line in example:gmatch("[^\r\n]+") do
      table.insert(lines, ex_line)
    end
    table.insert(lines, "```")
  end

  show_details_float(string.format("GraphQL %s: %s", label, field.name), lines, example)
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
    local is_mutation = (meta.category == "mutations")
    show_field_details(meta.data, is_mutation)
  end
end

--- Abre ou fecha a janela do explorer lateral
function M.toggle()
  -- Se a janela estiver aberta e for válida, fecha-a
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    local ok, _ = pcall(vim.api.nvim_win_close, M.win, true)
    if not ok then
      -- Se for a última janela (erro E444), apenas trocamos o buffer para não quebrar
      local target_buf = M.original_buf
      if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
        target_buf = vim.api.nvim_create_buf(true, false)
      end
      vim.api.nvim_win_set_buf(M.win, target_buf)
      pcall(vim.api.nvim_set_option_value, "winfixwidth", false, { win = M.win })
    end
    M.win = nil
    -- Fecha o float também se estiver aberto para não deixá-lo órfão na tela
    if M.float_win and vim.api.nvim_win_is_valid(M.float_win) then
      pcall(vim.api.nvim_win_close, M.float_win, true)
      M.float_win = nil
    end
    return
  end

  -- Salva o buffer original que o usuário estava editando antes de abrir o explorer
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= M.buf then
    M.original_buf = current_buf
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
    vim.keymap.set("n", "<CR>", M.handle_action, { buffer = M.buf, silent = true, desc = "Expand / Details" })
    vim.keymap.set("n", "q", M.toggle, { buffer = M.buf, silent = true, desc = "Close Explorer" })
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
