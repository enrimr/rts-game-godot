# Las Llamas de Tamarán — Historia de la Campaña

> Estado: **DOCUMENTO DE REVISIÓN** — la parte 1 recoge la historia tal como
> está en el juego, la parte 2 es la crítica, la parte 3 es la revisión
> propuesta. Nada de la parte 3 está implementado; cada propuesta anota su
> coste para poder aprobarlas por separado.

---

## 1 · La historia actual

**Título de la campaña:** *Las Llamas de Tamarán* — «los canarii contra la
invasión atlante — cuatro batallas por el archipiélago».

| # | Misión | Mapa / Modo | Punto de la historia |
|---|---|---|---|
| 0 | Prólogo: El Primer Asentamiento | Llanura, tutorial | «Antes de las velas de bronce, estaba la tierra.» Los ancianos enseñan a asentarse, alimentarse, defenderse. **Rival: castellanos. Jugador: guanches.** |
| 1 | La Vanguardia | Estándar, conquista | Velas de bronce al amanecer. Los atlantes levantan una cabeza de playa en Tamarán. **Doramas** reúne a los guerreros de los barrancos: destruid el campamento antes de que eche raíces. |
| 2 | Tierra de Fuego | Costa Volcánica, resistir 12 min | El volcán responde con ceniza. Tierra escasa, oleadas bajo la ceniza que cae. **Guayarmina** vigila desde el risco: resistid hasta que pase «la noche sagrada». |
| 3 | El Estrecho | Islas, conquista | Los invasores dominan el agua; su puerto en la otra orilla alimenta la guerra. Construye una flota en secreto, cruza, quémalo todo. *(Sin personajes con nombre.)* |
| 4 | La Última Montaña | Costa Volcánica, regicidio | Dos ejércitos atlantes cierran el cerco sobre el último bastión. «Mientras **su campeona que no muere** siga en pie, la invasión no podrá romperse. Encontradla. Acabad con esto.» *(Campeona sin nombre.)* |

Los textos completos de introducción de las misiones viven en
`project/assets/translations/translations.csv`
(`CAMP_M0_INTRO` … `CAMP_M4_INTRO`); los datos de las misiones, en
`project/scripts/campaign/campaign_data.gd`.

---

## 2 · Crítica

**Lo que ya funciona**

- El arco militar en cuatro actos es sólido: repeler la cabeza de playa →
  sobrevivir al contragolpe → romper su línea de suministro → cortar la
  cabeza. Clásico y limpio.
- Fuerte sentido del lugar: barrancos, ceniza, campos negros, el estrecho. La
  prosa tiene voz («velas de bronce cortan el horizonte»).
- La escalada llega a través de los SISTEMAS DEL JUEGO, no solo del texto: el
  clima se activa en la M2, la marina en la M3, el regicidio en la M4. Las
  mecánicas sostienen el drama.

**Debilidades**

1. **El prólogo rompe la ficción.** La campaña es canarii contra atlantes,
   pero el prólogo se juega como *guanches* contra *castellanos*: un
   protagonista Y un enemigo distintos de los de la historia que introduce.
2. **No hay hilo protagonista.** Doramas aparece en la M1 y desaparece;
   Guayarmina «vigila desde un risco» en la M2 y desaparece; la M3 y la M4 no
   las narra nadie. La campaña no tiene a nadie por quien preocuparse.
3. **La antagonista aparece de la nada.** La «campeona que no muere» de la M4
   nunca se ve, se nombra ni se anticipa en las M1–M3. La recompensa no tiene
   preparación.
4. **Los atlantes no tienen motivo.** ¿Por qué los señores del mar profundo
   quieren una isla volcánica? Sin una razón son villanos de decorado — y el
   juego ya posee la razón perfecta (ver parte 3).
5. **Las misiones terminan en silencio.** Hay textos de introducción pero no
   de cierre: quemas el puerto, la pantalla dice «Victoria» y la historia
   nunca reconoce lo que costó ni lo que significa. El arco no tiene tejido
   conectivo.
6. **La ficción más rica del juego está ausente de su propia campaña.** Las
   harimaguadas (sacerdotisas neutrales que atienden a todos los ejércitos),
   el presa canario, el almogarén, el sigilo de la Niebla del Mar, la calima —
   todos son sistemas reales con trasfondo real, y ninguno se menciona en la
   historia que debería lucirlos.
7. **«La noche sagrada» (M2) es un cabo suelto.** Evocadora, pero nunca se
   explica ni se vuelve a mencionar.

---

## 3 · Revisión propuesta

### 3.1 La premisa: dar un corazón a la invasión

**Los atlantes no son conquistadores: son los ahogados.** Su reino insular se
hundió bajo el Atlántico (la leyenda sobre la que ya está construida la
civilización). **Cleito, la Señora de las Mareas** — en los propios archivos
del juego, «esposa mortal de Poseidón en la leyenda de la Atlántida» — guía
la flota superviviente. Su pueblo cree que un reino muerto por agua solo puede
renacer por fuego: vienen a por **el volcán de Tamarán**, la última gran
llama del océano, para coronarlo como su nuevo trono. Refugiados convertidos
en invasores — equivocados, pero no malvados.

