# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

template init*() {.dirty.} =
  if not v.has("input"):
    display("Missing an input file")
    QuitFailure.quit
  
  var outputPath: string
  var path = v.get("input").absolutePath()
  var hasOutput = v.has("output")

  if not path.fileExists:
    display("File not found")
    QuitFailure.quit

  if hasOutput:
    outputPath = v.get("output")
    if outputPath.splitFile.ext != ".js":
      display("Output path missing `.js` extension\n" & outputPath)
      QuitFailure.quit
    if not outputPath.isAbsolute:
      outputPath.normalizePath
      outputPath = outputPath.absolutePath()
  if v.flag("b"):
    display("✨ Building...", br="after")
  var
    p: Parser
    c: Compiler
  let
    t = getMonotime()
    env: JSEnv =
      if v.flag("release"):
        JSEnv.prod
      else:
        JSEnv.dev