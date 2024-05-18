# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefix parseFunctionDecl:
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
  var hasGeneric: bool
  if p.curr in {tkLB, tkLT}:
    var endGen =
      if p.curr is tkLB: tkRB
      else: tkGT
    walk p # tkLB/tkLT
    var gens: seq[(TokenTuple, Type)]
    while p.curr isnot endGen:
      if likely(p.curr is tkIdentifier and p.curr.value.len == 1):
        var
          gentype: Type = tAny
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
        else:
          walk p
        add gens, (genid, gentype)
        for otherid in others:
          add gens, (otherid, gentype)
        if p.curr is tkComma:
          walk p
      else: return nil
    if gens.len > 0:
      result.fnHasGenerics = true
      expectWalkOrNil({tkRB, tkGT})
    for gen in gens:
      if likely result.fnGenerics.hasKey(gen[0].value) == false:
        result.fnGenerics[gen[0].value] = gen[1]
      else: errorWithArgs(redefinitionError, gen[0], [gen[0].value])
    reset(gens)

  # parse params
  if p.curr is tkLP:
    walk p
    var hasDocType: bool
    if parent != nil:
      hasDocType = parent.nt == ntDocComment 
    while p.curr is tkIdentifier:
      walk p
      let pIdent = p.prev
      if likely(not result.fnParams.hasKey(pIdent.value)):
        let pNode = p.parseVarIdent(tk, pIdent, vtVar, isArg = true, hasDocType = hasDocType)
        expectNotNil pNode:
          pNode.varArg = true
          result.fnParams[pIdent.value] = pNode
          if p.curr in {tkComma, tkSemiColon}: walk p
      else: errorWithArgs(redefineParameter, pIdent, [pIdent.value])
    expectWalkOrNil(tkRP)

    # parse function types from doc block-comment
    # todo. this is ugly af poor implementation.
    #       for parsing default values we'll need to combine
    #       secondary lexer/parser that validates and returns
    #       an AST tree back to the main parser
    if hasDocType:
      if likely(not result.fnHasGenerics):
        const unallowedTypes = ["tCustom", "void", "none"]
        for docTypeParam in parent.commentBlockParams:
          var dt = docTypeParam.split(":")
          var dtx = dt[1].split("=")
          var dtType = if dtx.len == 2: dtx[0] else: dt[1]
          var dtDefault = if dtx.len == 2: dtx[1] else: ""
          if likely(dt[1] notin unallowedTypes):
            if result.fnParams.hasKey(dt[0]):
              let vtype = dtType.toLowerAscii.getTypeByString
              result.fnParams[dt[0]].valType = vtype
              if dtDefault.len != 0:
                # echo dtDefault
                var valNode = newValueByType(vtype, dtDefault)
                # echo valNode
                result.fnParams[dt[0]].varValue = Node(nt: ntValue, val: valNode)
            else: discard
          else:
            errorWithArgs(invalidTypeDocBlock, tk, [dtType])
      else: error(invalidTypeDocGenericCombo, tk)
  # parse return type
  if p.curr is tkColon:
    walk p
    result.fnReturnType = p.curr.getType()
    case result.fnReturnType
    of tCustom:
      result.fnReturnIdent = newId(p.curr)
    of tAny:
      result.fnReturnIdent = newId(p.curr)
    of tNone:
      return nil
    else: discard
    walk p

newPrefix parseFunction:
  let tk = p.curr
  result = p.parseFunctionDecl()
  stmtBody(result.fnBody, excludes = {tkImport, tkInclude, tkExport})
