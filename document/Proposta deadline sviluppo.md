# ⏰ Mayor's Factory Tycoon - Roadmap 12 Settimane

## 📋 Assunzione

| Metrica | Valore |
|---------|--------|
| **Durata** | 12 settimane |
| **Disponibilità** | 20 ore/settimana |
| **Total** | 240 ore |
| **Launch Week** | +1 settimana solo polish & bugfix |

**Obiettivo:** Versione giocabile, salvabile, bilanciata e pubblicabile.

---

## 🗓️ Piano Settimanale

### **Week 1️⃣ - Consolidamento GDD & Data Model**
**Obiettivo:** Bloccare struttura dati e scope

**Deliverable:**
- ✅ Item definitions | Machine definitions | Recipe definitions
- ✅ NPC definitions | Reputation levels | Town Prestige levels
- ✅ Power values | Save data schema | Project structure
- ✅ Naming conventions

**Fine settimana:** Il progetto ha dati coerenti e sai cosa implementare.

---

### **Week 2️⃣ - Inventario, Hotbar & Shop Base**
**Obiettivo:** Gestire Placeable Items

**Deliverable:**
- ✅ Hotbar custom | Backpack/Inventory
- ✅ Assegnazione item a hotbar | Shop base
- ✅ Money spend | Delete mode integrata

**Fine settimana:** Player può comprare, tenere e piazzare oggetti.

---

### **Week 3️⃣ - Conveyor & Item Movement**
**Obiettivo:** Movimento deterministico di Production Items

**Deliverable:**
- ✅ Item spawn | Straight & Turn conveyor
- ✅ Next-tile validation | Destroy su tile invalido
- ✅ Stuck timer | Max item per plot | Pop-out animation

**Fine settimana:** Item viaggia su conveyor e sparisce correttamente.

---

### **Week 4️⃣ - Macchine & Crafting**
**Obiettivo:** Input → Storage → Crafting → Output

**Deliverable:**
- ✅ Machine input validation | Recipe check | Craft timer
- ✅ Output buffer | Output su conveyor
- ✅ Craft stop se bloccato | Machine UI debug

**Fine settimana:** Macchina riceve input, crafta, produce output.

---

### **Week 5️⃣ - Linea Legno + Mira 🪵**
**Obiettivo:** Prima linea produttiva completa

**Deliverable:**
- ✅ Lumber Harvester | Sawmill | Beam Cutter | Crate Assembler
- ✅ Log | Plank | Beam | Crate
- ✅ Mira sell zone | Reputation | Delivery Stats

**Fine settimana:** Player produce e vende legno a Mira.

---

### **Week 6️⃣ - Linea Pietra + Bront 🏗️**
**Obiettivo:** Seconda linea produttiva

**Deliverable:**
- ✅ Quarry | Stone Cutter | Brick Kiln
- ✅ Stone | Stone Block | Brick | Sand/Glass (opzionale)
- ✅ Bront sell zone | Reputation | Delivery Stats

**Fine settimana:** Player produce e vende pietra a Bront.

---

### **Week 7️⃣ - Linea Ferro + Elrik ⚒️**
**Obiettivo:** Terza linea + Componenti industriali

**Deliverable:**
- ✅ Iron Mine | Furnace | Plate Press | Gear Maker
- ✅ Iron Ore | Ingot | Plate | Gear
- ✅ Elrik sell zone | Reputation | Delivery Stats

**Fine settimana:** Tutti e 3 gli NPC specializzati funzionanti.

---

### **Week 8️⃣ - Power System & Generatori ⚡**
**Obiettivo:** Corrente come limite di espansione

**Deliverable:**
- ✅ Power Used / Power Capacity
- ✅ Power cost per machine | Generatori piazzabili
- ✅ Small Generator | Windmill | Power UI
- ✅ Blocco piazzamento se manca Power

**Fine settimana:** Player deve costruire generatori per espandere.

---

### **Week 9️⃣ - Sindaco + Town Prestige 🏛️**
**Obiettivo:** Progressione globale

**Deliverable:**
- ✅ Mayor NPC & UI | Town Prestige levels
- ✅ Requisiti basati su Delivery Stats & NPC Reputation
- ✅ House/Workshop/Generator Kit | Assembler combinati
- ✅ Town visual stage

**Fine settimana:** Player aumenta Town Prestige consegnando item.

---

### **Week 1️⃣0️⃣ - Salvataggio & Caricamento 💾**
**Obiettivo:** Gioco persistente

**Deliverable:**
- ✅ Save: Money | Diamond | NPC Reputation | Town Prestige
- ✅ Save: Unlocked machines | Inventory | Hotbar | Placed objects
- ✅ Save: Delivery Stats | Tutorial state
- ✅ Data corruption fallback | Autosave | Save on leave

**Fine settimana:** Player non perde progressione.

---

### **Week 1️⃣1️⃣ - Tutorial & UI Finale MVP 📚**
**Obiettivo:** Game comprensibile per nuovo player

**Deliverable:**
- ✅ Tutorial: Legno → Pietra → Ferro → Power → Sindaco
- ✅ Objective tracker | Messaggi errore chiari
- ✅ NPC/Machine/Shop UI rifinita
- ✅ Basic Almanac (se tempo)

**Fine settimana:** Nuovo player arriva ai 3 NPC senza spiegazioni.

---

### **Week 1️⃣2️⃣ - Stabilizzazione & Performance 🚀**
**Obiettivo:** Release candidate

**Deliverable:**
- ✅ Performance test (6 player) | Item limit tuning
- ✅ Bugfix: Conveyor | Crafting | Salvataggio
- ✅ Bilanciamento: Prezzi | Reputazione | Town Prestige
- ✅ Mobile check | Exploit check base
- ✅ Thumbnail | Description Roblox

**Fine settimana:** Versione pronta al lancio.

---

## 🎯 Launch Week - Polish & Release

**Regola:** ❌ Nessuna nuova feature.

**Attività:**
- 🐛 Bugfix critici
- 👥 Test con amici
- 📖 Correzioni onboarding
- 🖼️ Thumbnail & icona finale
- 📝 Descrizione
- ⚙️ Game settings Roblox
- 📊 Analytics base (se pronti)

---

## ⚠️ Tagli di Emergenza (Priority Order)

**Se in ritardo, taglia in questo ordine:**
1. Modelli rotanti negli shop
2. Almanacco
3. Leaderboard globale
4. Town visual stages (oltre 2°)
5. Diamond
6. Splitter/Merger
7. Glass/Sand
8. Windmill
9. Recipe multiple
10. Shop premium/Robux

**❌ NON TAGLIARE MAI:**
- ✅ Salvataggio
- ✅ Tutorial
- ✅ Sell zones
- ✅ Power system
- ✅ 3 NPC
- ✅ Town Prestige
- ✅ Machine crafting
- ✅ Item cleanup

---

## ✨ Milestone Finale - Publishable If

Il gioco è pubblicabile se TUTTE queste frasi sono vere:

- ✅ Un player nuovo completa il tutorial
- ✅ Tutti e 3 gli NPC si incontrano entro ~20 minuti
- ✅ Gli item fisici non causano accumuli infiniti
- ✅ Le macchine non duplicano item
- ✅ Player vende item e riceve Money/Reputation
- ✅ Sindaco aumenta Town Prestige con Delivery Stats
- ✅ Power limita correttamente l'espansione
- ✅ Salvataggio funziona
- ✅ 6 player giocano senza lag grave
- ✅ Gameplay dura 60-120 minuti