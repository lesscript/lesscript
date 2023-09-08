# A fast, statically typed Rock'n'Roll language that
# transpiles to Nim lang and JavaScript.
# 
# (c) 2023 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://lesscript.com
#          https://github.com/openpeeps

{.warning[ImplicitDefaultValue]:off.}

import std/[strutils, macros]
import ./tokens, ./ast, ./utils/logger

export logger

type
  Parser* = object
    lex: Lexer
    prev, curr, next: TokenTuple
    program: Program
    hasError: bool 
    logger*: Logger

  PrefixFunction = proc(p: var Parser, includes, excludes: set[TokenKind] = {}): Node
  InfixFunction = proc(p: var Parser, lhs: Node): Node

const
  mathTokens = {tkPlus, tkMinus, tkMulti, tkDiv}
  infixTokens = {tkEQ, tkNE, tkGT, tkGTE, tkLT, tkLTE}
  assgnTokens = {tkBool, tkString, tkInteger, tkFloat, tkFnCall,
      tkIdentifier, tkNew, tkFnDef, tkFuncDef, tkFunctionDef,
      tkVarCall, tkLB, tkLC}
  litTokens   = {tkLitArray, tkLitBool, tkLitBoolean, tkLitFloat, tkLitInt, tkLitObject, tkLitString}
  compTokens = {tkIdentifier, tkFunctionDef, tkFuncDef, tkFnDef,
    tkString, tkInteger, tkBool, tkFloat, tkLB, tkLC}
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
      )
    ],
    body
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

template expectWalkOrNil(kind: TokenKind): untyped {.dirty.} =
  if likely(p.curr is kind):
    walk p
  else: return nil

template expectWalkOrNil(kinds: set[TokenKind]): untyped {.dirty.} =
  if likely(p.curr in kinds):
    walk p
  else: return nil

#
# Forward declarations
#
proc getPrefixOrInfix(p: var Parser, includes, excludes: set[TokenKind] = {}): Node
proc getInfixFn(p: var Parser): InfixFunction
proc parse(p: var Parser, includes, excludes: set[TokenKind] = {}): Node
proc parseStmt(p: var Parser, parent: (TokenTuple, Node), includes, excludes: set[TokenKind] = {}, isCurlyStmt = false): Node
proc parseCall(p: var Parser, includes, excludes: set[TokenKind] = {}): Node

proc parseAnoArray(p: var Parser, includes, excludes: set[TokenKind] = {}): Node
proc parseAnoObject(p: var Parser, includes, excludes: set[TokenKind] = {}): Node
proc parseKeyType(p: var Parser, isStatic, isReadonly = false): Node

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

proc walk(p: var Parser, offset = 1) =
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()

proc isIdent(tk: TokenTuple, anyIdent, anyStringKey = false): bool =
  result = tk is tkIdentifier
  if result or (anyIdent and tk.kind != tkString):
    return tk.value.validIdentifier
  if result or anyStringKey:
    return tk.value.validIdentifier

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
    of tkLitObject: tObject
    of tkLitString: tString
    # of tkLitUint: tUint
    # of tkLitUint8: tUint
    # of tkLitUint16: tUint16
    # of tkLitUint32: tUint32
    # of tkLitUint64: tUint64
    else:
      if tk.kind == tkIdentifier: tCustom
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

proc getVarType(tk: TokenTuple): VarType =
  case tk.kind
  of tkVar: vtVar
  of tkLet: vtLet
  else: vtConst

#
# Literals
#
newPrefixProc "parseBoolLit":
  # parse bool
  result = ast.newBool(p.curr)
  walk p

newPrefixProc "parseFloatLit":
  # parse float
  result = ast.newFloat(p.curr)
  walk p

newPrefixProc "parseIntLit":
  # parse int
  result = ast.newInt(p.curr)
  walk p

newPrefixProc "parseStrLit":
  # parse a string
  result = ast.newStr(p.curr)
  walk p

newPrefixProc "parseThis":
  result = ast.newCall(p.curr)
  walk p

newPrefixProc "parseNew":
  if likely(p.next.isIdent):
    walk p, 2
    result = ast.newCall(p.prev)
    result.callType = CallType.classCall
    if p.curr is tkLP:
      walk p, 2

newPrefixProc "parseBlockComment":
  # parse comment
  result = ast.newComment(p.curr)
  walk p

