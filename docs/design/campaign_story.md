# The Flames of Tamarán — Campaign Story

> Status: **REVIEW DOCUMENT** — part 1 records the story as shipped, part 2 is
> the critique, part 3 is a proposed revision. Nothing in part 3 is
> implemented; each proposal notes its implementation cost so items can be
> approved individually.

---

## 1 · The story as shipped

**Campaign title:** *The Flames of Tamarán* — "the Canarii against the
Atlante invasion — four battles for the archipelago".

| # | Mission | Map / Mode | Story beat |
|---|---|---|---|
| 0 | Prologue: The First Settlement | Plains, tutorial | "Before the bronze sails, there was the land." The elders teach settlement, food, defense. **Rival: Castellanos. Player: Guanches.** |
| 1 | The Vanguard | Standard, conquest | Bronze sails at dawn. The Atlantes raise a beachhead on Tamarán. **Doramas** gathers the warriors of the ravines: destroy the camp before it takes root. |
| 2 | Land of Fire | Volcanic, survive 12 min | The volcano answers with ash. Scarce land, waves under falling ash. **Guayarmina** watches from the ridge: hold until "the sacred night" passes. |
| 3 | The Strait | Islands, conquest | The invaders rule the water; their far-shore dock feeds the war. Build a fleet in secret, cross, burn everything. *(No named characters.)* |
| 4 | The Last Mountain | Volcanic, regicide | Two Atlante armies close on the last stronghold. "While **their deathless champion** stands, the invasion cannot be broken. Find them. End this." *(Champion unnamed.)* |

Full mission intro texts live in `project/assets/translations/translations.csv`
(`CAMP_M0_INTRO` … `CAMP_M4_INTRO`); mission data in
`project/scripts/campaign/campaign_data.gd`.

---

## 2 · Critique

**What already works**

- The four-act military arc is sound: repel the beachhead → survive the
  counter-blow → break their supply line → cut off the head. Classic and clean.
- Strong sense of place: ravines, ash, black fields, the strait. The prose has
  voice ("bronze sails cut the horizon").
- Escalation through GAME SYSTEMS, not just text: weather turns on in M2, the
  navy in M3, regicide in M4. The mechanics carry the drama.

**Weaknesses**

1. **The prologue breaks the fiction.** The campaign is Canarii vs Atlantes,
   but the prologue is played as *Guanches* against *Castellanos* — a
   different protagonist AND a different enemy than the story it introduces.
2. **No protagonist thread.** Doramas appears in M1 and vanishes; Guayarmina
   "watches from a ridge" in M2 and vanishes; M3 and M4 are narrated by
   nobody. The campaign has no one to care about.
3. **The antagonist appears out of nowhere.** M4's "deathless champion" is
   never seen, named or foreshadowed in M1–M3. The payoff has no setup.
4. **The Atlantes have no motive.** Why do the lords of the deep sea want a
   volcanic island? Without a reason they are stage villains — and the game
   already owns the perfect reason (see part 3).
5. **Missions end in silence.** There are intro texts but no outros: you burn
   the dock, the screen says "Victory", and the story never acknowledges what
   it cost or what it means. The arc has no connective tissue.
6. **The game's richest fiction is absent from its own campaign.** The
   harimaguadas (neutral priestesses who tend every army), the presa canario,
   the almogarén, Sea Fog stealth, the calima — all real systems with real
   lore, none of them mentioned in the story that should showcase them.
7. **"The sacred night" (M2) is a loose thread.** Evocative, but it is never
   explained and never referenced again.

---

## 3 · Proposed revision

### 3.1 The premise: give the invasion a heart

**The Atlantes are not conquerors — they are the drowned.** Their island
kingdom sank beneath the Atlantic (the legend the civ is already built on).
**Cleito, Mistress of Tides** — in the game's own files, "mortal wife of
Poseidon in the Atlantis legend" — leads the survivor fleet. Her people believe
that a kingdom that died by water can only be reborn by fire: they have come
for **Tamarán's volcano**, the last great flame of the ocean, to crown it
their new throne. They are refugees turned invaders — wrong, but not evil.

This costs nothing mechanically — Cleito and her admiral **Artaxerax** already
exist as Atlante hero units, and M4 is already regicide: the "deathless
champion" the player must kill **is literally her**. The story only has to say
her name.

### 3.2 The protagonists: a thread to follow

- **Doramas** carries M1 and M4 — the warrior of the ravines who rises from
  vanguard skirmisher to the man who must end the war. His own unit text says
  he "can only be killed by treachery" (as in the historical legend): the
  campaign should SAY this, and let it hang over the finale as dread.
- **Guayarmina** carries M2 and M3 — the guardian archer. In M2 she holds the
  ridge; in M3 it is her plan to build the fleet in secret under the sea fog.
