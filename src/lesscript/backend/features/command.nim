# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

when declared jsp:
  discard
elif declared jsc:
  #
  # Transpiler - Handles Debug commands
  #
  newHandler handleCommand:
    case node.cmdType:
    of cEcho, cWarn, cInfo, cError, cAssert:
      casey c.env, dev:
        case node.cmd.nt:
        of ntCall:
          write js_console_log(c, node.meta, $node.cmdType)
          write js_par_start(c, node.meta)
          c.transpile(node.cmd, scope)
          write js_par_end(c, node.meta)
          # var scopedNode = c.scoped(node.cmd.callIdent, scope)
          # expectNotNil scopedNode:
          #   case scopedNode.nt
          #   of ntFuncDef:
          #     write js_console_log(c, node.meta,
          #       $node.cmdType, node.cmd.callIdent & "()")
          #   of ntVarDecl:
          #     case scopedNode.valType:
          #     of tFunction:
          #       write js_console_log(c, node.meta,
          #         $node.cmdType, node.cmd.callIdent & "()")
          #     else:
          #       write js_console_log(c, node.meta,
          #         $node.cmdType, node.cmd.callIdent)
          #   of ntEnum:
          #     write js_console_log(c, node.meta,
          #       $node.cmdType, node.cmd.callIdent)
          #   else: discard
          # do:
          #   case node.cmd.callType
          #   of identCall:
          #     compileError(undeclaredIdent,
          #       [node.cmd.callIdent], node.cmd.meta)
          #   of fnCall:
          #     compileError(undeclaredIdent,
          #       [node.cmd.callIdent], node.cmd.meta)
          #   else: discard
        of ntValue:
          write js_console_log(c, node.meta, $node.cmdType,
            c.toString(node.cmd, scope))
        of arrayDecl:
          write js_console_log(c, node.meta, $node.cmdType,
            c.toString(node.cmd, scope))
        of objectDecl:
          write js_console_log(c, node.meta, $node.cmdType,
            c.toString(node.cmd, scope))
        of ntDotExpr:
          let unpackedDot = c.unpackDotExpr(node.cmd, scope)
          write js_console_log(c, node.meta, $node.cmdType, unpackedDot)
        of ntBracketExpr:
          write js_console_log(c, node.meta, $node.cmdType,
            c.unpackBracketExpr(node.cmd, scope))
        of ntInfixMath:
          write js_console_log(c, node.meta,
            $node.cmdType, c.getInfixMath(node.cmd, scope))
        of ntInfix:
          write js_console_log(c, node.meta,
            $node.cmdType, c.getInfix(node.cmd, scope))
        else: discard
    of cCall:
      discard # todo
    of cReturn:
      if likely(returnType.isSome):
        let check = c.typeCheck(returnType.get(), node.cmd, scope)
        if unlikely(check[0] == false):
          compileError(fnReturnTypeMismatch, [$check[1], $check[2]], node.cmd.meta)
      write js_func_return(c, node.meta, c.toString(node.cmd, scope))