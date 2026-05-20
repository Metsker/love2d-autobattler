love.filesystem.setRequirePath(
  "libs/?.lua;libs/?/init.lua;"
  .. "modules/?.lua;modules/?/init.lua;"
  .. love.filesystem.getRequirePath()
)

local isWeb = love.system.getOS() == "Web"
local mcp = not isWeb and require("love_mcp") or nil

local Game

function love.load()
  if not isWeb then
    local ok, socket = pcall(require, "socket")
    if ok then
      _G._appLock = socket.bind("127.0.0.1", 21199)
      if not _G._appLock then
        print("[main] Another instance already running. Exiting.")
        love.event.quit()
        return
      end
    end
    if mcp then mcp.init({ port = 21110 }) end
  end

  love.math.setRandomSeed(os.time())

  _G._fonts = {
    ui    = love.graphics.newFont(16),
    ui_lg = love.graphics.newFont(28),
    ui_xl = love.graphics.newFont(64),
    emoji = love.graphics.newFont("assets/fonts/NotoEmoji-Regular.ttf", 32),
  }

  resource = {
    getFont = function(_, name) return _G._fonts[name] end,
  }

  local Sounds = require("sounds")
  Sounds.init()

  Game = require("game")
  Game.start()
end

function love.update(dt)              if Game then Game.update(dt) end end
function love.draw()                  if Game then Game.draw() end end
function love.resize(w, h)            if Game then Game.resize(w, h) end end
function love.mousemoved(x,y,dx,dy,t) if Game then Game.mousemoved(x,y,dx,dy,t) end end
function love.mousepressed(x,y,b,t)   if Game then Game.mousepressed(x,y,b,t) end end
function love.mousereleased(x,y,b,t)  if Game then Game.mousereleased(x,y,b,t) end end
function love.wheelmoved(dx,dy)       if Game then Game.wheelmoved(dx,dy) end end
function love.keypressed(k,s,r)       if Game then Game.keypressed(k,s,r) end end
function love.keyreleased(k)          if Game then Game.keyreleased(k) end end
function love.quit()                  if Game then Game.shutdown() end end
