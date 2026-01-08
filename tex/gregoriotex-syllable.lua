-- GREGORIO_VERSION 6.1.0

local err = gregoriotex.module.err
local warn = gregoriotex.module.warn
local info = gregoriotex.module.info
local log = gregoriotex.module.log
local debugmessage = gregoriotex.module.debugmessage

-- Vowel rules. Replaces:
-- - vowel/vowel.[ch] and vowel/vowel-rules.[lyh]
-- - in characters.c, read_vowel_rules(), gregorio_set_centering_language()

-- Data structure

local function add_language(rules, lang)
  if rules[lang] == nil then
    rules[lang] = {vowels={}, prefixes={}, suffixes={}, secondaries={}}
  end
end

local function add_alias(rules, src, tgt)
  rules[src] = {alias = tgt}
end

local function add_chars(set, chars)
  for char in string.utfcharacters(chars) do
    set[char] = true
  end
end

local function add_strings(set, strs)
  for _, str in ipairs(strs) do
    set[str] = true
  end
end

local function safe_concat(t, i, j)
  -- If t[i,...,j] can be concatenated, do so; otherwise, return nil
  for k = i, j do
    if type(t[k]) ~= 'string' then
      return nil
    end
  end
  return table.concat(t, '', i, j)
end

local function find_first(rules, chars)
  -- Find the first vowel, except if a vowel is the last letter of a
  -- prefix and followed by another vowel or an elision (presumably
  -- an elided vowel), then it is not considered a vowel.
  
  -- For example (curly braces mark the nucleus):
  --   Latin    i{a}m         because i is a prefix followed by a vowel
  --   Latin    {i}n          because i is a prefix, but followed by a consonant
  --   Latin    t{u}          because u is a prefix, but followed by end of syllable
  --   Latin    qu{i}         because u and i are prefixes, but i is followed by end of syllable
  --   Latin    qu{e} ab      because u is a prefix followed by an elision
  --   English  qu{i}t        because qu is a prefix

  for i = 1, #chars do
    local is_vowel = rules.vowels[chars[i]]
    local ends_prefix = false
    for j = i, 1, -1 do
      if rules.prefixes[safe_concat(chars, j, i)] then
        ends_prefix = true
        break
      end
    end
    local another_vowel = (rules.vowels[chars[i+1]] or
                           (type(chars[i+1]) == 'table' and chars[i+1]._cs == [[\GreElision]]))
    if is_vowel and not (ends_prefix and another_vowel) then
      return i
    end
  end
end

local function find_last(rules, chars, first)
  -- Find the last vowel in the run of vowels starting at first. If
  -- a suffix is encountered, then the last letter of the suffix is
  -- the last vowel. If there is more than one suffix, choose the
  -- longest.
  -- For example (curly braces mark the nucleus):
  --   English  {ow}n   because w is a suffix
  --   English  {owe}d  because we is a suffix
  for i = first, #chars do
    for j = #chars, i, -1 do
      if rules.suffixes[safe_concat(chars, i, j)] then
        return j
      end
    end
    if not rules.vowels[chars[i]] then
      return i-1
    end
  end
  return #chars
end

local function find_secondary(rules, chars)
  -- Find the first secondary. If there is more than one, choose the longest.
  for i = 1, #chars do
    for j = #chars, i, -1 do
      if rules.secondaries[safe_concat(chars, i, j)] then
        return i, j
      end
    end
  end
end
  
local function apply_rules(rules, chars)
  local first, last
  first = find_first(rules, chars)
  if first ~= nil then
    last = find_last(rules, chars, first)
  end
  if last == nil then
    first, last = find_secondary(rules, chars)
  end
  return first, last
end

-- Parser

local function skip_whitespace(str, i)
  local flag, j
  ::loop::
  -- whitespace
  flag, j = str:find('^[ \t\n\r\v\f]+', i)
  if flag then
    i = j + 1
    goto loop
  end
  -- comment
  flag, j = str:find('^#[^\n\r]*', i)
  if flag then
    i = j + 1
    goto loop
  end
  return i
end

