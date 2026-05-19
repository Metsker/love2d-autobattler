local C = require("constants")

local Loot = {}

local AFFIX_POOL = {
  { stat = "atk",     low = 1,    high = 5,    pct = false },
  { stat = "armor",   low = 1,    high = 4,    pct = false },
  { stat = "hpMax",   low = 5,    high = 25,   pct = false },
  { stat = "atkSpd",  low = 0.05, high = 0.25, pct = false },
  { stat = "crit",    low = 0.02, high = 0.10, pct = true  },
  { stat = "critDmg", low = 0.10, high = 0.40, pct = true  },
  { stat = "dodge",   low = 0.02, high = 0.08, pct = true  },
}

local function pickRarity()
  local total = 0
  for _, w in ipairs(C.RARITY_WEIGHTS) do total = total + w end
  local roll = love.math.random() * total
  local acc = 0
  for i, w in ipairs(C.RARITY_WEIGHTS) do
    acc = acc + w
    if roll <= acc then return i end
  end
  return 1
end

local function rollAffix()
  local def = AFFIX_POOL[love.math.random(#AFFIX_POOL)]
  local raw = def.low + love.math.random() * (def.high - def.low)
  local val = def.pct and raw or math.floor(raw + 0.5)
  return { stat = def.stat, value = val, pct = def.pct }
end

function Loot.roll(floor)
  local base = C.ITEM_BASES[love.math.random(#C.ITEM_BASES)]
  local rIdx = pickRarity()
  local rarity = C.RARITY[rIdx]
  local item = {
    slot   = base.slot,
    name   = base.name,
    emoji  = base.emoji,
    rarity = rIdx,
    base   = {
      atk     = base.atk     or 0,
      armor   = base.armor   or 0,
      hpMax   = base.hpMax   or 0,
      atkSpd  = base.atkSpd  or 0,
      crit    = base.crit    or 0,
      critDmg = base.critDmg or 0,
      dodge   = base.dodge   or 0,
    },
    affixes = {},
  }
  for i = 1, rarity.affixes do
    item.affixes[i] = rollAffix()
  end
  return item
end

function Loot.statSum(item, stat)
  local s = item.base[stat] or 0
  for _, a in ipairs(item.affixes) do
    if a.stat == stat then s = s + a.value end
  end
  return s
end

function Loot.label(item)
  local rarity = C.RARITY[item.rarity]
  return ("%s %s"):format(rarity.name, item.name)
end

return Loot
