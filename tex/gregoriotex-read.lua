--[[
  
  Convert a .gtex file into a data structure that (currently) closely
  mirrors the .gtex code.

  The data structure is a nested table which can be thought of as a tree.
  
  Each leaf node represents a token. Each interior node is either of the form
    {_cs = '\\GreMacro', args = {arg1, arg2, ...}}
  where \GreMacro is a macro and arg1, arg2, ... are its arguments, or
    {child1, child2, ...}
  which represents a group (curly braces) with contents child1, child2, ....

  For example,
    foo\bar{{baz}{quux}}
  becomes
    {'f', 'o', 'o', {_cs='\\bar', args={{'b', 'a', 'z'}, {'q', 'u', 'u', 'x'}}}}

  In the future, the hope is to simplify the .gtex file to mirror
  gregorio's internal data structure (src/struct.h) more closely, and
  then to parse the .gabc file directly.
--]]

local err = gregoriotex.module.err
local warn = gregoriotex.module.warn
local info = gregoriotex.module.info
local log = gregoriotex.module.log
local debugmessage = gregoriotex.module.debugmessage

local function skip_whitespace(str, i)
  flag, j = string.find(str, '^%s+', i)
  if flag then
    return j+1
  else
    return i
  end
end
      
local function skip_comments(str, i)
  -- A comment extends from % to the end of the line, and also eats up
  -- any whitespace at the beginning of the next line.
  flag, j = string.find(str, '^%%[^\n]*\n[ \t]*', i)
  while flag do
    i = j+1
    flag, j = string.find(str, '^%%[^\n]*\n[ \t]*', i)
  end
  -- The last line might not have a newline.
  flag, j = string.find(str, '^%%[^\n]*', i)
  if flag then
    return j+1
  else
    return i
  end
end

local function parse_cs(str, i)
  -- A control word eats up whitespace afterwards.
  flag, j, tok = string.find(str, [[^(\[A-Za-z@]+)%s*]], i)
  if flag then
    return true, tok, j+1
  end
  -- A control space also eats whitespace.
  flag, j, tok = string.find(str, [[^(\ )%s*]], i)
  if flag then
    return true, tok, j+1
  end
  -- A control character does not eat whitespace.
  flag, j, tok = string.find(str, [[^(\.)]], i)
  if flag then
    return true, tok, j+1
  end
end

