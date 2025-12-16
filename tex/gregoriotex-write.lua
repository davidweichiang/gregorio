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

local function table_extend(x, y)
  table.move(y, 1, #y, #x+1, x)
end

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

local function format_gtex(root)
  local acc = {}
  local function visit(node, depth)
    if type(node) == 'string' then
      table.insert(acc, format_token(node))
    elseif node._cs ~= nil then
      table.insert(acc, format_token(node._cs))
      if node.box_spec ~= nil then
        local s = string.format(' %s %dsp', node.box_spec[1], node.box_spec[2])
        table_extend(acc, string_to_list(s))
      end
      if node.args ~= nil then
        for _, arg in ipairs(node.args) do
          visit(arg, depth+1)
        end
      end
      if node.extra_args ~= nil then
        for _, arg in ipairs(node.extra_args) do
          visit(arg, depth+1)
        end
      end
      if depth == 0 then
        table.insert(acc, '%\n')
      end
    else
      table.insert(acc, '{')
      for _, child in ipairs(node) do
        visit(child, depth+1)
      end
      table.insert(acc, '}')
    end
  end
  for _, child in ipairs(root) do
    visit(child, 0)
  end
  return table.concat(acc)
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
gregoriotex.pprint = pprint
