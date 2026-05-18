# Civilizaciones, Unidades y Árbol de Tecnologías

> Datos extraídos directamente de los recursos del proyecto (`resources/`).
> Edades: **0** Dark Age · **1** Feudal · **2** Castle · **3** Imperial.

---

## Edificios comunes

| Edificio | Coste | Edad mín. | HP | Función |
|---|---|---|---|---|
| Town Center | 275 madera | 0 | 2400 | Entrena aldeanos · drop-off · reaparición héroe |
| Casa | 25 madera | 0 | 550 | +5 cap. población |
| Cuartel | 175 madera | 0 | 1200 | Entrena infantería |
| Establo | 175 madera | 0 | 1100 | Entrena caballería |
| Herrería | 150 madera | 1 | 1000 | Investiga armas y armaduras |
| Mercado | 175 madera | 1 | 900 | Comercio de recursos |
| Aserradero | 100 madera | 0 | 600 | Drop-off madera |
| Campamento minero | 100 madera | 0 | 600 | Drop-off oro / piedra |
| Granja | 60 madera | 0 | 300 | Fuente de comida continua |
| Muelle | 150 madera | 0 | 1800 | Entrena barcos |
| Taller de asedio | 200 madera | 2 | 1200 | Entrena asedio |
| Universidad | 200 madera | 2 | 1100 | Tecnologías avanzadas |
| Templo | 175 madera | 2 | 900 | Moral y curación |
| Segmento de muro | 5 piedra | 0 | 700 | Defensa |
| Puerta | 30 madera | 0 | 500 | Paso aliado |
| Trampa de peces | 75 madera | 0 | 600 | Fuente pasiva de comida (océano) |
| Maravilla | 2500m+2500c+2500p+5000o | 3 | — | Condición de victoria |

---

## Unidades comunes

### Aldeanos (Town Center)
| Unidad | Coste | Tiempo | HP | Vel | Ataque | Rango |
|---|---|---|---|---|---|---|
| Aldeano | 50 comida | 25 s | 25 | 120 | 3 | 1.5 |

### Infantería (Cuartel)
| Unidad | Edad | Coste | Tiempo | HP | Vel | Ataque | Rango | Armadura M/P |
|---|---|---|---|---|---|---|---|---|
| Milicia | 0 | 60c + 20m | 21 s | 40 | 100 | 4 | 1.5 | 0 / 0 |
| Arquero | 1 | 25m + 45o | 35 s | 30 | 110 | 5 | 4.0 | 0 / 0 |
| Lancero | 2 | 60c + 30o | 28 s | 65 | 90 | 7 | 1.5 | 1 / 0 |

### Caballería (Establo)
| Unidad | Edad | Coste | Tiempo | HP | Vel | Ataque | Rango | Armadura M/P | Notas |
|---|---|---|---|---|---|---|---|---|---|
| Scout | 0 | 80c | 30 s | 35 | 180 | 2 | 0.8 | 0 / 0 | Habilidad: Explorar 60 s |
| Heavy Scout | 1 | 80c + 30o | 30 s | 80 | 130 | 6 | 1.5 | 1 / 0 | |
| Caballero | 2 | 60c + 75o | 45 s | 120 | 115 | 9 | 1.5 | 2 / 1 | |

> **Scout — Habilidad Explorar (tecla E):** El Scout deambula autónomamente por el mapa durante **60 segundos**, eligiendo un nuevo destino cada 3-7 s. Se puede cancelar con el mismo botón.

### Asedio (Taller de asedio)
| Unidad | Edad | Coste | Tiempo | HP | Vel | Ataque | Rango | Notas |
|---|---|---|---|---|---|---|---|---|
| Ariete | 2 | 160m | 60 s | 180 | 55 | 40 | 1.0 | ×3 daño edificios · pop 2 |
| Mangonela | 2 | 160m + 135o | 60 s | 90 | 60 | 35 | 7.0 | AoE 72 px · rango mínimo · pop 2 |
| Trebuchet | 3 | 200m + 200o | 70 s | 70 | 48 | 200 | 12.0 | Despliega 3 s · pop 2 |

### Naval (Muelle)
| Unidad | Edad | Coste | Tiempo | HP | Vel | Ataque | Rango |
|---|---|---|---|---|---|---|---|
| Barca pesquera | 0 | 75m | 25 s | 45 | 90 | 0 | — |
| Barco transporte | 1 | 125m | 45 s | 150 | 80 | 0 | — |
| Galera de guerra | 1 | 75m + 35o | 35 s | 120 | 85 | 6 | 5.5 |

