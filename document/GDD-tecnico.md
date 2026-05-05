# 🔧 Mayor's Factory Tycoon - GDD Tecnico

## 📖 1. Panoramica

**Mayor's Factory Tycoon** è un factory/tycoon game Roblox dove ogni player possiede un **plot personale** su griglia.

Il player costruisce una fabbrica usando:
- 🏭 Macchinari | 🔗 Conveyor | 🔀 Splitter/Merger | ⚡ Generatori | 🎨 Decorazioni

Gli **item prodotti** sono fisici/visuali, scorrono sui conveyor, **non entrano nell'inventario** e servono solo come merci di produzione/trasporto/vendita.

### Tre Linee Produttive Iniziali

| Linea | NPC | Ruolo |
|-------|-----|-------|
| 🪵 **Legno** | Mira - Falegname | Legno base |
| 🏗️ **Pietra** | Bront - Muratore | Materiali costruzione |
| ⚒️ **Ferro** | Elrik - Fabbro | Componenti industriali |
| 🏛️ **Sindaco** | - | Progresso città (Town Prestige) |

---

## 🔄 2. Core Loop

```
Compra/Sblocca Macchinario
    ↓
Piazza nella fabbrica + Collega Conveyor/Splitter/Merger
    ↓
Genera Item Fisici
    ↓
Raffina/Combina con altre macchine
    ↓
Trasporta a Sell Zone NPC
    ↓
Ottieni Money + Reputazione NPC + Contributi Città
    ↓
Sblocca Nuove Macchine, Ricette, Generatori, Town Prestige
    ↓
Espandi & Riorganizza Fabbrica
```

**Principio:** Il player deve **migliorare progressivamente**, non solo comprare bottoni lineari.

---

## 📦 3. Tipi di Oggetti

### **3.1 Placeable Items** 🏗️
Oggetti posseduti dal player, piazzabili nella fabbrica.

| Categoria | Esempi |
|-----------|--------|
| **Produttori** | Lumber Harvester, Quarry, Iron Mine |
| **Lavoratori** | Sawmill, Furnace, Stone Cutter |
| **Trasporto** | Conveyor, Splitter, Merger |
| **Energia** | Small Generator, Windmill |
| **Decorazioni** | Trees, Signs, etc. |

**Proprietà:**
- ✅ Comprabili | ✅ Piazzabili | ✅ Rotabili | ✅ Rimovibili

### **3.2 Production Items** 📦
Merci generate da macchine, trasportate su conveyor.

| Linea | Item |
|-------|------|
| 🪵 Legno | Log, Plank, Beam, Crate |
| 🏗️ Pietra | Stone, Stone Block, Brick, Sand, Glass |
| ⚒️ Ferro | Iron Ore, Iron Ingot, Iron Plate, Gear |
| 🔗 Combinati | House Kit, Workshop Kit, Generator Kit |

**Regole:**
- ❌ Non raccoglibili dal player
- ❌ Non entrano nell'inventario
- ❌ Non salvati al logout
- ✅ Devono raggiungere macchine/sell zone fisicamente
- 💥 Distruzione con pop-out se percorso invalido

### **3.3 Contribution Stats** 📊
Statistiche automatiche generate dalle vendite.

```
LifetimeSold["Plank"] += 1
NpcSold["Mira"]["Plank"] += 1
MayorContribution["Plank"] += 1
```

Usate dal Sindaco per verificare requisiti Town Prestige.

---

## 👥 4. NPC Specializzati

### **4.1 🪵 Mira - Falegname**

| Aspetto | Dettagli |
|---------|----------|
| **Accetta** | Plank, Beam, Crate |
| **Sblocca** | Sawmill, Beam Cutter, Crate Assembler |
| **Bonus** | Prezzo item legno, Reputation boost legno |

### **4.2 🏗️ Bront - Muratore**

| Aspetto | Dettagli |
|---------|----------|
| **Accetta** | Stone Block, Brick, Glass |
| **Sblocca** | Stone Cutter, Brick Kiln, Glass Furnace |
| **Bonus** | Prezzo item pietra, Reputation boost pietra |

### **4.3 ⚒️ Elrik - Fabbro**

| Aspetto | Dettagli |
|---------|----------|
| **Accetta** | Iron Ingot, Iron Plate, Gear |
| **Sblocca** | Furnace, Plate Press, Gear Maker |
| **Bonus** | Ponte verso generatori avanzati & macchine industriali |

### **4.4 🏛️ Sindaco**

Gestisce il **Town Prestige** (non è NPC specialistico).

**Requisiti Town Prestige:**
- NPC Reputation X
- Contribution Stats (item venduti)
- Item combinati consegnati
- Generatori costruiti
- Obiettivi produttivi

**Ricompense per Stage:**
- ⚡ +Power Capacity
- 🏘️ Nuovi edifici cittadini
- 🛍️ Shop item aggiuntivi
- 🔧 Nuove recipe
- 🎨 Crescita visiva città

---

## 🌆 5. Town Prestige System

**Non è un rebirth:** la fabbrica continua, non resetta.

Rappresenta: il livello della città, lo stato del plot, accesso a contenuti avanzati.

