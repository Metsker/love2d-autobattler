local C      = require("constants")
local S      = require("state")
local Combat = require("combat")
local Loot   = require("loot")
local UI     = require("ui")
local Sounds = require("sounds")
local Dust   = require("dust")

local Run = {}

local enemyHitboxes = {}
local bagHitboxes   = {}
local equipHitboxes = {}
local benchHitboxes = {} -- entries: { x,y,w,h, kind = "input"|"result", slot = 1|2 (for input) }
local arenaRect     = { x = 0, y = 0, w = 0, h = 0 }
local muteRect      = { x = 0, y = 0, w = 0, h = 0 }

local mouseX, mouseY = -1, -1

-- Active drag. nil when idle. Fields:
--   item, source = { kind = "bag"|"bench"|"result", idx?, slot? },
--   offsetX, offsetY  (cursor-to-item-corner offset captured at pickup)
local drag = nil

-- Brief reject-flash overlay. nil when idle.
local rejectFlash = nil -- { x, y, w, h, age, life }

-- Cached dust counter screen position (set in drawBag, read by drawDustEvents).
local dustCounterPos = { x = 0, y = 0 }
-- Flash state on the dust counter: { kind = "gain"|"spend"|"reject", age, life }
local dustFlash = nil
-- Ejection animations: items shrinking/fading in place after overflow.
-- entries: { x, y, w, item, age, life }
local ejectAnims = {}
-- Active dust-number popups drifting toward the dust counter.
-- entries: { text, color, fromX, fromY, age, life }
local dustPopups = {}

local function speedMul()
  return C.SPEED_LEVELS[S.speed + 1] or 1
end

local function displayVal(stat, v)
  if C.STAT_DISPLAY_EXCLUDE[stat] then return v end
  return v * C.STAT_DISPLAY_MULT
end

local function statAccum(run)
  local h = run.hero
  local cls = C.CLASSES[run.class]
  local s = {
    hpMax = cls.hpMax, atk = cls.atk, armor = cls.armor, atkSpd = cls.atkSpd,
    crit = cls.crit, critDmg = cls.critDmg, dodge = cls.dodge,
    cleave = 0, lifesteal = 0, regen = 0, thorns = 0,
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

-- Forward-declared so Run.update can call it before its definition below.
local processDustEvents = function() end

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
  if rejectFlash then
    rejectFlash.age = rejectFlash.age + dt
    if rejectFlash.age >= rejectFlash.life then rejectFlash = nil end
  end
  if dustFlash then
    dustFlash.age = dustFlash.age + dt
    if dustFlash.age >= dustFlash.life then dustFlash = nil end
  end
  processDustEvents()
  do
    local i = 1
    while i <= #ejectAnims do
      local a = ejectAnims[i]
      a.age = a.age + dt
      if a.age >= a.life then table.remove(ejectAnims, i)
      else i = i + 1 end
    end
  end
  do
    local i = 1
    while i <= #dustPopups do
      local p = dustPopups[i]
      p.age = p.age + dt
      if p.age >= p.life then table.remove(dustPopups, i)
      else i = i + 1 end
    end
  end

  if S.run.roomState == "dead" then
    Sounds.play("gameover")
    local Game = require("game")
    Game.switch("gameover", { result = "dead", room = S.run.room })
  elseif S.run.roomState == "won" then
    if S.unlocks.classes.rogue == false then S.unlocks.classes.rogue = true end
    if S.unlocks.classes.monk == false then S.unlocks.classes.monk = true end
    S.unlocks.bossKills = (S.unlocks.bossKills or 0) + 1
    local Game = require("game")
    Game.switch("gameover", { result = "won", room = S.run.room })
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
  local m = C.STAT_DISPLAY_MULT
  love.graphics.printf(("%d / %d"):format(hp * m, hpMax * m), x, y + (h - font:getHeight()) / 2, w, "center")
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
    ("ATK %d"):format(displayVal("atk", h_.atk)),
    ("ARM %d"):format(displayVal("armor", h_.armor)),
    ("SPD %.2f"):format(displayVal("atkSpd", h_.atkSpd)),
    ("CRT %d%%"):format(math.floor(displayVal("crit", h_.crit) * 100)),
    ("CDM +%d%%"):format(math.floor(displayVal("critDmg", h_.critDmg - 1) * 100)),
    ("DDG %d%%"):format(math.floor(displayVal("dodge", h_.dodge) * 100)),
  }
  local font2 = resource:getFont("ui")
  love.graphics.setFont(font2)
  local statsX = x + math.min(420, w - 280)
  local colGap = 120
  for i, s in ipairs(stats) do
    love.graphics.print(s, statsX + ((i - 1) % 3) * colGap, y + 50 + math.floor((i - 1) / 3) * 28)
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
  love.graphics.print("EQUIPPED  (drag bag item onto slot)", x0, y0 - 22)
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

