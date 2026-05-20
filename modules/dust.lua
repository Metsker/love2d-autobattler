local Dust = {}

Dust.GAIN_BY_RARITY = { 1, 3, 6, 10, 15 }
Dust.MERGE_COST = { [2] = 5, [3] = 12, [4] = 22, [5] = 35 }

function Dust.gainFor(rarity)
  return Dust.GAIN_BY_RARITY[rarity] or 0
end

function Dust.mergeCost(targetRarity)
  return Dust.MERGE_COST[targetRarity] or 0
end

return Dust