**Stages iniziali:**
1. 🏕️ Outpost
2. 🏘️ Village
3. 🏙️ Town
4. 🌃 Small City

**Per ogni stage:**
- Requisiti specifici (Reputazione + Contribution Stats)
- Ricompense (Power +, Unlock, Visuals)
- Evoluzione edifici cittadini

---

## ⚡ 6. Power System

Ogni plot ha una **capacità energetica globale**.

**Formato UI:** `47 / 80 Power`

### Regole

| Elemento | Consuma Power? |
|----------|---|
| Macchine | ✅ Sì (variabile per tipo) |
| Conveyor | ❌ No |
| Splitter/Merger | ❌ No (al lancio) |
| Decorazioni | ❌ No |
| Generatori | ⚡ Aumentano Capacity |

### Esempi Capacità

| Generatore | Power Prodotto |
|------------|---|
| Base | 30 |
| Small Generator | +20 |
| Windmill | +40 |
| Steam Generator | +75 |

**Messaggio Errore:**
> Not enough Power. Build more generators or increase Town Prestige.

**Al lancio NON incluso:**
- ❌ Cavi/Reti separate
- ❌ Carburante/Manutenzione
- ❌ Range elettrico
- ❌ Blackout localizzati

---

## 🏠 7. Plot Structure

### **7.1 Zona Fabbrica** 🏭
L'unica area **realmente modificabile**.

Il player piazza:
- Macchine | Conveyor | Splitter | Merger | Generatori | Decorazioni

✅ Sistema di griglia già implementato.  
✅ Ogni item piazzabile = 1 blocco griglia.

### **7.2 Zona Vendita NPC** 🛍️
Posizionata su bordo del plot.

Contiene **sell zone dedicate** agli NPC.

Quando Production Item entra:
- ✅ NPC accetta → Venduto (Money + Rep)
- ❌ NPC non accetta → Distrutto
- ❌ Item da altro player → Ignorato/Distrutto

**Requisiti Production Item:**
- `ownerId` | `plotId` | `itemId`

### **7.3 Municipio / Sindaco** 🏛️
Contiene il Sindaco + menu Town Prestige.

L'aspetto cambia con ogni stage:
- 🏕️ Outpost
- 🏘️ Village
- 🏙️ Town
- 🌃 Small City

Al lancio: esplorazione opzionale, ma visibilità mandatoria.

### **7.4 Notice Board / Shop Area** 📌
Area di supporto:
- Reminder
- Premium shop
- Quest board
- Trash/Reclaim station

**Al lancio:** Semplice e non invasiva.

---

## 📱 8. Inventario & Hotbar

**Hotbar UI:**
- 1-9 Custom Hotbar
- 🗑️ Delete Mode button
- 🎒 Backpack button
- 💰 Money display
- 💎 Diamond display
- ⚡ Power display

**Delete Mode:**
- ✅ Select placed object
- ✅ Object → Transparent + Red border
- ✅ Confirm → Torna nell'inventario
- ✅ Input interni → Distrutti
- ✅ Item su conveyor → Distrutti

---

## 🎮 9. NPC UI Menus

**Posizione:** Top-left pulsanti

| Menu | Accesso |
|------|---------|
| 🏛️ Sindaco | Town Prestige |
| 🪵 Mira | Legno |
| 🏗️ Bront | Pietra |
| ⚒️ Elrik | Ferro |
| 📖 Almanacco | Guida/Scoperte |
| 🏆 Leaderboard | Classifiche |

### Tab Reputazione

Mostra:
- NPC modello & punchline
- Reputation level + progress bar
- Item accettati & prezzi
- Reputation guadagnata per item
- Ricompense per livello

**Unlock automazione:** Le ricompense importanti si sbloccano automaticamente.

### Tab Shop

| Colonna | Contenuto |
|---------|-----------|
| Icona | Modello item |
| Nome | Item name |
| Descrizione | Cosa fa |
| Recipe | Item richiesti |
| Prezzo | Money / Diamond / Robux |

---

## 🏭 10. Machine UI

Ogni macchina ha **overhead UI** (visibile quando vicino).

**Mostra:**
- Recipe attuale
- Input richiesti vs soddisfatti
- Output prodotto
- Craft progress
- Craft speed

**Interazione:** Tieni premuto E → Apri interfaccia macchina.

**Interfaccia Macchina:**
- Modello macchina
- Recipe disponibili
- Recipe attuale + progresso
- Input storage
- Output buffer

**Regola:** Se la macchina contiene input, non si può cambiare recipe finché non svuotata.

---

## 🚛 11. Production Items & Conveyor

**Ogni item ha:**
- `itemId` | `ownerUserId` | `plotId`
- `currentTile` | `direction` | `speed`
- `lifetime` | `stuckTimer` | `state`

**Movimento:** Deterministico **tile-to-tile** (non fisica Roblox arbitraria).

### Ogni Step

L'item controlla il prossimo tile:
- ✅ Conveyor compatibile → Avanza
- ✅ Machine input valido → Entra nella macchina
- ✅ Sell zone valida → Venduto
- ✅ Splitter/Merger → Instradato
- ❌ Tile invalido → Distrutto (pop-out animation)