newPrefixProc "parseAnoObject":
  # parse an anonymous object
  let anno = ast.newObject(p.curr)
  walk p # {
  while p.curr.isIdent(anyIdent = true, anyStringKey = true) and p.next.kind == tkColon:
    let fName = p.curr
    walk p, 2
    if likely(anno.objectItems.hasKey(fName.value) == false):
      var item: Node
      case p.curr.kind
      of tkLB:
        item = p.parseAnoArray()
      of tkLC:
        item = p.parseAnoObject()
      else:
        item = p.getPrefixOrInfix(includes = assgnTokens)
      if likely(item != nil):
        anno.objectItems[fName.value] = item
      else: return
    else:
      errorWithArgs(duplicateField, fName, [fName.value])
    if p.curr is tkComma:
      walk p # next k/v pair
  if likely(p.curr is tkRC):
    walk p
  return anno

newPrefixProc "parseAnoArray":
  # parse an anonymous array
  let tk = p.curr
  walk p # [
  var items: seq[Node]
  while p.curr.kind != tkRB:
    var item = p.getPrefixOrInfix(includes = assgnTokens)
    if likely(item != nil):
      add items, item
    else:
      if p.curr is tkLB:
        item = p.parseAnoArray()
        if likely(item != nil):
          add items, item
        else: return # todo error multi dimensional array
      elif p.curr is tkLC:
        item = p.parseAnoObject()
        if likely(item != nil):
          add items, item
        else: return # todo error object construction
      else: return # todo error
    if p.curr is tkComma:
      walk p
  expectWalkOrNil tkRB
  result = ast.newArray(tk, items)

proc parseAssignableNode(p: var Parser): Node =
  case p.curr.kind
  of tkBool:        p.parseBoolLit()
  of tkFloat:       p.parseFloatLit()
  of tkInteger:     p.parseIntLit()
  of tkLB:          p.parseAnoArray()
  of tkLC:          p.parseAnoObject()
  of tkString, tkSQuoteString:
    p.parseStrLit()
  of tkIdentifier:  p.parseCall()
  else: p.parse()

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

newPrefixProc "parseTypeDef":
  # parse a `type` definition
  let tk = p.curr
  walk p # tkTypeDef
  if p.curr.isIdent:
    let ident = p.curr
    if p.next is tkAssign:
      walk p, 2
      var typeNode: Node
      var typeLit: Type
      result = ast.newTypeDef(ident, nil, tObject)
      if p.curr in litTokens:
        typeLit = getType(p.curr)
        walk p
        if typeLit == tObject:
          stmtTree(result.typeNode)
        result.typeLit = typeLit
      else:
        stmtTree(result.typeNode)

template setVarType {.dirty.} =
  if implType == tNone:
    implType = commonVar.valType
    if commonVar.varValue != nil and node == nil:
      node = commonVar.varValue
  for someVar in varMulti:
    someVar.valType = commonVar.valType
    if commonVar.varValue != nil:
      someVar.varValue = commonVar.varValue

proc parseVar(p: var Parser, tk, ident: TokenTuple,
          varType: VarType, isArg, isUnpack = false): Node =
  # parse one or more variables/function parameters
  # supporting type, implicit value or both.
  # `var x: int = 0` or `x, y, z: int = 0`
  var
    node: Node
    implType: Type
    varMulti: seq[Node] # ntVarDef
    valTypeof: Node
  if p.curr is tkColon:
    walk p, 2
    implType = p.prev.getType
    if implType == tCustom:
      valTypeof = ast.newId(p.prev)
  if p.curr is tkAssign:
    walk p
    node = p.parseAssignableNode()
    if unlikely(node == nil):
      return nil
    if implType == tNone:
      implType = node.getType()
    if node.nt == ntCall:
      valTypeof = ast.newId(node.callIdent)

  if unlikely(varType == vtConst and node == nil) and isUnpack == false:
    errorWithArgs(immutableImplicitValue, ident, [ident.value])  
  if isArg and implType != tNone:
    return ast.newVar(ident, node, varType, implType, varMulti, tk)
  
  while p.curr is tkComma:
    walk p
    var commonVar: Node
    var varToken = p.curr 
    if p.curr.isIdent(anyIdent = true):
      commonVar = ast.newVar(p.curr, tk)
      walk p
      var typedOrDefault: bool
      if p.curr is tkColon:
        walk p, 2
        commonVar.valType = p.prev.getType
        typedOrDefault = true
      if p.curr is tkAssign:
        walk p
        var subNode = p.parseAssignableNode()
        if likely(subNode != nil):
          commonVar.varValue = subNode
          if commonVar.valType == tNone:
            commonVar.valType = subNode.getType
          typedOrDefault = true
        else: return nil
      varMulti.add(commonVar)
      if isArg and typedOrDefault:
        return ast.newVar(ident, node, varType, implType, varMulti, tk, valTypeof)
      var otherVar: Node
      if typedOrDefault and p.curr is tkComma:
        walk p, 2
        let otherIdent = p.prev
        otherVar = p.parseVar(tk, otherIdent, varType)
        # set type/value for the first var identifier
        setVarType()
        if likely(otherVar != nil):
          varMulti.add(otherVar)
          break
        else: return nil
      else:
        setVarType()
    else: return nil # unexpected token
  return ast.newVar(ident, node, varType, implType, varMulti, tk, valTypeof)

