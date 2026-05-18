# Civilizations, Units and Technology Tree

> Data extracted directly from project resources (`resources/`).
> Ages: **0** Dark Age · **1** Feudal Age · **2** Castle Age · **3** Imperial Age.

---

## Common Buildings

| Building | Cost | Min Age | HP | Function |
|---|---|---|---|---|
| Town Center | 275 wood | 0 | 2400 | Trains villagers · drop-off · hero respawn |
| House | 25 wood | 0 | 550 | +5 population cap |
| Barracks | 175 wood | 0 | 1200 | Trains infantry |
| Stable | 175 wood | 0 | 1100 | Trains cavalry |
| Blacksmith | 150 wood | 1 | 1000 | Researches weapon and armour upgrades |
| Market | 175 wood | 1 | 900 | Resource trading |
| Lumber Camp | 100 wood | 0 | 600 | Wood drop-off |
| Mining Camp | 100 wood | 0 | 600 | Gold / stone drop-off |
| Farm | 60 wood | 0 | 300 | Continuous food source |
| Dock | 150 wood | 0 | 1800 | Trains ships |
| Siege Workshop | 200 wood | 2 | 1200 | Trains siege units |
| University | 200 wood | 2 | 1100 | Advanced technology research |
| Temple | 175 wood | 2 | 900 | Morale and healing research |
| Wall Segment | 5 stone | 0 | 700 | Defensive barrier |
| Gate | 30 wood | 0 | 500 | Allied passage |
| Fish Trap | 75 wood | 0 | 600 | Passive food source (ocean) |
| Wonder | 2500w+2500f+2500s+5000g | 3 | — | Victory condition |

---

## Common Units

### Villagers (Town Center)
| Unit | Cost | Time | HP | Speed | Attack | Range |
|---|---|---|---|---|---|---|
| Villager | 50 food | 25 s | 25 | 120 | 3 | 1.5 |

### Infantry (Barracks)
| Unit | Age | Cost | Time | HP | Speed | Attack | Range | Armour M/P |
|---|---|---|---|---|---|---|---|---|
| Militia | 0 | 60f + 20w | 21 s | 40 | 100 | 4 | 1.5 | 0 / 0 |
| Archer | 1 | 25w + 45g | 35 s | 30 | 110 | 5 | 4.0 | 0 / 0 |
| Man-at-Arms | 1 | 60f + 20w | 21 s | 65 | 100 | 7 | 1.5 | 1 / 0 |
| Pikeman | 2 | 60f + 30g | 28 s | 65 | 90 | 7 | 1.5 | 1 / 0 |
| Long Swordsman | 2 | 60f + 20w | 21 s | 85 | 100 | 9 | 1.5 | 2 / 1 |

### Cavalry (Stable)
| Unit | Age | Cost | Time | HP | Speed | Attack | Range | Armour M/P | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Scout | 0 | 80f | 30 s | 35 | 180 | 2 | 0.8 | 0 / 0 | Explore ability (60 s) |
| Heavy Scout | 1 | 80f + 30g | 30 s | 80 | 130 | 6 | 1.5 | 1 / 0 | |
| Knight | 2 | 60f + 75g | 45 s | 120 | 115 | 9 | 1.5 | 2 / 1 | |

> **Scout — Explore ability (key E):** The Scout autonomously roams the map for **60 seconds**, picking a new random destination every 3–7 s. Can be cancelled with the same button.

### Siege (Siege Workshop)
| Unit | Age | Cost | Time | HP | Speed | Attack | Range | Notes |
|---|---|---|---|---|---|---|---|---|
| Battering Ram | 2 | 160w | 60 s | 180 | 55 | 40 | 1.0 | ×3 damage vs buildings · pop 2 |
| Mangonel | 2 | 160w + 135g | 60 s | 90 | 60 | 35 | 7.0 | AoE 72 px · minimum range · pop 2 |
| Trebuchet | 3 | 200w + 200g | 70 s | 70 | 48 | 200 | 12.0 | Deploys in 3 s · auto-undeploys on move · pop 2 |

### Naval (Dock)
| Unit | Age | Cost | Time | HP | Speed | Attack | Range |
|---|---|---|---|---|---|---|---|
| Fishing Boat | 0 | 75w | 25 s | 45 | 90 | 0 | — |
| Transport Ship | 1 | 125w | 45 s | 150 | 80 | 0 | — |
| War Galley | 1 | 75w + 35g | 35 s | 120 | 85 | 6 | 5.5 |

