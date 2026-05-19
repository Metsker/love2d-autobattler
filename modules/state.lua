local C = require("constants")

local S = {}

S.scene = "title"
S.speed = 1
S.shake = 0

S.unlocks = {
  classes = { warrior = true, rogue = false, monk = false },
  bossKills = 0,
}

S.run = nil

local function emptyBag()
  local bag = {}
  for i = 1, C.BAG_SIZE do bag[i] = nil end
  return bag
end

local function emptyEquip()
  local e = {}
  for _, slot in ipairs(C.SLOT_ORDER) do e[slot] = nil end
  return e
end

function S.newRun(className)
  local cls = C.CLASSES[className]
  S.run = {
    class = className,
    floor = 1,
    hero = {
      hpMax   = cls.hpMax,
      hp      = cls.hpMax,
      atk     = cls.atk,
      armor   = cls.armor,
      atkSpd  = cls.atkSpd,
      crit    = cls.crit,
      critDmg = cls.critDmg,
      dodge   = cls.dodge,
      cd      = 0,
      target  = nil,
      targetLocked = false,
    },
    enemies = {},
    bag = emptyBag(),
    locks = {},
    equip = emptyEquip(),
    log = {},
    floorState = "fighting",
  }
end

function S.pushLog(msg)
  if not S.run then return end
  table.insert(S.run.log, msg)
  while #S.run.log > 8 do table.remove(S.run.log, 1) end
end

function S.bagInsertHead(item)
  if not S.run then return false end
  if S.run.locks[1] then return false end
  local bag, locks = S.run.bag, S.run.locks
  local unlocked = {}
  for i = 1, C.BAG_SIZE do
    if not locks[i] then unlocked[#unlocked + 1] = i end
  end
  local n = #unlocked
  if n == 0 then return false end
  local items = { item }
  for k = 1, n - 1 do
    items[k + 1] = bag[unlocked[k]]
  end
  for k = 1, n do
    bag[unlocked[k]] = items[k]
  end
  return true
end

function S.toggleLock(idx)
  if not S.run then return end
  if not S.run.bag[idx] then return end
  S.run.locks[idx] = not S.run.locks[idx]
end

return S