local function startswith(pat, str, i)
  if i == nil then i = 1 end
  return str:sub(i, i+pat:len()-1) == pat
end

local function parse_error(msg, str, pos)
  local line = 1
  for i = 1, pos-1 do
    if str:sub(i,i) == '\n' then line = line + 1 end
  end
  error(string.format('error: %s at line %d', msg, line))
end

local function expect(pat, str, i)
  i = skip_whitespace(str, i)
  if startswith(pat, str, i) then
    return i + pat:len()
  else
    parse_error(string.format('expected %q', pat), str, i)
  end
end

local function parse_lang(str, i)
  i = skip_whitespace(str, i)
  local flag, j, lang = str:find('^%[([^]]+)%]', i)
  if flag then
    return lang, j+1
  else
    parse_error('expected [LANGUAGE]', str, i)
  end
end

local function parse_chars(str, i)
  i = skip_whitespace(str, i)
  local flag, j, chars = str:find('^([^;,# \t\n\r\v\f]+)', i)
  if flag then
    return chars, j+1
  else
    parse_error('expected characters', str, i)
  end
end

local function parse_strings(str, i)
  local strings = {}
  i = skip_whitespace(str, i)
  while i <= str:len() and str:sub(i,i) ~= ';' do
    local chars
    chars, i = parse_chars(str, i)
    table.insert(strings, chars)
    i = skip_whitespace(str, i)
  end
  return strings, i
end

local function parse_rules(rules, str, i)
  local flag, j
  local lang
  i = skip_whitespace(str, i)
  while i <= str:len() do
    -- No space is required after the keyword; that is, "vowelaeiou;"
    -- is equivalent to "vowel aeiou;" and "prefixi u;" is equivalent
    -- to "prefix i u;".
    if startswith('language', str, i) then
      i = i + #'language'
      lang, i = parse_lang(str, i)
      add_language(rules, lang)
    elseif startswith('alias', str, i) then
      local src, tgt
      i = i + #'alias'
      src, i = parse_lang(str, i)
      i = expect('to', str, i)
      tgt, i = parse_lang(str, i)
      add_alias(rules, src, tgt)
    elseif startswith('vowel', str, i) then
      local chars
      i = i + #'vowel'
      chars, i = parse_chars(str, i)
      add_chars(rules[lang].vowels, chars)
    elseif startswith('prefix', str, i) then
      local strs
      i = i + #'prefix'
      strs, i = parse_strings(str, i)
      add_strings(rules[lang].prefixes, strs)
    elseif startswith('suffix', str, i) then
      local strs
      i = i + #'suffix'
      strs, i = parse_strings(str, i)
      add_strings(rules[lang].suffixes, strs)
    elseif startswith('secondary', str, i) then
      local strs
      i = i + #'secondary'
      strs, i = parse_strings(str, i)
      add_strings(rules[lang].secondaries, strs)
    end
    i = expect(';', str, i)
    i = skip_whitespace(str, i)
  end
  if i ~= #str+1 then
    parse_error("unexpected characters at end of rules", str, i)
  end
end

local rules = {}
add_language(rules, 'la')
add_alias(rules, 'Latin', 'la')
add_alias(rules, 'latin', 'la')
add_alias(rules, 'lat', 'la')
add_chars(rules.la.vowels,
          "aàáâăąåAÀÁÂĂĄÅeèéêëěęEÈÉÊËĚĘiìíîIÌÍÎ"..
          "oòóôơőøOÒÓÔƠŐØuùúûưůűUÙÚÛƯŮŰyỳýYỲÝæǽÆǼœŒ")
add_strings(rules.la.prefixes, {'i', 'I', 'u', 'U'})

-- Load additional rules from gregorio-vowels.dat.
local rules_filename = kpse.find_file('gregorio-vowels.dat')
debugmessage('found rules file at %s', rules_filename)
local rules_file = io.open(rules_filename)
local rules_str = rules_file:read('a')
parse_rules(rules, rules_str, 1)

