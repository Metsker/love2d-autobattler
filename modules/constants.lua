local C = {}

C.WIN_W = 1600
C.WIN_H = 900
C.SPLIT_X = 800

C.MAX_FLOOR = 10
C.HEAL_PCT_PER_CLEAR = 0.35

C.ENEMY_SCALE_PER_FLOOR = 0.12
C.ENEMY_ATK_SCALE_PER_FLOOR = 0.08

C.SPEED_LEVELS = { 0, 1, 2, 4 }

C.CLASSES = {
  warrior = { hpMax = 120, atk = 12, armor = 2, atkSpd = 1.0,  crit = 0.05, critDmg = 1.5, dodge = 0.05 },
  rogue   = { hpMax =  80, atk = 10, armor = 0, atkSpd = 1.6,  crit = 0.25, critDmg = 1.8, dodge = 0.15 },
  monk    = { hpMax = 100, atk =  9, armor = 1, atkSpd = 1.3,  crit = 0.10, critDmg = 1.6, dodge = 0.25 },
}

C.ENEMY_BASE = {
  { name = "Slime",    hpMax = 22,  atk = 4,  armor = 0, atkSpd = 0.7 },
  { name = "Skeleton", hpMax = 32,  atk = 6,  armor = 1, atkSpd = 0.9 },
  { name = "Goblin",   hpMax = 26,  atk = 7,  armor = 0, atkSpd = 1.0 },
}

C.BOSS_BASE = { name = "Lich", hpMax = 140, atk = 11, armor = 2, atkSpd = 0.8 }

C.RARITY = {
  { name = "Common",    color = {0.85, 0.85, 0.85, 1}, affixes = 0 },
  { name = "Uncommon",  color = {0.40, 0.95, 0.40, 1}, affixes = 1 },
  { name = "Rare",      color = {0.40, 0.55, 0.95, 1}, affixes = 2 },
  { name = "Epic",      color = {0.75, 0.40, 0.95, 1}, affixes = 3 },
  { name = "Legendary", color = {0.95, 0.70, 0.20, 1}, affixes = 4 },
}

C.RARITY_WEIGHTS = { 50, 30, 14, 5, 1 }

C.ITEM_BASES = {
  { slot = "main",   name = "Sword",   atk = 6,             emoji = "\u{2694}"   },
  { slot = "main",   name = "Mace",    atk = 7, atkSpd=-0.1, emoji = "\u{1F528}" },
  { slot = "off",    name = "Shield",  armor = 3,           emoji = "\u{1F6E1}"  },
  { slot = "head",   name = "Helm",    armor = 2, hpMax=10, emoji = "\u{26D1}"   },
  { slot = "chest",  name = "Armor",   armor = 4, hpMax=20, emoji = "\u{1F9E5}"  },
  { slot = "legs",   name = "Greaves", armor = 2, hpMax=10, emoji = "\u{1F456}"  },
  { slot = "feet",   name = "Boots",   armor = 1, atkSpd=0.1, emoji = "\u{1F462}" },
  { slot = "ring",   name = "Ring",    crit = 0.05,         emoji = "\u{1F48D}"  },
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