---

## Technology Tree

### Blacksmith
| Technology | Age | Cost | Time | Prerequisite | Effect |
|---|---|---|---|---|---|
| Loom | 0 | 50f | 25 s | — | Villager HP ×1.15 |
| Forging | 1 | 75f | 40 s | — | Unit attack ×1.15 |
| Iron Casting | 2 | 150g | 55 s | Forging | Unit attack ×1.20 |
| Blast Furnace | 3 | 275f + 225g | 50 s | — | Unit attack ×1.15 |
| Scale Barding | 1 | 100f + 50g | 40 s | — | Unit melee armour +1 |
| Chain Barding | 2 | 200f + 100g | 45 s | Scale Barding | Unit melee armour +1 |
| Plate Barding | 3 | 300f + 200g | 60 s | Chain Barding | Unit melee armour +1 |
| Padded Archer Armour | 1 | 100f | 35 s | — | Archer pierce armour +1 |
| Fletching | 1 | 100g | 35 s | — | Archer attack ×1.20 |
| Bodkin Arrow | 2 | 100f + 150g | 35 s | Fletching | Archer attack ×1.20 · Range ×1.10 |
| Shipwright | 1 | 200w + 60g | 40 s | — | Ship HP ×1.15 · Cost −15% |

### University
| Technology | Age | Cost | Time | Prerequisite | Effect |
|---|---|---|---|---|---|
| Ballistics | 2 | 175g | 50 s | Fletching | Archer attack speed ×1.20 |
| Chemistry | 3 | 300g | 70 s | Ballistics | Archer attack ×1.15 |
| Siege Engineering | 2 | 200g | 60 s | — | Damage vs buildings ×1.20 |

### Temple (Monastery)
| Technology | Age | Cost | Time | Prerequisite | Effect |
|---|---|---|---|---|---|
| Fervor | 2 | 150g | 50 s | — | Unit move speed ×1.10 |
| Sanctity | 2 | 100f | 40 s | — | Swordsman HP ×1.15 |
| Atonement | 3 | 150f + 100g | 55 s | Sanctity | Cavalry HP ×1.20 |

### Unit Upgrades

Unit upgrade technologies transform all existing units of the source type immediately (HP scaled proportionally). The building then trains the new unit type going forward. Researched at the same building that trains the unit.

#### Barracks
| Technology | Age | Cost | Time | Prerequisite | Transforms |
|---|---|---|---|---|---|
| Man-at-Arms | 1 | 100f + 40g | 45 s | — | Militia → Man-at-Arms |
| Long Swordsman | 2 | 200f + 60g | 45 s | Man-at-Arms | Man-at-Arms → Long Swordsman |

#### Stable
| Technology | Age | Cost | Time | Prerequisite | Transforms |
|---|---|---|---|---|---|
| Heavy Scout | 1 | 150f + 75g | 45 s | — | Scout → Heavy Scout |
| Knight | 2 | 200f + 100g | 45 s | Heavy Scout | Heavy Scout → Knight |

---

## Civilizations

### Guanches
| Field | Value |
|---|---|
| **Hero** | Bencomo |
| **Ability** | *Menceyes Charge* — Rallies nearby allied units, granting +30% attack speed for 10 s · Cooldown 50 s |
| **Unique Unit** | Menceyes Guard |
| **Bonuses** | Stone building HP ×1.20 · Spears available in Dark Age · Can traverse malpais terrain |
| **Restrictions** | No cavalry · No gunpowder |

**Strategy:** Defensive fortress with resilient infantry. Strong on volcanic maps.

---

### Canarii
| Field | Value |
|---|---|
| **Hero** | Doramas |
| **Ability** | *Challenge* — Taunts the nearest enemy unit, forcing it to attack Doramas for 6 s · Cooldown 45 s |
| **Unique Unit** | Ravine Archer |
| **Bonuses** | Villagers gather food ×1.15 · Archer food cost ×0.80 |
| **Restrictions** | No heavy cavalry |

**Strategy:** Superior food economy + cheap archers. Great for early archer rushes.

---