Esto no cuesta nada a nivel mecánico: Cleito y su almirante **Artaxerax** ya
existen como unidades héroe atlantes, y la M4 ya es regicidio: la «campeona
que no muere» que el jugador debe matar **es literalmente ella**. La historia
solo tiene que decir su nombre.

### 3.2 Los protagonistas: un hilo que seguir

- **Doramas** sostiene la M1 y la M4 — el guerrero de los barrancos que
  asciende de escaramuzador de la vanguardia al hombre que debe acabar la
  guerra. El texto de su propia unidad dice que «solo puede matarlo la
  traición» (como en la leyenda histórica): la campaña debería DECIRLO, y
  dejar que penda sobre el final como un presagio.
- **Guayarmina** sostiene la M2 y la M3 — la arquera guardiana. En la M2
  defiende el risco; en la M3 el plan de construir la flota en secreto bajo la
  niebla del mar es suyo.
- **Las harimaguadas** son el hilo moral: sacerdotisas de las islas que
  atienden a *todos* los ejércitos que respetan sus santuarios — incluidos
  los heridos atlantes. A través de ellas el jugador conoce el dolor del
  enemigo (ver los momentos de la M2/M4), lo que hace que el final se sienta
  como una tragedia evitada y no como un exterminio.

### 3.3 Misión a misión

Cada bloque: **intro propuesta** (sustituye a la actual), **outro propuesta**
(nueva — requiere la pequeña función `outro_key`, ver 3.4), en español
primero para revisión; la réplica en inglés se escribirá al aprobarse.

---

**M0 · Prólogo — "El Primer Asentamiento"**

*Corrección:* el rival pasa a ser **atlantes** (una partida de exploración) y
el jugador pasa a ser **canarii**, en línea con la campaña. Un cambio de una
línea en los datos.

> **Intro (ES):** «Antes de las velas de bronce, estaba la tierra. Los ancianos
> guiarán tu mano: levanta un asentamiento, alimenta a tu gente, arma a sus
> defensores. Y presta atención a las velas extrañas que rondan la costa —
> los pescadores dicen que preguntan por la montaña de fuego.»
>
> **Outro (ES):** «El asentamiento respira. Pero esa noche, en la playa, las
> huellas de los extraños llegaban hasta el agua… y ninguna volvía.»

**M1 · "La Vanguardia"** *(texto actualizado, objetivos sin cambios — los
objetivos del Molino/perro ganan ahora su línea de historia)*

> **Intro (ES):** «Velas de bronce cortan el amanecer. Los atlantes — los
> ahogados del mar profundo — han clavado un campamento en la costa de
> Tamarán. Doramas reúne a los guerreros de los barrancos: "Cada oveja, cada
> molino, cada perro pastor alimenta esta guerra. Echadlos al agua antes de
> que echen raíces."»
>
> **Outro (ES):** «El campamento arde. Entre los restos, Doramas encuentra un
> estandarte empapado que ninguna ola trajo: un tridente coronado. "No es una
> incursión", dice. "Es un éxodo."»

**M2 · "Tierra de Fuego"** *(la «noche sagrada» recibe su significado; entran
las harimaguadas)*

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

**M3 · "El Estrecho"** *(Artaxerax entra como antagonista visible; la niebla
del mar se convierte en historia — ya es una mecánica de sigilo)*

> **Intro (ES):** «El almirante Artaxerax domina el agua entre las islas:
> ninguna canoa cruza sin encontrar espolones de bronce, y su puerto alimenta
> la guerra con guerreros y acero. Guayarmina señala la niebla del mar: "Su
> velo también puede ser el nuestro. Construid la flota donde la niebla
> duerme, cruzad el estrecho y quemad hasta el último tablón."»
>
> **Outro (ES):** «El puerto arde y Artaxerax se retira hacia el volcán. Antes
> de perderse en la calima, grita sobre el agua: "¡Habéis quemado madera! ¡La
> Señora de las Mareas no navega — espera!"»

**M4 · "La Última Montaña"** *(la campeona tiene un nombre y un dolor; la
leyenda de Doramas cierra el arco)*

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

### 3.4 Notas de implementación

| Propuesta | Coste |
|---|---|
| Reescribir los 5 textos de introducción (EN+ES en translations.csv) | Trivial — solo texto |
| Rival del prólogo castellanos→atlantes, civ guanches→canarii | Una línea en campaign_data.gd (volver a verificar que el guion del tutorial sigue pasando check_campaign) |
| **Outros**: `outro_key` por misión, mostrada como panel/aviso al vencer antes de volver a la pantalla de campaña | Pequeño — MissionDirector ya posee el gancho de la victoria y un sistema de avisos |
| Nombrar a Cleito/Artaxerax | Gratis — ambos héroes existen; el regicidio de la M4 ya hace aparecer al héroe atlante como el objetivo real a matar |
| Opcional: avisos de historia a mitad de misión (p. ej., M2, oleada 3: «¡La ceniza esconde sus estandartes!») reutilizando `_toast` en los tiempos de oleada | Pequeño — un campo `"story"` en las entradas de oleada |
| Opcional: aparición guionizada de Artaxerax entre las patrullas de la M3 | Medio — aparición de un héroe enemigo fuera del regicidio; prescindible, la línea del outro lo sostiene |

**No se propone:** ramificaciones, cinemáticas ni cambiar el número de
misiones — la forma de cuatro batallas es la correcta; solo necesita a su
gente y sus razones.