local function drawItemInCell(item, x, y, cell, emojiScale)
  local rc = C.RARITY[item.rarity].color
  love.graphics.setColor(rc[1], rc[2], rc[3], 1)
  love.graphics.rectangle("line", x, y, cell, cell, 4, 4)
  UI.drawEmoji(item.emoji or "?", x + cell / 2, y + cell / 2,
               math.floor(cell * (emojiScale or 0.55)), rc)
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
  love.graphics.print("BAG  (drag to equip / merge,  RMB = lock)", x0, y0 - 22)
  -- Dust counter, right-aligned within the bag's row width.
  local dustNum = tostring(run.dust or 0)
  local emojiSize = 18
  local numW = font:getWidth(dustNum)
  local glyphW = emojiSize
  local pad = 4
  local totalW = glyphW + pad + numW
  local dustX = x0 + rowW - totalW
  local dustY = y0 - 22
  local centerX = dustX + totalW / 2
  local centerY = dustY + font:getHeight() / 2
  local flashColor = {0.95, 0.95, 0.6, 1}
  local scale = 1.0
  if dustFlash then
    local a = math.max(0, 1 - dustFlash.age / dustFlash.life)
    scale = 1.0 + 0.25 * a
    if dustFlash.kind == "gain" then
      flashColor = {0.55 + 0.4 * a, 0.95, 0.55 + 0.4 * a, 1}
    elseif dustFlash.kind == "spend" then
      flashColor = {0.95, 0.95, 0.95, 1}
    elseif dustFlash.kind == "reject" then
      flashColor = {0.95, 0.4 + 0.5 * a, 0.4 + 0.5 * a, 1}
    end
  end
  UI.drawEmoji("💨", centerX - numW / 2 - pad / 2 - glyphW / 2 + (1 - scale) * 6,
               centerY, math.floor(emojiSize * scale), flashColor)
  love.graphics.setFont(font)
  love.graphics.setColor(flashColor)
  love.graphics.print(dustNum,
    centerX + (totalW / 2 - numW) - (scale - 1) * numW / 2,
    dustY - (scale - 1) * font:getHeight() / 2,
    0, scale, scale)
  love.graphics.setColor(1, 1, 1, 1)
  dustCounterPos.x = centerX
  dustCounterPos.y = centerY
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
  return y0 + C.BAG_ROWS * cell + (C.BAG_ROWS - 1) * gap
end