local macros = {
  GreAccentus = 'tt',
  GreAdHocSpaceEndOfElement = 'ttt',
  GreAdditionalLine = 'ttt',
  GreAnnotationLines = 'tt',
  GreAugmentumDuplex = 'ttt',
  GreBarBrace = 't',
  GreBarSyllable = 'ttctttttt',
  GreBarVEpisema = 't',
  GreBeginEUOUAE = 't',
  GreBeginHeaders = '',
  GreBeginNLBArea = 'tt',
  GreBeginScore = 'tttttttt',
  GreBold = 't',
  GreBracket = 'tttt',
  GreCPVirgaReversaAscendensOnDLine = 't',
  GreCavum = 't',
  GreChangeClef = 'ttttttt',
  GreCirculus = 'tt',
  GreClearSyllableText = '', 
  GreColored = 't',
  GreCustos = 'tt',
  GreDagger = '',
  GreDiscretionary = 'ttt',
  GreDivisioFinalis = 'tt',
  GreDivisioMaior = 'tt',
  GreDivisioMaiorDotted = 'tt',
  GreDivisioMinima = 'ttt',
  GreDivisioMinimaHigh = 'ttt',
  GreDivisioMinimaParen = 'ttt',
  GreDivisioMinimaParenHigh = 'ttt',
  GreDivisioMinimis = 'ttt',
  GreDivisioMinimisHigh = 'ttt',
  GreDivisioMinor = 'tt',
  GreDominica = 'ttt',
  GreDrawAdditionalLine = 'tttttt',
  GreElision = 't',
  GreEmptyFirstSyllableHyphen = '',
  GreEndEUOUAE = 't',
  GreEndHeaders = '',
  GreEndNLBArea = 'tt',
  GreEndOfElement = 'ttt',
  GreEndOfGlyph = 't',
  GreEndScore = '',
  GreFinalCustos = 'tt',
  GreFinalDivisioFinalis = 't',
  GreFinalDivisioMaior = 't',
  GreFinalNewLine = '',
  GreFirstSyllable = 't',
  GreFirstSyllableInitial = 't',
  GreFirstWord = 't',
  GreFlat = 'ttttt',
  GreFlatParen = 'ttttt',
  GreFlatSoft = 'ttttt',
  GreForceHyphen = '',
  GreFuse = '',
  GreFuseTwo = 'tt',
  GreGABCForceCenters = '',
  GreGABCNextForceCenters = '',
  GreGlyph = 'ttttttt',
  GreGlyphHeights = 'tt',
  GreHEpisema = 'ttttttttt',
  GreHEpisemaBridge = 'tttttt',
  GreHeader = 'tt',
  GreHighChoralSign = 'ttt',
  GreHyph = '',
  GreInDivisioFinalis = 'tt',
  GreInDivisioMaior = 'tt',
  GreInDivisioMaiorDotted = 'tt',
  GreInDivisioMinima = 'ttt',
  GreInDivisioMinimaHigh = 'ttt',
  GreInDivisioMinimaParen = 'ttt',
  GreInDivisioMinimaParenHigh = 'ttt',
  GreInDivisioMinimis = 'ttt',
  GreInDivisioMinimisHigh = 'ttt',
  GreInDivisioMinor = 'tt',
  GreInDominica = 'ttt',
  GreInVirgula = 'ttt',
  GreInVirgulaHigh = 'ttt',
  GreInVirgulaParen = 'ttt',
  GreInVirgulaParenHigh = 'ttt',
  GreInitialClefPosition = 'tt',
  GreItalic = 't',
  GreLastOfLine = '',
  GreLastOfScore = '',
  GreLastSyllableBeforeEUOUAE = 'tt',
  GreLowChoralSign = 'ttt',
  GreMode = 'ttt',
  GreModeNumber = 't',
  GreMusicaFictaFlat = 'tt',
  GreMusicaFictaNatural = 'tt',
  GreMusicaFictaSharp = 'tt',
  GreNABCChar = 't',
  GreNABCNeumes = 'tttt',
  GreNatural = 'ttttt',
  GreNaturalParen = 'ttttt',
  GreNaturalSoft = 'ttttt',
  GreNewLine = '',
  GreNewParLine = '',
  GreNextCustos = 'tt',
  GreNextSyllableBeginsEUOUAE = 'tt',
  GreNoBreak = '',
  GreNoNoteSyllable = 'ttctttttt',
  GreOverBrace = 'tttt',
  GreOverCurlyBrace = 'ttttt',
  GreProtrusion = 'tt',
  GreProtrusionFactor = 't',
  GrePunctumMora = 'tttt',
  GreResetEolCustos = '',
  GreReversedAccentus = 'tt',
  GreReversedSemicirculus = 'tt',
  GreScoreNABCLines = 't',
  GreScoreOpening = 'tttct',
  GreSemicirculus = 'tt',
  GreSetFirstSyllableText = 'tttttt',
  GreSetFixedNextTextFormat = 't',
  GreSetFixedTextFormat = 't',
  GreSetInitialClef = 'ttttttt',
  GreSetLargestClef = 'tttttt',
  GreSetLinesClef = 'ttttttt',
  GreSetNabcAboveLines = 't',
  GreSetNextSyllable = 'ttttt',
  GreSetNoFirstSyllableText = '',
  GreSetTextAboveLines = 't',
  GreSetThisSyllable = 'ttttt',
  GreSharp = 'ttttt',
  GreSharpParen = 'ttttt',
  GreSharpSoft = 'ttttt',
  GreSlur = 'tttttt',
  GreSmallCaps = 't',
  GreSpecial = 't',
  GreStar = '',
  GreSupposeHighLedgerLine = '',
  GreSupposeLowLedgerLine = '',
  GreSuppressEolCustos = '',
  GreSyllable = 'ttctttttt',
  GreSyllableNoteCount = 't',
  GreTranslationCenterEnd = '',
  GreTypewriter = 't',
  GreUnderBrace = 'tttt',
  GreUnderline = 't',
  GreUnstyled = 't',
  GreUpcomingNewLineForcesCustos = 't',
  GreVEpisema = 'tt',
  GreVarBraceLength = 't',
  GreVarBraceSavePos = 'ttt',
  GreVirgula = 'ttt',
  GreVirgulaHigh = 'ttt',
  GreVirgulaParen = 'ttt',
  GreVirgulaParenHigh = 'ttt',
  GreWriteTranslation = 't',
  GreWriteTranslationWithCenterBeginning = 't',
  GregorioTeXAPIVersion = 't',
  -- A few general TeX commands
  hbox = 't',
  vbox = 't',
  vtop = 't',
  endinput = '',
}

