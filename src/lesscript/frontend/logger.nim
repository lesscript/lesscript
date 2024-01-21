# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

import std/[sequtils, strutils]

from ./tokens import TokenTuple
from ./ast import Meta

when compileOption("app", "console"):
  import pkg/kapsis/cli

type
  Message* = enum
    invalidIndentation = "Invalid indentation [InvalidIndent]"
    undeclaredVar = "Undeclared variable $ [UndeclaredVar]"
    undeclaredIdent = "Undeclared identifier $ [UndeclaredIdent]"
    undeclaredField = "Undeclared field $ [UndeclaredField]"
    redefineIdent = "Attempt to redefine $ [RedefineIdent]"
    varInvalidIdent = "Invalid variable name $ [InvalidVarName]"
    untypedVariable = "Cannot parse untyped variables [UntypedVariable]"
    unexpectedToken = "Unexpected token $ [Unexpected]"
    badIndentation = "Nestable statement requires indentation"
    invalidInfixMissingValue = "Invalid infix missing assignable token"
    invalidInfixOp = "Invalid operator $ for $"
    invalidInfixOpExpect = "Invalid operator $ | Got $ expected $"
    declaredNotUsed = "Declared and not used $ [UnusedDeclaration]"
    eof =  "EOF reached before closing $ [EOF]"
    
    # class
    duplicateExtend = "Class $ extends $ multiple times [InvalidClassExtend]"
    duplicateImplement = "Class $ implements $ multiple times [InvalidClassImplement]"
    # accessor storage
    invalidAccessor = "Invalid accessor $ for $ [InvalidAccessor]"
    duplicateField = "Duplicate field $ [DuplicateField]"
    duplicateCaseLabel = "Duplicate case label [DuplicateCaseLabel]"
    indexDefect = "Index $ not in $..$ [IndexDefect]"

    typeMismatch = "Type mismatch | Got $ expected $ [TypeMismatch]"
    
    invalidTypeDocBlock = "Invalid type $ [InvalidTypeDoc]"
    invalidTypeDocGenericCombo = "Mixing Generics with TypeDoc is a bad combo [InvalidTypeDoc]"
    typeExpected = "Type expected. Got $ [TypeExpected]"
    redefinitionError = "Redefinition of $ [RedefinitionError]"
    missingAssignmentToken = "Missing assignment token"
    missingRB = "Missing closing bracket [MissingRightBracket]"
    missingRC = "Missing closing curly bracket [MissingRightCurly]"
    immutableReassign = "Cannot assign twice to immutable variable $ [ImmutableAssignment]"
    immutableNoImplicitValue = "Immutable identifier $ requires an implicit value [MissingImplicitValue]" 
    invalidCallContext = "Invalid call in this context"
    # Use/Imports
    importDuplicateModule = "Module $ already in use"
    importModuleNotFound = "Module $ not found [ModuleNotFound]"
    importCircular = "Circular import not allowed [ModuleCircularImport]"
    # Condition - Case statements
    caseInvalidValue = "Invalid case statement"
    caseInvalidValueType = "Invalid case statement. Got $, expected $"
    # Loops
    forInvalidIteration = "Invalid iteration [InvalidIteration]"
    invalidIterator = "Invalid iteration. Got $ | Expected array or object [InvalidIterator]"
    
    # warnings
    emptyBlockStatement = "Declared $ should not be empty [EmptyBlockStatement]"
    unnecessaryComma = "Unnecessary comma separator [UnnecessaryNightmare]"
    unnecessarySemiColon = "Unnecessary semi-colon separator [UnnecessaryNightmare]"

    # storage
    arrayMixedTypes = "Array with mixed types [ArrayMixedTypes]"

    nonImplementedFeature = "Non-Implemented feature [TODO]"

    # Functions
    fnUndeclared = "Undeclared function $"
    fnMismatchParam = "Type mismatch for $ | Got $ expected $"
    fnUnknownParam = "Unknown parameter $ [UnknownParameter]"
    fnExtraArg = "Function $ expects $ arguments, $ given [ExtraArguments]"
    fnReturnVoid = "Invalid return type for $ | Got void [InvalidReturnTypeVoid]"
    fnReturnTypeMismatch = "Invalid return type | Got $ expected $ [InvalidReturnType]"
    unreachableCode = "Unreachable code after `return` statement [UnreachableCode]"
    fnInvalidReturn = "Invalid return type [InvalidReturnType]"
    redefineParameter = "Attempt to redefine parameter $"
    fnOverload = "Attempt to redefine function $"
    fnAnoExport = "Anonymous functions cannot be exported"
    assertionInvalid = "Cannot assert $ [InvalidAssert]"
    suggestLabel = "Did you mean?"
    invalidContext = "Invalid $ in this context"
    internalError = "$"

  Level* = enum
    lvlInfo
    lvlNotice
    lvlWarn
    lvlError

  Log* = ref object
    msg: Message
    extraLabel: string
    line, col: int
    useFmt: bool
    args, extraLines: seq[string]

  Logger* = ref object
    filePath*: string
    infoLogs*, noticeLogs*, warnLogs*, errorLogs*: seq[Log]

