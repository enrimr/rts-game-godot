# Calima Kingdoms: Flames of the Atlantic — Gameplay Guide

A quick reference for controls, units, buildings, and strategy tips.

---

## Controls

### Camera

| Action | Input |
|---|---|
| Pan camera | W / A / S / D  or  Arrow keys |
| Edge-scroll | Move mouse to screen edge |
| Middle-click drag | Pan freely |
| Scroll wheel | Zoom in / out |
| Follow selected units | Click **Follow** button (bottom panel) |

### Selection

| Action | Input |
|---|---|
| Select unit or building | Left-click |
| Box-select multiple units | Left-click drag |
| Select up to 40 units at once | Drag over them |

### Orders

| Action | Input |
|---|---|
| Move selected units | Right-click on empty ground |
| Attack enemy unit or building | Right-click on enemy |
| Gather resource | Right-click on resource node |
| Move to minimap position | Right-click on minimap |
| Stop | X (while units selected) |
| Destroy selected unit/building | Delete |

### Building placement

| Action | Input |
|---|---|
| Rotate ghost 90° | R |
| Place building | Left-click on valid spot |
| Cancel placement | Right-click or Escape |

### Action shortcuts (bottom panel)

Shortcut keys are shown in brackets on each button, e.g. **[V] Villager**.

| Building selected | Available shortcuts |
|---|---|
| Town Center | V — train Villager, A — Advance Age |
| Barracks | M — Militia, A — Archer (Feudal+), P — Pikeman (Castle+) |
| Villager selected | B — Build menu, C — Gather Wood, G — Gather Gold, T — Gather Stone, H — Gather Food, X — Stop |

---

## Resources

| Resource | Source | Used for |
|---|---|---|
| **Food** | Sheep, deer, berries, farms | Train units, advance Age |
| **Wood** | Trees (Lumber Camp) | Build almost everything |
| **Gold** | Gold mines (Mining Camp) | Advanced units, Age advance |
| **Stone** | Stone quarries (Mining Camp) | Walls, gates |

Starting stockpile: 200 Food · 75 Wood · 50 Gold · 0 Stone — enough for one House and a few units.

---

## Age Progression

Advance your Age at the **Town Center** (press **A** or click the Advance button).  
Advancing takes time; a gold progress bar appears while researching.

| Age | Unlock | Cost | Time |
|---|---|---|---|
| Dark Age | Starting age | — | — |
| Feudal Age | Archer in Barracks | 500 Food | ~2 min |
| Castle Age | Pikeman in Barracks | 800 Food · 200 Gold | ~2:40 min |
| Imperial Age | (future techs) | 1000 Food · 800 Gold | ~3:10 min |

---

## Units

### Villager

- **Role:** economy — gathers resources and constructs buildings
- **Cost:** 50 Food · 30 s train time
- **Tip:** assign them immediately; idle villagers waste time

### Militia

- **Role:** cheap early melee fighter
- **Cost:** 60 Food · 20 Wood · 21 s
- **Available:** Dark Age

### Scout

- **Role:** fast exploration; low attack
- **Cost:** 80 Food · 25 s (spawns free at game start)
- **Tip:** run it around the map early to reveal resources and the enemy base

### Archer *(Feudal Age)*

- **Role:** ranged attacker; backs away when enemies get too close
- **Cost:** 25 Wood · 45 Gold · 35 s
- **Tip:** keep them behind Militia; they lose badly in melee

### Pikeman *(Castle Age)*

- **Role:** heavy melee; bonus armour
- **Cost:** 60 Food · 30 Gold · 28 s
- **Tip:** pairs well with Archers — Pikemen absorb hits while Archers deal damage

### Sheep

- **Role:** food source via conversion
- Walks toward the nearest unit and joins their team
- Very fragile (8 HP) — protect them if you want the food

---

## Buildings

| Building | Cost | Purpose |
|---|---|---|
| **House** | 25 Wood | +5 population cap each |
| **Town Center** | — (starts built) | Trains Villagers, Age advancement |
| **Barracks** | 175 Wood | Trains military units |
| **Lumber Camp** | 100 Wood | Drop-off point for wood; place near trees |
| **Mining Camp** | 100 Wood | Drop-off for Gold and Stone |
| **Farm** | 60 Wood | Renewable Food source; place villager on it |
| **Wall Segment** | 5 Stone | Defensive barrier |
| **Gate** | 30 Wood | Passable wall opening; lock with O |

### Building a structure

1. Select one or more Villagers.
2. Press **B** → choose a building from the menu (shortcut in brackets).
3. Move the ghost to a valid position (white = OK, red = blocked).
4. Left-click to place. Shift+click to keep placing the same type.
5. The Villager(s) walk over and construct it automatically.

---

## Fog of War

| Colour | Meaning |
|---|---|
| Black | Never explored — unknown |
| Dark grey | Explored but not currently visible — last known state shown |
| Clear | Within a unit's line of sight — live updates |

Enemy units are only visible when inside your line of sight (clear cells).  
Enemy buildings appear in explored cells but do not update — scout to confirm they're still there.

---

## Economy tips

- Build a **Lumber Camp** next to the nearest tree cluster immediately.
- Send 3–4 villagers to wood, 2 to food (sheep or hunt), 1 to gold.
- Queue a **House** early — hitting the population cap halts training.
- Farms are slow but renewable; hunt and sheep run out eventually.
- Drop-off buildings (Lumber Camp, Mining Camp, Town Center) must be within walking distance — villagers waste time on long trips.

---

## Victory and defeat

- **You win** — destroy the enemy Town Center.
- **You lose** — your Town Center is destroyed.
- A game-over screen appears with the result and a **Return to menu** button.

---

## AI behaviour

The enemy AI:

- Gathers resources and builds a Barracks automatically.
- Trains units and launches attacks every 30 seconds (faster when aggressive).
- Advances Ages as soon as it can afford to.
- **Escalates aggression** if you attack its units or enter its base — interval drops to ~10 s and it rallies all soldiers to defend.
- Upgrades its military as Ages unlock new units (Archer in Feudal, Pikeman in Castle).