proc parseDestructor(p: var Parser, xVar: TokenTuple, varType: VarType): Node =
  # unpack values from arrays or object
  # properties into distinct variables.
  walk p # tkLB
  result = Node(nt: ntUnpack)
  while p.curr.isIdent(anyIdent = true):
    let varIdent = p.curr
    walk p
    var x = p.parseVar(xVar, varIdent, varType, isUnpack = true)
    if likely(x != nil):
      result.unpackTo.add(x)
      if p.curr is tkComma:
        walk p
    else: return nil
  expectWalkOrNil tkRB
  if p.curr is tkAssign:
    walk p
    case p.curr.kind
    of tkIdentifier, tkLB, tkLC:
      result.unpackFrom = p.parse()
    else:
      errorWithArgs(invalidIterator, p.curr, [$(p.curr.getTypeByToken())])

newPrefixProc "parseVarDef":
  # parse variable declarations, `var`, `let`, `const`
  let
    tk = p.curr
    varType = getVarType(p.curr)
  case p.next.kind
  of tkLB:
    walk p
    result = p.parseDestructor(tk, varType)
  else:
    let ident = p.next
    walk p, 2
    return p.parseVar(tk, ident, varType)

newPrefixProc "parseAssign":
  # parse a new assignment
  let tk = p.curr
  let ident = ast.newId(p.curr)
  walk p, 2
  var node = p.parseAssignableNode()
  if likely(node != nil):
    result = ast.newAssignment(ident, node, tk)

newPrefixProc "parseDotExpr":
  # parse a new `x.y` dot expression
  let tk = p.curr
  let lhs = ast.newId(p.curr)
  walk p
  while p.curr is tkDot:
    result = ast.newDot(lhs)
    walk p
    case p.curr.kind
    of tkIdentifier:
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
    if likely(node != nil):
      return ast.newAssignment(result, node, tk)

newPrefixProc "parseEnum":
  # parse a new `enum` declaration
  let tk = p.curr
  if likely(p.next.isIdent):
    let ident = p.next
    walk p, 2
    if likely(p.curr is tkLC):
      walk p
      var enumTable = EnumTable()
      while p.curr is tkIdentifier:
        let fid = p.curr
        if not enumTable.hasKey(p.curr.value):
          walk p
          if p.curr is tkAssign:
            if likely(p.next in {tkInteger, tkString} ):
              walk p
              enumTable[fid.value] = p.parseAssignableNode()
          else:
            enumTable[fid.value] = nil
          if p.curr is tkComma:
            walk p
      if p.curr is tkRC:
        walk p
        result = ast.newEnum(ident, enumTable)

newPrefixProc "parseInterfaceDef":
  ## Parse `interface` definition
  let tk = p.curr
  let ident = p.next
  walk p, 2
  result = ast.newInterface(ident.value)
  result.interfaceStmt = ast.newStmtTree()
  if p.curr is tkLC:
    walk p # tkLC
    while p.curr isnot tkRC:
      var isReadonly, isStatic: bool
      while true:
        if p.curr is tkReadonly:
          isReadonly = true
          walk p
        elif p.curr is tkStatic:
          isStatic = true
          walk p
        else: break
      let field = p.curr
      var node = p.parseKeyType(isStatic, isReadonly)
      if likely(node != nil):
        if likely(result.interfaceStmt.stmtNode.tree.hasKey(node.pKey) == false):
          result.interfaceStmt.stmtNode.tree[node.pKey] = node
          if p.curr in {tkComma, tkSColon}:
            walk p
          elif p.curr.line == field.line:
            return nil # error, nested
        else:
          errorWithArgs(duplicateField, field, [field.value])
      else: break
    walk p # tkRC

