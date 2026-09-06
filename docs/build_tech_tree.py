#!/usr/bin/env python3
"""Tech-tree page generator for Calima: Flames of the Atlantic.

Reads the technology resources (project/resources/technologies/*.tres) and the
translation table (project/assets/translations/translations.csv) and emits two
self-contained monolingual pages:

    docs/design/tech_tree_en.html   (100% English)
    docs/design/tech_tree_es.html   (100% Spanish)

Run from the repository root:

    python3 docs/build_tech_tree.py

Stdlib only. Numbers (costs, times, effect percentages) always come from the
.tres data; Spanish strings come from the CSV when present, otherwise from the
curated fallback tables below.
"""

import csv
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TECH_DIR = ROOT / "project" / "resources" / "technologies"
CSV_PATH = ROOT / "project" / "assets" / "translations" / "translations.csv"
OUT_DIR = ROOT / "docs" / "design"

# TechnologyResource.ResearchBuilding enum order (technology_resource.gd).
BUILDING_ENUM = [
    "blacksmith", "university", "temple", "town_center", "market",
    "barracks", "stable", "lumber_camp", "mining_camp", "mill",
]

# Section order of the reference page; anchor -> CSV building key (None = fallback).
SECTION_ORDER = [
    "blacksmith", "university", "temple", "barracks", "stable",
    "lumber_camp", "mining_camp", "mill",
]

BUILDING_CSV_KEYS = {
    "blacksmith": "BUILDING_BLACKSMITH",
    "university": "BUILDING_UNIVERSITY",
    "temple": "BUILDING_TEMPLE",
    "barracks": "BUILDING_BARRACKS",
    "stable": "BUILDING_STABLE",
    "lumber_camp": "BUILDING_LUMBER_CAMP",
    "mining_camp": "BUILDING_MINING_CAMP",
}
BUILDING_FALLBACK = {"mill": {"en": "Mill", "es": "Molino"}}

AGE_CSV_KEYS = ["UI_AGE_DARK", "UI_AGE_FEUDAL", "UI_AGE_CASTLE", "UI_AGE_IMPERIAL"]

# Spanish tech names not present in translations.csv (camp-line techs are in the
# CSV as TECH_<ID>; everything here was cross-checked against docs/guide_es.md
# and the in-game HUD strings).
ES_NAMES = {
    "loom": "Telar",
    "carreta_canaria": "Carreta Canaria",
    "fletching": "Flechado",
    "forging": "Forja",
    "padded_archer_armor": "Armadura Acolchada",
    "scale_barding": "Armadura de Escamas",
    "shipwright": "Maestro Carpintero Naval",
    "bodkin_arrow": "Flecha Bodkin",
    "carreton_isleno": "Carretón Isleño",
    "chain_barding": "Armadura de Mallas",
    "iron_casting": "Fundición de Hierro",
    "blast_furnace": "Alto Horno",
    "plate_barding": "Armadura de Placas",
    "ballistics": "Balística",
    "siege_engineering": "Ingeniería de Asedio",
    "chemistry": "Química",
    "fervor": "Fervor",
    "sanctity": "Santidad",
    "atonement": "Expiación",
}