proc add(logger: Logger, lvl: Level, msg: Message, line, col: int,
        useFmt: bool, args: varargs[string]) =
  let log = Log(msg: msg, args: args.toSeq(),
                line: line, col: col, useFmt: useFmt)
  case lvl:
    of lvlInfo:
      logger.infoLogs.add(log)
    of lvlNotice:
      logger.noticeLogs.add(log)
    of lvlWarn:
      logger.warnLogs.add(log)
    of lvlError:
      logger.errorLogs.add(log)

proc add(logger: Logger, lvl: Level, msg: Message, line, col: int, useFmt: bool,
        extraLines: seq[string], extraLabel: string, args: varargs[string]) =
  let log = Log(
    msg: msg,
    args: args.toSeq(),
    line: line,
    col: col + 1,
    useFmt: useFmt,
    extraLines: extraLines,
    extraLabel: extraLabel
  )
  case lvl:
    of lvlInfo:
      logger.infoLogs.add(log)
    of lvlNotice:
      logger.noticeLogs.add(log)
    of lvlWarn:
      logger.warnLogs.add(log)
    of lvlError:
      logger.errorLogs.add(log)

proc getMessage*(log: Log): Message = 
  result = log.msg

proc newInfo*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, args:varargs[string]) =
  logger.add(lvlInfo, msg, line, col, useFmt, args)

proc newNotice*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, args:varargs[string]) =
  logger.add(lvlNotice, msg, line, col, useFmt, args)

proc newWarn*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, args:varargs[string]) =
  logger.add(lvlWarn, msg, line, col, useFmt, args)

proc newError*(logger: Logger, msg: Message, line, col: int, useFmt: bool, args:varargs[string]) =
  logger.add(lvlError, msg, line, col, useFmt, args)

proc newErrorMultiLines*(logger: Logger, msg: Message, line, col: int, 
        useFmt: bool, extraLines: seq[string], extraLabel: string, args:varargs[string]) =
  logger.add(lvlError, msg, line, col, useFmt, extraLines, extraLabel, args)

proc newWarningMultiLines*(logger: Logger, msg: Message, line, col: int,
        useFmt: bool, extraLines: seq[string], extraLabel: string, args:varargs[string]) =
  logger.add(lvlWarn, msg, line, col, useFmt, extraLines, extraLabel, args)

template warn*(msg: Message, tk: TokenTuple, args: varargs[string]) =
  p.logger.newWarn(msg, tk.line, tk.col, false, args)

template warn*(msg: Message, tk: TokenTuple, strFmt: bool, args: varargs[string]) =
  p.logger.newWarn(msg, tk.line, tk.col, true, args)  

proc warn*(logger: Logger, msg: Message, line, col: int, args: varargs[string]) =
  logger.add(lvlWarn, msg, line, col, false, args)

proc warn*(logger: Logger, msg: Message, line, col: int, strFmt: bool, args: varargs[string]) =
  logger.add(lvlWarn, msg, line, col, true, args)

