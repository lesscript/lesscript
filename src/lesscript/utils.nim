macro todo*(): untyped = 
  let (file, line, col) = instantiationInfo()
  warning("Non-Implemented feature [TODO]")
  result = macros.newStmtList()
  result.add quote do:
    discard
  # result = macros.newStmtList().add(nnkDiscardStmt.newTree(newEmptyNode()))

macro features*(x: varargs[string]): untyped =
  result = macros.newStmtList()
  for y in x:
    add result,
      nnkIncludeStmt.newTree(
        nnkInfix.newTree(
          ident("/"),
          ident("features"),
          y
        )
      )

when declared jsp:
  # Utils - Lesscript Parser
  template expectWalkOrNil(kind: TokenKind) {.dirty.} =
    if likely(p.curr is kind):
      walk p
    else: return nil

  template expectWalkOrNil(kinds: set[TokenKind]) {.dirty.} =
    if likely(p.curr in kinds):
      walk p
    else: return nil

  template expectToken(tk: TokenTuple, kinds: set[TokenKind], body) {.dirty.} =
    if likely(tk in kinds):
      body
    else: return nil

  template expectToken(x: TokenTuple, y: TokenKind, body: untyped) =
    if likely(x.kind == y):
      body
    else: return nil

when declared jsc:
  # Utils - JavaScript Transpiler
  template expectNode(x: untyped, name: string, meta: Meta, body: untyped): untyped =
    # checking if `x` is likely not nil, then injects the `body`,
    # otherwise print `UndeclaredIdent` and blocks code execution
    if likely(x != nil):
      body
    else:
      compileError(undeclaredIdent, [name], meta)

  template expectMatch(x, y: Type) =
    if likely(x == y):
      return true
    else:
      compileError(fnMismatchParam, [node.varIdent, $y, $x], node.varValue.meta)

  template expectMatch(x, y: Type, varIdent: string, meta: Meta, body) =
    if likely(x == y):
      body
    else:
      compileError(fnMismatchParam, [varIdent, $y, $x], meta)

  template expectMatchInfix(x, y: Type, body, err) =
    if likely(x == y):
      body
    else:
      err

# Common utils
template likelyNodeReturn(x): untyped =
  if likely(node != nil):
    return x

template expectNotNil(x, body): untyped =
  if likely(x != nil):
    body
  else: return nil

template expectNotNil(x, body, y): untyped =
  if likely(x != nil):
    body
  else: y