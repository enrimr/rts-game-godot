# Civilizaciones, Unidades y Árbol de Tecnologías

> Datos extraídos directamente de los recursos del proyecto (`resources/`).
> Edades: **0** Edad Oscura · **1** Edad Feudal · **2** Edad de Castillo · **3** Edad Imperial.

---

## Edificios comunes

| Edificio | Coste | Edad mín. | HP | Función |
|---|---|---|---|---|
| Centro urbano | 275 madera | 0 | 2400 | Entrena aldeanos · drop-off · reaparición del héroe |
| Casa | 25 madera | 0 | 550 | +5 cap. de población |
| Cuartel | 175 madera | 0 | 1200 | Entrena infantería |
| Establo | 175 madera | 0 | 1100 | Entrena caballería |
| Herrería | 150 madera | 1 | 1000 | Investiga mejoras de armas y armaduras |
| Mercado | 175 madera | 1 | 900 | Comercio de recursos |
| Aserradero | 100 madera | 0 | 600 | Drop-off de madera |
| Campamento minero | 100 madera | 0 | 600 | Drop-off de oro / piedra |
| Granja | 60 madera | 0 | 300 | Fuente continua de comida |
| Muelle | 150 madera | 0 | 1800 | Entrena barcos |
| Taller de asedio | 200 madera | 2 | 1200 | Entrena unidades de asedio |
| Universidad | 200 madera | 2 | 1100 | Investigación avanzada |
| Templo | 175 madera | 2 | 900 | Tecnologías de moral y curación |
| Segmento de muro | 5 piedra | 0 | 700 | Barrera defensiva |
| Puerta | 30 madera | 0 | 500 | Paso para aliados |
| Trampa de peces | 75 madera | 0 | 600 | Fuente pasiva de comida (océano) |
| Maravilla | 2500m+2500c+2500p+5000o | 3 | — | Condición de victoria |

---

## Unidades comunes

### Aldeanos (Centro urbano)
| Unidad | Coste | Tiempo | HP | Vel. | Ataque | Rango |
|---|---|---|---|---|---|---|
| Aldeano | 50 comida | 25 s | 25 | 120 | 3 | 1.5 |

### Infantería (Cuartel)
| Unidad | Edad | Coste | Tiempo | HP | Vel. | Ataque | Rango | Armadura M/P |
|---|---|---|---|---|---|---|---|---|
| Milicia | 0 | 60c + 20m | 21 s | 40 | 100 | 4 | 1.5 | 0 / 0 |
| Arquero | 1 | 25m + 45o | 35 s | 30 | 110 | 5 | 4.0 | 0 / 0 |
| Hombre de armas | 1 | 60c + 20m | 21 s | 65 | 100 | 7 | 1.5 | 1 / 0 |
| Lancero | 2 | 60c + 30o | 28 s | 65 | 90 | 7 | 1.5 | 1 / 0 |
| Espadachín largo | 2 | 60c + 20m | 21 s | 85 | 100 | 9 | 1.5 | 2 / 1 |

### Caballería (Establo)
| Unidad | Edad | Coste | Tiempo | HP | Vel. | Ataque | Rango | Armadura M/P | Notas |
|---|---|---|---|---|---|---|---|---|---|
| Scout | 0 | 80c | 30 s | 35 | 180 | 2 | 0.8 | 0 / 0 | Habilidad: Explorar 60 s |
| Heavy Scout | 1 | 80c + 30o | 30 s | 80 | 130 | 6 | 1.5 | 1 / 0 | |
| Caballero | 2 | 60c + 75o | 45 s | 120 | 115 | 9 | 1.5 | 2 / 1 | |

> **Scout — Habilidad Explorar (tecla E):** El Scout deambula autónomamente por el mapa durante **60 segundos**, eligiendo un nuevo destino aleatorio cada 3-7 s. Se puede cancelar con el mismo botón.

### Asedio (Taller de asedio)
| Unidad | Edad | Coste | Tiempo | HP | Vel. | Ataque | Rango | Notas |
|---|---|---|---|---|---|---|---|---|
| Ariete | 2 | 160m | 60 s | 180 | 55 | 40 | 1.0 | ×3 daño vs edificios · pop 2 |
| Mangonela | 2 | 160m + 135o | 60 s | 90 | 60 | 35 | 7.0 | AoE 72 px · rango mínimo · pop 2 |
| Trebuchet | 3 | 200m + 200o | 70 s | 70 | 48 | 200 | 12.0 | Despliega en 3 s · se undeploy al moverse · pop 2 |