local function gregorio_find_vowel_group(chars)
  -- Split syllable text into onset, nucleus, and coda.
  -- Arguments:
  --   - chars: a list of characters or nodes
  -- Returns:
  --   - the position of the first character in the nucleus
  --   - the position of the last character in the nucleus
  local lang = gregoriotex.headers['language']
  if lang == nil then lang = 'la' end
  while rules[lang] ~= nil and rules[lang].alias ~= nil do
    lang = rules[lang].alias
  end
  return apply_rules(rules[lang], chars)
end

-- Macros from gregoriotex-syllable.tex

local function traverse(node, open, leaf, close)
  -- Traverse a tree representing syllable text.
  -- Arguments:
  -- - node: the root node of the tree
  -- - open(n): callback before traversing the subtree rooted at n
  -- - leaf(n): callback when traversing a leaf node n
  -- - close(n): callback after traversing the subtree rooted at n
  local is_leaf = false
  local children

  if type(node) == 'string' then
    is_leaf = true
  elseif node._cs == [[\GreProtrusion]] then
    -- The first arg is the \GreProtrusionFactor, so only traverse the second arg
    if node.args[2] ~= nil then -- sometimes missing due to a bug
      children = node.args[2]
    else
      children = {}
    end
  elseif (node._cs == [[\GreItalic]] or
          node._cs == [[\GreSmallCaps]] or
          node._cs == [[\GreBold]] or
          node._cs == [[\GreTypewriter]] or
          node._cs == [[\GreUnderline]] or
          node._cs == [[\GreColored]] or
          node._cs == [[\GreFirstWord]] or
          node._cs == [[\GreFirstSyllable]] or
          node._cs == [[\GreFirstSyllableInitial]]) then
    assert(#node.args == 1)
    children = node.args[1]
  elseif node._cs == nil then
    children = node
  elseif node._cs == [[\GreSpecial]] or node._cs == [[\GreElision]] then
    -- Treat certain commands as single characters.
    -- Bug: We should also treat a <v> </v> element as a single
    -- character, but don't know where those elements are. This will
    -- only be fixed once the raw text is passed in.
    is_leaf = true
  else
    -- Treat everything else as single character
    is_leaf = true
  end

  if is_leaf then
    leaf(node)
  else
    open(node)
    for _, child in ipairs(children) do
      traverse(child, open, leaf, close)
    end
    close(node)
  end
end

local function leaves(tree, out)
  -- Get the leaves of the tree.
  -- Arguments:
  -- - tree: the root node
  -- - out: list to which the leaves should be appended.
  local function noop(node)
  end
  local function leaf(node)
    table.insert(out, node)
  end
  traverse(tree, noop, leaf, noop)
end

local function slice(root, i, k, out)
  -- Output tree from positions i to k, inclusive.
  -- Arguments:
  -- - root: the root node
  -- - i: first position of the slice
  -- - k: last position of the slice
  -- - out: list to which TeX strings should be appended.
  local format_gtex_node = gregoriotex.format_gtex_node
  local j = 0
  local in_slice = false
  local stack = {}
  local function open_print(node)
    table.insert(out, node._cs)
    if node._cs == [[\GreProtrusion]] then
      format_gtex_node(node.args[1], out)
    end
    table.insert(out, '{')
  end
  local function open(node)
    table.insert(stack, node)
    if in_slice then
      open_print(node)
    end
  end
  local function leaf(node)
    -- If j is just before i, print pending opens
    if i-1 == j and not in_slice then
      for s = 1, #stack do
        open_print(stack[s])
      end
      in_slice = true
    end
    if in_slice then
      format_gtex_node(node, out)
    end
    j = j + 1
    -- If j is just after k, print pending opens
    if j == k and in_slice then
      in_slice = false
      for s = #stack, 1, -1 do
        table.insert(out, string.format('}'))
      end
    end
  end
  local function close(node)
    -- If j is between two leaves in [i,k], print
    if i <= j and j <= k-1 then
      table.insert(out, '}')
    end
    table.remove(stack)
  end
  if i <= k then
    traverse(root, open, leaf, close)
  else
    table.insert(out, '{}')
  end
end

local function gre_set_syllable_text(nodes, out, drop_initial)
  -- Outputs TeX strings setting the three parts of a syllable text.
  -- Replaces \GreSetThisSyllable, \GreSetNextSyllable, \GreGABCForceCenters, \GreGABCNextForceCenters
  -- Arguments:
  -- - nodes: TeX tree to expand
  -- - out: list to which strings should be appended
  -- - drop_initial: whether the score has a dropped initial
  local format_gtex_node = gregoriotex.format_gtex_node
  local which, args
  local force_center = false
  local orig_parts -- if force_center is true, the three parts specified in the GABC code
  for _, node in ipairs(nodes) do
    if node._cs == [[\GreGABCForceCenters]] or node._cs == [[\GreGABCNextForceCenters]] then
      force_center = true
    elseif node._cs == [[\GreSetThisSyllable]] then
      which = ''
      orig_parts = node.args
    elseif node._cs == [[\GreSetNextSyllable]] then
      which = 'next'
      orig_parts = node.args
    elseif node._cs == [[\GreSetFirstSyllableText]] then
      which = ''
      if drop_initial then
        orig_parts = node.args[4]
      else
        orig_parts = node.args[5]
      end
    elseif node._cs == [[\GreSetNoFirstSyllableText]] then
      which = ''
      orig_parts = {{}, {}, {}}
    elseif node._cs == [[\GreLastOfLine]] or node._cs == [[\GreClearSyllableText]] then
      format_gtex_node(node, out)
    else
      warn("ignoring unknown control sequence in syllable text: %q", node._cs)
    end
  end

  -- Get lyric centering options (at beginning of score)
  local lyric_centering = tonumber(token.get_macro('gre@lyriccentering')) -- 0 = syllable, 1 = vowel, 2 = firstletter
  local allow_force_centers = gregoriotex.get_if('gre@gabcforcecenters') -- true = allow, false = prohibit

  -- If forced center, use it
  if force_center and allow_force_centers then
    -- Store the three parts in three macros
    table.insert(out, string.format([[\def\gre@%sfirstsyllablepart]], which))
    format_gtex_node(orig_parts[1], out)
    table.insert(out, string.format([[\def\gre@%smiddlesyllablepart]], which))
    format_gtex_node(orig_parts[2], out)
    table.insert(out, string.format([[\def\gre@%sendsyllablepart]], which))
    format_gtex_node(orig_parts[3], out)
    return
  end
  
  -- Tree representing the syllable text. Currently, the three parts
  -- in orig_parts are computed by gregorio using vowel centering, and
  -- we reassemble them into a single tree. In the future, gregorio
  -- may output a single part instead.
  local tree = {}
  gregoriotex.table_extend(tree, orig_parts[1])
  gregoriotex.table_extend(tree, orig_parts[2])
  gregoriotex.table_extend(tree, orig_parts[3])
  --gregoriotex.pprint(tree)

  -- List of characters in the syllable text.
  local text = {}
  leaves(tree, text)

  -- If the syllable has no text, output three empty parts and return
  -- (avoiding some edge cases below).
  if #text == 0 then
    table.insert(out, string.format([[\def\gre@%sfirstsyllablepart{}]], which))
    table.insert(out, string.format([[\def\gre@%smiddlesyllablepart{}]], which))
    table.insert(out, string.format([[\def\gre@%sendsyllablepart{}]], which))
    return
  end

  -- Split into three parts
  local first, last
  if lyric_centering == 0 then
    -- Center whole syllable
    first, last = 1, #text
  elseif lyric_centering == 1 then
    -- Center on vowel
    first, last = gregorio_find_vowel_group(text)
    if first == nil or last == nil then -- rules failed
      first, last = 1, #text
    end
  elseif lyric_centering == 2 then
    -- Center on first letter
    first, last = 1, 1
  end

  -- Store the three parts in three macros
  table.insert(out, string.format([[\def\gre@%sfirstsyllablepart]], which))
  slice(tree, 1, first-1, out)
  table.insert(out, string.format([[\def\gre@%smiddlesyllablepart]], which))
  slice(tree, first, last, out)
  table.insert(out, string.format([[\def\gre@%sendsyllablepart]], which))
  slice(tree, last+1, #text, out)
end

local function gre_score_opening(node, out)
  -- Print the initial letter, initial clef and stafflines, and first syllable.
  -- Replaces \GreScoreOpening, \GreSetFirstSyllableText, \GreSetNoFirstSyllableText, and \gre@setfirstsyllabletext.
  -- Arguments:
  -- - node: TeX tree to expand
  -- - out: list to which strings should be appended
  local format_gtex_node = gregoriotex.format_gtex_node
  assert(node._cs == [[\GreScoreOpening]])
  -- node.args[1] is unused
  local initial_clef = node.args[2]
  local before_first_syllable = node.args[3] -- \GreBeginEUOUAE, etc.
  local first_syllable_cs = node.args[4] -- \GreSyllable, \GreBarSyllable, \GreNoNoteSyllable, or empty
  local first_syllable_text = node.args[5]
  local first_syllable_args = node.extra_args

  -- Decide whether there is a dropped initial
  local initial_char, first_syllable_hyphen
  local drop_initial = tex.count['gre@count@initiallines'] > 0
  for _, child in ipairs(first_syllable_text) do
    if child._cs == [[\GreSetFirstSyllableText]] then
      initial_char = child.args[1]
      first_syllable_hyphen = child.args[6]
    elseif child._cs == [[\GreSetNoFirstSyllableText]] then
      drop_initial = false
    end
  end

  -- Commands before first syllable
  for _, tok in ipairs(before_first_syllable) do
    format_gtex_node(tok, out)
  end

  -- Commentary. Version 6.1.0 did not print commentary when there is
  -- no first syllable text, which appears to be a bug (#1678)
  format_gtex_node({_cs=[[\gre@printcommentary]]}, out, true)
  
  -- Initial letter
  if drop_initial then
    format_gtex_node({_cs=[[\gre@setinitial]], args={initial_char}}, out, true)
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
  table.insert(out, first_syllable_cs)
  table.insert(out, '{')
  gre_set_syllable_text(first_syllable_text, out, drop_initial)
  if drop_initial then
    for _, tok in ipairs(first_syllable_hyphen) do
      format_gtex_node(tok, out)
    end
  end
  table.insert(out, '}')
  format_gtex_node(first_syllable_args[1], out)
  format_gtex_node(first_syllable_args[2], out)
  format_gtex_node(first_syllable_args[3], out)
  table.insert(out, '{')
  gre_set_syllable_text(first_syllable_args[4], out)
  table.insert(out, '}')
  format_gtex_node(first_syllable_args[5], out)
  format_gtex_node(first_syllable_args[6], out)
  format_gtex_node(first_syllable_args[7], out)
  format_gtex_node(first_syllable_args[8], out)
  table.insert(out, '%\n')
end

local function gre_syllable(node, out)
  -- Print a syllable.
  -- Arguments:
  -- - node: TeX tree to expand
  -- - out: list to which strings should be appended
  local format_gtex_node = gregoriotex.format_gtex_node
  assert(node._cs == [[\GreSyllable]] or node._cs == [[\GreBarSyllable]])
  -- Currently we don't fully expand \GreSyllable; we just expand the arguments
  -- for the syllable text.
  table.insert(out, node._cs)
  table.insert(out, '{')
  gre_set_syllable_text(node.args[1], out)
  table.insert(out, '}')
  format_gtex_node(node.args[2], out)
  format_gtex_node({node.args[3]}, out)
  format_gtex_node(node.args[4], out)
  table.insert(out, '{')
  gre_set_syllable_text(node.args[5], out)
  table.insert(out, '}')
  format_gtex_node(node.args[6], out)
  format_gtex_node(node.args[7], out)
  format_gtex_node(node.args[8], out)
  format_gtex_node(node.args[9], out)
  table.insert(out, '%\n')
end
  
gregoriotex.gre_score_opening = gre_score_opening
gregoriotex.gre_syllable = gre_syllable
