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
    dust = 0,
  }
end

function S.addDust(amount)
  if not S.run or amount == 0 then return 0 end
  S.run.dust = (S.run.dust or 0) + amount
  if S.run.dust < 0 then S.run.dust = 0 end
  return S.run.dust
end

-- Pending dust events awaiting visual processing by the renderer.
-- Each entry: { kind = "gain"|"spend", amount, item?, origin? }
--   item: the item that turned into dust (for shrink-fade visual)
--   origin: "bagRight" (overflow ejection), "bagLeft" (all-locked rejection),
--           "equip:<slot>" (equip-swap destruction), or nil (no specific origin)
S.pendingDustEvents = {}

function S.queueDustEvent(kind, amount, item, origin)
  table.insert(S.pendingDustEvents, {
    kind = kind, amount = amount or 0, item = item, origin = origin,
  })
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

-- Strict left-to-right FIFO conveyor.
-- Locks are pins at their current slot. Unlocked items pack into the remaining
-- slots in insertion order, newest-first (left), oldest-last (right).
function S.bagReorder()
  if not S.run then return end
  local bag, locks = S.run.bag, S.run.locks
  local lockedAt = {}
  local unlockedItems = {}
  for i = 1, C.BAG_SIZE do
    if bag[i] then
      if locks[i] then
        lockedAt[i] = bag[i]
      else
        unlockedItems[#unlockedItems + 1] = bag[i]
      end
    end
  end
  -- Newest first (left), oldest last (right). Rightmost = next to die.
  table.sort(unlockedItems, function(a, b)
    return (a.uid or 0) > (b.uid or 0)
  end)
  for i = 1, C.BAG_SIZE do
    bag[i] = nil
    locks[i] = nil
  end
  local cursor = 1
  for _, item in ipairs(unlockedItems) do
    while lockedAt[cursor] do
      bag[cursor] = lockedAt[cursor]
      locks[cursor] = true
      cursor = cursor + 1
    end
    if cursor > C.BAG_SIZE then break end
    bag[cursor] = item
    cursor = cursor + 1
  end
  -- Pinned locks past the last unlocked item still need to land in place.
  for i = cursor, C.BAG_SIZE do
    if lockedAt[i] then
      bag[i] = lockedAt[i]
      locks[i] = true
    end
  end
end

-- Insert at the left end of the conveyor.
-- Returns: ok (bool), ejected (item|nil). When the bag is full an unlocked
-- rightmost item is ejected. When fully locked the incoming item is rejected
-- as ejected (so the caller can grant dust for it).
function S.bagInsertLeft(item)
  if not S.run then return false, nil end
  local bag, locks = S.run.bag, S.run.locks
  local hasFreeUnlocked = false
  for i = 1, C.BAG_SIZE do
    if not bag[i] and not locks[i] then hasFreeUnlocked = true; break end
  end
  if hasFreeUnlocked then
    -- Drop into any unlocked slot; bagReorder will sort by uid desc.
    for i = 1, C.BAG_SIZE do
      if not bag[i] and not locks[i] then
        bag[i] = item
        S.bagReorder()
        return true, nil
      end
    end
  end
  -- No free slot. Find the rightmost-unlocked item and eject it.
  local ejectIdx
  for i = C.BAG_SIZE, 1, -1 do
    if bag[i] and not locks[i] then ejectIdx = i; break end
  end
  if not ejectIdx then
    -- Everything is locked: the incoming item itself is ejected.
    return true, item
  end
  local ejected = bag[ejectIdx]
  bag[ejectIdx] = item
  S.bagReorder()
  return true, ejected
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