# Spanish descriptions not present in translations.csv (faithful es-ES
# renderings of the .tres description fields).
ES_DESCS = {
    "loom": "Los aldeanos ganan salud adicional gracias a ropas reforzadas.",
    "carreta_canaria": "Robustas carretas de madera permiten a los aldeanos cargar un 25% más por viaje. Las granjas depositan al instante y no se ven afectadas.",
    "fletching": "Astiles de flecha mejorados aumentan el ataque de los arqueros.",
    "forging": "Mejora el ataque cuerpo a cuerpo de la infantería.",
    "padded_archer_armor": "Mejora la armadura perforante de los arqueros.",
    "scale_barding": "La armadura de escamas mejora la protección cuerpo a cuerpo de todas las unidades.",
    "shipwright": "Maestros carpinteros navales construyen cascos más resistentes y reducen los costes de construcción.",
    "bodkin_arrow": "Puntas bodkin perforantes mejoran el ataque y el alcance de los arqueros.",
    "carreton_isleno": "Carretones reforzados: los aldeanos cargan otro 25% más por viaje.",
    "chain_barding": "Anillas entrelazadas proporcionan una armadura cuerpo a cuerpo superior.",
    "iron_casting": "Aleaciones superiores mejoran el ataque de todas las unidades.",
    "blast_furnace": "La forja a alta temperatura produce armas superiores para todas las unidades.",
    "plate_barding": "La armadura de placas completa otorga la máxima protección cuerpo a cuerpo.",
    "ballistics": "Los arqueros predicen el movimiento enemigo, aumentando su velocidad de ataque.",
    "siege_engineering": "Las unidades militares infligen un 20% más de daño a los edificios.",
    "chemistry": "Propelentes mejorados aumentan el daño de todos los ataques a distancia.",
    "fervor": "La disciplina espiritual aumenta la velocidad de movimiento de todas las unidades.",
    "sanctity": "Los guerreros bendecidos ganan salud adicional.",
    "atonement": "Las prácticas espirituales mejoran la salud de la caballería.",
    "upgrade_man_at_arms": "Mejora toda la Milicia a Hombres de Armas y entrena Hombres de Armas en adelante.",
    "upgrade_long_swordsman": "Mejora todos los Hombres de Armas a Espadachines y entrena Espadachines en adelante.",
    "upgrade_heavy_scout": "Mejora todos los Exploradores a Exploradores Pesados y entrena Exploradores Pesados en adelante.",
    "upgrade_knight": "Mejora todos los Exploradores Pesados a Caballeros y entrena Caballeros en adelante.",
}

UNIT_FALLBACK = {
    "militia": {"en": "Militia", "es": "Milicia"},
    "man_at_arms": {"en": "Man-at-Arms", "es": "Hombre de Armas"},
    "long_swordsman": {"en": "Long Swordsman", "es": "Espadachín"},
    "scout": {"en": "Scout", "es": "Explorador"},
    "heavy_scout": {"en": "Heavy Scout", "es": "Explorador Pesado"},
    "knight": {"en": "Knight", "es": "Caballero"},
}

# Effect key -> per-language label. Scopes verified against CivBonusManager:
# unit_armor_melee is cavalry-only (get_unit_armor_bonus), archer_armor_pierce
# is the archer line, both additive flat points (_ADDITIVE_KEYS); the rest are
# multipliers rendered as percentages.
ADDITIVE_KEYS = {"unit_armor_melee", "archer_armor_pierce"}
EFFECT_LABELS = {
    "villager_hp": {"en": "Villager HP", "es": "PV de los aldeanos"},
    "villager_carry_capacity": {
        "en": "Villager carry capacity (farms unaffected)",
        "es": "Capacidad de carga de los aldeanos (no afecta a las granjas)",
    },
    "archer_attack": {"en": "Archer attack", "es": "Ataque de los arqueros"},
    "archer_range": {"en": "Archer range", "es": "Alcance de los arqueros"},
    "archer_attack_speed": {"en": "Archer attack speed", "es": "Velocidad de ataque de los arqueros"},
    "archer_armor_pierce": {"en": "Archer-line pierce armour", "es": "Armadura perforante de la línea de arqueros"},
    "unit_attack": {"en": "All unit attack", "es": "Ataque de todas las unidades"},
    "unit_armor_melee": {"en": "Cavalry melee armour", "es": "Armadura cuerpo a cuerpo de la caballería"},
    "unit_move_speed": {"en": "All unit move speed", "es": "Velocidad de movimiento de todas las unidades"},
    "cavalry_hp": {"en": "Cavalry HP", "es": "PV de la caballería"},
    "swordsman_hp": {"en": "Infantry (swordsman line) HP", "es": "PV de la infantería (línea de espadachines)"},
    "ship_hp": {"en": "Ship HP", "es": "PV de los barcos"},
    "ship_cost": {"en": "Ship cost", "es": "Coste de los barcos"},
    "siege_attack_bonus": {"en": "Damage vs buildings (all units)", "es": "Daño contra edificios (todas las unidades)"},
    "villager_food_gather_rate": {"en": "Food gather rate", "es": "Ritmo de recolección de comida"},
    "villager_wood_gather_rate": {"en": "Wood gather rate", "es": "Ritmo de recolección de madera"},
    "villager_gold_gather_rate": {"en": "Gold gather rate", "es": "Ritmo de recolección de oro"},
    "villager_stone_gather_rate": {"en": "Stone gather rate", "es": "Ritmo de recolección de piedra"},
    "villager_food_carry": {"en": "Food carry", "es": "Carga de comida"},
    "villager_wood_carry": {"en": "Wood carry", "es": "Carga de madera"},
    "villager_gold_carry": {"en": "Gold carry", "es": "Carga de oro"},
    "villager_stone_carry": {"en": "Stone carry", "es": "Carga de piedra"},
}