local function drawBench(run, halfW, yStart)
  benchHitboxes = {}
  local bench = run.bench
  local cell = 78
  local gap = 24
  local rowW = cell * 3 + gap * 2
  local x0 = (halfW - rowW) / 2
  local y0 = yStart + 30
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("MERGE  (drag two same-slot + same-rarity items here)", x0, y0 - 22)

  local positions = { 1, 2, 3 } -- input1, result, input2
  local labels = { "1", "=", "2" }
  for i, _ in ipairs(positions) do
    local x = x0 + (i - 1) * (cell + gap)
    local y = y0
    local kind = (i == 2) and "result" or "input"
    local slot = (i == 1) and 1 or (i == 3) and 2 or nil

    -- arrow between inputs and result
    if i == 2 then
      love.graphics.setColor(0.20, 0.22, 0.28, 1)
    else
      love.graphics.setColor(0.12, 0.13, 0.16, 1)
    end
    love.graphics.rectangle("fill", x, y, cell, cell, 4, 4)

    local item = nil
    if kind == "input" then item = bench.input[slot] end
    if kind == "result" then item = bench.result end

    if item then
      drawItemInCell(item, x, y, cell, 0.6)
    else
      love.graphics.setColor(0.28, 0.30, 0.34, 1)
      love.graphics.rectangle("line", x, y, cell, cell, 4, 4)
      love.graphics.setColor(0.45, 0.45, 0.50, 1)
      love.graphics.printf(labels[i], x, y + (cell - font:getHeight()) / 2, cell, "center")
    end

    benchHitboxes[#benchHitboxes + 1] = { x = x, y = y, w = cell, h = cell, kind = kind, slot = slot, item = item }
  end
  return y0 + cell
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

    local emoji = C.ENEMY_EMOJI[e.name] or "👾"
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
  local glyph = Sounds.isMuted() and "🔇" or "🔉"
  UI.drawEmoji(glyph, x + size / 2, y + size / 2, 22,
    Sounds.isMuted() and {0.95, 0.4, 0.4, 1} or {0.85, 0.85, 0.9, 1})
end

local function drawTopBar(run, splitX, W)
  local rightW = W - splitX
  local font = resource:getFont("ui_lg")
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(("Room %d / %d"):format(run.room, C.MAX_ROOM), splitX, 30, rightW, "center")

  local font2 = resource:getFont("ui")
  love.graphics.setFont(font2)
  local mul = C.SPEED_LEVELS[S.speed + 1] or 1
  local txt = (mul == 0) and "PAUSED" or ("speed: %d×"):format(mul)
  love.graphics.printf(txt, splitX, 90, rightW - 60, "right")
  love.graphics.printf("SPACE pause   1/2/3 = 1×/2×/4×   click enemy = lock target", splitX, 120, rightW, "center")

  drawMuteButton(splitX, W)
end

local function drawClearedHint(run, splitX, W)
  if run.roomState ~= "cleared" then return end
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
  love.graphics.printf("ROOM CLEARED — click arena for next", x, y + 14, w, "center")
end

local STAT_LABEL = {
  hpMax     = "Max HP",
  atk       = "ATK",
  armor     = "Armor",
  atkSpd    = "Atk Speed",
  crit      = "Crit",
  critDmg   = "Crit Dmg",
  dodge     = "Dodge",
  cleave    = "Cleave",
  lifesteal = "Lifesteal",
  regen     = "Regen",
  thorns    = "Thorns",
}

local STAT_ORDER = { "atk", "hpMax", "armor", "atkSpd", "crit", "critDmg", "dodge" }

local PCT_STATS = { crit = true, critDmg = true, dodge = true, cleave = true, lifesteal = true, thorns = true }

local function fmtStat(stat, val, isPct)
  if val == 0 then return nil end
  local dv = displayVal(stat, val)
  if stat == "atkSpd" then
    return ("%+0.2f %s"):format(dv, STAT_LABEL[stat])
  elseif isPct or PCT_STATS[stat] then
    return ("%+d%% %s"):format(math.floor(dv * 100 + 0.5), STAT_LABEL[stat])
  else
    return ("%+d %s"):format(dv, STAT_LABEL[stat])
  end
end

local function fmtDelta(stat, delta)
  if delta == 0 then return nil end
  local dv = displayVal(stat, delta)
  local body
  if stat == "atkSpd" then
    body = ("%+0.2f %s"):format(dv, STAT_LABEL[stat])
  elseif PCT_STATS[stat] then
    body = ("%+d%% %s"):format(math.floor(dv * 100 + 0.5), STAT_LABEL[stat])
  else
    body = ("%+d %s"):format(dv, STAT_LABEL[stat])
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
  local affixGroups = Loot.groupedAffixes(item)
  if #affixGroups > 0 then
    lines[#lines + 1] = { text = "—", color = {0.5, 0.5, 0.5, 1} }
    for _, g in ipairs(affixGroups) do
      local s = fmtStat(g.stat, g.total, g.pct)
      if s then
        if g.count and g.count > 1 then
          s = s .. (" (×%d)"):format(g.count)
        end
        local line = { text = s, color = {0.85, 0.85, 0.85, 1} }
        if g.tier then
          local tc = C.TIER_COLOR[g.tier] or {1, 1, 1, 1}
          line.prefix = g.overflow
            and ("T%d★ "):format(g.tier)
            or  ("T%d "):format(g.tier)
          line.prefixColor = tc
        end
        lines[#lines + 1] = line
      end
    end
  end
  local u = item.unique
  if u then
    lines[#lines + 1] = { text = "—", color = {0.5, 0.5, 0.5, 1} }
    local s = fmtStat(u.stat, u.value, u.pct)
    if s then
      local line = { text = s, color = C.UNIQUE_COLOR }
      if u.tier then
        line.prefix = ("T%d "):format(u.tier)
        line.prefixColor = C.UNIQUE_COLOR
      end
      lines[#lines + 1] = line
    end
  end
  return lines
end

local function resultTooltipLines(item)
  local lines = {}
  for _, stat in ipairs(STAT_ORDER) do
    local v = (item.base[stat] or 0)
    local s = fmtStat(stat, v, false)
    if s then lines[#lines + 1] = { text = s, color = {0.85, 0.85, 0.85, 1} } end
  end
  lines[#lines + 1] = { text = "—", color = {0.5, 0.5, 0.5, 1} }
  lines[#lines + 1] = { text = "???", color = {0.85, 0.85, 0.95, 1} }
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

local function drawTooltip(item, fromBag, W, H, isResult)
  if not item then return end
  local font = resource:getFont("ui")
  love.graphics.setFont(font)
  local rarity = C.RARITY[item.rarity]
  local title = ("%s %s"):format(rarity.name, item.name)
  local slotLine = "Slot: " .. (C.SLOT_LABEL[item.slot] or item.slot)
  local lines = isResult and resultTooltipLines(item) or tooltipLines(item)

  local compLines, hasComp = nil, false
  if fromBag and not isResult then
    compLines, hasComp = comparisonLines(item, S.run)
  end

  local pad = 10
  local lineH = font:getHeight() + 2
  local sepBefore = (hasComp and compLines and #compLines > 0)
  local function lineWidth(l)
    local w = font:getWidth(l.text)
    if l.prefix then w = w + font:getWidth(l.prefix) end
    return w
  end
  local width = math.max(font:getWidth(title), font:getWidth(slotLine))
  for _, l in ipairs(lines) do
    width = math.max(width, lineWidth(l))
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
    local lx = tx + pad
    local ly = ty + pad + lineH * (i + 1)
    if l.prefix then
      love.graphics.setColor(l.prefixColor or l.color)
      love.graphics.print(l.prefix, lx, ly)
      lx = lx + font:getWidth(l.prefix)
    end
    love.graphics.setColor(l.color)
    love.graphics.print(l.text, lx, ly)
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
      return hb.item, false, false, hb
    end
  end
  for _, hb in ipairs(bagHitboxes) do
    if hb.item and mouseX >= hb.x and mouseX <= hb.x + hb.w
       and mouseY >= hb.y and mouseY <= hb.y + hb.h then
      return hb.item, true, false, hb
    end
  end
  for _, hb in ipairs(benchHitboxes) do
    if hb.item and mouseX >= hb.x and mouseX <= hb.x + hb.w
       and mouseY >= hb.y and mouseY <= hb.y + hb.h then
      return hb.item, false, hb.kind == "result", hb
    end
  end
  return nil, false, false, nil
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
  -- Bench is hidden from UI for now (state + helpers preserved for later).
  benchHitboxes = {}

  drawTopBar(run, splitX, W)
  drawEnemies(run, splitX, W, H)
  drawLog(splitX, W, H)
  drawClearedHint(run, splitX, W)

  if sk > 0 then love.graphics.pop() end

  -- Highlight valid drop targets while dragging.
  if drag then
    local item = drag.item
    local src  = drag.source
    local function outline(hb, color)
      love.graphics.setColor(color[1], color[2], color[3], 0.85)
      love.graphics.setLineWidth(3)
      love.graphics.rectangle("line", hb.x - 1, hb.y - 1, hb.w + 2, hb.h + 2, 4, 4)
      love.graphics.setLineWidth(1)
    end
    for _, hb in ipairs(equipHitboxes) do
      if hb.slot == item.slot then outline(hb, {0.35, 0.95, 0.45, 1}) end
    end
    if src.kind == "bag" then
      for _, hb in ipairs(benchHitboxes) do
        if hb.kind == "input" and not hb.item then
          outline(hb, {0.95, 0.85, 0.30, 1})
        end
      end
    end
    if src.kind ~= "bag" then
      for _, hb in ipairs(bagHitboxes) do
        if not hb.item then outline(hb, {0.50, 0.75, 0.95, 1}) end
      end
    end
    local font = resource:getFont("ui")
    love.graphics.setFont(font)
    for _, hb in ipairs(bagHitboxes) do
      if hb.item and Loot.canMerge(item, hb.item) then
        outline(hb, {0.85, 0.50, 1.0, 1})
        local cost = Dust.mergeCost(hb.item.rarity + 1)
        local have = S.run.dust or 0
        local label, color
        if have >= cost then
          label = ("%d dust"):format(cost)
          color = {0.55, 0.95, 0.55, 1}
        else
          label = ("%d dust (have %d)"):format(cost, have)
          color = {1.0, 0.45, 0.45, 1}
        end
        local lw = font:getWidth(label)
        love.graphics.setColor(0.06, 0.07, 0.10, 0.92)
        love.graphics.rectangle("fill", hb.x + hb.w / 2 - lw / 2 - 4, hb.y + hb.w + 4, lw + 8, font:getHeight() + 4, 3, 3)
        love.graphics.setColor(color)
        love.graphics.print(label, hb.x + hb.w / 2 - lw / 2, hb.y + hb.w + 6)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  if rejectFlash then
    local a = math.max(0, 1 - rejectFlash.age / rejectFlash.life)
    love.graphics.setColor(0.95, 0.30, 0.30, a * 0.7)
    love.graphics.rectangle("fill", rejectFlash.x, rejectFlash.y, rejectFlash.w, rejectFlash.h, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- Ejection shrink/fade animations (item turning to dust in-slot).
  for _, a in ipairs(ejectAnims) do
    local t = a.age / a.life
    local alpha = 1 - t
    local s = 1 - 0.6 * t
    local cx, cy = a.x + a.w / 2, a.y + a.w / 2
    local cell = a.w * s
    love.graphics.setColor(0.08, 0.09, 0.12, alpha * 0.75)
    love.graphics.rectangle("fill", cx - cell / 2, cy - cell / 2, cell, cell, 4, 4)
    love.graphics.setColor(1, 1, 1, alpha)
    drawItemInCell(a.item, cx - cell / 2, cy - cell / 2, cell, 0.55)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- "+N dust" popups drifting toward the dust counter.
  do
    local font = resource:getFont("ui_lg")
    love.graphics.setFont(font)
    for _, p in ipairs(dustPopups) do
      local t = math.min(1, p.age / p.life)
      local ease = t * t * (3 - 2 * t)
      local x = p.fromX + (dustCounterPos.x - p.fromX) * ease
      local y = p.fromY + (dustCounterPos.y - p.fromY) * ease
      local a = 1 - t
      love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
      local w = font:getWidth(p.text)
      love.graphics.print(p.text, x - w / 2, y - font:getHeight() / 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  if drag then
    local item = drag.item
    local cell = drag.originRect.w
    local gx = mouseX - drag.offsetX
    local gy = mouseY - drag.offsetY
    love.graphics.setColor(0.08, 0.09, 0.12, 0.75)
    love.graphics.rectangle("fill", gx, gy, cell, cell, 4, 4)
    drawItemInCell(item, gx, gy, cell, 0.6)
  else
    local item, fromBag, isResult, hoverHb = hoveredItem()
    if item then
      for _, hb in ipairs(bagHitboxes) do
        if hb.item and hb.item ~= item and Loot.canMerge(item, hb.item) then
          love.graphics.setColor(0.85, 0.50, 1.0, 0.9)
          love.graphics.setLineWidth(3)
          love.graphics.rectangle("line", hb.x - 1, hb.y - 1, hb.w + 2, hb.h + 2, 4, 4)
          love.graphics.setLineWidth(1)
        end
      end
      if hoverHb then
        love.graphics.setColor(0.85, 0.50, 1.0, 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", hoverHb.x - 1, hoverHb.y - 1, hoverHb.w + 2, hoverHb.h + 2, 4, 4)
        love.graphics.setLineWidth(1)
      end
      love.graphics.setColor(1, 1, 1, 1)
      drawTooltip(item, fromBag, W, H, isResult)
    end
  end
end

local function inRect(rx, ry, rw, rh, px, py)
  return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

local function findHit(list, x, y)
  for _, hb in ipairs(list) do
    if inRect(hb.x, hb.y, hb.w, hb.h, x, y) then return hb end
  end
  return nil
end

local function startRejectFlash(rect)
  rejectFlash = { x = rect.x, y = rect.y, w = rect.w, h = rect.h, age = 0, life = 0.35 }
end

local function snapBackToSource()
  if not drag then return end
  if drag.source.kind == "bag" then
    S.run.bag[drag.source.idx] = drag.item
  elseif drag.source.kind == "bench" then
    S.benchSet(drag.source.slot, drag.item)
  end
  -- result source: item still in bench.result; nothing to restore
  if drag.originRect then startRejectFlash(drag.originRect) end
  Sounds.play("click")
end

local function flashDust(kind)
  dustFlash = { kind = kind, age = 0, life = 0.4 }
end

local function spawnDustPopup(text, color, fromX, fromY)
  table.insert(dustPopups, {
    text = text, color = color, fromX = fromX, fromY = fromY,
    age = 0, life = 0.9,
  })
end

local function findBagRect(corner)
  if #bagHitboxes == 0 then return nil end
  if corner == "right" then
    -- Rightmost-occupied (or rightmost slot if none occupied).
    local rect
    for _, hb in ipairs(bagHitboxes) do
      if hb.item then rect = hb end
    end
    return rect or bagHitboxes[#bagHitboxes]
  end
  return bagHitboxes[1]
end

local function spawnEjectAnim(rect, item)
  if not rect or not item then return end
  table.insert(ejectAnims, {
    x = rect.x, y = rect.y, w = rect.w,
    item = item, age = 0, life = 0.28,
  })
end

processDustEvents = function()
  while #S.pendingDustEvents > 0 do
    local e = table.remove(S.pendingDustEvents, 1)
    flashDust(e.kind)
    if e.kind == "gain" then
      Sounds.play("dust")
      local rect
      if e.origin == "bagRight" then rect = findBagRect("right")
      elseif e.origin == "bagLeft" then rect = findBagRect("left")
      elseif type(e.origin) == "string" and e.origin:sub(1, 6) == "equip:" then
        local slot = e.origin:sub(7)
        for _, hb in ipairs(equipHitboxes) do
          if hb.slot == slot then rect = hb; break end
        end
      end
      if rect then
        spawnEjectAnim(rect, e.item)
        spawnDustPopup(("+%d dust"):format(e.amount),
                       {0.85, 0.95, 0.55, 1},
                       rect.x + rect.w / 2, rect.y + rect.w / 2)
      end
    end
  end
end

local function destroyPrevEquip(prev, slot)
  if not prev then return end
  local amount = Dust.gainFor(prev.rarity)
  S.addDust(amount)
  S.queueDustEvent("gain", amount, prev, "equip:" .. slot)
  S.pushLog(("destroyed %s → %d dust"):format(Loot.label(prev), amount))
end

local function tryMerge(a, b)
  if not Loot.canMerge(a, b) then return nil, "incompatible" end
  local targetRarity = a.rarity + 1
  local cost = Dust.mergeCost(targetRarity)
  if (S.run.dust or 0) < cost then return nil, "dust", cost end
  local result = Loot.merge(a, b)
  if not result then return nil, "incompatible" end
  S.addDust(-cost)
  flashDust("spend")
  return result, nil, cost
end

function Run.mousemoved(x, y)
  mouseX, mouseY = x, y
end

function Run.mousepressed(x, y, b)
  if b == 1 then
    if inRect(muteRect.x, muteRect.y, muteRect.w, muteRect.h, x, y) then
      Sounds.toggleMute()
      if not Sounds.isMuted() then Sounds.play("click") end
      return
    end
    for _, hb in ipairs(enemyHitboxes) do
      if hb.unit and hb.unit.hp > 0 and inRect(hb.x, hb.y, hb.w, hb.h, x, y) then
        S.run.hero.target = hb.unit
        S.run.hero.targetLocked = true
        S.pushLog(("targeting %s"):format(hb.unit.name))
        Sounds.play("click")
        return
      end
    end

    local benchHit = findHit(benchHitboxes, x, y)
    if benchHit then
      if benchHit.kind == "result" and benchHit.item then
        drag = {
          item = benchHit.item,
          source = { kind = "result" },
          offsetX = x - benchHit.x, offsetY = y - benchHit.y,
          originRect = benchHit,
        }
        return
      elseif benchHit.kind == "input" and benchHit.item then
        drag = {
          item = benchHit.item,
          source = { kind = "bench", slot = benchHit.slot },
          offsetX = x - benchHit.x, offsetY = y - benchHit.y,
          originRect = benchHit,
        }
        S.benchTake(benchHit.slot)
        return
      end
    end

    local bagHit = findHit(bagHitboxes, x, y)
    if bagHit and bagHit.item then
      drag = {
        item = bagHit.item,
        source = { kind = "bag", idx = bagHit.idx },
        offsetX = x - bagHit.x, offsetY = y - bagHit.y,
        originRect = bagHit,
      }
      S.run.bag[bagHit.idx] = nil
      return
    end

    if S.run.roomState == "cleared"
       and inRect(arenaRect.x, arenaRect.y, arenaRect.w, arenaRect.h, x, y) then
      Combat.advanceRoom()
      return
    end
  elseif b == 2 then
    for _, hb in ipairs(bagHitboxes) do
      if inRect(hb.x, hb.y, hb.w, hb.h, x, y) then
        S.toggleLock(hb.idx)
        Sounds.play("lock")
        return
      end
    end
  end
end

local function mousereleasedImpl(x, y, b)
  if b ~= 1 or not drag then return end
  local item = drag.item
  local src  = drag.source

  local equipHit = findHit(equipHitboxes, x, y)
  local bagHit   = findHit(bagHitboxes, x, y)
  local benchHit = findHit(benchHitboxes, x, y)

  -- Cancel: drop on origin slot puts item back, no flash.
  if src.kind == "bag" and bagHit and bagHit.idx == src.idx then
    S.run.bag[src.idx] = item
    drag = nil
    return
  end
  if src.kind == "bench" and benchHit and benchHit.kind == "input" and benchHit.slot == src.slot then
    S.benchSet(src.slot, item)
    drag = nil
    return
  end

  -- Equip target (slot must match item.slot). Always a plain equip-swap:
  -- previous equipped item is destroyed for dust, no merge.
  if equipHit and equipHit.slot == item.slot then
    if src.kind == "bag" or src.kind == "bench" then
      local prev = S.run.equip[item.slot]
      S.run.equip[item.slot] = item
      destroyPrevEquip(prev, item.slot)
      S.pushLog(("equipped %s"):format(Loot.label(item)))
      Sounds.play("equip")
      drag = nil
      return
    elseif src.kind == "result" then
      local result = S.benchCommit()
      if not result then snapBackToSource(); drag = nil; return end
      local prev = S.run.equip[result.slot]
      S.run.equip[result.slot] = result
      destroyPrevEquip(prev, result.slot)
      S.pushLog(("merged + equipped %s"):format(Loot.label(result)))
      Sounds.play("equip")
      drag = nil
      return
    end
  end

  -- Bench input target (only bag source allowed; must be empty + compatible)
  if benchHit and benchHit.kind == "input" and src.kind == "bag" then
    if benchHit.item then snapBackToSource(); drag = nil; return end
    if S.benchSet(benchHit.slot, item) then
      S.pushLog(("bench %d: %s"):format(benchHit.slot, Loot.label(item)))
      Sounds.play("click")
      drag = nil
      return
    end
    snapBackToSource(); drag = nil; return
  end

  -- Bag occupied target with bag source: merge attempt (drag-on-drop).
  if bagHit and bagHit.item and src.kind == "bag" and Loot.canMerge(item, bagHit.item) then
    local result, err, cost = tryMerge(item, bagHit.item)
    if result then
      S.run.bag[bagHit.idx] = result
      S.pushLog(("merged: %s (-%d dust)"):format(Loot.label(result), cost))
      Sounds.play("loot")
      drag = nil
      return
    elseif err == "dust" then
      flashDust("reject")
      Sounds.play("reject")
      S.pushLog(("merge needs %d dust"):format(cost))
      snapBackToSource(); drag = nil; return
    end
  end

  -- Bag empty target. Bag-source forbidden (no bag-rearrange).
  if bagHit and not bagHit.item then
    if src.kind == "bench" then
      S.run.bag[bagHit.idx] = item
      drag = nil
      return
    elseif src.kind == "result" then
      local result = S.benchCommit()
      if not result then snapBackToSource(); drag = nil; return end
      S.run.bag[bagHit.idx] = result
      S.pushLog(("merged: %s"):format(Loot.label(result)))
      Sounds.play("loot")
      drag = nil
      return
    end
    -- bag → bag rearrange is not allowed; fall through to snap-back.
  end

  snapBackToSource()
  drag = nil
end

function Run.mousereleased(x, y, b)
  mousereleasedImpl(x, y, b)
  S.bagCompact()
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
