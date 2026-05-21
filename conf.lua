function love.conf(t)
  t.identity = "autobattler"
  t.version  = "11.5"
  t.window.title  = "Autobattler"
  t.window.width  = 1600
  t.window.height = 900
  t.window.resizable = true
  -- Render at the device's physical pixel resolution rather than the OS's
  -- logical pixel count. love.graphics.getDimensions() returns physical pixels
  -- in this mode; the canvas/viewport scaling math already uses that.
  t.window.highdpi = true
  t.console = true
end