template warnWithArgs*(msg: Message, tk: TokenTuple, args: openarray[string]) =
  if not p.hasError:
    p.logger.newWarn(msg, tk.line, tk.col, true, args)

template error*(msg: Message, tk: TokenTuple) =
  if not p.hasError:
    p.logger.newError(msg, tk.line, tk.col, false)
    p.hasError = true
  return # block code execution

template error*(msg: Message, tk: TokenTuple, args: openarray[string]) =
  if not p.hasError:
    p.logger.newError(msg, tk.line, tk.col, false, args)
    p.hasError = true
  return # block code execution

template error*(msg: Message, tk: TokenTuple, strFmt: bool,
            extraLines: seq[string], extraLabel: string, args: varargs[string]) =
  if not p.hasError:
    newErrorMultiLines(p.logger, msg, tk.line, tk.col, strFmt, extraLines, extraLabel, args)
    p.hasError = true
  return # block code execution

template errorWithArgs*(msg: Message, tk: TokenTuple, args: openarray[string]) =
  if not p.hasError:
    p.logger.newError(msg, tk.line, tk.col, true, args)
    p.hasError = true
  return # block code execution

template compileError*(msg: Message, args: openarray[string], meta: Meta = (0,0)) =
  c.logger.newError(msg, meta.line, meta.pos, true, args)
  return

template compileError*(msg: Message, meta: Meta = (0,0)) =
  c.logger.newError(msg, meta.line, meta.pos, true, [])
  return

template compileWarning*(msg: Message, args: openarray[string], meta: Meta = (0,0), blocky = false) =
  c.logger.newWarn(msg, meta.line, meta.pos, true, args)
  if blocky: return

proc error*(logger: Logger, msg: Message, line, col: int, args: varargs[string]) =
  logger.add(lvlError, msg, line, col, false, args)

when defined napiOrWasm:
  proc runIterator(i: Log, label = ""): string =
    if label.len != 0:
      add result, label
    add result, "(" & $i.line & ":" & $i.col & ")" & spaces(1)
    if i.useFmt:
      var x: int
      var str = split($i.msg, "$")
      let length = count($i.msg, "$") - 1
      for s in str:
        add result, s.strip()
        if length >= x:
          add result, indent(i.args[x], 1)
        inc x
    else:
      add result, $i.msg
      for a in i.args:
        add result, a

  proc `$`*(i: Log): string =
    runIterator(i)

  iterator warnings*(logger: Logger): string =
    for i in logger.warnLogs:
      yield runIterator(i, "Warning")

  iterator errors*(logger: Logger): string =
    for i in logger.errorLogs:
      yield runIterator(i)
      if i.extraLines.len != 0:
        if i.extraLabel.len != 0:
          var extraLabel = "\n"
          add extraLabel, indent(i.extraLabel, 6)
          yield extraLabel
        for extraLine in i.extraLines:
          var extra = "\n"
          add extra, indent(extraLine, 12)
          yield extra

elif compileOption("app", "console"):
  proc runIterator(i: Log, label: string, fgColor: ForegroundColor): Row =
    add result, span(label, fgColor, indentSize = 0)
    add result, span("(" & $i.line & ":" & $i.col & ")")
    if i.useFmt:
      var x: int
      var str = split($i.msg, "$")
      let length = count($i.msg, "$") - 1
      for s in str:
        add result, span(s.strip())
        if length >= x:
          add result, span(i.args[x], fgBlue)
        inc x
    else:
      add result, span($i.msg)
      for a in i.args:
        add result, span(a, fgBlue)

  iterator warnings*(logger: Logger): Row =
    for i in logger.warnLogs:
      yield runIterator(i, "Warning", fgYellow)

  iterator errors*(logger: Logger): Row =
    for i in logger.errorLogs:
      yield runIterator(i, "Error", fgRed)
      if i.extraLines.len != 0:
        if i.extraLabel.len != 0:
          var extraLabel: Row
          extraLabel.add(span(i.extraLabel, indentSize = 6))
          yield extraLabel
        for extraLine in i.extraLines:
          var extra: Row
          extra.add(span(extraLine, indentSize = 12))
          yield extra