### Mahos
| Field | Value |
|---|---|
| **Hero** | Guadarfía |
| **Ability** | *Ambush* — Nearly invisible for 8 s; enemies cannot auto-attack Guadarfía while cloaked · Cooldown 45 s |
| **Unique Unit** | Sand Raider |
| **Bonuses** | Building wood cost ×0.70 · Scout / light cavalry speed ×1.25 · Can traverse dunes |
| **Restrictions** | No heavy cavalry upgrades |

**Strategy:** Fast cheap expansion + light cavalry raids. Excellent on arid maps.

---

### Franks
| Field | Value |
|---|---|
| **Hero** | Jean de Béthencourt |
| **Ability** | *Forced Diplomacy* — Converts the nearest enemy unit for 12 s · Cooldown 60 s |
| **Unique Unit** | Chevalier Normand |
| **Bonuses** | Age advance cost ×0.85 · Cavalry HP ×1.15 · Farm build speed ×1.20 |
| **Restrictions** | No full archery · No late naval |

**Strategy:** Fast age advancement + powerful cavalry. Strong pressure in Castle Age.

---

### Britons
| Field | Value |
|---|---|
| **Hero** | Francis Drake |
| **Ability** | *Plunder* — Earns 15 gold for each enemy unit killed within range for 20 s · Cooldown 55 s |
| **Unique Unit** | Longbowman |
| **Bonuses** | Archer range +1 per age advanced · Warship attack speed ×1.20 |
| **Restrictions** | No heavy cavalry upgrades |

**Strategy:** Naval dominance + long-range archers. Very effective on Islands maps.

---

### Castellanos
| Field | Value |
|---|---|
| **Hero** | Don Quijote |
| **Ability** | *Knight Errant Charge* — Charges forward in a straight line, dealing heavy damage to all units in the path · Cooldown 55 s |
| **Unique Unit** | Conquistador |
| **Bonuses** | Swordsman HP ×1.15 · Tower / castle range ×1.10 · Free Blacksmith technology per age advance |
| **Restrictions** | None |

**Strategy:** Well-rounded civilisation with no restrictions. Snowballs hard in late game with free technologies.

---

### Atlantes
| Field | Value |
|---|---|
| **Hero** | Artaxerax |
| **Ability** | *Calima* — Shrouds nearby allied units in a calima veil for 12 s; cloaked units cannot be targeted by enemies · Cooldown 60 s |
| **Unique Unit** | Tidecaller |
| **Bonuses** | Coastal vision ×1.50 · Ship attack speed ×1.20 · No shallow water penalty · Can traverse ocean |
| **Restrictions** | No heavy cavalry · No siege workshop |

**Strategy:** Absolute naval supremacy. Devastating on coastal and Islands maps.

---

### Fenicios
| Field | Value |
|---|---|
| **Hero** | Hannón el Navegante |
| **Ability** | *Trade Route* — Generates 50 gold over 30 s · Cooldown 50 s |
| **Unique Unit** | Trireme |
| **Bonuses** | Market available from Dark Age · Merchant ships generate passive gold |
| **Restrictions** | No knights · No castle infantry |

**Strategy:** Superior gold economy from minute one. Ideal for funding expensive technologies and units.

---

## Heroes — Quick Reference

| Hero | Civilisation | HP | Speed | Attack | Range | Armour M/P | Ability | Cooldown |
|---|---|---|---|---|---|---|---|---|
| Bencomo | Guanches | 180 | 105 | 14 | 1.5 | 3/1 | +30% attack speed allies 10 s | 50 s |
| Doramas | Canarii | 160 | 115 | 12 | 1.5 | 2/2 | Taunt enemy 6 s | 45 s |
| Guadarfía | Mahos | 140 | 130 | 11 | 1.5 | 1/2 | Cloak 8 s | 45 s |
| Jean de Béthencourt | Franks | 150 | 110 | 11 | 1.5 | 3/2 | Convert enemy 12 s | 60 s |
| Francis Drake | Britons | 145 | 120 | 10 | 3.5 | 1/3 | 15 gold/kill for 20 s | 55 s |
| Don Quijote | Castellanos | 170 | 125 | 16 | 1.5 | 4/1 | Straight-line charge | 55 s |
| Artaxerax | Atlantes | 155 | 110 | 10 | 4.0 | 2/3 | Cloak allies 12 s | 60 s |
| Hannón el Navegante | Fenicios | 135 | 105 | 8 | 3.5 | 1/2 | 50 gold over 30 s | 50 s |
