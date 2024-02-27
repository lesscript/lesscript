# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

{.warning[ImplicitDefaultValue]:off.}

import std/[strutils, macros]
import ./tokens, ./ast, ./logger
import importer

export logger

type
  Parser* = object
    lex: Lexer
    prev, curr, next: TokenTuple
    module: Module
    hasError: bool 
    logger*: Logger
    importPaths: seq[string]

  PrefixFunction = proc(p: var Parser, includes, excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.}
  InfixFunction = proc(p: var Parser, lhs: Node): Node {.gcsafe.}

const
  mathTokens = {tkPlus, tkMinus, tkMulti, tkDiv}
  infixTokens = {tkEQ, tkNE, tkGT, tkGTE, tkLT, tkLTE}
  assgnTokens = {tkBool, tkString, tkInteger, tkFloat, tkFnCall,
      tkIdentifier, tkNew, tkFnDef, tkFuncDef, tkFunctionDef,
      tkVarCall, tkLB, tkLC}
  litTokens   = {tkLitArray, tkLitBool, tkLitBoolean, tkLitFloat,
    tkLitInt, tkLitObject, tkLitString, tkLitRange}
  compTokens = {tkIdentifier, tkFunctionDef, tkFuncDef, tkFnDef,
    tkString, tkInteger, tkBool, tkFloat, tkLB, tkLC}

  jsp = true


#
# Compile-time internal utils
#
macro newPrefixProc(name: static string, body: untyped) =
  ## Create a new prefix proc with `name` and `body`
  ident(name).newProc(
    [
      ident("Node"), # return type
      nnkIdentDefs.newTree(
        ident("p"),
        nnkVarTy.newTree(ident("Parser")),
        newEmptyNode()
      ),
      nnkIdentDefs.newTree(
        ident("includes"),
        ident("excludes"),
        nnkBracketExpr.newTree(ident("set"), ident("TokenKind")),
        newNimNode(nnkCurly),
      ),
      nnkIdentDefs.newTree(
        ident("parent"),
        ident("Node"),
        newNilLit()
      ),
    ],
    body = body,
    pragmas = nnkPragma.newTree(
      ident("gcsafe")
    )
  )

macro casey(tkTuple, kind, body: untyped, elseBody: untyped = nil) =
  ## Create a case statement with a single `of` branch.
  ## When `elseBody` is `nil` will insert a `discard` statement 
  result = macros.newStmtList()
  var elseStmt =
    if elseBody.kind == nnkNilLit:
      nnkDiscardStmt.newTree(newEmptyNode())
    else:
      elseBody
  result.add(
    nnkCaseStmt.newTree(
      newDotExpr(tkTuple, ident("kind")),
      nnkOfBranch.newTree(kind, body),
      nnkElse.newTree(
        macros.newStmtList(elseStmt)
      )
    )
  )

include ../utils

#
# Forward declarations
#
proc getPrefixOrInfix(p: var Parser, includes,
    excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.}

proc getInfixFn(p: var Parser): InfixFunction {.gcsafe.}

proc parse(p: var Parser, includes,
    excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.}

proc parseStmt(p: var Parser, parent: (TokenTuple, Node),
    includes, excludes: set[TokenKind] = {}, isCurlyStmt = false): Node {.gcsafe.}

proc parseCall(p: var Parser, includes,
    excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.}

proc parseFunction(p: var Parser, includes,
    excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.}

proc parseAnoArray(p: var Parser, includes,
    excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.}

proc parseAnoObject(p: var Parser, includes,
    excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.}

proc parseKeyType(p: var Parser, isStatic, isReadonly = false): Node {.gcsafe.}

proc parseAssignableNode(p: var Parser): Node {.gcsafe.}

#
# Parse Utils
#
proc hasErrors*(p: Parser): bool = p.hasError

proc isInfix*(p: var Parser): bool {.inline.} =
  p.curr.kind in infixTokens + mathTokens 

proc isInfix*(tk: TokenTuple): bool {.inline.} =
  tk.kind in infixTokens + mathTokens 

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

proc isChild(tk, parent: TokenTuple): bool =
  (tk.line > parent.line and tk.pos - parent.pos == 2)

proc isNested(tk, parent: TokenTuple): bool {.inline.} =
  tk isnot tkEOF and (tk.line > parent.line and tk.pos > parent.pos)

proc identChild(tk, parent: TokenTuple): bool {.inline.} =
  tk is tkIdentifier and isNested(tk, parent)

proc walk(p: var Parser, offset = 1) =
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()
    case p.next.kind
    of tkComment:
      p.next = p.lex.getToken() # skip inline comments
    else: discard

