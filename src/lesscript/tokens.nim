# A fast, statically typed Rock'n'Roll language that
# transpiles to Nim lang and JavaScript.
# 
# (c) 2023 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps
#          https://lesscript.com

import toktok
export toktok

const toktokSettings* =
  Settings(
    tkPrefix: "tk",
    lexerName: "Lexer",
    lexerTuple: "TokenTuple",
    lexerTokenKind: "TokenKind",
    tkModifier: defaultTokenModifier,      
    useDefaultIdent: true,
    useDefaultInt: true,
    keepUnknown: true,
    keepChar: true,
  )

handlers:
  proc handleDocBlock(lex: var Lexer, kind: TokenKind) =
    while true:
      case lex.buf[lex.bufpos]
      of '*':
        add lex
        if lex.current == '/':
          add lex
          break
      of NewLines:
        inc lex.lineNumber
        add lex        
      of EndOfFile: break
      else: add lex
    lex.kind = kind

  proc handleSingleQuote(lex: var Lexer, kind: TokenKind) =
    lexReady lex
    inc lex.bufpos
    while true:
      case lex.buf[lex.bufpos]
      of '\'':
        inc lex.bufpos
        break
      of EndOfFile: break
      else: add lex
    lex.kind = kind

  proc handleElseElseIf(lex: var Lexer, kind: TokenKind) =
    if lex.next("if"):
      inc lex.bufpos, 3
      add lex.token, indent("if", 1)
      lex.kind = tkElseIf
    else:
      lex.kind = kind
      add lex

registerTokens toktokSettings:
  plus = '+'
  minus = '-'
  multi = '*'
  `div` = '/':
    doc = tokenize(handleDocBlock, '*')
    comment = '/' .. EOL
  `mod` =  '%'
  assign = '=':
    eq = '='
    arrExp = '>'
  `not` = '!':
    ne = '='
  bitwise = '|':
    `or` = '|'
  gt = '>':
    gte = '='
  lt = '<':
    lte = '='
  qmark = '?'
  square = '^'
  tilde = '~'
  hash = '#'
  `and` = '&'
    # `and2` = '&' or `concat` = '='
  lp = '('
  rp = ')'
  lb = '['
  rb = ']'
  lc = '{'
  rc = '}'
  colon = ':'
  scolon = ';'
  comma = ','
  dot = '.'
  sQuoteString = tokenize(handleSingleQuote, '\'')

  litArray = "array"
  litBool = "bool"
  litBoolean = "boolean"
  litFloat = "float"
  litFloat8 = "float8"
  litFloat16 = "float16"
  litFloat32 = "float32"
  litFloat64 = "float64"
  litInt = "int"
  litInt8 = "int8"
  litInt16 = "int16"
  litInt32 = "int32"
  litInt64 = "int64"
  litBigInt = "bigint"
  litObject = "object"
  litString = "string"
  litNull = "null"
  litNil = "nil"

  litNatural = "Natural"
  litOrdinal = "Ordinal"
  litPositive = "Positive"
  litVoid = "void"

  fnCall
  varCall

  `interface` = "interface"
  readonly = "readonly"
  `static` = "static"

  `await` = "await"
  `bool` = ["true", "false"]
  `break` = "break"
  `case` = "case"
  catch = "catch"
  classDef = "class"
  `const` = "const"
  `continue` = "continue"
  debugger = "debugger"
  default = "default"
  delete = "delete"
  declare = "declare"
  `do` = "do"
  `echo` = "echo"
  `else` = tokenize(handleElseElseIf, "else")
  elseif
  `export` = "export"
  extends = "extends"
  enumDef = "enum"
  error = "error"
  `finally` = "finally"
  `for` = "for"
  `from` = "from"
  functionDef = "function"
  funcDef = "func"
  fnDef = "fn"
  `if` = "if"
  `import` = "import"
  `include` = "include"
  `in` = "in"
  info = "info"
  instanceof = "instanceof"
  implements = "implements"
  `let` = "let"
  `new` = "new"
  `of` = "of"
  public = "public"
  protected = "protected"
  private = "private"
  `return` = "return"
  super = "super"
  switch = "switch"
  this = "this"
  throw = "throw"
  `try` = "try"
  typeof = "typeof"
  typeDef = "type"
  `var` = "var"
  `while` = "while"
  with = "with"
  warn = "warn"
  `yield` = "yield"