---

## Árbol de tecnologías

### Herrería (Blacksmith)
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Efecto |
|---|---|---|---|---|---|
| Telares | 0 | 50c | 25 s | — | HP aldeanos ×1.15 |
| Forja | 1 | 75c | 40 s | — | Ataque unidades ×1.15 |
| Fundición de hierro | 2 | 150o | 55 s | Forja | Ataque unidades ×1.20 |
| Alto horno | 3 | 275c + 225o | 50 s | — | Ataque unidades ×1.15 |
| Armadura de escamas | 1 | 100c + 50o | 40 s | — | Armadura cuerpo a cuerpo +1 |
| Armadura de cadenas | 2 | 200c + 100o | 45 s | Esc. escamas | Armadura cuerpo a cuerpo +1 |
| Armadura de placas | 3 | 300c + 200o | 60 s | Esc. cadenas | Armadura cuerpo a cuerpo +1 |
| Armadura arquero | 1 | 100c | 35 s | — | Armadura perforante arquero +1 |
| Flechado | 1 | 100o | 35 s | — | Ataque arquero ×1.20 |
| Punta bodkin | 2 | 100c + 150o | 35 s | Flechado | Ataque arquero ×1.20 · Rango ×1.10 |
| Barda de escamas | 1 | 100c + 50o | 40 s | — | Armadura M unidades +1 |
| Barda de placas | 3 | 300c + 200o | 60 s | Barda cadenas | Armadura M unidades +1 |
| Astillero | 1 | 200m + 60o | 40 s | — | HP barcos ×1.15 · Coste -15% |

### Universidad (University)
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Efecto |
|---|---|---|---|---|---|
| Balística | 2 | 175o | 50 s | Flechado | Vel. ataque arquero ×1.20 |
| Química | 3 | 300o | 70 s | Balística | Ataque arquero ×1.15 |
| Ingeniería de asedio | 2 | 200o | 60 s | — | Daño a edificios ×1.20 |

### Templo (Temple / Monastery)
| Tecnología | Edad | Coste | Tiempo | Prerrequisito | Efecto |
|---|---|---|---|---|---|
| Fervor | 2 | 150o | 50 s | — | Vel. movimiento unidades ×1.10 |
| Santidad | 2 | 100c | 40 s | — | HP espadachín ×1.15 |
| Expiación | 3 | 150c + 100o | 55 s | Santidad | HP caballería ×1.20 |

---

## Civilizaciones

### Guanches
| Campo | Valor |
|---|---|
| **Héroe** | Bencomo |
| **Habilidad** | *Carga de Menceyes* — Galvaniza unidades aliadas cercanas: +30% velocidad de ataque durante 10 s · Recarga 50 s |
| **Unidad única** | Menceyes Guard |
| **Bonificadores** | Edificios de piedra HP ×1.20 · Lanzas desde Dark Age · Atraviesan malpais |
| **Restricciones** | Sin caballería · Sin pólvora |

**Estrategia:** Fortaleza defensiva con infantería resistente. Ideal para mapas con volcanes.

---

### Canarii
| Campo | Valor |
|---|---|
| **Héroe** | Doramas |
| **Habilidad** | *Desafío* — Provoca a la unidad enemiga más cercana para que ataque a Doramas durante 6 s · Recarga 45 s |
| **Unidad única** | Arquero de barranco |
| **Bonificadores** | Aldeanos recolectan comida ×1.15 · Coste comida arqueros ×0.80 |
| **Restricciones** | Sin caballería pesada |

**Estrategia:** Economía de comida superior + arquería barata. Ideal para rush de arqueros.

---

### Mahos
| Campo | Valor |
|---|---|
| **Héroe** | Guadarfía |
| **Habilidad** | *Emboscada* — Casi invisible durante 8 s; enemigos no pueden atacarle automáticamente · Recarga 45 s |
| **Unidad única** | Sand Raider |
| **Bonificadores** | Coste madera edificios ×0.70 · Scout/caballería ligera vel. ×1.25 · Atraviesan dunas |
| **Restricciones** | Sin actualizaciones caballería pesada |

**Estrategia:** Expansión rápida y barata + raids de caballería ligera. Excelente en mapas áridos.

