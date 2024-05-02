# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseConsole:
  # parse a `echo`, `warn`, `info`,
  # `error`, and `assert` commands
  let tk = p.curr
  let cmdType =
    case tk.kind
    of tkWarn: cWarn
    of tkInfo: cInfo
    of tkError: cError
    of tkAssert: cAssert # todo assert custom messages
    else: cEcho
  walk p
  let node = p.parseAssignableNode()
  expectNotNil node:
    return ast.newCommand(cmdType, node, tk)

newPrefix parseReturn:
  # parse a new `return` command
  let tk = p.curr
  walk p
  let node = p.parseAssignableNode()
  expectNotNil node:
    return ast.newCommand(cReturn, node, tk)

newPrefix parseCall:
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
          expectToken p.curr, assgnTokens:
            arg.argValue = p.parseAssignableNode()
        else:
          arg.argValue = p.parseAssignableNode()
        if p.curr is tkComma: walk p
        elif p.curr isnot tkRP: return nil
      else: return nil 
      result.callArgs.add(arg)
    walk p # tkRP
    result.callType = CallType.fnCall

  while likely(p.curr.line == ident.line and p.curr.wsno == 0):
    case p.curr.kind
    of tkDot:
      result = newDot(result)
      walk p
      if p.curr.isIdent(anyIdent = true):
        result.rhs = ast.newCall(p.curr)
        walk p
        if p.curr is tkLP:
          walk p
          walk p # todo
          result.rhs.callType = CallType.fnCall
      else: break
    of tkLB:
      walk p
      let indexNode =
        case p.curr.kind
        of tkInteger: p.parseIntLit()
        of tkString: p.parseStrLit()
        of tkIdentifier: p.parseCall()
        else:
          if p.curr.isIdent(anyIdent = true):
            p.parseCall()
          else: return nil # error
      if likely(p.curr is tkRB):
        walk p
        result = ast.newBracket(result, indexNode)
      else: return nil
    else: break