proc isIdent(tk: TokenTuple, anyIdent, anyStringKey = false): bool =
  result = tk is tkIdentifier
  if result or (anyIdent and tk.kind != tkString):
    return tk.value.validIdentifier
  if result or anyStringKey:
    return tk.value.validIdentifier

template checkIndent(prevToken, currToken: TokenTuple, kind: TokenKind) {.dirty.} =
  if currToken is kind and currToken.line == prevToken.line:
    error(badIndentation, currToken)

proc isIdent(p: var Parser): bool =
  p.curr.isIdent

#
# Stmt List
#
template isInsideBlock: untyped = 
  if unlikely(isCurlyStmt == false):
    (p.curr.line > parent[0].line and p.curr.pos > parent[0].pos)
  else:
    (p.curr isnot tkRC)

template stmtBody(body: untyped, includes, excludes: set[TokenKind] = {}) {.dirty.} =
  var isCurlyStmt =
    if p.curr is tkLC:
      walk p; true
    else: false
  body = p.parseStmt((tk, result), includes, excludes, isCurlyStmt)
  if likely(isCurlyStmt):
    casey p.curr, tkRC:
      walk p
    do: error(missingRC, tk)

proc parseStmt(p: var Parser, parent: (TokenTuple, Node), includes,
  excludes: set[TokenKind] = {}, isCurlyStmt = false): Node =
  ## Creates a new `ntStmtList` node
  result = ast.newStmtList()
  while p.curr isnot tkEOF and isInsideBlock:
    var node: Node = p.parse()
    if likely(node != nil):
      case node.nt
      of ntCommand:
        if node.cmdType == cReturn and parent[1] != nil:
          parent[1].fnHasReturnType = true
        result.stmtNode.list.add(node)
      else:
        result.stmtNode.list.add(node)
    else: return nil

proc parseStmtTree(p: var Parser, parent: (TokenTuple, Node), includes,
    excludes: set[TokenKind] = {}, isCurlyStmt = false): Node =
  ## Creates a new `ntStmtTree` node
  result = ast.newStmtTree()
  while p.curr isnot tkEOF and isInsideBlock:
    let tk = p.curr
    var node: Node = p.parseKeyType()
    if likely(node != nil):
      if likely(result.stmtNode.tree.hasKey(node.pKey) == false):
        result.stmtNode.tree[node.pKey] = node
      else: errorWithArgs(duplicateField, tk, [tk.value])
    else: return nil

template stmtTree(body: untyped, includes, excludes: set[TokenKind] = {}) {.dirty.} =
  var isCurlyStmt =
    if p.curr is tkLC:
      walk p; true
    else: false
  body = p.parseStmtTree((tk, result), includes, excludes, isCurlyStmt)
  if likely(isCurlyStmt):
    casey p.curr, tkRC:
      walk p
    do: error(missingRC, tk)

proc getType(tk: TokenTuple): Type =
  case tk.kind
    of tkLitArray: tArray
    of tkLitBool: tBool
    of tkLitFloat: tFloat
    of tkLitFloat8: tFloat8
    of tkLitFloat16: tFloat16
    of tkLitFloat32: tFloat32
    of tkLitFloat64: tFloat64
    of tkLitInt: tInt
    of tkLitInt8: tInt8
    of tkLitInt16: tInt16
    of tkLitInt32: tInt32
    of tkLitInt64: tInt64
    of tkLitBigInt: tBigInt
    of tkLitObject, tkLC: tObject
    of tkLitString: tString
    of tkLitRange: tRange
    # of tkLitUint: tUint
    # of tkLitUint8: tUint
    # of tkLitUint16: tUint16
    # of tkLitUint32: tUint32
    # of tkLitUint64: tUint64
    of tkFuncDef, tkFnDef, tkFunctionDef: tFunction
    of tkClassDef: tClass
    else:
      if tk.value.len == 1 and tk.value[0].isUpperAscii:
        tAny
      elif tk.kind == tkIdentifier:
        tCustom
      else: tNone

proc getTypeByToken(tk: TokenTuple): Type =
  case tk.kind
    of tkBool: tBool
    of tkFloat: tFloat
    of tkInteger: tInt
    of tkString: tString
    of tkLB: tArray
    of tkLC: tObject
    of tkNew: tClass
    else: tNone

proc getTypeByString(str: string): Type =
  # Retrieves a field from `Type` enum.
  # Used to parse `@param` types from block comments 
  try:
    parseEnum[Type](str)
  except ValueError:
    return tCustom

proc getVarType(tk: TokenTuple): VarType =
  case tk.kind
  of tkVar: vtVar
  of tkLet: vtLet
  else: vtConst

newPrefixProc "parseNew":
  if likely(p.next.isIdent):
    walk p, 2
    result = ast.newCall(p.prev)
    result.callType = CallType.classCall
    if p.curr is tkLP:
      walk p, 2