newPrefixProc "parseFunction":
  let tk = p.curr
  var ident: TokenTuple
  if tk.isIdent:
    ident = tk
    result = ast.newFunction(ident.value, tk)
    walk p
  elif p.next.isIdent:
    ident = p.next 
    walk p, 2
    result = ast.newFunction(ident.value, tk)
  else:
    result = ast.newFunction(tk) # an anonymous function
    walk p
  # parse generics
  if p.curr in {tkLB, tkLT}:
    var endGen =
      if p.curr is tkLB: tkRB
      else: tkGT
    walk p # tkLB/tkLC
    var gens: seq[(TokenTuple, Type)]
    while p.curr isnot endGen:
      if likely(p.curr is tkIdentifier and p.curr.value.len == 1):
        var
          gentype: Type
          genid: TokenTuple = p.curr
          others: seq[TokenTuple]
        if p.next is tkColon:
          walk p, 2
          if likely(p.curr in litTokens + {tkIdentifier}):
            gentype = p.curr.getType()
            walk p
        elif p.next is tkComma:
          walk p
          while p.curr is tkComma:
            walk p
            if likely(p.curr is tkIdentifier and p.curr.value.len == 1):
              others.add(p.curr)
              walk p
            else: return # error
          if p.curr is tkColon:
            walk p
            if likely(p.curr in litTokens + {tkIdentifier}):
              gentype = p.curr.getType()
              walk p
        add gens, (genid, gentype)
        for otherid in others:
          add gens, (otherid, gentype)
        if p.curr is tkComma:
          walk p
      else: return nil
    if gens.len > 0:
      expectWalkOrNil({tkRB, tkGT})
    for gen in gens:
      if likely result.fnGenerics.hasKey(gen[0].value) == false:
        result.fnGenerics[gen[0].value] = gen[1]
      else: errorWithArgs(redefinitionError, gen[0], [gen[0].value])
    reset(gens)
  
  # parse params
  if p.curr is tkLP:
    walk p
    while p.curr is tkIdentifier:
      walk p
      let pIdent = p.prev
      if likely(result.fnParams.hasKey(pIdent.value) == false):
        let pNode = p.parseVar(tk, pIdent, vtVar, isArg = true)
        if likely(pNode != nil):
          result.fnParams[pIdent.value] = pNode
        else: return nil
        if p.curr is tkComma: walk p
      else: errorWithArgs(redefineParameter, pIdent, [pIdent.value])
    expectWalkOrNil(tkRP)

  # parse return type
  if p.curr is tkColon:
    walk p
    result.fnReturnType = p.curr.getType()
    case result.fnReturnType
    of tCustom:
      result.fnReturnIdent = newId(p.curr)
    of tNone:
      return nil
    else: discard
    walk p
  # parse function body
  stmtBody(result.fnBody, excludes = {tkImport, tkInclude, tkExport})
  # result.fnFwd = true