STRINGS = {
    "en": {
        "lang": "en",
        "title": "Calima: Flames of the Atlantic — Tech Tree",
        "subtitle_tpl": "{techs} technologies · {buildings} research buildings",
        "portal": ("Portal", "../index_en.html"),
        "toggle": ("Versión en español", "tech_tree_es.html"),
        "intro": (
            "Each building researches <b>one technology at a time</b> and queues up to <b>5 in flight</b> "
            "(paid when queued, fully refunded on cancel; a destroyed building refunds its whole queue). "
            "The three camp economy lines (Lumber Camp, Mining Camp, Mill) chain <b>one step per age from "
            "the Feudal Age</b>. <b>Castellanos</b> receive the oldest unresearched Blacksmith technology "
            "free on every age advance."
        ),
        "count_one": "1 technology",
        "count_many": "{n} technologies",
        "requires": "Requires:",
        "upgrade_tpl": "▲ {a} → {b} — upgrades every living unit and all future training",
        "footer": (
            "Generated from the game data: <code>project/resources/technologies/*.tres</code> "
            "({techs} files) — regenerate with <code>python3 docs/build_tech_tree.py</code>. "
            "Effect scopes follow <code>CivBonusManager</code>/<code>TechManager</code> "
            "(barding = cavalry line, padded armour = archer line)."
        ),
    },
    "es": {
        "lang": "es",
        "title": "Calima: Flames of the Atlantic — Árbol de Tecnologías",
        "subtitle_tpl": "{techs} tecnologías · {buildings} edificios de investigación",
        "portal": ("Portal", "../index_es.html"),
        "toggle": ("English version", "tech_tree_en.html"),
        "intro": (
            "Cada edificio investiga <b>una tecnología a la vez</b> y encola hasta <b>5 en curso</b> "
            "(pagadas al encolar, reembolso íntegro al cancelar; un edificio destruido reembolsa toda su "
            "cola). Las tres líneas económicas de campamento (Campamento Maderero, Campamento Minero, "
            "Molino) encadenan <b>un paso por edad desde la Edad Feudal</b>. Los <b>Castellanos</b> "
            "reciben gratis la tecnología de Herrería más antigua sin investigar en cada avance de edad."
        ),
        "count_one": "1 tecnología",
        "count_many": "{n} tecnologías",
        "requires": "Requiere:",
        "upgrade_tpl": "▲ {a} → {b} — mejora todas las unidades vivas y todo el entrenamiento futuro",
        "footer": (
            "Generado desde <code>project/resources/technologies/*.tres</code> ({techs} archivos) — "
            "regenera con <code>python3 docs/build_tech_tree.py</code>. Los ámbitos de los efectos "
            "siguen <code>CivBonusManager</code>/<code>TechManager</code> (las bardas = línea de "
            "caballería, la armadura acolchada = línea de arqueros)."
        ),
    },
}