features "literal", "var", "assign", "data", "for",
          "type", "enum", "interface", "function", "class",
          "command", "condition", "comment"

proc parseAssignableNode(p: var Parser): Node =
  case p.curr.kind
  of tkLB:          p.parseAnoArray()
  of tkLC:          p.parseAnoObject()
  of tkIdentifier:  p.parseCall()
  else: p.getPrefixOrInfix(includes = {tkBool, tkFloat, tkInteger,
          tkString, tkSQuoteString, tkLB, tkLC, tkIdentifier, tkAssert})

proc parseKeyType(p: var Parser, isStatic, isReadonly = false): Node =
  # Parse pairs of `key: value` or `key: type = value`
  if likely((p.curr in {tkIdentifier, tkString} or p.curr.value.validIdentifier) and p.next in {tkColon, tkQMark}):
    var prop = ast.newProperty(p.curr.value)    
    walk p
    prop.pReadonly = isReadonly
    prop.pStatic = isStatic
    if p.curr is tkQMark:
      prop.pOptional = true
      walk p # tkQMark
      if p.curr is tkColon: walk p
      else: return nil
    else:
      walk p
    if likely(p.curr in litTokens or p.curr is tkIdentifier):
      let pTypeIdent = p.curr
      prop.pType = p.curr.getType
      walk p
      if p.curr is tkAssign:
        if p.next in assgnTokens:
          walk p
          prop.pVal = p.parseAssignableNode()
        else: return nil # non assignnable node
      if prop.pType == tCustom:
        prop.pIdent = pTypeIdent.value
      result = prop

newPrefixProc "parseDotExpr":
  # parse a new `x.y` dot expression
  # todo newInfixProc
  let tk = p.curr
  let lhs = ast.newId(p.curr)
  walk p
  while p.curr is tkDot:
    result = ast.newDot(lhs)
    walk p
    if p.curr.isIdent(anyIdent = true):
      result.rhs = ast.newCall(p.curr)
      walk p
      if p.curr is tkLP:
        walk p
        walk p
        result.rhs.callType = CallType.fnCall
    else: break
  if p.curr is tkAssign:
    walk p
    var node = p.parseAssignableNode()
    likelyNodeReturn:
      ast.newAssignment(result, node, tk)

newPrefixProc "parseDeclare":
  # parse a new `declare` definition
  let tk = p.curr; walk p
  let node = p.parse(includes = {tkFnDef, tkFuncDef,
    tkFunctionDef, tkVar, tkConst, tkLet})
  likelyNodeReturn:
    ast.newDeclareStmt(tk, node)


newPrefixProc "parseImport":
  let tk = p.curr
  if p.next in {tkSQuoteString, tkString}:
    walk p
    result = ast.newImport(p.curr.value)
    p.importPaths.add(p.curr.value)
    walk p

newPrefixProc "parseBlockStmt":
  let tk = p.curr
  walk p
  result = ast.newStmtList()
  while p.curr notin {tkEOF, tkRC}:
    var node: Node = p.parse(excludes = {tkReturn})
    if likely(node != nil):
      result.stmtNode.list.add(node)
    else: return nil
  if p.curr is tkRC:
    walk p
  else:
    return nil

#
# Main Prefix Handler
# 
proc getPrefixFn(p: var Parser, includes, excludes: set[TokenKind] = {}): PrefixFunction =
  case p.curr.kind
  of tkInterface:
    parseInterface
  of tkVar, tkLet, tkConst:
    parseVar
  of tkInteger: parseIntLit
  of tkFloat:   parseFloatLit
  of tkBool:    parseBoolLit
  of tkString:  parseStrLit
  of tkLitRange:   parseRangeLit
  of tkIf:
    parseIf
  of tkClassDef:
    parseClassDef
  of tkFnDef, tkFunctionDef, tkFuncDef:
    parseFunction
  of tkTypeDef:
    parseTypeDef
  of tkIdentifier:
    case p.next.kind
    of tkAssign: parseAssign
    of tkDot:    parseDotExpr
    else:        parseCall
  of tkFor: parseFor
  of tkEcho, tkWarn, tkError, tkInfo, tkAssert:
    parseConsole
  of tkReturn:  parseReturn
  of tkEnumDef: parseEnum
  of tkThis: parseThis
  of tkNew: parseNew
  of tkDeclare: parseDeclare
  of tkImport: parseImport
  of tkLC: parseBlockStmt
  of tkDoc:
    parseBlockComment
  else: nil

#
# Infix Parse Handlers
#
proc parseMathExp(p: var Parser, lhs: Node): Node {.gcsafe.}
proc parseCompExp(p: var Parser, lhs: Node): Node {.gcsafe.}