newPrefixProc "parseClassDef":
  ## Parse a new `class` definition
  walk p
  if p.curr.isIdent:
    let ident = p.curr
    walk p
    result = ast.newClass(ident)
    var implements: bool
    while true:
      if p.curr is tkExtends:
        if likely(result.classExtends.len == 0):
          walk p 
          if p.curr.isIdent:
            result.classExtends.add(p.curr.value)
            walk p
            while p.curr is tkComma:
              walk p
              if p.curr.isIdent and p.curr.value notin result.classExtends:
                result.classExtends.add(p.curr.value)
                walk p
              else: errorWithArgs(duplicateExtend, p.curr, [ident.value, p.curr.value])
          else: return nil
        else: return nil
      elif p.curr is tkImplements:
        if not implements:
          if p.next is tkIdentifier:
            walk p
            result.classImplements.add(p.curr.value)
            walk p
            while p.curr is tkComma:
              walk p
              if p.curr is tkIdentifier:
                if p.curr.value notin result.classImplements:
                  result.classImplements.add(p.curr.value)
                  walk p
                else: errorWithArgs(duplicateImplement, p.curr, [ident.value, p.curr.value])
              else: return nil
          implements = true
        else: return nil
      else: break

    if p.curr is tkLC:
      walk p # tkLC
      while p.curr isnot tkRC:
        if p.curr is tkEOF:
          error(missingRC, p.curr)
        var isReadonly, isStatic: bool
        if p.curr is tkReadonly:
          isReadonly = true
          walk p
        if p.curr is tkStatic:
          isStatic = true
          walk p
        case p.curr.kind
        of tkIdentifier:
          if p.next in {tkColon, tkQMark}:
            let fieldIdent = p.curr
            var propNode = p.parseKeyType(isStatic, isReadonly)
            if likely(propNode != nil):
              if likely(result.properties.hasKey(propNode.pKey) == false):
                result.properties[propNode.pKey] = propNode
              else: errorWithArgs(duplicateField, fieldIdent, [fieldIdent.value])
            else: return nil
          elif p.next is tkLP:
            var fnNode = p.parseFunction()
            if likely(fnNode != nil):
              result.methods.add(fnNode)
        # of tkReadonly:
          # p.parseKeyType(true, isStatic)
        else: return nil
      if p.curr is tkRC:
        walk p

newPrefixProc "parseDeclare":
  # parse a new `declare` definition
  let tk = p.curr; walk p
  let node = p.parse(includes = {tkFnDef, tkFuncDef,
    tkFunctionDef, tkVar, tkConst, tkLet})
  if likely(node != nil):
    result = newDeclareStmt(tk, node)

newPrefixProc "parseCall":
  # parse a new call command
  var ident = p.curr
  result = ast.newCall(ident)
  walk p
  casey p.curr, tkLP:
    walk p
    while p.curr isnot tkRP:
      if p.curr is tkEOF: 
        errorWithArgs(eof, p.curr, [$(tkRP)])
      var arg: CallArg
      case p.curr.kind
      of assgnTokens:
        case p.next.kind
        of tkAssign:
          arg.argName = p.curr.value
          walk p, 2
          if likely(p.curr in assgnTokens):
            arg.argValue = p.parseAssignableNode()
          else: return nil
        else:
          arg.argValue = p.parseAssignableNode()
        if p.curr is tkComma: walk p
        elif p.curr isnot tkRP: return nil
      else: return nil 
      result.callArgs.add(arg)
    walk p # tkRP
    result.callType = CallType.fnCall

  while p.curr is tkDot:
    result = newDot(result)
    walk p
    case p.curr.kind
    of tkIdentifier:
      result.rhs = ast.newCall(p.curr)
      walk p
      if p.curr is tkLP:
        walk p
        walk p
        result.rhs.callType = CallType.fnCall
    else: discard

newPrefixProc "parseEcho":
  # parse a new `echo` command
  let tk = p.curr
  let cmdType =
    case tk.kind
    of tkWarn: cWarn
    of tkInfo: cInfo
    of tkError: cError
    else: cEcho
  walk p
  let node = p.parseAssignableNode()
  if likely(node != nil):
    result = ast.newCommand(cmdType, node, tk)

newPrefixProc "parseReturn":
  # parse a new `return` command
  let tk = p.curr
  walk p
  let node = p.parseAssignableNode()
  if likely(node != nil):
    result = ast.newCommand(cReturn, node, tk)

newPrefixProc "parseIf":
  # parse a new `if` statement
  let tk = p.curr
  const condBodyExcludes = {tkImport, tkInclude, tkExport}
  walk p
  # parse `if` branch
  var ifBranch: ConditionBranch
  expectWalkOrNil tkLP
  ifBranch.cond #[ntInfix]# = p.getPrefixOrInfix()
  if likely(ifBranch.cond != nil):
    expectWalkOrNil tkRP
    stmtBody(ifBranch.body, excludes = condBodyExcludes)
    result = newIfCond(ifBranch, tk)
  # parse `else if` branches
  while p.curr is tkElseIf:
    let elifx = p.curr
    walk p; expectWalkOrNil tkLP
    var elifBranch: ConditionBranch
    elifBranch.cond #[ntInfix]# = p.getPrefixOrInfix()
    if likely(elifBranch.cond != nil):
      expectWalkOrNil tkRP
      stmtBody(elifBranch.body, excludes = condBodyExcludes)
      elifBranch.body.meta = elifx.trace
      result.elifBranch.add(elifBranch)
    else: return nil # unexpected token
  # parse `else` branch
  if p.curr is tkElse:
    let elsex = p.curr
    walk p
    stmtBody(result.elseBranch, excludes = condBodyExcludes)
    if unlikely(result.elseBranch == nil):
      return nil
    result.elseBranch.meta = elsex.trace

