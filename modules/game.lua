local Scenes  = {}
local current = nil
local currentName = nil

local Game = {}

function Game.switch(name, args)
  if current and current.exit then current.exit() end
  current = assert(Scenes[name], "no scene: " .. tostring(name))
  currentName = name
  if current.enter then current.enter(args) end
end

function Game.currentName() return currentName end

function Game.start()
  Scenes.title     = require("scenes.title")
  Scenes.classpick = require("scenes.classpick")
  Scenes.run       = require("scenes.run")
  Scenes.gameover  = require("scenes.gameover")
  Game.switch("title")
end

function Game.update(dt)              if current and current.update       then current.update(dt) end end
function Game.draw()                  if current and current.draw         then current.draw() end end
function Game.resize(w, h)            if current and current.resize       then current.resize(w, h) end end
function Game.mousemoved(x,y,dx,dy,t) if current and current.mousemoved   then current.mousemoved(x,y,dx,dy,t) end end
function Game.mousepressed(x,y,b,t)   if current and current.mousepressed then current.mousepressed(x,y,b,t) end end
function Game.mousereleased(x,y,b,t)  if current and current.mousereleased then current.mousereleased(x,y,b,t) end end
function Game.wheelmoved(dx,dy)       if current and current.wheelmoved   then current.wheelmoved(dx,dy) end end
function Game.keypressed(k,s,r)       if current and current.keypressed   then current.keypressed(k,s,r) end end
function Game.keyreleased(k)          if current and current.keyreleased  then current.keyreleased(k) end end
function Game.shutdown()              if current and current.shutdown     then current.shutdown() end end

return Game
