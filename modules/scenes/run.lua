local C      = require("constants")
local S      = require("state")
local Combat = require("combat")
local Loot   = require("loot")
local UI     = require("ui")
local Sounds = require("sounds")

local Run = {}

local enemyHitboxes = {}
local bagHitboxes   = {}
local equipHitboxes = {}
local arenaRect     = { x = 0, y = 0, w = 0, h = 0 }
local muteRect      = { x = 0, y = 0, w = 0, h = 0 }

local mouseX, mouseY = -1, -1

local function speedMul()
  return C.SPEED_LEVELS[S.speed + 1] or 1
end

local function statAccum(run)
  local h = run.hero
  local cls = C.CLASSES[run.class]
  local s = {
    hpMax = cls.hpMax, atk = cls.atk, armor = cls.armor, atkSpd = cls.atkSpd,
    crit = cls.crit, critDmg = cls.critDmg, dodge = cls.dodge,
  }
  for _, item in pairs(run.equip) do
    if item then
      for k in pairs(s) do
        s[k] = s[k] + Loot.statSum(item, k)
      end
    end
  end
  for k, v in pairs(s) do h[k] = v end
  if h.hp > h.hpMax then h.hp = h.hpMax end
end

local function tickPopups(entity, dt)
  if not entity or not entity.popups then return end
  local i = 1
  while i <= #entity.popups do
    local p = entity.popups[i]
    p.age = p.age + dt
    p.dy = p.dy - 60 * dt
    if p.age >= p.life then
      table.remove(entity.popups, i)
    else
      i = i + 1
    end
  end
  if entity.hitFlash and entity.hitFlash > 0 then
    entity.hitFlash = math.max(0, entity.hitFlash - dt)
  end
end

local function drawPopups(entity, anchorX, anchorY)
  if not entity or not entity.popups then return end
  local font = resource:getFont("ui_lg")
  love.graphics.setFont(font)
  for _, p in ipairs(entity.popups) do
    local a = math.max(0, 1 - p.age / p.life)
    love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
    local sx = p.scale
    local w = font:getWidth(p.text) * sx
    love.graphics.print(p.text, anchorX - w / 2, anchorY + p.dy, 0, sx, sx)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Run.enter()
  enemyHitboxes = {}
  bagHitboxes = {}
  equipHitboxes = {}
end

function Run.update(dt)
  if not S.run then return end
  local mul = speedMul()
  if mul > 0 then
    Combat.tick(dt * mul)
  end
  -- Popups/flash always animate (even when paused) so feedback stays smooth.
  tickPopups(S.run.hero, dt)
  for _, e in ipairs(S.run.enemies) do tickPopups(e, dt) end
  if S.shake and S.shake > 0 then
    S.shake = math.max(0, S.shake - dt * 1.5)
  end

  if S.run.floorState == "dead" then
    Sounds.play("gameover")
    local Game = require("game")
    Game.switch("gameover", { result = "dead", floor = S.run.floor })
  elseif S.run.floorState == "won" then
    if S.unlocks.classes.rogue == false then S.unlocks.classes.rogue = true end
    if S.unlocks.classes.monk == false then S.unlocks.classes.monk = true end
    S.unlocks.bossKills = (S.unlocks.bossKills or 0) + 1
    local Game = require("game")
    Game.switch("gameover", { result = "won", floor = S.run.floor })
  end
end

