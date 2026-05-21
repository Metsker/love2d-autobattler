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
  }

  local okV, Version = pcall(require, "version")
  if not okV or type(Version) ~= "table" then Version = { n = 0, sha = "dev" } end
  _G._versionLabel = (Version.n and Version.n > 0)
    and ("v" .. tostring(Version.n))
    or "vdev"

  resource = {
    getFont = function(_, name) return _G._fonts[name] end,
  }

  local UI = require("ui")
  UI.preloadEmoji()

  local Sounds = require("sounds")
  Sounds.init()

  Game = require("game")
  Game.start()
end

-- Touch→mouse synthesis. Only the first finger drives the synthesized mouse.
-- - press synthesizes mousepressed(x,y,1)
-- - move >TOUCH_DRAG_PX before TOUCH_HOLD_S confirms drag (no synthesis switch needed)
-- - sitting still past TOUCH_HOLD_S promotes to b=2: synth a release at the
--   start position (drop-on-origin = snap-back without flash), then synth
--   mousepressed(x,y,2) so the existing right-click lock path runs.
-- - release synthesizes mousereleased(x,y,1) unless already promoted.
-- _G._touchHold is published while a press is pending promotion so scenes can
-- render a long-press pulse on whatever's under the finger.
local TOUCH_HOLD_S = 0.4
local TOUCH_DRAG_PX = 8
local touch = nil -- { id, x0, y0, x, y, t, promoted }

local function touchEnded()
  touch = nil
  _G._touchHold = nil
end

function love.update(dt)
  if Game then Game.update(dt) end
  if touch and not touch.promoted then
    touch.t = touch.t + dt
    local dx, dy = touch.x - touch.x0, touch.y - touch.y0
    local moved = dx * dx + dy * dy > TOUCH_DRAG_PX * TOUCH_DRAG_PX
    if moved then
      _G._touchHold = nil
    elseif touch.t >= TOUCH_HOLD_S then
      touch.promoted = true
      _G._touchHold = nil
      if Game then
        Game.mousereleased(touch.x0, touch.y0, 1)
        Game.mousepressed(touch.x0, touch.y0, 2)
      end
    else
      _G._touchHold = { x = touch.x0, y = touch.y0, frac = touch.t / TOUCH_HOLD_S }
    end
  end
end
function love.draw()
  if Game then Game.draw() end
  if _G._versionLabel and _G._fonts and _G._fonts.ui then
    local font = _G._fonts.ui
    love.graphics.setFont(font)
    local w = font:getWidth(_G._versionLabel)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.print(_G._versionLabel, love.graphics.getWidth() - w - 6, 2)
    love.graphics.setColor(1, 1, 1, 1)
  end
end
function love.resize(w, h)            if Game then Game.resize(w, h) end end
function love.mousemoved(x,y,dx,dy,t) if Game then Game.mousemoved(x,y,dx,dy,t) end end
function love.mousepressed(x,y,b,t)   if Game then Game.mousepressed(x,y,b,t) end end
function love.mousereleased(x,y,b,t)  if Game then Game.mousereleased(x,y,b,t) end end
function love.wheelmoved(dx,dy)       if Game then Game.wheelmoved(dx,dy) end end
function love.keypressed(k,s,r)       if Game then Game.keypressed(k,s,r) end end
function love.keyreleased(k)          if Game then Game.keyreleased(k) end end

function love.touchpressed(id, x, y)
  if touch then return end
  touch = { id = id, x0 = x, y0 = y, x = x, y = y, t = 0, promoted = false }
  _G._touchHold = { x = x, y = y, frac = 0 }
  if Game then
    -- Prime the scene's pointer position so a stationary first touch still
    -- has the right coords for the lifted-item render.
    Game.mousemoved(x, y, 0, 0)
    Game.mousepressed(x, y, 1)
  end
end

function love.touchmoved(id, x, y)
  if not touch or touch.id ~= id then return end
  touch.x, touch.y = x, y
  if not touch.promoted and Game then Game.mousemoved(x, y, 0, 0) end
end

function love.touchreleased(id, x, y)
  if not touch or touch.id ~= id then return end
  local promoted = touch.promoted
  touchEnded()
  if not promoted and Game then Game.mousereleased(x, y, 1) end
end

function love.quit()                  if Game then Game.shutdown() end end
