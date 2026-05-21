love.filesystem.setRequirePath(
  "libs/?.lua;libs/?/init.lua;"
  .. "modules/?.lua;modules/?/init.lua;"
  .. love.filesystem.getRequirePath()
)

local isWeb = love.system.getOS() == "Web"
local mcp = not isWeb and require("love_mcp") or nil

local Game

-- Virtual coordinate system. Everything the game draws assumes a 1920×1080
-- frame; the actual window can be any size or aspect ratio. We render
-- directly to the screen using a translate+scale transform — no intermediate
-- canvas, so text and lines hit the framebuffer at native device resolution
-- instead of being upscaled from a 1080p texture (matters on high-DPI phones).
-- All input is mapped back into virtual coords with windowToGame.
local VIRT_W, VIRT_H = 1920, 1080
local viewport = { scale = 1, ox = 0, oy = 0 }

-- Fullscreen-toggle widget lives in WINDOW coords (outside the letterbox) so
-- it stays reachable on phones regardless of the canvas aspect ratio.
-- On Web (love.js), love.window.setFullscreen is a no-op; the deploy template
-- ships an HTML overlay button at the same screen position that calls
-- document.requestFullscreen() instead. We hide the Lua-drawn button on Web so
-- the HTML overlay is the only thing the user sees and taps.
local FS_SIZE = 36
local fsRect = { x = 0, y = 0, w = FS_SIZE, h = FS_SIZE }

local function recomputeViewport()
  local sw, sh = love.graphics.getDimensions()
  viewport.scale = math.min(sw / VIRT_W, sh / VIRT_H)
  viewport.ox = math.floor((sw - VIRT_W * viewport.scale) * 0.5)
  viewport.oy = math.floor((sh - VIRT_H * viewport.scale) * 0.5)
  fsRect.x = sw - FS_SIZE - 8
  fsRect.y = sh - FS_SIZE - 8
end

local function windowToGame(wx, wy)
  return (wx - viewport.ox) / viewport.scale,
         (wy - viewport.oy) / viewport.scale
end

local function pointInRect(x, y, r)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function toggleFullscreen()
  local was = love.window.getFullscreen()
  love.window.setFullscreen(not was, "desktop")
  recomputeViewport()
end

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

  recomputeViewport()

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
-- _G._inputMode flips between "mouse" and "touch" so scenes can suppress
-- hover-only affordances (tooltips) when there's no cursor on the screen.
-- Touch hold has two thresholds:
--   TOUCH_HOVER_S: show the item tooltip (touch's equivalent of mouse hover)
--   TOUCH_HOLD_S:  toggle lock on the slot (synthesized button 2)
-- Movement past TOUCH_DRAG_PX cancels both and commits to a drag.
local TOUCH_HOVER_S = 0.2
local TOUCH_HOLD_S = 1.5
local TOUCH_DRAG_PX = 8
local touch = nil -- { id, x0, y0, x, y, t, promoted } -- coords in game space

_G._inputMode = "mouse"

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
      _G._touchHold = {
        x = touch.x0, y = touch.y0,
        frac = touch.t / TOUCH_HOLD_S,
        hovering = touch.t >= TOUCH_HOVER_S,
      }
    end
  end
end

local function drawFullscreenButton()
  if isWeb then return end -- HTML overlay handles it on Web (see deploy.yml)
  local fs = love.window.getFullscreen()
  love.graphics.setColor(0.15, 0.16, 0.20, 0.85)
  love.graphics.rectangle("fill", fsRect.x, fsRect.y, fsRect.w, fsRect.h, 6, 6)
  love.graphics.setColor(0.6, 0.6, 0.7, 1)
  love.graphics.rectangle("line", fsRect.x, fsRect.y, fsRect.w, fsRect.h, 6, 6)
  if _G._fonts and _G._fonts.ui then
    love.graphics.setFont(_G._fonts.ui)
    love.graphics.setColor(0.85, 0.85, 0.9, 1)
    love.graphics.printf(fs and "[ ]" or "[+]", fsRect.x, fsRect.y + 9, fsRect.w, "center")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function love.draw()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.push()
  love.graphics.translate(viewport.ox, viewport.oy)
  love.graphics.scale(viewport.scale, viewport.scale)
  if Game then Game.draw() end
  if _G._versionLabel and _G._fonts and _G._fonts.ui then
    local font = _G._fonts.ui
    love.graphics.setFont(font)
    local w = font:getWidth(_G._versionLabel)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.print(_G._versionLabel, VIRT_W - w - 6, 2)
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.pop()

  drawFullscreenButton()
end

function love.resize()
  recomputeViewport()
end

function love.mousemoved(x, y, dx, dy, istouch)
  -- Ignore LÖVE's auto-converted touch→mouse events; the real path is
  -- love.touchpressed/moved/released, which feeds our synthesizer.
  if istouch then return end
  _G._inputMode = "mouse"
  local gx, gy = windowToGame(x, y)
  local gdx, gdy = dx / viewport.scale, dy / viewport.scale
  if Game then Game.mousemoved(gx, gy, gdx, gdy, istouch) end
end

function love.mousepressed(x, y, button, istouch)
  if istouch then return end
  if not isWeb and button == 1 and pointInRect(x, y, fsRect) then
    toggleFullscreen()
    return
  end
  _G._inputMode = "mouse"
  local gx, gy = windowToGame(x, y)
  if Game then Game.mousepressed(gx, gy, button, istouch) end
end

function love.mousereleased(x, y, button, istouch)
  if istouch then return end
  local gx, gy = windowToGame(x, y)
  if Game then Game.mousereleased(gx, gy, button, istouch) end
end

function love.wheelmoved(dx, dy) if Game then Game.wheelmoved(dx, dy) end end
function love.keypressed(k, s, r) if Game then Game.keypressed(k, s, r) end end
function love.keyreleased(k)      if Game then Game.keyreleased(k) end end

function love.touchpressed(id, x, y)
  if not isWeb and pointInRect(x, y, fsRect) then
    toggleFullscreen()
    return
  end
  if touch then return end
  _G._inputMode = "touch"
  local gx, gy = windowToGame(x, y)
  touch = { id = id, x0 = gx, y0 = gy, x = gx, y = gy, t = 0, promoted = false }
  _G._touchHold = { x = gx, y = gy, frac = 0 }
  if Game then
    -- Prime the scene's pointer position so a stationary first touch still
    -- has the right coords for the lifted-item render.
    Game.mousemoved(gx, gy, 0, 0)
    Game.mousepressed(gx, gy, 1)
  end
end

function love.touchmoved(id, x, y)
  if not touch or touch.id ~= id then return end
  local gx, gy = windowToGame(x, y)
  touch.x, touch.y = gx, gy
  if not touch.promoted and Game then Game.mousemoved(gx, gy, 0, 0) end
end

function love.touchreleased(id, x, y)
  if not touch or touch.id ~= id then return end
  local gx, gy = windowToGame(x, y)
  local promoted = touch.promoted
  touchEnded()
  if not promoted and Game then Game.mousereleased(gx, gy, 1) end
end

function love.quit() if Game then Game.shutdown() end end