- **The harimaguadas** are the moral thread: priestesses of the islands who
  tend *every* army that respects their shrines — including Atlante wounded.
  Through them the player learns the enemy's grief (see M2/M4 beats), which
  makes the ending land as tragedy averted rather than extermination.

### 3.3 Mission-by-mission

Each block: **proposed intro** (replaces the current one), **proposed outro**
(new — requires the small `outro_key` feature, see 3.4). The texts were
drafted in Spanish first for review; the English mirrors are given here.

---

**M0 · Prologue — "The First Settlement"**

*Fix:* rival becomes **Atlantes** (a scouting party), player becomes
**Canarii**, matching the campaign. One-line data change.

> **Intro (EN):** "Before the bronze sails, there was the land. The elders
> will guide your hand: raise a settlement, feed your people, arm their
> defenders. And mind the strange sails prowling the coast — the fishermen
> say they ask about the mountain of fire."
>
> **Outro (EN):** "The settlement breathes. But that night, on the beach, the
> strangers' footprints ran down to the water — and none came back."

**M1 · "The Vanguard"** *(text updated, objectives unchanged — the Mill/dog
objectives now get their story line)*

> **Intro (EN):** "Bronze sails cut the dawn. The Atlantes — the drowned of
> the deep sea — have driven a camp into the shore of Tamarán. Doramas
> gathers the warriors of the ravines: 'Every sheep, every mill, every herding
> dog feeds this war. Throw them back into the water before they take root.'"
>
> **Outro (EN):** "The camp burns. Among the wreckage Doramas finds a sodden
> banner no wave carried in: a crowned trident. 'This is no raid,' he says.
> 'It is an exodus.'"

**M2 · "Land of Fire"** *(the "sacred night" gets its meaning; the
harimaguadas enter)*

> **Intro (EN):** "The mountain answers the invasion with ash and thunder:
> the sacred night, when the harimaguadas climb to the almogarén to pray the
> fire calm. Guayarmina keeps watch from the ridge. 'The Atlantes have come
> for the volcano,' she says. 'Hold until dawn: if the mountain wakes ours,
> ours it will remain.'"
>
> **Outro (EN):** "At dawn the harimaguadas come down from the almogarén —
> carrying wounded from both sides. One of them repeats a dying Atlante
> woman's words: 'Our queen does not want your land. She wants your fire,
> because the water took hers.'"

**M3 · "The Strait"** *(Artaxerax enters as the visible antagonist; the sea
fog becomes story — it is already a stealth mechanic)*

> **Intro (EN):** "Admiral Artaxerax rules the water between the islands: no
> canoe crosses without meeting bronze rams, and his dock feeds the war with
> warriors and steel. Guayarmina points at the sea fog: 'Their veil can be
> ours too. Build the fleet where the fog sleeps, cross the strait, and burn
> every last plank.'"
>
> **Outro (EN):** "The dock burns and Artaxerax falls back toward the
> volcano. Before the calima swallows him he shouts across the water: 'You
> have burned timber! The Mistress of Tides does not sail — she waits!'"

**M4 · "The Last Mountain"** *(the champion has a name and a grief; Doramas'
legend closes the arc)*

> **Intro (EN):** "It all ends at the foot of the volcano. Two armies close
> the ring, and at their head stands her: Cleito, Mistress of Tides, queen of
> a drowned kingdom, the champion who does not die. The elders speak with one
> voice: while she stands, the invasion will not break. Doramas whets his
> tabona and smiles: 'Only treachery can kill me. Only the truth can kill
> her: this mountain will not give her kingdom back.'"
>
> **Outro (EN):** "The tide withdraws. The harimaguadas sing for the dead of
> both peoples, and the Atlantes who lay down their bronze are shown a shore
> to build houses on — far from the volcano. The mountain belongs to those
> who listen to it, not to those who crown it. Tamarán breathes."

### 3.4 Implementation notes

| Proposal | Cost |
|---|---|
| Rewrite the 5 intro texts (EN+ES in translations.csv) | Trivial — text only |
| Prologue rival Castellanos→Atlantes, civ Guanches→Canarii | One line in campaign_data.gd (re-verify the tutorial script still passes check_campaign) |
| **Outros**: `outro_key` per mission, shown as a panel/toast on victory before returning to the campaign screen | Small — MissionDirector already owns the victory hook and a toast system |
| Name-drop Cleito/Artaxerax | Free — both heroes exist; M4 regicide already spawns the Atlante hero as the actual kill target |
| Optional: mid-mission story toasts (e.g. M2 wave 3: "The ash hides their banners!") reusing `_toast` at wave times | Small — a `"story"` field on wave entries |
| Optional: M3 scripted Artaxerax appearance among the patrols | Medium — enemy hero spawn outside regicide; skippable, the outro line carries him |

**Not proposed:** branching, cutscenes, new mission count — the four-battle
shape is right; it only needs its people and its reasons.
