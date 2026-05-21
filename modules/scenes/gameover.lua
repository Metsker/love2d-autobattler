local S  = require("state")
local UI = require("ui")

local Gameover = {}

local result
local room

local BTN_W, BTN_H = 180, 56
local BTN_GAP = 40

local function buttonRects()
  local W, H = UI.dims()
  local totalW = BTN_W * 2 + BTN_GAP
  local y = H * 0.74
  local x0 = (W - totalW) / 2
  return {
    retry = { x = x0,                       y = y, w = BTN_W, h = BTN_H },
    title = { x = x0 + BTN_W + BTN_GAP,     y = y, w = BTN_W, h = BTN_H },
  }
end

local function inRect(x, y, r)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function drawButton(r, label, color)
  love.graphics.setColor(0.15, 0.16, 0.20, 1)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8, 8)
  love.graphics.setColor(color)
  love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 8, 8)
  love.graphics.setFont(resource:getFont("ui_lg"))
  local font = resource:getFont("ui_lg")
  local ty = r.y + (r.h - font:getHeight()) / 2
  love.graphics.printf(label, r.x, ty, r.w, "center")
end

function Gameover.enter(args)
  result = (args and args.result) or "dead"
  room   = (args and args.room)   or 1
end

function Gameover.draw()
  local W, H = UI.dims()
  love.graphics.clear(0.05, 0.05, 0.08, 1)

  local emoji = (result == "won") and "👑" or "💀"
  local emojiColor = (result == "won") and {0.95, 0.85, 0.3, 1} or {0.9, 0.3, 0.3, 1}
  UI.drawEmoji(emoji, W / 2, H * 0.28, 120, emojiColor)

  love.graphics.setFont(resource:getFont("ui_xl"))
  if result == "won" then
    love.graphics.setColor(0.4, 0.9, 0.4, 1)
    love.graphics.printf("VICTORY", 0, H * 0.46, W, "center")
  else
    love.graphics.setColor(0.95, 0.3, 0.3, 1)
    love.graphics.printf("DEFEATED", 0, H * 0.46, W, "center")
  end
  love.graphics.setFont(resource:getFont("ui_lg"))
  love.graphics.setColor(0.85, 0.85, 0.85, 1)
  love.graphics.printf(("reached room %d"):format(room), 0, H * 0.62, W, "center")
  love.graphics.setFont(resource:getFont("ui"))
  love.graphics.setColor(0.7, 0.7, 0.7, 1)
  if result == "won" and S.unlocks.bossKills == 1 then
    love.graphics.printf("new classes unlocked!", 0, H * 0.68, W, "center")
  end

  local rects = buttonRects()
  drawButton(rects.retry, "RETRY", {0.4, 0.9, 0.4, 1})
  drawButton(rects.title, "TITLE", {0.6, 0.6, 0.7, 1})

  love.graphics.setFont(resource:getFont("ui"))
  love.graphics.setColor(0.55, 0.55, 0.6, 1)
  love.graphics.printf("press R to retry  —  ESC to title", 0, H * 0.74 + BTN_H + 20, W, "center")
end

function Gameover.keypressed(k)
  local Game = require("game")
  if k == "r" then
    Game.switch("classpick")
  elseif k == "escape" or k == "return" or k == "space" then
    Game.switch("title")
  end
end

function Gameover.mousepressed(x, y, b)
  if b ~= 1 then return end
  local Game = require("game")
  local rects = buttonRects()
  if inRect(x, y, rects.retry) then
    Game.switch("classpick")
  elseif inRect(x, y, rects.title) then
    Game.switch("title")
  end
end

return Gameover
