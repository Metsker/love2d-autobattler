local C = {}

C.WIN_W = 1600
C.WIN_H = 900
C.SPLIT_X = 800

C.MAX_ROOM = 30

C.ENEMY_SCALE_PER_ROOM = 0.12
C.ENEMY_ATK_SCALE_PER_ROOM = 0.08
C.ENEMY_DAMAGE_MULT = 1.5

C.SPEED_LEVELS = { 0, 1, 2, 4 }

C.CLASSES = {
  warrior = { hpMax = 120, atk = 12, armor = 2, atkSpd = 1.0,  crit = 0.05, critDmg = 1.5, dodge = 0.05 },
  rogue   = { hpMax =  80, atk = 10, armor = 0, atkSpd = 1.6,  crit = 0.25, critDmg = 1.8, dodge = 0.15 },
  monk    = { hpMax = 100, atk =  9, armor = 1, atkSpd = 1.3,  crit = 0.10, critDmg = 1.6, dodge = 0.25 },
}

C.ENEMY_BASE = {
  { name = "Slime",    hpMax = 28,  atk = 5,  armor = 0, atkSpd = 0.7 },
  { name = "Skeleton", hpMax = 40,  atk = 8,  armor = 1, atkSpd = 0.9 },
  { name = "Goblin",   hpMax = 32,  atk = 9,  armor = 0, atkSpd = 1.0 },
}

C.BOSS_ROOMS = {
  [10] = { name = "Ogre",   hpMax = 110, atk = 10, armor = 3, atkSpd = 0.7 },
  [20] = { name = "Dragon", hpMax = 130, atk = 12, armor = 2, atkSpd = 0.9 },
  [30] = { name = "Lich",   hpMax = 140, atk = 11, armor = 2, atkSpd = 0.8 },
}

C.RARITY = {
  { name = "Common",    color = {0.85, 0.85, 0.85, 1}, affixes = 0 },
  { name = "Uncommon",  color = {0.40, 0.95, 0.40, 1}, affixes = 1 },
  { name = "Rare",      color = {0.40, 0.55, 0.95, 1}, affixes = 2 },
  { name = "Epic",      color = {0.75, 0.40, 0.95, 1}, affixes = 3 },
  { name = "Legendary", color = {0.95, 0.70, 0.20, 1}, affixes = 4 },
}

C.RARITY_WEIGHTS = { 50, 30, 14, 5, 1 }

C.RARITY_BASE_MULT = { 1.0, 1.15, 1.35, 1.6, 2.0 }

C.STAT_LIST = { "atk", "armor", "hpMax", "atkSpd", "crit", "critDmg", "dodge", "regen" }
C.ATTACK_STAT_LIST  = { "atk", "atkSpd", "crit", "critDmg" }
C.DEFENSE_STAT_LIST = { "armor", "hpMax", "dodge" }
C.JEWELRY_STAT_LIST = { "crit", "critDmg", "dodge", "regen" }

C.WEAPON_SLOTS  = { main = true, off = true }
C.ARMOR_SLOTS   = { head = true, chest = true, legs = true, feet = true }
C.JEWELRY_SLOTS = { ring = true, amulet = true }

-- Per-stat tiers. T1-T3 reachable via fresh loot drops; T4-T5 only via merging.
C.AFFIX_TIERS = {
  atk     = { float = false, pct = false, tiers = {{1,2},{3,4},{5,6},{7,9},{10,13}} },
  armor   = { float = false, pct = false, tiers = {{1,1},{2,2},{3,3},{4,5},{6,7}} },
  hpMax   = { float = false, pct = false, tiers = {{5,10},{11,15},{16,20},{21,30},{31,45}} },
  atkSpd  = { float = true,  pct = false, tiers = {{0.05,0.10},{0.11,0.15},{0.16,0.20},{0.21,0.30},{0.31,0.45}} },
  crit    = { float = true,  pct = true,  tiers = {{0.04,0.06},{0.08,0.12},{0.14,0.20},{0.22,0.30},{0.32,0.40}} },
  critDmg = { float = true,  pct = true,  tiers = {{0.10,0.15},{0.16,0.25},{0.26,0.40},{0.41,0.60},{0.61,0.80}} },
  dodge   = { float = true,  pct = true,  tiers = {{0.02,0.03},{0.04,0.05},{0.06,0.08},{0.09,0.12},{0.13,0.18}} },
  regen   = { float = false, pct = false, tiers = {{1,2},{3,4},{5,6},{7,9},{10,13}} },
}

