local C      = require("constants")
local S      = require("state")
local Loot   = require("loot")
local Sounds = require("sounds")

local Combat = {}

local function isAlive(u) return u and u.hp > 0 end

local function pushPopup(target, text, color, scale)
  target.popups = target.popups or {}
  table.insert(target.popups, {
    text  = text,
    color = color or {1, 1, 1, 1},
    age   = 0,
    life  = 0.9,
    dy    = 0,
    scale = scale or 1.0,
  })
end

local function pickTarget(hero, enemies)
  if hero.targetLocked and isAlive(hero.target) then return hero.target end
  hero.targetLocked = false
  for _, e in ipairs(enemies) do
    if isAlive(e) then return e end
  end
  return nil
end

local function attack(attacker, defender, isHeroAttacker)
  if love.math.random() < (defender.dodge or 0) then
    pushPopup(defender, "dodge", {0.7, 0.85, 1, 1}, 0.85)
    Sounds.play("dodge")
    return 0, false, true
  end
  local raw = attacker.atk
  local crit = love.math.random() < (attacker.crit or 0)
  if crit then raw = math.floor(raw * (attacker.critDmg or 1.5)) end
  local taken = math.max(1, raw - (defender.armor or 0))
  defender.hp = math.max(0, defender.hp - taken)
  defender.hitFlash = 0.18

  if crit then
    pushPopup(defender, ("%d!"):format(taken), {1, 0.85, 0.2, 1}, 1.35)
    Sounds.play("crit")
    S.shake = math.max(S.shake, 0.22)
  else
    if isHeroAttacker then
      pushPopup(defender, tostring(taken), {1, 0.95, 0.95, 1}, 1.0)
    else
      pushPopup(defender, ("-%d"):format(taken), {1, 0.5, 0.5, 1}, 1.0)
    end
    Sounds.play("hit")
  end
  return taken, crit, false
end

local function dropLoot(floor)
  local n = love.math.random(1, 3)
  Sounds.play("loot")
  for i = 1, n do
    local item = Loot.roll(floor)
    local ok = S.bagInsertHead(item)
    if ok then
      S.pushLog(("loot: %s"):format(Loot.label(item)))
    else
      S.pushLog(("discarded: %s (bag full)"):format(Loot.label(item)))
    end
  end
end

function Combat.tick(dt)
  local run = S.run
  if not run or run.floorState ~= "fighting" then return end
  local hero = run.hero
  local enemies = run.enemies

  hero.target = pickTarget(hero, enemies)
  if hero.target and isAlive(hero) then
    hero.cd = hero.cd - dt * hero.atkSpd
    if hero.cd <= 0 then
      hero.cd = hero.cd + 1.0
      local dmg, crit, dodged = attack(hero, hero.target, true)
      if dodged then
        S.pushLog(("%s dodged"):format(hero.target.name))
      else
        S.pushLog(("you hit %s for %d%s"):format(hero.target.name, dmg, crit and " (crit!)" or ""))
        if hero.target.hp == 0 then
          S.pushLog(("%s dies"):format(hero.target.name))
          Sounds.play("death")
          dropLoot(run.floor)
          hero.target = nil
          hero.targetLocked = false
        end
      end
    end
  end

  for _, e in ipairs(enemies) do
    if isAlive(e) and isAlive(hero) then
      e.cd = e.cd - dt * e.atkSpd
      if e.cd <= 0 then
        e.cd = e.cd + 1.0
        local dmg, crit, dodged = attack(e, hero, false)
        if dodged then
          S.pushLog("you dodged")
        else
          S.pushLog(("%s hits you for %d%s"):format(e.name, dmg, crit and " (crit!)" or ""))
        end
      end
    end
  end

  local anyAlive = false
  for _, e in ipairs(enemies) do if isAlive(e) then anyAlive = true; break end end

  if not isAlive(hero) then
    run.floorState = "dead"
  elseif not anyAlive then
    run.floorState = "cleared"
  end
end

function Combat.spawnFloor(floor)
  local run = S.run
  run.enemies = {}
  local count = math.min(3, 1 + math.floor((floor - 1) / 4))
  local hpScale  = 1 + (floor - 1) * C.ENEMY_SCALE_PER_FLOOR
  local atkScale = 1 + (floor - 1) * C.ENEMY_ATK_SCALE_PER_FLOOR
  if floor == C.MAX_FLOOR then
    local b = C.BOSS_BASE
    table.insert(run.enemies, {
      name = b.name,
      hpMax = math.floor(b.hpMax * hpScale), hp = math.floor(b.hpMax * hpScale),
      atk = math.floor(b.atk * atkScale), armor = b.armor,
      atkSpd = b.atkSpd, cd = 1.0,
      crit = 0.08, critDmg = 1.4, dodge = 0.0,
    })
  else
    for i = 1, count do
      local base = C.ENEMY_BASE[love.math.random(#C.ENEMY_BASE)]
      table.insert(run.enemies, {
        name = base.name,
        hpMax = math.floor(base.hpMax * hpScale), hp = math.floor(base.hpMax * hpScale),
        atk = math.floor(base.atk * atkScale), armor = base.armor,
        atkSpd = base.atkSpd, cd = 1.0,
        crit = 0.04, critDmg = 1.4, dodge = 0.0,
      })
    end
  end
  run.hero.cd = 1.0 / math.max(0.01, run.hero.atkSpd)
  run.hero.target = nil
  run.hero.targetLocked = false
  run.floorState = "fighting"
end

function Combat.advanceFloor()
  local run = S.run
  if not run then return end
  local healed = math.floor(run.hero.hpMax * C.HEAL_PCT_PER_CLEAR)
  run.hero.hp = math.min(run.hero.hpMax, run.hero.hp + healed)
  run.floor = run.floor + 1
  if run.floor > C.MAX_FLOOR then
    run.floorState = "won"
    Sounds.play("victory")
    return
  end
  Sounds.play("advance")
  Combat.spawnFloor(run.floor)
end

return Combat
