local C      = require("constants")
local S      = require("state")
local Loot   = require("loot")
local Sounds = require("sounds")
local Dust   = require("dust")

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

  local mult = C.STAT_DISPLAY_MULT
  local shown = taken * mult
  if crit then
    pushPopup(defender, ("%d!"):format(shown), {1, 0.85, 0.2, 1}, 1.35)
    Sounds.play("crit")
    S.shake = math.max(S.shake, 0.22)
  else
    if isHeroAttacker then
      pushPopup(defender, tostring(shown), {1, 0.95, 0.95, 1}, 1.0)
    else
      pushPopup(defender, ("-%d"):format(shown), {1, 0.5, 0.5, 1}, 1.0)
    end
    Sounds.play("hit")
  end

  if taken > 0 and (attacker.lifesteal or 0) > 0 and attacker.hpMax then
    local heal = math.max(1, math.floor(taken * attacker.lifesteal))
    local before = attacker.hp
    attacker.hp = math.min(attacker.hpMax, attacker.hp + heal)
    local gained = attacker.hp - before
    if gained > 0 then
      pushPopup(attacker, ("+%d"):format(gained * mult), {0.4, 1, 0.4, 1}, 0.85)
    end
  end

  if taken > 0 and (defender.thorns or 0) > 0 and isAlive(attacker) then
    local reflect = math.max(1, math.floor(taken * defender.thorns))
    attacker.hp = math.max(0, attacker.hp - reflect)
    attacker.hitFlash = 0.18
    pushPopup(attacker, ("-%d ⚘"):format(reflect * mult), {0.8, 0.5, 1, 1}, 0.85)
  end

  return taken, crit, false
end

local function dropLoot(floor, isBoss)
  local n = love.math.random(1, 3)
  Sounds.play("loot")
  local legendaryDropped = false
  for i = 1, n do
    local item = Loot.roll(floor, isBoss, { excludeLegendary = legendaryDropped })
    if item.rarity == #C.RARITY then legendaryDropped = true end
    local ok, ejected = S.bagInsertLeft(item)
    if ok then
      if ejected == item then
        -- All-locked rejection: the new item turned to dust at the entry point.
        local amount = Dust.gainFor(item.rarity)
        S.addDust(amount)
        S.queueDustEvent("gain", amount, item, "bagLeft")
        S.pushLog(("bag fully locked, %s → %d dust"):format(Loot.label(item), amount))
      else
        S.pushLog(("loot: %s"):format(Loot.label(item)))
        if ejected then
          local amount = Dust.gainFor(ejected.rarity)
          S.addDust(amount)
          S.queueDustEvent("gain", amount, ejected, "bagRight")
          S.pushLog(("%s → %d dust"):format(Loot.label(ejected), amount))
        end
      end
    else
      S.pushLog(("discarded: %s (bag full)"):format(Loot.label(item)))
    end
  end
end

function Combat.tick(dt)
  local run = S.run
  if not run or run.roomState ~= "fighting" then return end
  local hero = run.hero
  local enemies = run.enemies

  hero.target = pickTarget(hero, enemies)
  if hero.target and isAlive(hero) then
    hero.cd = hero.cd - dt * hero.atkSpd
    if hero.cd <= 0 then
      hero.cd = hero.cd + 1.0
      local primaryTarget = hero.target
      local dmg, crit, dodged = attack(hero, primaryTarget, true)
      if dodged then
        S.pushLog(("%s dodged"):format(primaryTarget.name))
      else
        S.pushLog(("you hit %s for %d%s"):format(primaryTarget.name, dmg, crit and " (crit!)" or ""))
        if (hero.cleave or 0) > 0 and dmg > 0 then
          local cleaveDmg = math.max(1, math.floor(dmg * hero.cleave))
          for _, e in ipairs(enemies) do
            if e ~= primaryTarget and isAlive(e) then
              e.hp = math.max(0, e.hp - cleaveDmg)
              e.hitFlash = 0.18
              pushPopup(e, ("-%d"):format(cleaveDmg), {1, 0.65, 0.25, 1}, 0.9)
              if e.hp == 0 then
                S.pushLog(("%s dies (cleave)"):format(e.name))
                Sounds.play("death")
                dropLoot(run.room, e.isBoss)
              end
            end
          end
        end
        if primaryTarget.hp == 0 then
          S.pushLog(("%s dies"):format(primaryTarget.name))
          Sounds.play("death")
          dropLoot(run.room, primaryTarget.isBoss)
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
    run.roomState = "dead"
  elseif not anyAlive then
    run.roomState = "cleared"
    Combat.advanceRoom()
  end
end

function Combat.spawnRoom(room)
  local run = S.run
  run.enemies = {}
  local count = math.min(3, 1 + math.floor((room - 1) / 4))
  local hpScale  = 1 + (room - 1) * C.ENEMY_SCALE_PER_ROOM
  local atkScale = 1 + (room - 1) * C.ENEMY_ATK_SCALE_PER_ROOM
  local b = C.BOSS_ROOMS[room]
  if b then
    table.insert(run.enemies, {
      name = b.name,
      hpMax = math.floor(b.hpMax * hpScale), hp = math.floor(b.hpMax * hpScale),
      atk = math.floor(b.atk * atkScale * C.ENEMY_DAMAGE_MULT), armor = b.armor,
      atkSpd = b.atkSpd, cd = 1.0,
      crit = 0.08, critDmg = 1.4, dodge = 0.0,
      isBoss = true,
    })
  else
    for i = 1, count do
      local base = C.ENEMY_BASE[love.math.random(#C.ENEMY_BASE)]
      table.insert(run.enemies, {
        name = base.name,
        hpMax = math.floor(base.hpMax * hpScale), hp = math.floor(base.hpMax * hpScale),
        atk = math.floor(base.atk * atkScale * C.ENEMY_DAMAGE_MULT), armor = base.armor,
        atkSpd = base.atkSpd, cd = 1.0,
        crit = 0.04, critDmg = 1.4, dodge = 0.0,
      })
    end
  end
  run.hero.cd = 1.0 / math.max(0.01, run.hero.atkSpd)
  run.hero.target = nil
  run.hero.targetLocked = false
  run.roomState = "fighting"
end

function Combat.advanceRoom()
  local run = S.run
  if not run then return end
  local hero = run.hero
  local before = hero.hp
  if C.BOSS_ROOMS[run.room] then
    hero.hp = hero.hpMax
  elseif (hero.regen or 0) > 0 then
    hero.hp = math.min(hero.hpMax, hero.hp + hero.regen)
  end
  local gained = hero.hp - before
  if gained > 0 then
    pushPopup(hero, ("+%d"):format(gained * C.STAT_DISPLAY_MULT), {0.4, 1, 0.4, 1}, 1.0)
    Sounds.play("heal")
  end
  run.room = run.room + 1
  if run.room > C.MAX_ROOM then
    run.roomState = "won"
    Sounds.play("victory")
    return
  end
  Sounds.play("advance")
  Combat.spawnRoom(run.room)
end

return Combat
