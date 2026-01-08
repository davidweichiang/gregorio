--[[
  
  Convert a score data structure (see gregoriotex-read.lus) into TeX
  code.

  In the future, the hope is to emit lower-level TeX commands and/or
  to write nodes directly.

--]]

local err = gregoriotex.module.err
local warn = gregoriotex.module.warn
local info = gregoriotex.module.info
local log = gregoriotex.module.log
local debugmessage = gregoriotex.module.debugmessage

local catcode_at_letter = luatexbase.catcodetables['gre@atletter']

local function string_to_list(s)
  return string.explode(s, '')
end

local function format_token(tok)
  -- If a control word is followed by a letter or @, then a space must be inserted.
  -- Always insert the space to be safe.
  if string.match(tok, [[^\[A-Za-z@]+]]) then
    return tok..' '
  else
    return tok
  end
end

local function format_gtex_node(node, out, newlines)
  if type(node) == 'string' then
    table.insert(out, format_token(node))
  elseif node._cs ~= nil then
    
    -- Intercept some macros here but still expand them in TeX
    if node._cs == [[\GreBeginHeaders]] then
      gregoriotex.headers = {}
    elseif node._cs == [[\GreHeader]] then
      local value = {}
      for _, tok in ipairs(node.args[2]) do
        format_gtex_node(tok, value)
      end
      gregoriotex.headers[table.concat(node.args[1])] = table.concat(value)
    end
    
    -- Intercept some macros to expand in Lua
    if node._cs == [[\GreScoreOpening]] then
      gregoriotex.gre_score_opening(node, out)
    elseif node._cs == [[\GreSyllable]] or node._cs == [[\GreBarSyllable]] then
      gregoriotex.gre_syllable(node, out)
    else
      -- Pass node through to TeX
      table.insert(out, format_token(node._cs))
      if node.box_spec ~= nil then
        local s = string.format('%s %dsp', node.box_spec[1], node.box_spec[2])
        gregoriotex.table_extend(out, string_to_list(s))
      end
      if node.args ~= nil then
        for _, arg in ipairs(node.args) do
          format_gtex_node(arg, out)
        end
      end
      assert(node.extra_args == nil) -- handled by score_opening
      if newlines then
        table.insert(out, '%\n')
      end
    end
  else
    table.insert(out, '{')
    for _, child in ipairs(node) do
      format_gtex_node(child, out)
    end
    table.insert(out, '}')
  end
end
  
local function format_gtex(root)
  local out = {}
  for _, child in ipairs(root) do
    format_gtex_node(child, out, true)
  end
  return table.concat(out)
end

local function compare_keys(x, y)
  if type(x) == type(y) then
    return x < y
  else
    return type(x) > type(y) -- 'string' before 'number'
  end
end

-- Print a table. This is useful for debugging.
local function pprint(x, indent)
  if indent == nil then indent = 0 end
  if type(x) == 'table' then
    io.write('{\n')
    local keys = {}
    for key in pairs(x) do
      table.insert(keys, key)
    end
    table.sort(keys, compare_keys)
    for _, key in ipairs(keys) do
      if type(key) == 'string' then
        io.write(string.rep(' ', indent*4+4) .. string.format("%s = ", key))
      else
        io.write(string.rep(' ', indent*4+4) .. string.format("[%q] = ", key))
      end
      pprint(x[key], indent+1)
    end
    io.write(string.rep(' ', indent*4) .. '}\n')
  else
    io.write(string.format("%q\n", x))
  end
end

gregoriotex.format_gtex = format_gtex
gregoriotex.format_gtex_node = format_gtex_node
gregoriotex.pprint = pprint