### Naval (Muelle)
| Unidad | Edad | Coste | Tiempo | HP | Vel. | Ataque | Rango |
|---|---|---|---|---|---|---|---|
| Barca pesquera | 0 | 75m | 25 s | 45 | 90 | 0 | — |
| Barco transporte | 1 | 125m | 45 s | 150 | 80 | 0 | — |
| Galera de guerra | 1 | 75m + 35o | 35 s | 120 | 85 | 6 | 5.5 |

---

## Unidades Únicas

Cada civilización dispone de una unidad exclusiva entrenada en su edificio militar principal. Solo disponible al jugar con esa civilización.

| Unidad | Civilización | Edificio | Edad | Coste | Tiempo | HP | Vel. | Ataque | Rango | Arm. C/P | Pob | Habilidad especial |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Guardia Menceyes | Guanches | Cuartel | 2 | 65c + 25o | 32 s | 95 | 85 | 9 | 1,5 | 2/1 | 1 | **Aura de Furia** — PV<50%: cada 2 s otorga +3 ataque a aliados en 80 px durante 3 s |
| Arquero de Barranco | Canarii | Cuartel | 2 | 40m + 55o | 35 s | 45 | 105 | 7 | 5,0 | 0/1 | 1 | **Disparo en Emboscada** — quieto ≥1,5 s → primer disparo hace ×2 daño |
| Saquador de Dunas | Mahos | Establo | 1 | 60c + 40o | 28 s | 70 | 135 | 8 | 1,5 | 0/0 | 1 | **Golpe y Retirada** — tras cada ataque retrocede 90 px y vuelve a cargar |
| Caballero Normando | Francos | Establo | 2 | 75c + 65o | 40 s | 130 | 110 | 10 | 1,5 | 2/1 | 1 | **Carga de Lanza** — primer ataque tras moverse ≥80 px hace ×2,5 daño |
| Arquero de Longbow | Britanos | Cuartel | 2 | 30m + 60o | 38 s | 40 | 95 | 6 | 6,5 | 0/1 | 1 | **Perforación de Armadura** — +4 daño extra contra caballería |
| Conquistador | Castellanos | Cuartel | 2 | 60c + 60o | 36 s | 80 | 95 | 8 | 1,2 | 1/1 | 1 | **Salva** (CD 12 s) — 3 disparos rápidos de 6 daño c/u, ignora armadura |
| Invocador de Mareas | Atlantes | Cuartel | 2 | 50c + 70o | 38 s | 75 | 80 | 7 | 3,0 | 1/2 | 1 | **Pulso Mareal** — cada ataque hace 2 daño en área a todos los enemigos en 65 px |
| Trirreme | Fenicios | Puerto | 1 | 100m + 50o | 50 s | 160 | 90 | 9 | 3,0 | 2/1 | 2 | **Espolón** — ×2 daño contra barcos + empuja al objetivo 40 px · pob 2 |

---

## Árbol de tecnologías

### Herrería
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Efecto |
|---|---|---|---|---|---|
| Telares | 0 | 50c | 25 s | — | HP aldeanos ×1.15 |
| Forja | 1 | 75c | 40 s | — | Ataque unidades ×1.15 |
| Fundición de hierro | 2 | 150o | 55 s | Forja | Ataque unidades ×1.20 |
| Alto horno | 3 | 275c + 225o | 50 s | — | Ataque unidades ×1.15 |
| Armadura de escamas | 1 | 100c + 50o | 40 s | — | Armadura cuerpo a cuerpo +1 |
| Armadura de cadenas | 2 | 200c + 100o | 45 s | Esc. de escamas | Armadura cuerpo a cuerpo +1 |
| Armadura de placas | 3 | 300c + 200o | 60 s | Esc. de cadenas | Armadura cuerpo a cuerpo +1 |
| Protección arquero | 1 | 100c | 35 s | — | Armadura perforante arquero +1 |
| Flechado | 1 | 100o | 35 s | — | Ataque arquero ×1.20 |
| Punta bodkin | 2 | 100c + 150o | 35 s | Flechado | Ataque arquero ×1.20 · Rango ×1.10 |
| Astillero | 1 | 200m + 60o | 40 s | — | HP barcos ×1.15 · Coste −15% |

### Universidad
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Efecto |
|---|---|---|---|---|---|
| Balística | 2 | 175o | 50 s | Flechado | Vel. ataque arquero ×1.20 |
| Química | 3 | 300o | 70 s | Balística | Ataque arquero ×1.15 |
| Ingeniería de asedio | 2 | 200o | 60 s | — | Daño a edificios ×1.20 |

