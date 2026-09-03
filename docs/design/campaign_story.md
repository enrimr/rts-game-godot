# The Flames of Tamarán — Campaign Story / La Historia de la Campaña

> Status: **REVIEW DOCUMENT** — part 1 records the story as shipped, part 2 is
> the critique, part 3 is a proposed revision. Nothing in part 3 is
> implemented; each proposal notes its implementation cost so items can be
> approved individually.
>
> *Estado: **DOCUMENTO DE REVISIÓN** — la parte 1 recoge la historia tal como
> está en el juego, la parte 2 es la crítica, la parte 3 es la revisión
> propuesta. Nada de la parte 3 está implementado; cada propuesta anota su
> coste para poder aprobarlas por separado.*

---

## 1 · The story as shipped / La historia actual

**Campaign title:** *The Flames of Tamarán / Las Llamas de Tamarán* — "the
Canarii against the Atlante invasion — four battles for the archipelago".

| # | Mission | Map / Mode | Story beat |
|---|---|---|---|
| 0 | Prologue: The First Settlement | Plains, tutorial | "Before the bronze sails, there was the land." The elders teach settlement, food, defense. **Rival: Castellanos. Player: Guanches.** |
| 1 | The Vanguard / La Vanguardia | Standard, conquest | Bronze sails at dawn. The Atlantes raise a beachhead on Tamarán. **Doramas** gathers the warriors of the ravines: destroy the camp before it takes root. |
| 2 | Land of Fire / Tierra de Fuego | Volcanic, survive 12 min | The volcano answers with ash. Scarce land, waves under falling ash. **Guayarmina** watches from the ridge: hold until "the sacred night" passes. |
| 3 | The Strait / El Estrecho | Islands, conquest | The invaders rule the water; their far-shore dock feeds the war. Build a fleet in secret, cross, burn everything. *(No named characters.)* |
| 4 | The Last Mountain / La Última Montaña | Volcanic, regicide | Two Atlante armies close on the last stronghold. "While **their deathless champion** stands, the invasion cannot be broken. Find them. End this." *(Champion unnamed.)* |

Full mission intro texts live in `project/assets/translations/translations.csv`
(`CAMP_M0_INTRO` … `CAMP_M4_INTRO`); mission data in
`project/scripts/campaign/campaign_data.gd`.

---

## 2 · Critique / Crítica

**What already works / Lo que ya funciona**

- The four-act military arc is sound: repel the beachhead → survive the
  counter-blow → break their supply line → cut off the head. Classic and clean.
- Strong sense of place: ravines, ash, black fields, the strait. The prose has
  voice ("velas de bronce cortan el horizonte").
- Escalation through GAME SYSTEMS, not just text: weather turns on in M2, the
  navy in M3, regicide in M4. The mechanics carry the drama.

**Weaknesses / Debilidades**

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

## 3 · Proposed revision / Revisión propuesta

### 3.1 The premise: give the invasion a heart / La premisa

**The Atlantes are not conquerors — they are the drowned.** Their island
kingdom sank beneath the Atlantic (the legend the civ is already built on).
**Cleito, Mistress of Tides** — in the game's own files, "mortal wife of
Poseidon in the Atlantis legend" — leads the survivor fleet. Her people believe
that a kingdom that died by water can only be reborn by fire: they have come
for **Tamarán's volcano**, the last great flame of the ocean, to crown it
their new throne. They are refugees turned invaders — wrong, but not evil.

*Los atlantes no son conquistadores: son los ahogados. Su reino insular se
hundió bajo el Atlántico. **Cleito, la Señora de las Mareas**, guía la flota
superviviente. Su pueblo cree que un reino muerto por agua solo puede renacer
por fuego: vienen a por **el volcán de Tamarán**, la última gran llama del
océano, para coronarlo como su nuevo trono. Refugiados convertidos en
invasores — equivocados, pero no malvados.*

This costs nothing mechanically — Cleito and her admiral **Artaxerax** already
exist as Atlante hero units, and M4 is already regicide: the "deathless
champion" the player must kill **is literally her**. The story only has to say
her name.

### 3.2 The protagonists: a thread to follow / Los protagonistas

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

### 3.3 Mission-by-mission / Misión a misión

Each block: **proposed intro** (replaces the current one), **proposed outro**
(new — requires the small `outro_key` feature, see 3.4), in Spanish first for
review, English mirror to be written on approval.

---

**M0 · Prologue — "El Primer Asentamiento"**

*Fix:* rival becomes **Atlantes** (a scouting party), player becomes
**Canarii**, matching the campaign. One-line data change.