CSS = """
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg:          #1a1108;
    --card-bg:     #2a1f0e;
    --card-border: #3d2e18;
    --gold:        #c8a84b;
    --gold-dim:    #8c7232;
    --gold-bright: #f0cc6a;
    --text:        #d4c49a;
    --text-dim:    #7a6a4a;
    --food:        #e86c2a;
    --wood:        #6aaa3a;
    --gold-res:    #e8c830;
    --shadow:      rgba(0,0,0,0.6);
    --glow:        rgba(200,168,75,0.3);
  }

  body {
    background: var(--bg);
    color: var(--text);
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    font-size: 14px;
    min-height: 100vh;
  }

  header {
    background: linear-gradient(180deg, #0d0904 0%, #1a1108 100%);
    border-bottom: 2px solid var(--gold-dim);
    padding: 18px 24px 12px;
    text-align: center;
    box-shadow: 0 4px 20px var(--shadow);
  }

  header h1 {
    color: var(--gold);
    font-size: 1.6rem;
    font-variant: small-caps;
    letter-spacing: 0.12em;
    text-shadow: 0 0 20px rgba(200,168,75,0.5);
  }

  header .subtitle {
    color: var(--text-dim);
    font-size: 0.85rem;
    margin-top: 4px;
  }

  nav {
    display: flex;
    justify-content: center;
    flex-wrap: wrap;
    gap: 2px 14px;
    margin-top: 10px;
  }

  nav a {
    color: var(--text-dim);
    text-decoration: none;
    font-variant: small-caps;
    letter-spacing: 0.06em;
    font-size: 0.85rem;
  }
  nav a:hover { color: var(--gold-bright); }
  nav a.lang-toggle {
    border: 1px solid var(--gold-dim);
    border-radius: 12px;
    color: var(--gold);
    font-variant: normal;
    padding: 1px 10px;
  }
  nav a.lang-toggle:hover { border-color: var(--gold); color: var(--gold-bright); }

  main {
    padding: 24px 20px 40px;
    max-width: 1400px;
    margin: 0 auto;
  }

  .intro {
    color: var(--text-dim);
    font-size: 0.85rem;
    line-height: 1.55;
    max-width: 940px;
    margin: 0 auto 8px;
  }
  .intro b { color: var(--text); }

  .card {
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 6px;
    padding: 12px;
    transition: border-color 0.2s, box-shadow 0.2s;
  }
  .card:hover { border-color: var(--gold-dim); box-shadow: 0 0 12px var(--glow); }

  .card-title {
    color: var(--gold);
    font-size: 0.9rem;
    font-variant: small-caps;
    letter-spacing: 0.06em;
  }
  .card-subtitle {
    color: var(--text-dim);
    font-size: 0.76rem;
    font-style: italic;
    margin-bottom: 2px;
  }

  .cost { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
  .cost-item { border-radius: 3px; font-size: 0.78rem; font-weight: 600; padding: 2px 7px; }
  .cost-food { background: rgba(232,108,42,0.18); color: var(--food);     border: 1px solid rgba(232,108,42,0.35); }
  .cost-wood { background: rgba(106,170,58,0.18); color: var(--wood);     border: 1px solid rgba(106,170,58,0.35); }
  .cost-gold { background: rgba(232,200,48,0.18); color: var(--gold-res); border: 1px solid rgba(232,200,48,0.35); }

  .tech-section { margin: 34px 0; }

  .tech-section-heading {
    color: var(--gold);
    font-size: 1.1rem;
    font-variant: small-caps;
    letter-spacing: 0.1em;
    margin-bottom: 4px;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--card-border);
  }
  .tech-section-heading .count {
    color: var(--text-dim);
    font-size: 0.75rem;
    letter-spacing: 0.03em;
    margin-left: 10px;
  }

  .tech-age-col {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 0;
    margin-top: 10px;
  }

  .tech-grid-header {
    padding: 8px;
    font-variant: small-caps;
    font-size: 0.8rem;
    color: var(--gold-bright);
    letter-spacing: 0.07em;
    border-bottom: 2px solid var(--card-border);
  }
  .tech-grid-header.age-0 { background: rgba(74,53,32,0.4); }
  .tech-grid-header.age-1 { background: rgba(74,64,32,0.4); }
  .tech-grid-header.age-2 { background: rgba(58,58,80,0.4); }
  .tech-grid-header.age-3 { background: rgba(74,32,32,0.4); }

  .tech-cards-column {
    padding: 8px 6px 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .empty-slot { color: var(--text-dim); text-align: center; padding: 16px 0; }

  .tech-effect {
    background: rgba(60,100,60,0.15);
    border-left: 2px solid rgba(80,160,80,0.4);
    color: #8ecf8e;
    font-size: 0.73rem;
    margin-top: 6px;
    padding: 3px 7px;
    line-height: 1.4;
  }

  .prereq-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-top: 5px;
    align-items: center;
  }
  .prereq-label { color: var(--text-dim); font-size: 0.68rem; }
  .prereq-chip {
    background: rgba(200,100,40,0.12);
    border: 1px solid rgba(200,100,40,0.3);
    border-radius: 12px;
    color: #e8a040;
    font-size: 0.68rem;
    padding: 1px 7px;
  }

  .tech-times { color: var(--text-dim); font-size: 0.73rem; margin-top: 4px; }

  .tech-card.upgrade-card { border-color: rgba(200,168,75,0.5); }
  .tech-card.upgrade-card:hover { border-color: var(--gold); box-shadow: 0 0 14px rgba(200,168,75,0.4); }
  .upgrade-transform {
    background: rgba(200,168,75,0.08);
    border-left: 2px solid var(--gold-dim);
    color: var(--gold);
    font-size: 0.73rem;
    margin-top: 6px;
    padding: 3px 7px;
    line-height: 1.4;
  }

  footer {
    border-top: 1px solid var(--card-border);
    color: var(--text-dim);
    font-size: 0.75rem;
    text-align: center;
    padding: 16px 20px 28px;
    line-height: 1.6;
  }
  footer code {
    background: rgba(0,0,0,0.3);
    border-radius: 3px;
    padding: 1px 5px;
    font-size: 0.72rem;
  }
  footer a { color: var(--gold-dim); }

  @media (max-width: 900px) { .tech-age-col { grid-template-columns: repeat(2, 1fr); } }
  @media (max-width: 560px) { .tech-age-col { grid-template-columns: 1fr; } }

  ::-webkit-scrollbar { width: 8px; background: #0d0904; }
  ::-webkit-scrollbar-thumb { background: var(--card-border); border-radius: 4px; }
"""


