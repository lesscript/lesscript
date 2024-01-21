# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A fast, statically typed Rock'n'Roll language that transpiles to Nim lang & JavaScript"
license       = "LGPLv3"
srcDir        = "src"
bin           = @["lesscript"]
binDir        = "bin"
installExt    = @["nim"]


# Dependencies

requires "nim >= 2.0.0"
requires "kapsis#head"
requires "bigints"
requires "checksums"
requires "denim"
requires "toktok#head"
requires "malebolgia"
requires "watchout#head"
requires "https://github.com/georgelemon/jsony#add-critbits-support"
requires "httpx", "websocketx"
requires "flatty", "supersnappy"
requires "https://github.com/openpeeps/importer"

task dev, "dev build":
  exec "nimble build"

task prod, "prod build":
  exec "nimble build -d:release"

# task plugin, "build a sample plugin":
#   exec "nim c --app:lib --noMain --mm:arc --out:./bin/plugin.so examples/plugin.nim"

# task pluginp, "build a sample plugin":
#   exec "nim c --app:lib --noMain --mm:arc -d:release --out:./bin/plugin.so examples/plugin.nim"