local C = require("constants")

local Loot = {}

local nextUid = 1
local function assignUid()
  local u = nextUid
  nextUid = nextUid + 1
  return u
end

local function pickWeighted(weights)
  local total = 0
  for _, w in ipairs(weights) do total = total + w end
  local r = love.math.random() * total
  local acc = 0
  for i, w in ipairs(weights) do
    acc = acc + w
    if r <= acc then return i end
  end
  return #weights
end

local function rollValue(def, tier)
  local lo, hi = def.tiers[tier][1], def.tiers[tier][2]
  local raw = lo + love.math.random() * (hi - lo)
  if def.float then return raw end
  return math.floor(raw + 0.5)
end

local function statPoolForSlot(slot)
  if C.WEAPON_SLOTS[slot] then return C.ATTACK_STAT_LIST end
  if C.ARMOR_SLOTS[slot] then return C.DEFENSE_STAT_LIST end
  if C.JEWELRY_SLOTS[slot] then return C.JEWELRY_STAT_LIST end
  return C.STAT_LIST
end

local function uniquePoolForSlot(slot)
  if C.WEAPON_SLOTS[slot] then return { "cleave", "lifesteal" } end
  if C.ARMOR_SLOTS[slot] then return { "thorns" } end
  return { "cleave", "lifesteal", "thorns" }
end