proc parseCompExp(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse logical expressions with symbols (==, !=, >, >=, <, <=)
  let op = getInfixOp(p.curr.kind, false)
  walk p
  let rhs = p.parse(includes = compTokens)
  if likely(rhs != nil):
    result = ast.newInfix(lhs)
    result.infixOp = op
    if p.curr.kind in mathTokens:
      result.rhsInfix = p.parseMathExp(rhs)
    else:
      result.rhsInfix = rhs
    case p.curr.kind
    of tkOr, tkAnd:
      result = ast.newInfix(result)
      result.infixOp = getInfixOp(p.curr.kind, true)
      walk p
      let rhs = p.getPrefixOrInfix()
      if likely(rhs != nil):
        result.rhsInfix = rhs
    # of tkAndAsgn:
    #   todo()
    else: discard

proc parseMathExp(p: var Parser, lhs: Node): Node {.gcsafe.} =
  # parse math expressions (+, -, *, /)
  let infixOp = ast.getInfixCalcOp(p.curr.kind, false)
  walk p
  let rhs = p.parse(includes = compTokens)
  if likely(rhs != nil):
    result = ast.newInfixMath(lhs)
    result.infixMathOp = infixOp
    case p.curr.kind
    of tkMulti, tkDiv:
      result.rhsMath = p.parseMathExp(rhs)
    of tkPlus, tkMinus:
      result.rhsMath = rhs
      result = p.parseMathExp(result)
    else:
      result.rhsMath = rhs

proc getInfixFn(p: var Parser): InfixFunction {.gcsafe.} =
  case p.curr.kind
  of infixTokens: parseCompExp
  of mathTokens: parseMathExp
  else: nil

proc parseInfix(p: var Parser, lhs: Node): Node {.gcsafe.} =
  var infixNode: Node # ntInfix
  let infixFn = p.getInfixFn()
  if likely(infixFn != nil):
    result = p.infixFn(lhs)
  # if p.curr in infixTokens:
  #   result = p.parseCompExp(result)

proc getPrefixOrInfix(p: var Parser, includes,
    excludes: set[TokenKind] = {}, parent: Node = nil): Node {.gcsafe.} =
  let lhs = p.parse(includes, excludes)
  var infixNode: Node
  if p.curr.isInfix:
    if likely(lhs != nil):
      infixNode = p.parseInfix(lhs)
      if likely(infixNode != nil):
        return infixNode
  result = lhs

proc parse(p: var Parser, includes, excludes: set[TokenKind] = {},
    parent: Node = nil): Node {.gcsafe.} =
  if excludes.len > 0:
    if unlikely p.curr in excludes:
      errorWithArgs(invalidContext, p.curr, [p.curr.value])
  if includes.len > 0:
    if unlikely p.curr notin includes:
      errorWithArgs(invalidContext, p.curr, [p.curr.value])
  let prefixFn = p.getPrefixFn(includes, excludes)
  if likely(prefixFn != nil):
    let lhsNode = p.prefixFn()
    if likely(lhsNode != nil):
      return lhsNode
  errorWithArgs(unexpectedToken, p.curr, [p.curr.value])

#
# Public API
#
proc parseModule*(code: string, filePath = "", isLocal = false): Parser {.gcsafe.}
proc getModule*(p: Parser): Module = p.module

proc parseHandle[T](imp: Import[T], importFile: ImportFile,
    ticket: ptr TicketLock): seq[string] {.gcsafe, nimcall.} =
  let filePath = importFile.getImportPath
  if likely(not imp.handle.module.imports.hasKey(filePath)):
    var localParser = parseModule(importFile.source, filePath, isLocal = true)
    imp.handle.module.imports[filePath] = localParser.getModule()
    if localParser.importPaths.len > 0:
      return localParser.importPaths

proc parseModule*(code: string, filePath = "", isLocal = false): Parser {.gcsafe.} =
  var imp = newImport[Parser](filepath)
  # var p = imp.handle
  imp.handle.lex = newLexer(code, allowMultilineStrings = true)
  imp.handle.module = Module()
  imp.handle.curr = imp.handle.lex.getToken()
  imp.handle.next = imp.handle.lex.getToken()

  while true:
    case imp.handle.curr.kind
    of tkComment:
      # skip inline comments
      imp.handle.curr = imp.handle.next
      imp.handle.next = imp.handle.lex.getToken()
    else: break

  imp.handle.logger = Logger(filePath: filePath)
  imp.handle.module.path = filePath
  
  while not imp.handle.hasErrors:
    if imp.handle.curr.kind == tkEOF: break
    let node = imp.handle.parse(excludes = {tkReturn})
    if likely(node != nil):
      add imp.handle.module.nodes, node
    else: break
  imp.handle.lex.close()
  if not isLocal:
    if imp.handle.importPaths.len > 0:
      imp.imports(imp.handle.importPaths, parseHandle[Parser])
  result = imp.handle
