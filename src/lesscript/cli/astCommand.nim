# A high-performance, statically typed Rock'n'Roll language
# with Nim and JavaScript transpilation capabilities
#
# (c) 2024 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/lesscript
#          https://lesscript.com

import std/[os, monotimes, times, tables, strutils]

import ../frontend/parser
import ../backend/javascript

import pkg/[flatty, supersnappy]
import pkg/kapsis/[runtime, cli]

proc runCommand*(v: Values) =
  if not v.has("input"):
    display("Missing an input file")
    QuitFailure.quit
  var path = v.get("input").absolutePath()
  if not path.fileExists:
    display("File not found")
    QuitFailure.quit
  var outputPath = 
    if v.has("output"):
      v.get("output").absolutePath()
    else:
      path.changeFileExt("ast")

  # parse
  display("✨ Building AST...", br="after")
  let t = getMonotime()
  var p = parseModule(readFile(path), path)
  if p.hasErrors:
    display("Build failed with errors")
    for error in p.logger.errors:
      display error
    display(" 👉 " & p.logger.filePath)
    QuitFailure.quit

  # if p.hasWarnings:
  #   for warning in p.logger.warnings:
  #     display(warning)
  #   display(" 👉 " & p.logger.filePath)

  let total = $(getMonotime() - t)
  writeFile(outputPath, p.getModule.toFlatty())
  display("Done in " & total)
  QuitSuccess.quit