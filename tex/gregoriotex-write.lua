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

local function table_extend(x, y)
  table.move(y, 1, #y, #x+1, x)
end

local function string_to_list(s)
  return string.explode(s, '')
end

local function call_macro(cs, ...)
  local args = table.pack(...)
  args.n = nil
  local expected_args = gregoriotex.macros[cs:sub(2)] -- remove backslash
  if expected_args == nil then
    err('Unknown macro %q', cs)
  end
  if #args ~= #expected_args then
    err('macro %q expected %d arguments but only got %d', cs, #expected_args, #args)
  end
  return {_cs=cs, args=args}
end

local format_gtex_node

-- Print the initial letter, initial clef and stafflines, and first syllable.
-- Replaces \GreScoreOpening, \GreSetFirstSyllableText, \GreSetNoFirstSyllableText, and \gre@setfirstsyllabletext.
local function format_score_opening(node, out)
  assert(node._cs == [[\GreScoreOpening]])
  -- node.args[1] is unused
  local initial_clef = node.args[2]
  local before_first_syllable = node.args[3] -- \GreBeginEUOUAE, etc.
  local first_syllable_cs = node.args[4] -- \GreSyllable, \GreBarSyllable, \GreNoNoteSyllable, or empty
  local first_syllable_args = node.extra_args
  local first_syllable_has_text, first_syllable_text_args
  local first_syllable_text = {}
  for _, child in ipairs(node.args[5]) do
    if child._cs == [[\GreGABCForceCenters]] then
      table.insert(first_syllable_text, child)
    elseif child._cs == [[\GreSetFirstSyllableText]] then
      first_syllable_has_text = true
      first_syllable_text_args = child.args
    elseif child._cs == [[\GreSetNoFirstSyllableText]] then
      first_syllable_has_text = false
    else
      err('Unsupported command %q for first syllable text', child._cs)
    end
  end
  local drop_initial = tex.count['gre@count@initiallines'] > 0 and first_syllable_has_text

  -- Commands before first syllable
  for _, tok in ipairs(before_first_syllable) do
    format_gtex_node(tok, out)
  end

  -- Commentary. Version 6.1.0 did not print commentary when there is
  -- no first syllable text, which appears to be a bug
  format_gtex_node({_cs=[[\gre@printcommentary]]}, out, true)
  
  -- Initial letter
  if drop_initial then
    format_gtex_node({_cs=[[\gre@setinitial]], args={first_syllable_text_args[1]}}, out, true)
  else
    format_gtex_node({_cs=[[\gre@noinitial]]}, out, true)
  end
  
  -- Initial clef and stafflines
  for _, tok in ipairs(initial_clef) do
    format_gtex_node(tok, out, true)
  end

  -- If there is no first syllable at all, return early
  if first_syllable_cs == '' then return end

  -- First syllable
  local vowel_parts, firstletter_parts
  if drop_initial then
    vowel_parts = first_syllable_text_args[4]
    firstletter_parts = {first_syllable_text_args[2], first_syllable_text_args[3]}
  elseif first_syllable_has_text then
    vowel_parts = first_syllable_text_args[5]
    firstletter_parts = {first_syllable_text_args[1], {}}
    table_extend(firstletter_parts[2], first_syllable_text_args[2])
    table_extend(firstletter_parts[2], first_syllable_text_args[3])
  else
    vowel_parts = {{}, {}, {}}
    firstletter_parts = {{}, {}}
  end
  
  -- The .gtex file has \GreFirstWord, etc., on vowel_parts but not firstletter_parts,
  -- so add them here
  firstletter_parts = {
    {call_macro([[\GreFirstWord]],
       call_macro([[\GreFirstSyllable]],
         call_macro([[\GreFirstSyllableInitial]],
           firstletter_parts[1])))},
    {call_macro([[\GreFirstWord]],
       call_macro([[\GreFirstSyllable]],
         firstletter_parts[2]))}}

  table.insert(first_syllable_text,
    call_macro([[\GreSetThisSyllable]],
      vowel_parts[1], vowel_parts[2], vowel_parts[3],
      firstletter_parts[1], firstletter_parts[2]))
  
  if drop_initial then
    table_extend(first_syllable_text, first_syllable_text_args[6]) -- \GreEmptyFirstSyllableHyphen
  end
  
  local first_syllable = call_macro(
    first_syllable_cs,
    first_syllable_text,
    table.unpack(first_syllable_args)
  )
  
  format_gtex_node(first_syllable, out, true)
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

function format_gtex_node(node, out, newlines)
  if type(node) == 'string' then
    table.insert(out, format_token(node))
  elseif node._cs ~= nil then
    
    -- Intercept some macros to expand in Lua
    if node._cs == [[\GreScoreOpening]] then
      format_score_opening(node, out)
      
    else
      -- Pass node through to TeX
      table.insert(out, format_token(node._cs))
      if node.box_spec ~= nil then
        local s = string.format(' %s %dsp', node.box_spec[1], node.box_spec[2])
        table_extend(out, string_to_list(s))
      end
      if node.args ~= nil then
        for _, arg in ipairs(node.args) do
          format_gtex_node(arg, out)
        end
      end
      assert(node.extra_args == nil) -- handled by format_score_opening
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
gregoriotex.pprint = pprint
