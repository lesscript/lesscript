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
    if likely(not c.inCurrentScope(node.varIdent, scope)):
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
      # if node.varValue != nil:
      #   # Handle var definitions with implicit value
      #   case node.valType
      #   of tNone:
      #     # set as `tNone` when the assigned value is an
      #     # identifier that can't be known at parser level,
      #     # in this case we'll have to determine the type of `x`
      #     # `var x = y` by checking for `y` in the scope tables.
      #     var scopedNode = c.scoped(node.varValue.callIdent, scope)
      #     if likely(scopedNode != nil):
      #       node.valType = scopedNode.getType()
      #       write js_var_assignment(c, node.meta, $(node.vartype), node.varIdent, node.varValue.callIdent)
      #       c.stack(node, scope)
      #       return
      #     compileError(undeclaredIdent, [node.varValue.callIdent], node.varValue.meta)
      #   else:
      #     if likely(c.typeCheck(node, node.varValue, scope)):
      #       case node.varValue.nt
      #       of ntFuncDef:
      #         node.valType = tFunction
      #         write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
      #         c.handleFunction(node.varValue, scope)
      #         semiColon()
      #       of objectDecl:
      #         write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
      #         write writeObject(c, node.varValue, scope, true)
      #       of arrayDecl:
      #         write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
      #         write writeArray(c, node.varValue, scope)
      #         semiColon()
      #       of ntCall:
      #           write js_var_assign(c, node.meta, $(node.varType), node.varIdent)
      #           c.callDefinition(node.varValue, scope, node)
      #       else:
      #         write js_var_assignment(c, node.meta, $(node.vartype),
      #           node.varIdent, c.toString(node.varValue, scope, node.valType))
      #       c.stack(node, scope)
      #     # else:
      #       # compileError(fnMismatchParam, [node.varIdent,
      #         # $(node.varValue.getType), $(node.valType)], node.meta)
      # else:
      #   # Handle var definitions without implicit value
      #   if node.valTypeof == nil:
      #     # if node.valType == tCustom:
      #     #   var scopedNode = c.scoped(node.valTypeof.identName, scope)
      #     #   if likely(scopedNode != nil):
      #     #     write js_var_assignment(c, node.meta, $(node.varType), node.varIdent, c.toString(node.varValue, scope, node.valType))
      #     #   else:
      #     #     compileError(undeclaredIdent, ["X"])
      #     # else:
      #     write js_var_assignment(c, node.meta, $(node.varType), node.varIdent, c.toString(node.varValue, scope, node.valType))
      #   else:
      #     var scopedNode = c.scoped(node.valTypeof.identName, scope)
      #     if likely(scopedNode != nil):
      #       case scopedNode.nt:
      #       of ntClassDef:
      #         node.valTypeof.identType = tClass
      #         write js_var_definition(c, node.meta, $(node.vartype), node.varIdent)
      #       of ntFuncDef:
      #         node.valTypeof.identType = tFunction
      #         write js_var_definition(c, node.meta, $(node.vartype), node.varIdent)
      #       of ntTypeDef:
      #         echo scopedNode
      #         node.valTypeof.identType = scopedNode.typeLit
      #         if scopedNode.typeLit != tCustom:
      #           # writes a var def with default implicit value
      #           # `var x: SomeString` => `var x = "";`
      #           write js_var_assignment(c, node.meta, $(node.vartype),
      #                     node.varIdent, c.toString(nil, scope, scopedNode.typeLit))
      #       else: discard
      #     else:
      #       compileError(undeclaredIdent, [node.valTypeof.identName], node.valTypeof.meta)
      #       return
      #   c.stack(node, scope)
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