C.TIER_DROP_MAX = 3                       -- fresh drops roll only T1-T3
C.TIER_WEIGHTS_MERGE = { 50, 25, 15, 8, 2 } -- T1..T5

C.UNIQUE_AFFIXES = {
  cleave    = { theme = "offense", float = true, pct = true,  tiers = {{0.10,0.15},{0.16,0.20},{0.21,0.25},{0.26,0.32},{0.33,0.40}} },
  lifesteal = { theme = "offense", float = true, pct = true,  tiers = {{0.05,0.08},{0.09,0.12},{0.13,0.16},{0.17,0.20},{0.21,0.25}} },
  thorns    = { theme = "defense", float = true, pct = true,  tiers = {{0.15,0.20},{0.21,0.25},{0.26,0.30},{0.31,0.35},{0.36,0.45}} },
}

C.UNIQUE_COLOR = {0.95, 0.6, 0.2, 1}

C.STAT_DISPLAY_MULT = 10
C.STAT_DISPLAY_EXCLUDE = { crit = true, critDmg = true, dodge = true }

C.TIER_COLOR = {
  {0.75, 0.75, 0.75, 1}, -- T1 grey
  {0.55, 0.85, 0.55, 1}, -- T2 green
  {0.45, 0.65, 0.95, 1}, -- T3 blue
  {0.80, 0.50, 0.95, 1}, -- T4 purple
  {0.95, 0.75, 0.30, 1}, -- T5 gold
}

C.ITEM_BASES = {
  { slot = "main",   name = "Sword",   atk = 6,             emoji = "\u{2694}"   },
  { slot = "main",   name = "Mace",    atk = 7, atkSpd=-0.1, emoji = "\u{1F528}" },
  { slot = "off",    name = "Shield",  armor = 3,           emoji = "\u{1F6E1}"  },
  { slot = "head",   name = "Helm",    armor = 2, hpMax=10, emoji = "\u{26D1}"   },
  { slot = "chest",  name = "Armor",   armor = 4, hpMax=20, emoji = "\u{1F9E5}"  },
  { slot = "legs",   name = "Greaves", armor = 2, hpMax=10, emoji = "\u{1F456}"  },
  { slot = "feet",   name = "Boots",   armor = 1, atkSpd=0.1, emoji = "\u{1F462}" },
  { slot = "ring",   name = "Ring",    crit = 0.10,         emoji = "\u{1F48D}"  },
  { slot = "amulet", name = "Amulet",  critDmg = 0.2,       emoji = "\u{1F4FF}"  },
}

C.SLOT_EMOJI = {
  head   = "\u{26D1}",
  amulet = "\u{1F4FF}",
  chest  = "\u{1F9E5}",
  main   = "\u{2694}",
  off    = "\u{1F6E1}",
  legs   = "\u{1F456}",
  ring   = "\u{1F48D}",
  feet   = "\u{1F462}",
}

C.CLASS_EMOJI = {
  warrior = "\u{2694}",
  rogue   = "\u{1F5E1}",
  monk    = "\u{1F94B}",
}

C.HERO_EMOJI = "\u{1F9D1}"

C.ENEMY_EMOJI = {
  Slime    = "\u{1F47E}",
  Skeleton = "\u{1F480}",
  Goblin   = "\u{1F479}",
  Ogre     = "\u{1F9CC}",
  Dragon   = "\u{1F409}",
  Lich     = "\u{1F9D9}",
}

C.SLOT_ORDER = { "head", "amulet", "chest", "main", "off", "legs", "ring", "feet" }
C.SLOT_LABEL = {
  head = "Head", amulet = "Amulet", chest = "Chest", main = "Main",
  off = "Off",  legs = "Legs",     ring = "Ring",   feet = "Feet",
}

C.BAG_COLS = 7
C.BAG_ROWS = 4
C.BAG_SIZE = C.BAG_COLS * C.BAG_ROWS

C.SAVE_VERSION = 1
C.SAVE_FILE    = "save.lua"

return C
