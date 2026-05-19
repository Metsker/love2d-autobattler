local C  = require("constants")
local S  = require("state")
local UI = require("ui")

local Classpick = {}

local choices = { "warrior", "rogue", "monk" }

local function layout()
  local W, H = UI.dims()
  local boxW = math.min(320, (W - 80) / 3 - 30)
  local boxH = 380
  local gap  = 40
  local totalW = boxW * 3 + gap * 2
  local startX = (W - totalW) / 2
  local y0 = math.max(160, H * 0.20)
  return W, H, boxW, boxH, gap, startX, y0
end

local function startWith(name)
  if not S.unlocks.classes[name] then return end
  S.newRun(name)
  local Combat = require("combat")
  Combat.spawnFloor(1)
  local Game = require("game")
  Game.switch("run")
end

function Classpick.draw()
  local W, H, boxW, boxH, gap, startX, y0 = layout()
  love.graphics.clear(0.08, 0.08, 0.10, 1)

  love.graphics.setFont(resource:getFont("ui_lg"))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Choose Class", 0, 60, W, "center")

  local font = resource:getFont("ui")
  for i, name in ipairs(choices) do
    local x = startX + (i - 1) * (boxW + gap)
    local unlocked = S.unlocks.classes[name]
    if unlocked then
      love.graphics.setColor(0.18, 0.22, 0.28, 1)
    else
      love.graphics.setColor(0.12, 0.12, 0.14, 1)
    end
    love.graphics.rectangle("fill", x, y0, boxW, boxH, 8, 8)
    love.graphics.setColor(unlocked and 1 or 0.4, unlocked and 1 or 0.4, unlocked and 1 or 0.4, 1)
    love.graphics.rectangle("line", x, y0, boxW, boxH, 8, 8)

    local emoji = C.CLASS_EMOJI[name]
    UI.drawEmoji(emoji, x + boxW / 2, y0 + 70, 72,
      unlocked and {0.95, 0.85, 0.4, 1} or {0.5, 0.5, 0.5, 1})

    love.graphics.setColor(1, 1, 1, unlocked and 1 or 0.45)
    love.graphics.setFont(font)
    love.graphics.printf(("[%d] %s"):format(i, name:upper()), x, y0 + 130, boxW, "center")
    local cls = C.CLASSES[name]
    local lines = {
      ("HP    %d"):format(cls.hpMax),
      ("ATK   %d"):format(cls.atk),
      ("Armor %d"):format(cls.armor),
      ("AtkS  %.2f"):format(cls.atkSpd),
      ("Crit  %d%%"):format(math.floor(cls.crit * 100)),
      ("CDmg  +%d%%"):format(math.floor((cls.critDmg - 1) * 100)),
      ("Dodge %d%%"):format(math.floor(cls.dodge * 100)),
    }
    for li, l in ipairs(lines) do
      love.graphics.printf(l, x + 20, y0 + 170 + (li - 1) * 24, boxW - 40, "left")
    end
    if not unlocked then
      love.graphics.setColor(0.9, 0.3, 0.3, 1)
      love.graphics.printf("locked — beat boss to unlock", x, y0 + boxH - 40, boxW, "center")
    end
  end

  love.graphics.setColor(0.7, 0.7, 0.7, 1)
  love.graphics.printf("press 1/2/3  —  ESC to title", 0, y0 + boxH + 30, W, "center")
end

function Classpick.keypressed(k)
  if k == "1" then startWith("warrior")
  elseif k == "2" then startWith("rogue")
  elseif k == "3" then startWith("monk")
  elseif k == "escape" then
    local Game = require("game")
    Game.switch("title")
  end
end

function Classpick.mousepressed(x, y, b)
  if b ~= 1 then return end
  local _, _, boxW, boxH, gap, startX, y0 = layout()
  for i, name in ipairs(choices) do
    local bx = startX + (i - 1) * (boxW + gap)
    if x >= bx and x <= bx + boxW and y >= y0 and y <= y0 + boxH then
      startWith(name)
      return
    end
  end
end

return Classpick
