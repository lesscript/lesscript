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
  # Transpiler - Handle function declaration
  #
  template handleCustomType =
    var scopedNode = c.scoped(pNode.valTypeof.identName, scope)
    expectNode scopedNode, pNode.valTypeof.identName, pNode.meta:
      pNode.valTypeof.identType = scopedNode.getType
      add docBlockComment, c.genCommentFnParam(pNode)
      if pNode.varValue != nil:
        add jsParams, js_assignment(c, pNode.meta, pNode.varIdent,
          c.toString(pNode.varValue, scope, pNode.valType))
      else:
        add jsParams, js_ident_call(c, pNode.meta, pNode.varIdent)
      c.stack(pNode, scope)

  newHandler "handleFunction":
    if unlikely(c.inScope(node.fnIdent, scope)): 
      compileError(redefineIdent, [node.fnIdent], node.meta)
    if likely(node.fnFwd == false):
      if likely(node.fnBody.stmtNode.list.len > 0):
        var docBlockComment: string
        newScope:
          # write parameters
          var jsParams: seq[string]
          for pIdent, pNode in node.fnParams:
            case pNode.valType
            of tNone:
              discard
            of tCustom:
              handleCustomType()
            of tAny:
              # handle generics or any other generic-like (single letter)
              # custom type identifier
              if likely(node.fnHasGenerics):
                if node.fnGenerics.hasKey(pNode.valTypeof.identName):
                  pNode.valType = node.fnGenerics[pNode.valTypeof.identName]
                  pNode.valTypeof.identType = tGeneric
                  add docBlockComment, c.genCommentFnParam(pNode)
                  if pNode.varValue != nil:
                    add jsParams, js_assignment(c, pNode.meta, pNode.varIdent,
                      c.toString(pNode.varValue, scope, pNode.valType))
                  else:
                    add jsParams, js_ident_call(c, pNode.meta, pNode.varIdent)
                  c.stack(pNode, scope)
                else:
                  handleCustomType()
              else:
                echo "Undeclared identifier"
            else:
              add docBlockComment, c.genCommentFnParam(pNode)
              if pNode.varValue != nil:
                add jsParams, js_assignment(c, pNode.meta, pNode.varIdent,
                  c.toString(pNode.varValue, scope, pNode.valType))
              else:
                add jsParams, js_ident_call(c, pNode.meta, pNode.varIdent)
              c.stack(pNode, scope)
          add docBlockComment, c.genCommentFnReturn(node.fnReturnType)
          write(js_doc_comment(c, node.meta, docBlockComment))
          write(js_func_def(c, node.meta, node.fnIdent, jsParams.join(",")))
          
          # write function body
          curlyBlock:
            # var hasReturnType: bool
            for innerNode in node.fnBody.stmtNode.list:
              casey node.fnHasReturnType, true:
                compileWarning(unreachableCode, [node.fnIdent], innerNode.meta)
                add c.output, "}"
                return
              case innerNode.nt
              of ntCommand:
                # case innerNode.cmdType
                # of cReturn:
                #   node.fnHasReturnType = true
                #   let check = c.typeCheck(node.fnReturnType, innerNode.cmd, scope)
                #   if unlikely(check[0] == false):
                #     compileError(fnReturnTypeMismatch, [$check[1], $check[2]], innerNode.cmd.meta)
                # else: discard
                c.handleCommand(innerNode, scope, nil, some(node.fnReturnType))
              else:
                c.transpile(innerNode, scope, some(node.fnReturnType))
            if node.fnHasReturnType == false and node.fnReturnType notin {tNone, tVoid}:
              write js_func_return(c, node.meta, c.toString(nil, scope, node.fnReturnType))
        do: delScope()
      else: compileWarning(emptyBlockStatement, [node.fnIdent], node.meta)
      c.stack(node, scope)
    else:
      discard