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
  newHandler handleVarAssign:
    # Handle assignment declarations
    let identName =
      case node.asgnIdent.nt
        of ntDotExpr:
          node.asgnIdent.lhs.identName
        of ntIdentifier:
          node.asgnIdent.identName
        else: ""
    var scopedNode = c.scoped(identName, scope)
    if likely(scopedNode != nil):
      casey scopedNode.varType, vtConst:
        # can't reassing to a immutable `const` var
        compileError(immutableReassign, [scopedNode.varIdent], node.meta)
        return
      if c.typeCheck(scopedNode, node.asgnValue, scope):
        case node.asgnValue.nt
        of ntCall:
          write js_assignment(c, node.meta, identName,
            js_func_call(c, node.meta, "new " & node.asgnValue.callIdent, ""))
          semiColon()
        of ntFuncDef:
          discard # todo
        else:
          write js_assignment(c, node.meta,
            $(scopedNode.varIdent), c.toString(node.asgnValue, scope))
          semiColon()
          scopedNode.varValue = node.asgnValue
      else: discard
    else:
      compileError(undeclaredIdent, [identName], node.meta)