### Templo (Monasterio)
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Efecto |
|---|---|---|---|---|---|
| Fervor | 2 | 150o | 50 s | — | Vel. movimiento unidades ×1.10 |
| Santidad | 2 | 100c | 40 s | — | HP espadachín ×1.15 |
| Expiación | 3 | 150c + 100o | 55 s | Santidad | HP caballería ×1.20 |

### Mejoras de unidades

Las tecnologías de mejora de unidades transforman inmediatamente todas las unidades existentes del tipo de origen (HP escalado proporcionalmente). A partir de ese momento, el edificio entrena el nuevo tipo. Se investigan en el mismo edificio que entrena la unidad.

#### Cuartel
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Transforma |
|---|---|---|---|---|---|
| Hombre de armas | 1 | 100c + 40o | 45 s | — | Milicia → Hombre de armas |
| Espadachín largo | 2 | 200c + 60o | 45 s | Hombre de armas | Hombre de armas → Espadachín largo |

#### Establo
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Transforma |
|---|---|---|---|---|---|
| Heavy Scout | 1 | 150c + 75o | 45 s | — | Scout → Heavy Scout |
| Caballero | 2 | 200c + 100o | 45 s | Heavy Scout | Heavy Scout → Caballero |

---

## Civilizaciones

### Guanches
| Campo | Valor |
|---|---|
| **Héroe** | Bencomo |
| **Habilidad** | *Carga de Menceyes* — Galvaniza unidades aliadas cercanas con +30% de velocidad de ataque durante 10 s · Recarga 50 s |
| **Unidad única** | **Guardia Menceyes** — 95 PV · 65c+25o · Edad 2 · *Aura de Furia*: PV<50% → +3 ataque a aliados en 80 px |
| **Bonificadores** | HP edificios de piedra ×1.20 · Lanzas disponibles desde Edad Oscura · Pueden atravesar terreno de malpais |
| **Restricciones** | Sin caballería · Sin pólvora |

**Estrategia:** Fortaleza defensiva con infantería resistente. Muy fuerte en mapas volcánicos.

---

### Canarii
| Campo | Valor |
|---|---|
| **Héroe** | Doramas |
| **Habilidad** | *Desafío* — Provoca a la unidad enemiga más cercana para que ataque a Doramas durante 6 s · Recarga 45 s |
| **Unidad única** | **Arquero de Barranco** — 45 PV · 40m+55o · Edad 2 · *Disparo en Emboscada*: quieto ≥1,5 s → ×2 primer disparo |
| **Bonificadores** | Aldeanos recolectan comida ×1.15 · Coste comida arqueros ×0.80 |
| **Restricciones** | Sin caballería pesada |

**Estrategia:** Economía de comida superior + arqueros baratos. Ideal para rush de arqueros temprano.

---

### Mahos
| Campo | Valor |
|---|---|
| **Héroe** | Guadarfía |
| **Habilidad** | *Emboscada* — Casi invisible durante 8 s; los enemigos no pueden atacarle automáticamente · Recarga 45 s |
| **Unidad única** | **Saquador de Dunas** — 70 PV · 60c+40o · Edad 1 · *Golpe y Retirada*: retrocede 90 px tras cada ataque y vuelve a cargar |
| **Bonificadores** | Coste madera edificios ×0.70 · Vel. Scout / caballería ligera ×1.25 · Pueden atravesar dunas |
| **Restricciones** | Sin mejoras de caballería pesada |

**Estrategia:** Expansión rápida y barata + raids de caballería ligera. Excelente en mapas áridos.

---

### Francos
| Campo | Valor |
|---|---|
| **Héroe** | Jean de Béthencourt |
| **Habilidad** | *Diplomacia Forzada* — Convierte la unidad enemiga más cercana durante 12 s · Recarga 60 s |
| **Unidad única** | **Caballero Normando** — 130 PV · 75c+65o · Edad 2 · *Carga de Lanza*: primer ataque tras ≥80 px hace ×2,5 daño |
| **Bonificadores** | Coste avance de edad ×0.85 · HP caballería ×1.15 · Vel. construcción granjas ×1.20 |
| **Restricciones** | Sin arquería completa · Sin armada tardía |

**Estrategia:** Avance rápido de edad + caballería potente. Presión constante en Edad de Castillo.

---

