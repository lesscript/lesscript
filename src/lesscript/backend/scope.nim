# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

proc globalScope(c: Compiler, node: Node) =
  ## add `node` to global scope
  case node.nt:
  of ntFuncDef:
    c.globalScope[node.fnIdent] = node
  of ntVarDecl:
    c.globalScope[node.varIdent] = node
  else: discard

proc toScope(scope: ScopeTable, node: Node) =
  ## add `node` to current `scope`
  case node.nt:
  of ntFuncDef:
    scope[node.fnIdent] = node
  of ntVarDecl:
    scope[node.varIdent] = node
  of ntClassDef:
    scope[node.classIdent] = node
  of ntEnum:
    scope[node.enumIdent] = node
  of ntTypeDef:
    scope[node.typeIdent] = node
  else: discard

proc stack(c: Compiler, node: Node, scopetables: var seq[ScopeTable]) =
  ## Stack `node` into local/global scope
  if scopetables.len > 0:
    toScope(scopetables[^1], node)
  else:
    toScope(c.globalScope, node)

proc getScope(c: Compiler, name: string, scopetables: var seq[ScopeTable]): tuple[st: ScopeTable, index: int] =
  ## Search through available seq[ScopeTable] for `name`,
  if scopetables.len > 0:
    for i in countdown(scopetables.high, scopetables.low):
      if scopetables[i].hasKey(name):
        return (scopetables[i], i)
  if c.globalScope.hasKey(name):
    return (c.globalScope, 0)

proc getScope(c: Compiler, scopetables: var seq[ScopeTable]): ScopeTable =
  ## Returns the current scope
  if scopetables.len > 0:
    return scopetables[^1]
  return c.globalScope

proc inScope(c: Compiler, id: string, scopetables: var seq[ScopeTable]): bool =
  ## Perform a `getScope` call, if `nil` then returns false
  result = c.getScope(id, scopetables).st != nil

proc inScope(id: string, scopetables: var seq[ScopeTable]): bool =
  ## Performs a quick search in the current `ScopeTable`
  if scopetables.len > 0:
    return scopetables[^1].hasKey(id)

proc inCurrentScope*(c: Compiler, id: string, scopetables: var seq[ScopeTable]): bool =
  ## Determine if `id` is in current ScopeTable
  if scopetables.len > 0:
    return scopetables[^1].hasKey(id)
  return c.globalScope.hasKey(id)

proc scoped(c: Compiler, id: string, scope: var seq[ScopeTable]): Node =
  ## Returns a callable node from `scope` table. Returns `nil` when not found
  let currentScope = c.getScope(id, scope)
  if currentScope.st != nil:
    result = currentScope.st[id]

proc scoped(c: Compiler, name: string, scopetables: var seq[ScopeTable], index: int): (Node, int) =
  ## Returns a callable node from a `scope` table at given `index`
  if scopetables.len > 0:
    if scopetables[index].hasKey(name):
      return (scopetables[index][name], index)
  if c.globalScope.hasKey(name):
    return (c.globalScope[name], 0)

template delScope {.dirty.} =
  ## Delete current scope
  scope.delete(scope.high)

template newScope(x, y: untyped): untyped {.dirty.} =
  ## Creates a new local scope
  var localScope = ScopeTable()
  scope.add(localScope)
  x; y