local parse_token, parse_tokens

local function parse_args(codes, str, i)
  local args = {}
  for k = 1, #codes do
    local code = codes:sub(k, k)
    local flag, arg, j
    i = skip_whitespace(str, i)
    local has_braces = i <= #str and str:sub(i, i) == '{'
    if code == 't' then
      flag, arg, j = parse_token(str, i)
      if not has_braces then arg = {arg} end -- \foo bar is the same as \foo{b}{a}{r}
    elseif code == 'c' then
      if has_braces then
        j = i + 1
        if j <= #str and str:sub(j, j) == '}' then -- empty braces
          flag, arg, j = true, nil, j+1
        else          
          flag, arg, j = parse_cs(str, j)
        end
        if j <= #str and str:sub(j, j) == '}' then
          j = j + 1
        else
          flag = false
        end
      else
        flag, arg, j = parse_cs(str, i)
      end
    end
    if flag then
      i = j
    else
      return false, args, i
    end
    table.insert(args, arg)
  end
  return true, args, i
end

function parse_dimen(str, i)
  local m, num, unit = string.match(str, '^(%s*(%d+)%s*([a-z][a-z]))', i)
  if m == nil then
    return false
  end
  i = i + m:len()
  return true, tex.sp(m), i
end  

function parse_token(str, i)
  i = skip_comments(str, i)

  if i >= str:len() then
    return false
  end

  local flag, j, tok

  -- Any number of whitespace characters are treated as one space.
  flag, j = string.find(str, '^%s+', i)
  if flag then
    return true, ' ', j+1
  end

  -- A control sequence.
  flag, tok, j = parse_cs(str, i)
  if flag then
    local sem = {_cs=tok}
    
    -- Special case: \hbox, \vbox, \vtop
    if tok == [[\hbox]] or tok == [[\vbox]] or tok == [[\vtop]] then
      local word
      if string.find(str, '^to', j) then word = 'to'
      elseif string.find(str, '^spread', j) then word = 'spread' end
      if word then
        k = j + word:len()
        local dimen
        flag, dimen, k = parse_dimen(str, k)
        if flag then
          sem.box_spec = {word, dimen}
          j = k
        end
      end
    end
    
    -- Main case for any control sequence
    local codes = macros[tok:sub(2)] -- remove backslash
    if codes ~= nil then
      flag, sem.args, j = parse_args(codes, str, j)
      if not flag then
        -- See issue #1677
        warn('macro %q expected %d arguments but only got %d', tok, #codes, #sem.args)
      end
    elseif string.match(tok, [[^\GreCP]]) or string.match(tok, [[^\GreOCase]]) then
      -- There are many zero-argument macros for notes. We don't
      -- include them in the macro table and we don't print a warning
      -- for them.
    else
      warn('unknown macro %q', tok)
    end
    
    -- Special case: \GreScoreOpening may have additional arguments
    if tok == [[\GreScoreOpening]] then
      local cs = sem.args[4]
      if cs ~= nil then
        codes = macros[cs:sub(2)] -- remove backslash
        codes = codes:sub(2) -- remove first argument (first syllable text)
        flag, sem.extra_args, j = parse_args(codes, str, j)
        if not flag then return false end
      end
    end
    
    return true, sem, j
    
  end

  -- A group enclosed by curly braces.
  if str:sub(i, i) == '{' then
    local flag, toks, j = parse_tokens(str, i+1)
    j = skip_comments(str, j)
    if j <= str:len() and str:sub(j, j) == '}' then
      return true, toks, j+1
    else
      err('expected }')
    end
  end
    
  if str:sub(i, i) == '}' then
    return false
  end
    
  -- An ordinary character.
  return true, str:sub(i, i), i+1
end

-- Parse zero or more tokens or groups and return them as a list.
function parse_tokens(str, i)
  local toks = {}
  local flag, tok, j = parse_token(str, i)
  while flag do
    table.insert(toks, tok)
    i = j
    flag, tok, j = parse_token(str, i)
  end
  return true, toks, i
end

local function parse_gtex(str)
  local i = 1
  local flag, toks, i = parse_tokens(str, i)
  if flag then
    i = skip_comments(str, i)
    if i == str:len()+1 then
      return toks
    else
      err(string.format('unexpected %s', str:sub(i, i)))
    end
  else
    err('parse failed')
  end
end

gregoriotex.parse_gtex = parse_gtex