def load_translations() -> dict:
    table = {}
    with CSV_PATH.open(encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            table[row["keys"]] = {"en": row["en"], "es": row["es"]}
    return table


def parse_tres(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    tech = {"file": path.name}

    def grab(field: str, pattern: str, cast=str, default=None):
        m = re.search(rf"^{field} = {pattern}$", text, re.MULTILINE)
        tech[field] = cast(m.group(1)) if m else default

    grab("id", r'"(.*)"')
    grab("display_name", r'"(.*)"')
    grab("description", r'"(.*)"')
    grab("required_age", r"(\d+)", int, 0)
    grab("research_building", r"(\d+)", int, 0)
    grab("research_time", r"([\d.]+)", float, 0.0)
    for res in ("food", "wood", "gold"):
        grab(f"cost_{res}", r"(\d+)", int, 0)
    grab("upgrade_from_unit_id", r'"(.*)"', default="")
    grab("upgrade_to_unit_id", r'"(.*)"', default="")

    effects_m = re.search(r"^effects = \{(.*)\}$", text, re.MULTILINE)
    tech["effects"] = dict(
        (k, float(v))
        for k, v in re.findall(r'"(\w+)":\s*([\d.]+)', effects_m.group(1) or "")
    ) if effects_m else {}

    prereq_m = re.search(r"^prerequisites = \[(.*)\]$", text, re.MULTILINE)
    tech["prerequisites"] = re.findall(r'"(\w+)"', prereq_m.group(1)) if prereq_m else []
    return tech


def tech_name(tech: dict, lang: str, i18n: dict) -> str:
    if lang == "en":
        return tech["display_name"]
    key = "TECH_" + tech["id"].upper()
    if key in i18n:
        return i18n[key]["es"]
    return ES_NAMES.get(tech["id"], tech["display_name"])


def tech_desc(tech: dict, lang: str, i18n: dict) -> str:
    if lang == "en":
        return tech["description"]
    key = "TECH_" + tech["id"].upper() + "_DESC"
    if key in i18n:
        return i18n[key]["es"]
    return ES_DESCS.get(tech["id"], tech["description"])


def unit_name(unit_id: str, lang: str, i18n: dict) -> str:
    key = "UNIT_" + unit_id.upper()
    if key in i18n:
        return i18n[key][lang]
    fallback = UNIT_FALLBACK.get(unit_id)
    return fallback[lang] if fallback else unit_id


def building_name(building: str, lang: str, i18n: dict) -> str:
    key = BUILDING_CSV_KEYS.get(building)
    if key and key in i18n:
        return i18n[key][lang]
    return BUILDING_FALLBACK[building][lang]


def fmt_signed_pct(mult: float) -> str:
    pct = round((mult - 1.0) * 100)
    return f"+{pct}%" if pct >= 0 else f"−{abs(pct)}%"


def effect_text(effects: dict, lang: str) -> str:
    parts = []
    for key, value in effects.items():
        label = EFFECT_LABELS[key][lang]
        if key in ADDITIVE_KEYS:
            parts.append(f"{label} +{value:g}")
        else:
            parts.append(f"{label} {fmt_signed_pct(value)}")
    return " · ".join(parts)


def card_html(tech: dict, lang: str, i18n: dict, s: dict, names_by_id: dict) -> str:
    is_upgrade = bool(tech["upgrade_to_unit_id"])
    cls = "card tech-card upgrade-card" if is_upgrade else "card tech-card"
    out = [f'<div class="{cls}">']
    out.append(f'<div class="card-title">{html.escape(tech_name(tech, lang, i18n))}</div>')
    out.append(f'<div class="card-subtitle">{html.escape(tech_desc(tech, lang, i18n))}</div>')

    cost_items = []
    for res, icon in (("food", "\U0001F356"), ("wood", "\U0001FAB5"), ("gold", "\U0001F4B0")):
        amount = tech[f"cost_{res}"]
        if amount > 0:
            cost_items.append(f'<span class="cost-item cost-{res}">{icon} {amount}</span>')
    if cost_items:
        out.append('<div class="cost">' + "".join(cost_items) + "</div>")

    out.append(f'<div class="tech-times">⏱ {tech["research_time"]:g} s</div>')

    if tech["prerequisites"]:
        chips = "".join(
            f'<span class="prereq-chip">{html.escape(names_by_id[p])}</span>'
            for p in tech["prerequisites"]
        )
        out.append(
            f'<div class="prereq-chips"><span class="prereq-label">{s["requires"]}</span>{chips}</div>'
        )

    if is_upgrade:
        line = s["upgrade_tpl"].format(
            a=unit_name(tech["upgrade_from_unit_id"], lang, i18n),
            b=unit_name(tech["upgrade_to_unit_id"], lang, i18n),
        )
        out.append(f'<div class="upgrade-transform">{html.escape(line)}</div>')
    elif tech["effects"]:
        out.append(f'<div class="tech-effect">{html.escape(effect_text(tech["effects"], lang))}</div>')

    out.append("</div>")
    return "".join(out)


def section_html(building: str, techs: list, lang: str, i18n: dict, s: dict,
                 names_by_id: dict, ages: list) -> str:
    anchor = building.replace("_", "-")
    count = s["count_one"] if len(techs) == 1 else s["count_many"].format(n=len(techs))
    out = [f'<div class="tech-section" id="{anchor}">']
    out.append(
        f'<div class="tech-section-heading">{html.escape(building_name(building, lang, i18n))}'
        f' <span class="count">{count}</span></div>'
    )
    out.append('<div class="tech-age-col">')
    for age_idx, age_label in enumerate(ages):
        out.append(f'<div class="tech-grid-header age-{age_idx}">{html.escape(age_label)}</div>')
    for age_idx in range(4):
        column = sorted((t for t in techs if t["required_age"] == age_idx), key=lambda t: t["id"])
        out.append('<div class="tech-cards-column">')
        if column:
            out.extend(card_html(t, lang, i18n, s, names_by_id) for t in column)
        else:
            out.append('<div class="empty-slot">—</div>')
        out.append("</div>")
    out.append("</div></div>")
    return "".join(out)


def build_page(lang: str, techs: list, i18n: dict) -> str:
    s = STRINGS[lang]
    ages = [i18n[k][lang] for k in AGE_CSV_KEYS]
    names_by_id = {t["id"]: tech_name(t, lang, i18n) for t in techs}
    by_building = {}
    for t in techs:
        by_building.setdefault(BUILDING_ENUM[t["research_building"]], []).append(t)

    sections = [b for b in SECTION_ORDER if b in by_building]
    subtitle = s["subtitle_tpl"].format(techs=len(techs), buildings=len(sections))

    nav_chrome = [
        f'<a href="{s["portal"][1]}">{s["portal"][0]}</a>',
        '<a href="../manual/manual_es.html">Manual (ES)</a>',
        '<a href="../manual/manual_en.html">Manual (EN)</a>',
        f'<a class="lang-toggle" href="{s["toggle"][1]}" '
        f'lang="{"es" if lang == "en" else "en"}">{s["toggle"][0]}</a>',
    ]
    nav_sections = [
        f'<a href="#{b.replace("_", "-")}">{html.escape(building_name(b, lang, i18n))}</a>'
        for b in sections
    ]

    body_sections = "\n".join(
        section_html(b, by_building[b], lang, i18n, s, names_by_id, ages) for b in sections
    )

    return f"""<!DOCTYPE html>
<html lang="{s['lang']}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{html.escape(s['title'])}</title>
<style>{CSS}</style>
</head>
<body>

<header>
  <h1>{html.escape(s['title'])}</h1>
  <div class="subtitle">{html.escape(subtitle)}</div>
  <nav>{' '.join(nav_chrome)}</nav>
  <nav>{' '.join(nav_sections)}</nav>
</header>

<main>
  <p class="intro">{s['intro']}</p>
{body_sections}
</main>

<footer>
  {s['footer'].format(techs=len(techs))}
</footer>
</body>
</html>
"""


def main() -> None:
    i18n = load_translations()
    techs = [parse_tres(p) for p in sorted(TECH_DIR.glob("*.tres"))]
    for lang, filename in (("en", "tech_tree_en.html"), ("es", "tech_tree_es.html")):
        out = OUT_DIR / filename
        out.write_text(build_page(lang, techs, i18n), encoding="utf-8")
        print(f"wrote {out.relative_to(ROOT)} ({len(techs)} technologies)")


if __name__ == "__main__":
    main()
