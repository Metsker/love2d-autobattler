local S  = require("state")
local UI = require("ui")

local Gameover = {}

local result
local room

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
    love.graphics.printf("new classes unlocked!", 0, H * 0.70, W, "center")
  end
  love.graphics.printf("press R to retry  —  ESC to title", 0, H * 0.78, W, "center")
end

function Gameover.keypressed(k)
  local Game = require("game")
  if k == "r" then
    Game.switch("classpick")
  elseif k == "escape" or k == "return" or k == "space" then
    Game.switch("title")
  end
end

return Gameover