local function drawHpBar(x, y, w, h, hp, hpMax, color)
  love.graphics.setColor(0.1, 0.1, 0.12, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  local f = (hpMax > 0) and (hp / hpMax) or 0
  love.graphics.setColor(color[1], color[2], color[3], 1)
  love.graphics.rectangle("fill", x, y, w * f, h)
  love.graphics.setColor(0.7, 0.7, 0.7, 1)
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.setColor(1, 1, 1, 1)
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  love.graphics.printf(("%d / %d"):format(hp, hpMax), x, y + (h - font:getHeight()) / 2, w, "center")
end

local function drawHero(run, halfW)
  local x, y, w, h = 20, 20, halfW - 40, 130
  love.graphics.setColor(0.14, 0.16, 0.20, 1)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  love.graphics.setColor(0.6, 0.6, 0.7, 1)
  love.graphics.rectangle("line", x, y, w, h, 6, 6)

  local h_ = run.hero
  local emoji = C.CLASS_EMOJI[run.class] or C.HERO_EMOJI
  UI.drawEmoji(emoji, x + 60, y + h / 2, 64, {0.95, 0.85, 0.4, 1})

  local font = resource:getFont("ui_lg")
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(("Hero (%s)"):format(run.class), x + 130, y + 8)

  local barW = math.min(280, w - 280)
  drawHpBar(x + 130, y + 50, barW, 22, h_.hp, h_.hpMax, {0.8, 0.2, 0.25})
  local cdFrac = math.max(0, math.min(1, 1 - h_.cd))
  love.graphics.setColor(0.1, 0.1, 0.12, 1)
  love.graphics.rectangle("fill", x + 130, y + 80, barW, 10)
  love.graphics.setColor(0.95, 0.8, 0.2, 1)
  love.graphics.rectangle("fill", x + 130, y + 80, barW * cdFrac, 10)

  local stats = {
    ("ATK %d"):format(h_.atk),
    ("ARM %d"):format(h_.armor),
    ("SPD %.2f"):format(h_.atkSpd),
    ("CRT %d%%"):format(math.floor(h_.crit * 100)),
    ("CDM +%d%%"):format(math.floor((h_.critDmg - 1) * 100)),
    ("DDG %d%%"):format(math.floor(h_.dodge * 100)),
  }
  local font2 = resource:getFont("ui")
  love.graphics.setFont(font2)
  local statsX = x + math.min(420, w - 240)
  for i, s in ipairs(stats) do
    love.graphics.print(s, statsX + ((i - 1) % 3) * 80, y + 50 + math.floor((i - 1) / 3) * 28)
  end

  if h_.hitFlash and h_.hitFlash > 0 then
    love.graphics.setColor(1, 0.3, 0.3, h_.hitFlash * 1.5)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
  end

  drawPopups(h_, x + 60, y + 10)
end

local function drawEquip(run, halfW, yStart)
  equipHitboxes = {}
  local gap = 6
  local margin = 20
  local n = #C.SLOT_ORDER
  local available = halfW - margin * 2 - gap * (n - 1)
  local cell = math.max(50, math.min(70, math.floor(available / n)))
  local rowW = cell * n + gap * (n - 1)
  local x0 = (halfW - rowW) / 2
  local y0 = yStart + 30
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("EQUIPPED  (dbl-LMB on bag = equip)", x0, y0 - 22)
  for i, slot in ipairs(C.SLOT_ORDER) do
    local x = x0 + (i - 1) * (cell + gap)
    local y = y0
    love.graphics.setColor(0.10, 0.12, 0.16, 1)
    love.graphics.rectangle("fill", x, y, cell, cell, 4, 4)
    local item = run.equip[slot]
    if item then
      local rc = C.RARITY[item.rarity].color
      love.graphics.setColor(rc[1], rc[2], rc[3], 1)
      love.graphics.rectangle("line", x, y, cell, cell, 4, 4)
      UI.drawEmoji(item.emoji or "?", x + cell / 2, y + cell / 2, math.floor(cell * 0.6), rc)
    else
      love.graphics.setColor(0.30, 0.30, 0.35, 1)
      love.graphics.rectangle("line", x, y, cell, cell, 4, 4)
      UI.drawEmoji(C.SLOT_EMOJI[slot] or "?", x + cell / 2, y + cell / 2, math.floor(cell * 0.5), {0.35, 0.38, 0.42, 1})
    end
    equipHitboxes[#equipHitboxes + 1] = { x = x, y = y, w = cell, h = cell, slot = slot, item = item, fromBag = false }
  end
  return y0 + cell
end

local function bagCellSize(halfW)
  local gap = 4
  local margin = 20
  local available = halfW - margin * 2 - gap * (C.BAG_COLS - 1)
  return math.max(50, math.min(80, math.floor(available / C.BAG_COLS))), gap
end

local function drawBag(run, halfW, yStart)
  bagHitboxes = {}
  local cell, gap = bagCellSize(halfW)
  local rowW = cell * C.BAG_COLS + gap * (C.BAG_COLS - 1)
  local x0 = (halfW - rowW) / 2
  local y0 = yStart + 30
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("BAG  (RMB = lock,  dbl-LMB = equip)", x0, y0 - 22)
  for r = 1, C.BAG_ROWS do
    for c = 1, C.BAG_COLS do
      local idx = (r - 1) * C.BAG_COLS + c
      local x = x0 + (c - 1) * (cell + gap)
      local y = y0 + (r - 1) * (cell + gap)
      love.graphics.setColor(0.12, 0.13, 0.16, 1)
      love.graphics.rectangle("fill", x, y, cell, cell, 4, 4)
      local item = run.bag[idx]
      if item then
        local rc = C.RARITY[item.rarity].color
        love.graphics.setColor(rc[1], rc[2], rc[3], 1)
        love.graphics.rectangle("line", x, y, cell, cell, 4, 4)
        UI.drawEmoji(item.emoji or "?", x + cell / 2, y + cell / 2, math.floor(cell * 0.55), rc)
      else
        love.graphics.setColor(0.25, 0.27, 0.30, 1)
        love.graphics.rectangle("line", x, y, cell, cell, 4, 4)
      end
      if run.locks[idx] then
        love.graphics.setColor(0.95, 0.8, 0.2, 1)
        love.graphics.rectangle("line", x + 1, y + 1, cell - 2, cell - 2, 4, 4)
        love.graphics.setFont(font)
        love.graphics.print("L", x + cell - 14, y + 2)
      end
      bagHitboxes[#bagHitboxes + 1] = { x = x, y = y, w = cell, h = cell, idx = idx, item = item, fromBag = true }
    end
  end
end

local function drawEnemies(run, splitX, W, H)
  enemyHitboxes = {}
  local x0, x1, y0 = splitX + 40, W - 40, math.floor(H * 0.28)
  local areaW = x1 - x0
  local n = #run.enemies
  if n == 0 then return end
  local cellGap = 20
  local cellW = math.min(220, math.floor((areaW - cellGap * (n - 1)) / n))
  local cellH = 260
  local totalW = cellW * n + cellGap * (n - 1)
  local startX = x0 + (areaW - totalW) / 2
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  for i, e in ipairs(run.enemies) do
    local x = startX + (i - 1) * (cellW + cellGap)
    local y = y0
    if e.hp > 0 then
      love.graphics.setColor(0.18, 0.10, 0.10, 1)
    else
      love.graphics.setColor(0.10, 0.10, 0.10, 1)
    end
    love.graphics.rectangle("fill", x, y, cellW, cellH, 6, 6)
    if run.hero.target == e and run.hero.targetLocked then
      love.graphics.setColor(0.95, 0.8, 0.2, 1)
    else
      love.graphics.setColor(0.6, 0.3, 0.3, 1)
    end
    love.graphics.rectangle("line", x, y, cellW, cellH, 6, 6)

    local emoji = C.ENEMY_EMOJI[e.name] or "\u{1F47E}"
    local emojiColor = e.hp > 0 and {0.95, 0.5, 0.5, 1} or {0.35, 0.35, 0.35, 1}
    UI.drawEmoji(emoji, x + cellW / 2, y + 90, 80, emojiColor)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(font)
    love.graphics.printf(e.name, x, y + 12, cellW, "center")
    drawHpBar(x + 16, y + 160, cellW - 32, 18, e.hp, e.hpMax, {0.85, 0.25, 0.25})
    local cdF = math.max(0, math.min(1, 1 - e.cd))
    love.graphics.setColor(0.1, 0.1, 0.12, 1)
    love.graphics.rectangle("fill", x + 16, y + 188, cellW - 32, 8)
    love.graphics.setColor(0.9, 0.55, 0.2, 1)
    love.graphics.rectangle("fill", x + 16, y + 188, (cellW - 32) * cdF, 8)
    love.graphics.setColor(0.85, 0.85, 0.85, 1)
    love.graphics.setFont(font)
    love.graphics.printf(("ATK %d"):format(e.atk), x, y + 210, cellW, "center")
    if e.hp == 0 then
      love.graphics.setColor(1, 0.3, 0.3, 1)
      love.graphics.printf("DEAD", x, y + 232, cellW, "center")
    end

    if e.hitFlash and e.hitFlash > 0 then
      love.graphics.setColor(1, 1, 1, e.hitFlash * 1.5)
      love.graphics.rectangle("fill", x, y, cellW, cellH, 6, 6)
      love.graphics.setColor(1, 1, 1, 1)
    end

    drawPopups(e, x + cellW / 2, y + 30)

    enemyHitboxes[#enemyHitboxes + 1] = { x = x, y = y, w = cellW, h = cellH, unit = e }
  end
end

local function drawLog(splitX, W, H)
  local x = splitX + 40
  local h = 160
  local y = H - h - 20
  local w = W - splitX - 80
  love.graphics.setColor(0.10, 0.10, 0.12, 1)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  love.graphics.setColor(0.4, 0.4, 0.45, 1)
  love.graphics.rectangle("line", x, y, w, h, 4, 4)
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  for i, line in ipairs(S.run.log) do
    love.graphics.print(line, x + 8, y + 4 + (i - 1) * 18)
  end
end

local function drawMuteButton(splitX, W)
  local size = 32
  local x = W - size - 20
  local y = 14
  muteRect.x, muteRect.y, muteRect.w, muteRect.h = x, y, size, size
  love.graphics.setColor(0.15, 0.16, 0.20, 1)
  love.graphics.rectangle("fill", x, y, size, size, 4, 4)
  love.graphics.setColor(Sounds.isMuted() and {0.95, 0.3, 0.3, 1} or {0.6, 0.6, 0.7, 1})
  love.graphics.rectangle("line", x, y, size, size, 4, 4)
  local glyph = Sounds.isMuted() and "\u{1F507}" or "\u{1F509}"
  UI.drawEmoji(glyph, x + size / 2, y + size / 2, 22,
    Sounds.isMuted() and {0.95, 0.4, 0.4, 1} or {0.85, 0.85, 0.9, 1})
end

local function drawTopBar(run, splitX, W)
  local rightW = W - splitX
  local font = resource:getFont("ui_lg")
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(("Floor %d / %d"):format(run.floor, C.MAX_FLOOR), splitX, 30, rightW, "center")

  local font2 = resource:getFont("ui")
  love.graphics.setFont(font2)
  local mul = C.SPEED_LEVELS[S.speed + 1] or 1
  local txt = (mul == 0) and "PAUSED" or ("speed: %d×"):format(mul)
  love.graphics.printf(txt, splitX, 90, rightW - 60, "right")
  love.graphics.printf("SPACE pause   1/2/3 = 1×/2×/4×   click enemy = lock target", splitX, 120, rightW, "center")

  drawMuteButton(splitX, W)
end

local function drawClearedHint(run, splitX, W)
  if run.floorState ~= "cleared" then return end
  local rightW = W - splitX
  local x = splitX + 60
  local y = 160
  local w = rightW - 120
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x, y, w, 60, 6, 6)
  love.graphics.setColor(0.3, 0.9, 0.3, 1)
  love.graphics.rectangle("line", x, y, w, 60, 6, 6)
  love.graphics.setFont(resource:getFont("ui_lg"))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("FLOOR CLEARED — click arena for next", x, y + 14, w, "center")
end

local STAT_LABEL = {
  hpMax   = "Max HP",
  atk     = "ATK",
  armor   = "Armor",
  atkSpd  = "Atk Speed",
  crit    = "Crit",
  critDmg = "Crit Dmg",
  dodge   = "Dodge",
}

local STAT_ORDER = { "atk", "hpMax", "armor", "atkSpd", "crit", "critDmg", "dodge" }

local PCT_STATS = { crit = true, critDmg = true, dodge = true }

local function fmtStat(stat, val, isPct)
  if val == 0 then return nil end
  if stat == "atkSpd" then
    return ("%+0.2f %s"):format(val, STAT_LABEL[stat])
  elseif isPct or PCT_STATS[stat] then
    return ("%+d%% %s"):format(math.floor(val * 100 + 0.5), STAT_LABEL[stat])
  else
    return ("%+d %s"):format(val, STAT_LABEL[stat])
  end
end

local function fmtDelta(stat, delta)
  if delta == 0 then return nil end
  local body
  if stat == "atkSpd" then
    body = ("%+0.2f %s"):format(delta, STAT_LABEL[stat])
  elseif PCT_STATS[stat] then
    body = ("%+d%% %s"):format(math.floor(delta * 100 + 0.5), STAT_LABEL[stat])
  else
    body = ("%+d %s"):format(delta, STAT_LABEL[stat])
  end
  local color = delta > 0 and {0.4, 0.9, 0.4, 1} or {0.95, 0.4, 0.4, 1}
  return body, color
end

local function itemStatTotal(item, stat)
  return Loot.statSum(item, stat)
end

local function tooltipLines(item)
  local lines = {}
  for _, stat in ipairs(STAT_ORDER) do
    local v = (item.base[stat] or 0)
    local s = fmtStat(stat, v, false)
    if s then lines[#lines + 1] = { text = s, color = {0.85, 0.85, 0.85, 1} } end
  end
  if #item.affixes > 0 then
    lines[#lines + 1] = { text = "—", color = {0.5, 0.5, 0.5, 1} }
    for _, a in ipairs(item.affixes) do
      local s = fmtStat(a.stat, a.value, a.pct)
      if s then lines[#lines + 1] = { text = s, color = {0.55, 0.85, 0.95, 1} } end
    end
  end
  return lines
end

local function comparisonLines(item, run)
  local equipped = run.equip[item.slot]
  if not equipped then return nil, false end
  local lines = {}
  for _, stat in ipairs(STAT_ORDER) do
    local delta = itemStatTotal(item, stat) - itemStatTotal(equipped, stat)
    local s, color = fmtDelta(stat, delta)
    if s then lines[#lines + 1] = { text = s, color = color } end
  end
  return lines, true
end

local function drawTooltip(item, fromBag, W, H)
  if not item then return end
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  local rarity = C.RARITY[item.rarity]
  local title = ("%s %s"):format(rarity.name, item.name)
  local slotLine = "Slot: " .. (C.SLOT_LABEL[item.slot] or item.slot)
  local lines = tooltipLines(item)

  local compLines, hasComp = nil, false
  if fromBag then
    compLines, hasComp = comparisonLines(item, S.run)
  end

  local pad = 10
  local lineH = font:getHeight() + 2
  local sepBefore = (hasComp and compLines and #compLines > 0)
  local width = math.max(font:getWidth(title), font:getWidth(slotLine))
  for _, l in ipairs(lines) do
    width = math.max(width, font:getWidth(l.text))
  end
  local compHeader = "vs equipped:"
  if sepBefore then
    width = math.max(width, font:getWidth(compHeader))
    for _, l in ipairs(compLines) do
      width = math.max(width, font:getWidth(l.text))
    end
  end
  width = width + pad * 2
  local totalLines = 2 + #lines
  if sepBefore then totalLines = totalLines + 2 + #compLines end
  local height = pad * 2 + lineH * totalLines

  local tx = mouseX + 16
  local ty = mouseY + 16
  if tx + width > W then tx = mouseX - width - 16 end
  if ty + height > H then ty = H - height - 4 end
  if tx < 4 then tx = 4 end
  if ty < 4 then ty = 4 end

  love.graphics.setColor(0.04, 0.05, 0.07, 0.97)
  love.graphics.rectangle("fill", tx, ty, width, height, 6, 6)
  love.graphics.setColor(rarity.color[1], rarity.color[2], rarity.color[3], 1)
  love.graphics.rectangle("line", tx, ty, width, height, 6, 6)

  love.graphics.print(title, tx + pad, ty + pad)
  love.graphics.setColor(0.7, 0.7, 0.7, 1)
  love.graphics.print(slotLine, tx + pad, ty + pad + lineH)
  for i, l in ipairs(lines) do
    love.graphics.setColor(l.color)
    love.graphics.print(l.text, tx + pad, ty + pad + lineH * (i + 1))
  end
  if sepBefore then
    local offset = pad + lineH * (#lines + 2)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.print(compHeader, tx + pad, ty + offset)
    for i, l in ipairs(compLines) do
      love.graphics.setColor(l.color)
      love.graphics.print(l.text, tx + pad, ty + offset + lineH * i)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function hoveredItem()
  for _, hb in ipairs(equipHitboxes) do
    if hb.item and mouseX >= hb.x and mouseX <= hb.x + hb.w
       and mouseY >= hb.y and mouseY <= hb.y + hb.h then
      return hb.item, false
    end
  end
  for _, hb in ipairs(bagHitboxes) do
    if hb.item and mouseX >= hb.x and mouseX <= hb.x + hb.w
       and mouseY >= hb.y and mouseY <= hb.y + hb.h then
      return hb.item, true
    end
  end
  return nil, false
end

function Run.draw()
  local run = S.run
  if not run then return end
  love.graphics.clear(0.06, 0.06, 0.08, 1)
  statAccum(run)

  local W, H = UI.dims()
  local splitX = math.floor(W * 0.5)
  local halfW = splitX

  arenaRect.x = splitX
  arenaRect.y = 0
  arenaRect.w = W - splitX
  arenaRect.h = H

  local sk = S.shake or 0
  if sk > 0 then
    love.graphics.push()
    love.graphics.translate(
      (love.math.random() * 2 - 1) * 10 * sk,
      (love.math.random() * 2 - 1) * 10 * sk
    )
  end

  love.graphics.setColor(0.25, 0.25, 0.30, 1)
  love.graphics.line(splitX, 0, splitX, H)

  drawHero(run, halfW)
  local equipBottom = drawEquip(run, halfW, 150)
  drawBag(run, halfW, equipBottom + 6)

  drawTopBar(run, splitX, W)
  drawEnemies(run, splitX, W, H)
  drawLog(splitX, W, H)
  drawClearedHint(run, splitX, W)

  if sk > 0 then love.graphics.pop() end

  local item, fromBag = hoveredItem()
  if item then drawTooltip(item, fromBag, W, H) end
end

local lastClick = { idx = nil, t = -10 }

local function autoEquipFromBag(idx)
  local run = S.run
  if not run then return end
  local item = run.bag[idx]
  if not item then return end
  local slot = item.slot
  local prev = run.equip[slot]
  run.equip[slot] = item
  run.bag[idx] = nil
  if prev then
    S.pushLog(("discarded %s"):format(Loot.label(prev)))
  end
  S.pushLog(("equipped %s"):format(Loot.label(item)))
  Sounds.play("equip")
end

function Run.mousemoved(x, y)
  mouseX, mouseY = x, y
end

function Run.mousepressed(x, y, b)
  if b == 1 then
    if x >= muteRect.x and x <= muteRect.x + muteRect.w
       and y >= muteRect.y and y <= muteRect.y + muteRect.h then
      Sounds.toggleMute()
      if not Sounds.isMuted() then Sounds.play("click") end
      return
    end
    for _, hb in ipairs(enemyHitboxes) do
      if hb.unit and hb.unit.hp > 0
         and x >= hb.x and x <= hb.x + hb.w
         and y >= hb.y and y <= hb.y + hb.h then
        S.run.hero.target = hb.unit
        S.run.hero.targetLocked = true
        S.pushLog(("targeting %s"):format(hb.unit.name))
        Sounds.play("click")
        return
      end
    end
    for _, hb in ipairs(bagHitboxes) do
      if x >= hb.x and x <= hb.x + hb.w and y >= hb.y and y <= hb.y + hb.h then
        local now = love.timer.getTime()
        if lastClick.idx == hb.idx and (now - lastClick.t) < 0.35 then
          autoEquipFromBag(hb.idx)
          lastClick.t = -10
        else
          lastClick.idx = hb.idx
          lastClick.t = now
        end
        return
      end
    end
    if S.run.floorState == "cleared"
       and x >= arenaRect.x and x <= arenaRect.x + arenaRect.w
       and y >= arenaRect.y and y <= arenaRect.y + arenaRect.h then
      Combat.advanceFloor()
      return
    end
  elseif b == 2 then
    for _, hb in ipairs(bagHitboxes) do
      if x >= hb.x and x <= hb.x + hb.w and y >= hb.y and y <= hb.y + hb.h then
        S.toggleLock(hb.idx)
        Sounds.play("lock")
        return
      end
    end
  end
end

function Run.keypressed(k)
  if k == "space" then
    if S.speed == 0 then S.speed = 1 else S.speed = 0 end
  elseif k == "1" then S.speed = 1
  elseif k == "2" then S.speed = 2
  elseif k == "3" then S.speed = 3
  elseif k == "m" then
    Sounds.toggleMute()
  elseif k == "escape" then
    local Game = require("game")
    Game.switch("title")
  end
end

return Run