newPrefixProc "parseFor":
  # parse a new `for` statement
  # https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Loops_and_iteration
  let tk = p.curr
  walk p
  expectWalkOrNil tkLP
  case p.curr.kind
  of tkVar, tkLet, tkConst:
    let xVar = p.curr
    let varType = getVarType(p.curr)
    var itemNode: Node
    if unlikely(p.next is tkLB):
      walk p
      itemNode = p.parseDestructor(xVar, varType)
    else:
      itemNode = p.parseVarDef()
    if p.curr.kind in {tkIn, tkOf}:
      walk p
      var itemsNode = p.parse()
      expectWalkOrNil tkRP
      result = newFor(itemNode, itemsNode, tk)
      stmtBody(result.forBody)
  else: discard

#
# Main Prefix Handler
#
proc getPrefixFn(p: var Parser, includes, excludes: set[TokenKind] = {}): PrefixFunction =
  case p.curr.kind
  of tkInterface:
    parseInterfaceDef
  of tkVar, tkLet, tkConst:
    parseVarDef
  of tkInteger: parseIntLit
  of tkFloat:   parseFloatLit
  of tkBool:    parseBoolLit
  of tkString:  parseStrLit
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
  of tkEcho, tkWarn, tkError, tkInfo:
    parseEcho
  of tkReturn:  parseReturn
  of tkEnumDef: parseEnum
  of tkThis: parseThis
  of tkNew: parseNew
  of tkDeclare: parseDeclare
  of tkDoc:
    parseBlockComment
  else: nil


#
# Infix Parse Handlers
#
proc parseMathExp(p: var Parser, lhs: Node): Node
proc parseCompExp(p: var Parser, lhs: Node): Node

proc parseCompExp(p: var Parser, lhs: Node): Node =
  # parse logical expressions with symbols (==, !=, >, >=, <, <=)
  let op = getInfixOp(p.curr.kind, false)
  walk p
  let rhsToken = p.curr
  let rhs = p.parse(includes = compTokens)
  if likely(rhs != nil):
    result = ast.newInfix(lhs, rhsToken)
    result.infixOp = op
    if p.curr.kind in mathTokens:
      result.rhsInfix = p.parseMathExp(rhs)
    else:
      result.rhsInfix = rhs

proc parseMathExp(p: var Parser, lhs: Node): Node =
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

proc getInfixFn(p: var Parser): InfixFunction =
  case p.curr.kind
  of infixTokens: parseCompExp
  of mathTokens: parseMathExp
  else: nil

proc parseInfix(p: var Parser, lhs: Node): Node =
  var infixNode: Node # ntInfix
  let infixFn = p.getInfixFn()
  if likely(infixFn != nil):
    result = p.infixFn(lhs)
  if p.curr in infixTokens:
    result = p.parseCompExp(result)

proc getPrefixOrInfix(p: var Parser, includes, excludes: set[TokenKind] = {}): Node =
  let lhs = p.parse(includes, excludes)
  var infixNode: Node
  if p.curr.isInfix:
    if likely(lhs != nil):
      infixNode = p.parseInfix(lhs)
      if likely(infixNode != nil):
        return infixNode
  result = lhs

proc parse(p: var Parser, includes, excludes: set[TokenKind] = {}): Node =
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
proc getProgram*(p: Parser): Program = p.program
proc parseProgram*(code: string, filePath = ""): Parser =
  var p = Parser()
  p.lex = newLexer(code)
  p.program = Program()
  # p.prev doesn't matter when initializing
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  p.logger = Logger(filePath: filePath)
  p.program.path = filePath
  while not p.hasErrors:
    if p.curr.kind == tkEOF: break
    let node = p.parse()
    if likely(node != nil):
      add p.program.nodes, node
    else: break
  p.lex.close()
  result = p
