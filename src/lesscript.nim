# A fast, statically typed Rock'n'Roll language that
# transpiles to Nim lang and JavaScript.
# 
# (c) 2023 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://lesscript.com
#          https://github.com/openpeeps

when defined napibuild:
  import denim
  import std/sequtils
  import ./lesscript/frontend/parser
  import ./lesscript/backend/javascript

  init proc(module: Module) =
    proc parseProgram(path: string) {.export_napi.} =
      var p = parseProgram(readFile(path), path)
      if likely(p.hasErrors == false):
        var c = newCompiler(p.getProgram, env = JSEnv.dev)
        if unlikely(c.hasErrors):
          assert error($(c.logger.errors.toSeq[0]), "LesscriptError")
        return %* c.getOutput
      assert error($(p.logger.errors.toSeq[0], "LesscriptError"))

elif isMainModule:
  import std/[os, parseopt]
  import ./lesscript/frontend/[ast, parser]
  import ./lesscript/backend/javascript
  import pkg/kapsis/cli

  let params = commandLineParams()
  if params.len > 0:
    let fpath = params[0].absolutePath
    if not fpath.fileExists:
      display("File not found")
      QuitFailure.quit

    let buildErrorLabel = "Build failed with errors:"
    var hasOutput = params.len == 2
    var p: Parser = parseModule(fpath.readFile, fpath)
    var c: Compiler
    if not p.hasErrors:
      c = newCompiler(p.getModule(), env = JSEnv.dev)
      if not c.hasErrors:
        if hasOutput:
          var outputPath = params[1]
          if outputPath.splitFile.ext != ".js":
            display("Output path missing `.js` extension\n" & outputPath)
            QuitFailure.quit
          if not outputPath.isAbsolute:
            outputPath.normalizePath
            outputPath = outputPath.absolutePath()
          writeFile(outputPath, c.getOutput)
          QuitSuccess.quit
        else:
          echo c.getOutput
          QuitSuccess.quit
      else:
        display(buildErrorLabel)
        for err in c.logger.errors:
          display(err)
        display(" 👉 " & c.logger.filePath)
        QuitFailure.quit

      if c.hasWarnings:
        display("Build warnings")
        for warning in c.logger.warnings:
          display(warning)
        display(" 👉 " & c.logger.filePath)
    else:
      display(buildErrorLabel)
      for err in p.logger.errors:
        display(err)
      display(" 👉 " & p.logger.filePath)
      QuitFailure.quit

# todo
# elif isMainModule:
#   import kapsis/commands
#   import kapsis/db
#   import ./lesscript/cli/[cCommand, astCommand]

#   App:
#     settings(
#       mainCmd = "c"
#     )

#     about:
#       "A fast, statically typed Rock'n'Roll language that\ntranspiles to Nim lang & JavaScript.\n"
#       "   (c) Made by Humans from OpenPeeps | LGPLv3"
#       "   https://lesscript.com"
#       "   https://github.com/lesscript"

#     commands:
#       $ "c" `input` `output` ["release"] 'b':
#         ? "Transpile Lesscript to JavaScript"
#       # $ "exec" `input`:
#         # ? "Parse a Lesscript file and execute it via JavaScriptCore"
#       $ "ast" `input` `output`:
#         ? "Generates static binary AST"