### Britanos
| Campo | Valor |
|---|---|
| **Héroe** | Francis Drake |
| **Habilidad** | *Saqueo* — Genera 15 de oro por cada unidad enemiga eliminada en rango durante 20 s · Recarga 55 s |
| **Unidad única** | **Arquero de Longbow** — 40 PV · 30m+60o · Edad 2 · *Perforación de Armadura*: +4 daño extra vs caballería |
| **Bonificadores** | Rango arqueros +1 por edad avanzada · Vel. ataque barcos de guerra ×1.20 |
| **Restricciones** | Sin mejoras de caballería pesada |

**Estrategia:** Dominio naval + arquería de largo alcance. Muy eficaz en mapas de islas.

---

### Castellanos
| Campo | Valor |
|---|---|
| **Héroe** | Don Quijote |
| **Habilidad** | *Carga del Caballero Errante* — Carga en línea recta causando gran daño a todo lo que encuentre · Recarga 55 s |
| **Unidad única** | **Conquistador** — 80 PV · 60c+60o · Edad 2 · *Salva* (CD 12 s): 3 disparos de 6 daño c/u, ignora armadura |
| **Bonificadores** | HP espadachín ×1.15 · Rango torres/castillos ×1.10 · Tecnología gratis en Herrería por avance de edad |
| **Restricciones** | Ninguna |

**Estrategia:** Civilización completa sin restricciones. Muy poderosa en partidas largas gracias a las tecnologías gratuitas.

---

### Atlantes
| Campo | Valor |
|---|---|
| **Héroe** | Artaxerax |
| **Habilidad** | *Calima* — Envuelve unidades aliadas cercanas en una niebla de calima durante 12 s; las unidades camufladas no pueden ser apuntadas por enemigos · Recarga 60 s |
| **Unidad única** | **Invocador de Mareas** — 75 PV · 50c+70o · Edad 2 · *Pulso Mareal*: cada ataque hace 2 daño en área en 65 px |
| **Bonificadores** | Visión costera ×1.50 (unidades y edificios a menos de 400 px de la costa) · Vel. ataque barcos ×1.20 · Más difíciles de detectar en la Niebla Marina (se descubren a 90 px en vez de 180 px) · Sin penalización en aguas poco profundas · Pueden atravesar océano |
| **Restricciones** | Sin caballería pesada · Sin taller de asedio |

**Estrategia:** Supremacía naval absoluta. Devastadores en mapas costeros y de islas.

---

### Fenicios
| Campo | Valor |
|---|---|
| **Héroe** | Hannón el Navegante |
| **Habilidad** | *Ruta Comercial* — Genera 50 de oro a lo largo de 30 s · Recarga 50 s |
| **Unidad única** | **Trirreme** — 160 PV · 100m+50o · Edad 1 · *Espolón*: ×2 daño vs barcos + empuja 40 px · pob 2 |
| **Bonificadores** | Mercado disponible desde Edad Oscura · Los barcos mercantes generan oro pasivo |
| **Restricciones** | Sin caballeros · Sin infantería de castillo |

**Estrategia:** Economía de oro superior desde el primer minuto. Ideal para financiar tecnologías y unidades caras.

---

## Héroes — Referencia rápida

| Héroe | Civilización | HP | Vel. | Ataque | Rango | Arm. M/P | Habilidad | Recarga |
|---|---|---|---|---|---|---|---|---|
| Bencomo | Guanches | 180 | 105 | 14 | 1.5 | 3/1 | +30% vel. ataque aliados 10 s | 50 s |
| Doramas | Canarii | 160 | 115 | 12 | 1.5 | 2/2 | Taunt enemigo 6 s | 45 s |
| Guadarfía | Mahos | 140 | 130 | 11 | 1.5 | 1/2 | Invisibilidad 8 s | 45 s |
| Jean de Béthencourt | Francos | 150 | 110 | 11 | 1.5 | 3/2 | Conversión enemigo 12 s | 60 s |
| Francis Drake | Britanos | 145 | 120 | 10 | 3.5 | 1/3 | 15 oro/baja durante 20 s | 55 s |
| Don Quijote | Castellanos | 170 | 125 | 16 | 1.5 | 4/1 | Carga en línea recta | 55 s |
| Artaxerax | Atlantes | 155 | 110 | 10 | 4.0 | 2/3 | Sigilo aliados 12 s | 60 s |
| Hannón el Navegante | Fenicios | 135 | 105 | 8 | 3.5 | 1/2 | 50 oro en 30 s | 50 s |
