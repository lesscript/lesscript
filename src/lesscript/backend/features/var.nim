# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

when declared nimc:
  discard
elif declared jsc:
  #
  # Transpiler - Handle variable declaration
  #
  newHandler handleVarDecl:
    let some = c.getScope(node.varIdent, scope)
    var overwriteVarArg: bool
    if some.scopeTable != nil:
      try:
        if some.scopeTable[node.varIdent].varArg:
          overwriteVarArg = true
      except KeyError: discard
    if likely(some.scopeTable == nil) or overwriteVarArg:
      if c.typeCheckAssign(node, scope):
        if node.varValue != nil:
          # Write variables with implicit value
          case node.varValue.nt
          of ntFuncDef:
            write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
            c.handleFunction(node.varValue, scope)
            semiColon()
          of objectDecl:
            write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
            write writeObject(c, node.varValue, scope, true)
          of arrayDecl:
            write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
            write writeArray(c, node.varValue, scope)
            semiColon()
          of ntCall:
              write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
              c.callDefinition(node.varValue, scope, node)
          else:
            write js_var_assignment(c, node.meta, $(node.vartype),
              node.varIdent, c.toString(node.varValue, scope, node.valType))
          c.stack(node, scope)
        else:
          # Write variables without an implicit value
          write js_var_assignment(c, node.meta, $(node.varType),
            node.varIdent, c.toString(node.varValue, scope, node.valType))
          c.stack(node, scope)
      for someVar in node.varInline:
        someVar.varValue = node.varValue
        someVar.valType = node.valType
        someVar.valTypeof = node.valTypeof
        c.handleVarDecl(someVar, scope)
        for otherVar in someVar.varOthers:
          c.handleVarDecl(otherVar, scope)
      for otherVar in node.varOthers:
        c.handleVarDecl(otherVar, scope)
    else:
      if node.varType in {vtVar, vtLet}:
        compileError(redefineIdent, [node.varIdent], node.meta)
      compileError(immutableReassign, [node.varIdent], node.meta)