> **Intro (ES):** «Antes de las velas de bronce, estaba la tierra. Los ancianos
> guiarán tu mano: levanta un asentamiento, alimenta a tu gente, arma a sus
> defensores. Y presta atención a las velas extrañas que rondan la costa —
> los pescadores dicen que preguntan por la montaña de fuego.»
>
> **Outro (ES):** «El asentamiento respira. Pero esa noche, en la playa, las
> huellas de los extraños llegaban hasta el agua… y ninguna volvía.»

**M1 · "La Vanguardia"** *(text updated, objectives unchanged — the Mill/dog
objectives now get their story line)*

> **Intro (ES):** «Velas de bronce cortan el amanecer. Los atlantes — los
> ahogados del mar profundo — han clavado un campamento en la costa de
> Tamarán. Doramas reúne a los guerreros de los barrancos: "Cada oveja, cada
> molino, cada perro pastor alimenta esta guerra. Echadlos al agua antes de
> que echen raíces."»
>
> **Outro (ES):** «El campamento arde. Entre los restos, Doramas encuentra un
> estandarte empapado que ninguna ola trajo: un tridente coronado. "No es una
> incursión", dice. "Es un éxodo."»

**M2 · "Tierra de Fuego"** *(the "sacred night" gets its meaning; the
harimaguadas enter)*

> **Intro (ES):** «La montaña responde a la invasión con ceniza y truenos: la
> noche sagrada, cuando las harimaguadas suben al almogarén a pedir que el
> fuego se calme. Guayarmina vigila desde el risco. "Los atlantes vienen a por
> el volcán", dice. "Resistid hasta el alba: si la montaña amanece nuestra,
> seguirá siéndolo."»
>
> **Outro (ES):** «Al alba, las harimaguadas bajan del almogarén — y traen
> heridos de los dos bandos. Una de ellas repite las palabras de una moribunda
> atlante: "Nuestra reina no quiere vuestra tierra. Quiere vuestro fuego,
> porque el agua le quitó el suyo."»

**M3 · "El Estrecho"** *(Artaxerax enters as the visible antagonist; the sea
fog becomes story — it is already a stealth mechanic)*

> **Intro (ES):** «El almirante Artaxerax domina el agua entre las islas:
> ninguna canoa cruza sin encontrar espolones de bronce, y su puerto alimenta
> la guerra con guerreros y acero. Guayarmina señala la niebla del mar: "Su
> velo también puede ser el nuestro. Construid la flota donde la niebla
> duerme, cruzad el estrecho y quemad hasta el último tablón."»
>
> **Outro (ES):** «El puerto arde y Artaxerax se retira hacia el volcán. Antes
> de perderse en la calima, grita sobre el agua: "¡Habéis quemado madera! ¡La
> Señora de las Mareas no navega — espera!"»

**M4 · "La Última Montaña"** *(the champion has a name and a grief; Doramas'
legend closes the arc)*

> **Intro (ES):** «Todo termina al pie del volcán. Dos ejércitos cierran el
> cerco, y a su cabeza está ella: Cleito, la Señora de las Mareas, reina de un
> reino ahogado, la campeona que no muere. Los ancianos hablan con una sola
> voz: mientras ella siga en pie, la invasión no se romperá. Doramas afila la
> tabona y sonríe: "A mí solo puede matarme la traición. A ella, solo la
> verdad: esta montaña no le devolverá su reino."»
>
> **Outro (ES):** «La marea se retira. Las harimaguadas cantan por los muertos
> de los dos pueblos, y a los atlantes que deponen el bronce se les señala una
> costa donde levantar casas — lejos del volcán. La montaña sigue siendo de
> quien la escucha, no de quien la corona. Tamarán respira.»

### 3.4 Implementation notes / Notas de implementación

| Proposal | Cost |
|---|---|
| Rewrite the 5 intro texts (EN+ES in translations.csv) | Trivial — text only |
| Prologue rival Castellanos→Atlantes, civ Guanches→Canarii | One line in campaign_data.gd (re-verify the tutorial script still passes check_campaign) |
| **Outros**: `outro_key` per mission, shown as a panel/toast on victory before returning to the campaign screen | Small — MissionDirector already owns the victory hook and a toast system |
| Name-drop Cleito/Artaxerax | Free — both heroes exist; M4 regicide already spawns the Atlante hero as the actual kill target |
| Optional: mid-mission story toasts (e.g. M2 wave 3: "¡La ceniza esconde sus estandartes!") reusing `_toast` at wave times | Small — a `"story"` field on wave entries |
| Optional: M3 scripted Artaxerax appearance among the patrols | Medium — enemy hero spawn outside regicide; skippable, the outro line carries him |

**Not proposed:** branching, cutscenes, new mission count — the four-battle
shape is right; it only needs its people and its reasons.