local function rollFreshAffix(tierMax, slot)
  local pool = statPoolForSlot(slot)
  local stat = pool[love.math.random(#pool)]
  local def = C.AFFIX_TIERS[stat]
  local tier = love.math.random(tierMax)
  return { stat = stat, value = rollValue(def, tier), pct = def.pct, tier = tier }
end

local function rollAffixAtTier(tier, slot)
  local pool = statPoolForSlot(slot)
  local stat = pool[love.math.random(#pool)]
  local def = C.AFFIX_TIERS[stat]
  return { stat = stat, value = rollValue(def, tier), pct = def.pct, tier = tier }
end

local function rollUniqueAffix(slot, tierMax)
  local pool = uniquePoolForSlot(slot)
  local stat = pool[love.math.random(#pool)]
  local def = C.UNIQUE_AFFIXES[stat]
  local tier = love.math.random(tierMax)
  return { stat = stat, value = rollValue(def, tier), pct = def.pct, tier = tier }
end

local function pickRarity(maxIdx)
  maxIdx = maxIdx or #C.RARITY_WEIGHTS
  local total = 0
  for i = 1, maxIdx do total = total + C.RARITY_WEIGHTS[i] end
  local roll = love.math.random() * total
  local acc = 0
  for i = 1, maxIdx do
    acc = acc + C.RARITY_WEIGHTS[i]
    if roll <= acc then return i end
  end
  return 1
end

local function scaleBaseValue(v, mult)
  if not v or v == 0 then return 0 end
  if math.abs(v) < 1 then return v * mult end
  if v < 0 then return -math.ceil(-v * mult) end
  return math.ceil(v * mult)
end

local function emptyBase(base, rarity)
  local mult = C.RARITY_BASE_MULT[rarity or 1] or 1.0
  return {
    atk     = scaleBaseValue(base.atk,     mult),
    armor   = scaleBaseValue(base.armor,   mult),
    hpMax   = scaleBaseValue(base.hpMax,   mult),
    atkSpd  = scaleBaseValue(base.atkSpd,  mult),
    crit    = scaleBaseValue(base.crit,    mult),
    critDmg = scaleBaseValue(base.critDmg, mult),
    dodge   = scaleBaseValue(base.dodge,   mult),
  }
end

local function rawBaseByName(name)
  for _, b in ipairs(C.ITEM_BASES) do
    if b.name == name then return b end
  end
  return nil
end

function Loot.roll(room, isBoss)
  local base = C.ITEM_BASES[love.math.random(#C.ITEM_BASES)]
  local rIdx
  if isBoss and love.math.random() < 0.5 then
    rIdx = #C.RARITY
  else
    rIdx = pickRarity(#C.RARITY - 1)
  end
  local rarity = C.RARITY[rIdx]
  local item = {
    uid     = assignUid(),
    slot    = base.slot,
    name    = base.name,
    emoji   = base.emoji,
    rarity  = rIdx,
    base    = emptyBase(base, rIdx),
    affixes = {},
  }
  for i = 1, rarity.affixes do
    item.affixes[i] = rollFreshAffix(C.TIER_DROP_MAX, base.slot)
  end
  if rIdx == #C.RARITY then
    item.unique = rollUniqueAffix(base.slot, C.TIER_DROP_MAX)
  end
  return item
end

function Loot.canMerge(a, b)
  if not a or not b then return false end
  if a.slot ~= b.slot then return false end
  if a.rarity ~= b.rarity then return false end
  if a.rarity >= #C.RARITY then return false end
  return true
end

function Loot.merge(a, b)
  if not Loot.canMerge(a, b) then return nil end
  local newRarity = a.rarity + 1

  local newAffixes = {}
  for _, af in ipairs(a.affixes) do newAffixes[#newAffixes + 1] = af end
  for _, af in ipairs(b.affixes) do newAffixes[#newAffixes + 1] = af end

  local source = (love.math.random() < 0.5) and a or b

  if #newAffixes == 0 then
    local tier = pickWeighted(C.TIER_WEIGHTS_MERGE)
    newAffixes[1] = rollAffixAtTier(tier, source.slot)
  end

  local raw = rawBaseByName(source.name) or source.base
  local result = {
    uid     = assignUid(),
    slot    = source.slot,
    name    = source.name,
    emoji   = source.emoji,
    rarity  = newRarity,
    base    = emptyBase(raw, newRarity),
    affixes = newAffixes,
  }
  if newRarity == #C.RARITY then
    result.unique = rollUniqueAffix(source.slot, C.TIER_DROP_MAX)
  end
  return result
end

function Loot.tierFromValue(stat, value)
  if not value or value <= 0 then return nil, false end
  local def = C.AFFIX_TIERS[stat]
  if not def then return nil, false end
  local tiers = def.tiers
  if value > tiers[#tiers][2] then return #tiers, true end
  for i = 1, #tiers do
    if value <= tiers[i][2] then return i, false end
  end
  return #tiers, true
end

local STAT_ORDER_IDX
function Loot.groupedAffixes(item)
  if not STAT_ORDER_IDX then
    STAT_ORDER_IDX = {}
    for i, s in ipairs(C.STAT_LIST) do STAT_ORDER_IDX[s] = i end
  end
  local groups, map = {}, {}
  for _, af in ipairs(item.affixes) do
    local g = map[af.stat]
    if not g then
      local def = C.AFFIX_TIERS[af.stat]
      g = { stat = af.stat, total = 0, count = 0, pct = def and def.pct or false }
      map[af.stat] = g
      groups[#groups + 1] = g
    end
    g.total = g.total + af.value
    g.count = g.count + 1
  end
  for _, g in ipairs(groups) do
    g.tier, g.overflow = Loot.tierFromValue(g.stat, g.total)
  end
  table.sort(groups, function(x, y)
    local xt, yt = x.tier or 0, y.tier or 0
    if xt ~= yt then return xt > yt end
    if x.total ~= y.total then return x.total > y.total end
    return STAT_ORDER_IDX[x.stat] < STAT_ORDER_IDX[y.stat]
  end)
  return groups
end

function Loot.statSum(item, stat)
  local s = item.base[stat] or 0
  for _, a in ipairs(item.affixes) do
    if a.stat == stat then s = s + a.value end
  end
  if item.unique and item.unique.stat == stat then
    s = s + item.unique.value
  end
  return s
end

function Loot.label(item)
  local rarity = C.RARITY[item.rarity]
  return ("%s %s"):format(rarity.name, item.name)
end

return Loot
