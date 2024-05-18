# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
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

template setDocTypeParam(str: var string) {.dirty.} =
  str.add(lex.buf[lex.bufpos])
  inc lex.bufpos
  while true:
    case lex.current
    of IdentChars:
      str.add(lex.buf[lex.bufpos])
      inc lex.bufpos
    else: break

handlers:
  proc handleDocBlock(lex: var Lexer, kind: TokenKind) =
    while true:
      case lex.buf[lex.bufpos]
      of '*':
        add lex
        if lex.current == '/':
          add lex
          break
      of '@':
        if lex.next("param"):
          inc lex.bufpos, 6
          skip lex
          if lex.current == '{':
            var ptype, pname, pdesc: string
            var pdefault = "="
            inc lex.bufpos
            while true:
              case lex.current:
              of '}':
                inc lex.bufpos
                skip lex # skip whitespaces
                while true:
                  case lex.current:
                  of IdentStartChars:
                    # collect param name
                    setDocTypeParam(pname)
                  else: break
              of '[':
                # collect ident name with an implicit default value
                # Example: [name = John Do]
                inc lex.bufpos
                skip lex # skip whitespaces
                while true:
                  case lex.current:
                  of IdentStartChars:
                    # param name
                    setDocTypeParam(pname)
                  of '=':
                    # default value
                    inc lex.bufpos
                    skip lex
                    setDocTypeParam(pdefault)
                  of ']':
                    inc lex.bufpos
                    break
                  else: break
              of IdentStartChars:
                # collect ident type 
                setDocTypeParam(ptype)
              else: break
            lex.attr.add(pname & ":" & ptype & pdefault)
        elif lex.next("return"):
          inc lex.bufpos, 7
        else:
          add lex
      of NewLines:
        inc lex.lineNumber
        add lex
      of EndOfFile: break
      else: add lex
    lex.kind = kind

  proc handleInlineComment(lex: var Lexer, kind: TokenKind) =
    inc lex.bufpos
    while true:
      case lex.buf[lex.bufpos]:
        of NewLines:
          lex.handleNewLine()
          break
        of EndOfFile: break
        else:
          inc lex.bufpos
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
  # https://github.com/Constellation/iv/blob/master/iv/token.h
  plus = '+':
    asgnAdd = '='
  minus = '-':
    asgnSub = '='
  multi = '*':
    asgnMulti = '='
  `div` = '/':
    doc = tokenize(handleDocBlock, '*')
    comment = tokenize(handleInlineComment, '/')
  `mod` =  '%':
    asgnMod = '='
  assign = '=':
    eq = '='
    arrExp = '>'
  `not` = '!':
    ne = '='
  bitwise = '|':
    asgnBitOr = '='
    `or` = '|'
  gt = '>':
    asgnSar = ">="
    asgnShr = ">>="
    gte = '='
  lt = '<':
    lte = '='
  qmark = '?'
  square = '^':
    asgnBitXor = '='
  tilde = '~'
  hash = '#'
  amp = '&':
    `and` = '&'
    andAsgn = "&=" # asgnBitAnd
  lp = '('
  rp = ')'
  lb = '['
  rb = ']'
  lc = '{'
  rc = '}'
  colon = ':'
  semiColon = ';'
  comma = ','
  dot = '.'
  at = '@':
    htmlTag = "html"
    timlTag = "timl"
    bassTag = "bass"
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
  litRange = "range"
  litNull = "null"
  litNil = "nil"
  litNumber = "number"

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
  `assert` = "assert"
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

