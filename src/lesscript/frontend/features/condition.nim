# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

newPrefixProc "parseIf":
  # parse a new `if` statement
  let tk = p.curr
  const condBodyExcludes = {tkImport, tkInclude, tkExport}
  walk p
  # parse `if` branch
  var ifBranch: ConditionBranch
  expectWalkOrNil tkLP
  ifBranch.cond #[ntInfix]# = p.getPrefixOrInfix()
  expectNotNil ifBranch.cond:
    expectWalkOrNil tkRP
    stmtBody(ifBranch.body, excludes = condBodyExcludes)
    result = newIfCond(ifBranch, tk)
  # parse `else if` branches
  while p.curr is tkElseIf:
    let elifx = p.curr
    walk p; expectWalkOrNil tkLP
    var elifBranch: ConditionBranch
    elifBranch.cond #[ntInfix]# = p.getPrefixOrInfix()
    expectNotNil elifBranch.cond:
      expectWalkOrNil tkRP
      stmtBody(elifBranch.body, excludes = condBodyExcludes)
      elifBranch.body.meta = elifx.trace
      result.elifBranch.add(elifBranch)
  # parse `else` branch
  if p.curr is tkElse:
    let elsey = p.curr
    walk p
    stmtBody(result.elseBranch, excludes = condBodyExcludes)
    expectNotNil result.elseBranch:
      result.elseBranch.meta = elsey.trace