---

### Francos
| Campo | Valor |
|---|---|
| **Héroe** | Jean de Béthencourt |
| **Habilidad** | *Diplomacia Forzada* — Convierte la unidad enemiga más cercana durante 12 s · Recarga 60 s |
| **Unidad única** | Chevalier Normand |
| **Bonificadores** | Coste avance de edad ×0.85 · HP caballería ×1.15 · Vel. construcción granjas ×1.20 |
| **Restricciones** | Sin arquería completa · Sin armada tardía |

**Estrategia:** Avance rápido de edad + caballería potente. Presión constante en Castle Age.

---

### Britanos
| Campo | Valor |
|---|---|
| **Héroe** | Francis Drake |
| **Habilidad** | *Saqueo* — Genera 15 oro por unidad enemiga eliminada en rango durante 20 s · Recarga 55 s |
| **Unidad única** | Longbowman |
| **Bonificadores** | Rango arqueros +1 por edad avanzada · Vel. ataque barcos de guerra ×1.20 |
| **Restricciones** | Sin actualizaciones caballería pesada |

**Estrategia:** Dominancia naval + arquería de largo alcance. Muy eficaz en mapas Islands.

---

### Castellanos
| Campo | Valor |
|---|---|
| **Héroe** | Don Quijote |
| **Habilidad** | *Carga del Caballero Errante* — Carga en línea recta dañando todo lo que encuentre · Recarga 55 s |
| **Unidad única** | Conquistador |
| **Bonificadores** | HP espadachín ×1.15 · Rango torres/castillos ×1.10 · Tecnología gratis en Herrería por avance de edad |
| **Restricciones** | Ninguna |

**Estrategia:** Civilización completa sin restricciones. Fuerte en late game con tecnologías gratuitas.

---

### Atlantes
| Campo | Valor |
|---|---|
| **Héroe** | Artaxerax |
| **Habilidad** | *Calima* — Envuelve unidades aliadas cercanas en calima durante 12 s; los enemigos no pueden apuntarles · Recarga 60 s |
| **Unidad única** | Tidecaller |
| **Bonificadores** | Visión costera ×1.50 · Vel. ataque barcos ×1.20 · Sin penalización agua poco profunda · Atraviesan océano |
| **Restricciones** | Sin caballería pesada · Sin taller de asedio |

**Estrategia:** Supremacía naval absoluta. Devastadores en mapas costeros e Islands.

---

### Fenicios
| Campo | Valor |
|---|---|
| **Héroe** | Hannón el Navegante |
| **Habilidad** | *Ruta Comercial* — Genera 50 de oro a lo largo de 30 s · Recarga 50 s |
| **Unidad única** | Trireme |
| **Bonificadores** | Mercado disponible desde Dark Age · Tasa pasiva de oro en barcos mercantes |
| **Restricciones** | Sin caballeros · Sin infantería de castillo |

**Estrategia:** Economía de oro superior desde el primer minuto. Ideal para financiar tecnologías y unidades caras.

---

## Héroes — referencia rápida

| Héroe | Civilización | HP | Vel | Ataque | Rango | Arm M/P | Habilidad | Recarga |
|---|---|---|---|---|---|---|---|---|
| Bencomo | Guanches | 180 | 105 | 14 | 1.5 | 3/1 | +30% vel. ataque aliados 10 s | 50 s |
| Doramas | Canarii | 160 | 115 | 12 | 1.5 | 2/2 | Taunt enemigo 6 s | 45 s |
| Guadarfía | Mahos | 140 | 130 | 11 | 1.5 | 1/2 | Invisibilidad 8 s | 45 s |
| Jean de Béthencourt | Francos | 150 | 110 | 11 | 1.5 | 3/2 | Conversión enemigo 12 s | 60 s |
| Francis Drake | Britanos | 145 | 120 | 10 | 3.5 | 1/3 | 15 oro/kill en 20 s | 55 s |
| Don Quijote | Castellanos | 170 | 125 | 16 | 1.5 | 4/1 | Carga en línea | 55 s |
| Artaxerax | Atlantes | 155 | 110 | 10 | 4.0 | 2/3 | Sigilo aliados 12 s | 60 s |
| Hannón el Navegante | Fenicios | 135 | 105 | 8 | 3.5 | 1/2 | 50 oro en 30 s | 50 s |
