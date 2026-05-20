local C = require("constants")
local Loot = require("loot")

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
    room = 1,
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
    roomState = "fighting",
    bench = { input = { nil, nil }, result = nil },
  }
end

function S.benchRecompute()
  if not S.run then return end
  local b = S.run.bench
  local a, c = b.input[1], b.input[2]
  if a and c and Loot.canMerge(a, c) then
    if b._cachedPair and b._cachedPair[1] == a and b._cachedPair[2] == c and b._cachedResult then
      b.result = b._cachedResult
    else
      b.result = Loot.merge(a, c)
      b._cachedPair = { a, c }
      b._cachedResult = b.result
    end
  else
    b.result = nil
  end
end

function S.benchSet(slot, item)
  if not S.run then return false end
  local b = S.run.bench
  if b.input[slot] then return false end
  if slot == 2 and b.input[1] and not Loot.canMerge(b.input[1], item) then return false end
  if slot == 1 and b.input[2] and not Loot.canMerge(item, b.input[2]) then return false end
  b.input[slot] = item
  S.benchRecompute()
  return true
end

function S.benchTake(slot)
  if not S.run then return nil end
  local b = S.run.bench
  local item = b.input[slot]
  b.input[slot] = nil
  S.benchRecompute()
  return item
end

function S.benchCommit()
  if not S.run then return nil end
  local b = S.run.bench
  local r = b.result
  if not r then return nil end
  b.input[1] = nil
  b.input[2] = nil
  b.result = nil
  b._cachedPair = nil
  b._cachedResult = nil
  return r
end

function S.pushLog(msg)
  if not S.run then return end
  table.insert(S.run.log, msg)
  while #S.run.log > 8 do table.remove(S.run.log, 1) end
end

function S.bagReorder()
  if not S.run then return end
  local bag, locks = S.run.bag, S.run.locks
  local lockedItems, unlockedItems = {}, {}
  for i = 1, C.BAG_SIZE do
    if bag[i] then
      if locks[i] then
        lockedItems[#lockedItems + 1] = bag[i]
      else
        unlockedItems[#unlockedItems + 1] = bag[i]
      end
    end
  end
  table.sort(lockedItems, function(a, b)
    local ar, br = a.rarity or 0, b.rarity or 0
    if ar ~= br then return ar > br end
    return (a.uid or 0) < (b.uid or 0)
  end)
  table.sort(unlockedItems, function(a, b)
    return (a.uid or 0) < (b.uid or 0)
  end)
  for i = 1, C.BAG_SIZE do
    bag[i] = nil
    locks[i] = nil
  end
  local k = 0
  for _, item in ipairs(lockedItems) do
    k = k + 1
    bag[k] = item
    locks[k] = true
  end
  for _, item in ipairs(unlockedItems) do
    k = k + 1
    bag[k] = item
  end
end

function S.bagInsertHead(item)
  if not S.run then return false end
  local bag, locks = S.run.bag, S.run.locks
  for i = 1, C.BAG_SIZE do
    if not bag[i] and not locks[i] then
      bag[i] = item
      S.bagReorder()
      return true
    end
  end
  local worstIdx, worstRarity
  for i = 1, C.BAG_SIZE do
    if bag[i] and not locks[i] then
      local r = bag[i].rarity or 0
      if not worstIdx or r < worstRarity then
        worstIdx = i
        worstRarity = r
      end
    end
  end
  if not worstIdx then return false end
  bag[worstIdx] = item
  S.bagReorder()
  return true
end

function S.bagCompact()
  if not S.run then return end
  local bag, locks = S.run.bag, S.run.locks
  for i = 1, C.BAG_SIZE do
    if locks[i] and not bag[i] then locks[i] = nil end
  end
  S.bagReorder()
end

function S.toggleLock(idx)
  if not S.run then return end
  if not S.run.bag[idx] then return end
  S.run.locks[idx] = not S.run.locks[idx] or nil
  S.bagReorder()
end

return S