### Limiti Consigliati

| Limite | Valore |
|--------|--------|
| Max item lifetime | 60 sec |
| Max stuck time | 2 sec |
| Max active items/plot | 100 |
| Max sell events/NPC/sec | Debounced |

---

## 🔧 12. Macchine & Crafting

**Ogni macchina ha:**
- `machineId` | `ownerId` | `plotId`
- `recipeId` | `inputStorage` | `outputBuffer`
- `craftTime` | `powerCost` | `gridPosition` | `rotation`

### Regole Crafting

1. ✅ Se input storage contiene tutti gli item → Craft inizia
2. ✅ A fine craft → Output entra output buffer
3. ✅ Se tile output libero → Output emesso
4. ❌ Se output bloccato → Macchina si ferma
5. ❌ Se macchina rimossa → Input & output interni distrutti

---

## 💰 13. Economy

### Money 💵
- **Uso:** Comprare macchine, conveyor, generatori, upgrade
- **Source:** Vendere item

### Diamond 💎
- **Uso:** Boost, skin, decorazioni, slot extra, convenience
- **Source:** Giocando (rare) + acquisto
- **Importante:** ❌ Non deve bloccare progressione core

### Robux ⚙️
- **Uso:** Gamepass, developer products, Diamond packs, cosmetici, booster
- **Al lancio escludere:**
  - ❌ Loot box
  - ❌ Ricompense random premium
  - ❌ Macchine OP premium-only
  - ❌ Admin abuse

### Formula Prezzo

```
FinalPrice = BasePrice × NpcDemandMult × PlayerBoostMult × ServerBoostMult
FinalRep = BaseRep × NpcRepMult × PlayerRepBoost
```

**Al lancio:** Sistema semplice, nessun mercato complesso.

---

## 💾 14. Salvataggio

### Da Salvare ✅
- 💰 Money | 💎 Diamond
- 🏛️ Town Prestige & NPC Reputation
- 🔧 Unlocked Machines
- 📦 Placeable Inventory & Hotbar
- 🗺️ Placed Plot Objects
- ⚡ Power Capacity
- 📊 Delivery Stats
- 📚 Tutorial State

### Da NON Salvare ❌
- 🚛 Production Items sui conveyor
- 📥 Input interni macchine
- ⏱️ Craft progress in corso
- 🔒 Item bloccati in transito

### Al Rientro del Player
- ✅ Fabbrica caricata completa
- ✅ Conveyor vuoti
- ✅ Macchine vuote
- ✅ Progressione + inventario + layout conservati

---

## 🔒 15. Server Authority

**Server autoritativo su:**
- ✅ Acquisti | ✅ Piazzamento | ✅ Rimozione
- ✅ Vendita item | ✅ Money & Diamond
- ✅ Reputazione & Town Prestige
- ✅ Delivery Stats | ✅ Robux receipts
- ✅ Salvataggio & Unlock

**Client gestisce:**
- 🎮 Preview piazzamento
- 🎨 UI & animazioni
- ✨ Effetti visivi
- ⌨️ Input utente

**Regola Oro:** ❌ Il client NON decide vendite, soldi, reputazione o progressione.

---

## 🎓 16. Tutorial / FTUE

**Obiettivo:** Introdurre tutti e 3 gli NPC in ~20 minuti.

**Sequenza:**
1. Piazza Lumber Harvester
2. Piazza Conveyor
3. Piazza Sawmill
4. Vendi Plank a Mira → Apri menu Mira
5. Sblocca Beam Cutter
6. Piazza Quarry → Vendi Stone Block a Bront
7. Piazza Iron Mine → Vendi Iron Ingot a Elrik
8. Costruisci primo generatore
9. Produci item combinato
10. Consegnalo al Sindaco → Introduci Town Prestige

**Principio:** Un sistema alla volta, non tutti insieme.

---

## 📋 17. Launch Scope

### Must Have 🔴
- ✅ 6 plot | ✅ Grid placement
- ✅ Hotbar + Inventory | ✅ Place/Remove/Rotate
- ✅ Conveyor straight/turn | ✅ Item fisici deterministici
- ✅ Machine crafting | ✅ Sell zones NPC
- ✅ 3 NPC + Sindaco | ✅ Reputazione
- ✅ Town Prestige | ✅ Money & Power
- ✅ Generatori | ✅ Salvataggio
- ✅ Tutorial | ✅ NPC/Machine/Shop UI

### Should Have 🟡
- ⚠️ Splitter & Merger
- ⚠️ Diamond system
- ⚠️ Almanacco semplice
- ⚠️ Leaderboard base
- ⚠️ Town visual stages
- ⚠️ NPC punchlines
- ⚠️ Prezzi con moltiplicatori

### Post-Launch 🟢
- 🟢 Apple/Farming | 🟢 Clay/Carbon | 🟢 Gold/Copper
- 🟢 Admin events chaos | 🟢 Leaderboard nazionale
- 🟢 Edifici esplorabili | 🟢 Prezzi dinamici
- 🟢 Recipe multiple | 🟢 Daily rewards avanzate
