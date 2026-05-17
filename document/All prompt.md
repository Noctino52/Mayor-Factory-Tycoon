# 🎯 Mayor's Factory Tycoon - Lista di 100 Prompt Incrementali

## 📌 Istruzioni Uso
- Ogni prompt **presuppone che il precedente sia completato**
- Leggi il contesto all'inizio di ogni prompt per capire il punto di partenza
- Ogni prompt è focalizzato su **una feature specifica**, non tutto insieme
- Al fine di ogni implementazione, il gioco deve essere **almeno testabile** (anche se non perfetto)

---

# 🔴 FASE 1: Data Model & Struttura Base (Prompt 1-5)

## 📝 PROMPT 1 - Creare il Data Model Centralizzato

### Contesto
Attualmente il sistema ha solo item piazzabili base (RubiksCube, TreeFarm, MineEntrance, Sawmill) e non esiste una struttura dati centralizzata che definisca:
- Tutti gli item e le loro proprietà
- I macchinari e le loro ricette
- Gli NPC e cosa comprano
- I costi e ricavi

### Obiettivo
Creare un modulo **Definitions.lua** in `ReplicatedStorage/Shared/` che funzioni sia lato server che client, contenente tutte le definizioni immutabili del gioco.

### Dettagli Tecnici

**File da creare:** `src/Shared/Definitions.luau`

Deve contenere le seguenti tabelle di definizioni:

```
ITEMS = {
  -- Production Items (item di trasporto/vendita, NON piazzabili)
  Log = { name = "Log", icon = "🪵", category = "wood", value = 10, rarity = "common" }
  Plank = { name = "Plank", icon = "🪨", category = "wood", value = 15, rarity = "common" }
  Stone = { name = "Stone", icon = "🪨", category = "stone", value = 12, rarity = "common" }
  StoneBlock = { name = "StoneBlock", icon = "🧱", category = "stone", value = 18, rarity = "common" }
  IronOre = { name = "IronOre", icon = "⚙️", category = "iron", value = 20, rarity = "common" }
  IronIngot = { name = "IronIngot", icon = "⚙️", category = "iron", value = 30, rarity = "common" }
  
  -- Placeable Items (item che il player piazza nella fabbrica)
  TreeFarm = { name = "TreeFarm", icon = "🌳", category = "machine", cost = 100, type = "producer" }
  MineEntrance = { name = "MineEntrance", icon = "⛏️", category = "machine", cost = 150, type = "producer" }
  Sawmill = { name = "Sawmill", icon = "🏭", category = "machine", cost = 75, type = "processor" }
  Conveyor = { name = "Conveyor", icon = "🔗", category = "transport", cost = 25, type = "transport" }
  Splitter = { name = "Splitter", icon = "🔀", category = "transport", cost = 50, type = "transport" }
  Merger = { name = "Merger", icon = "🔀", category = "transport", cost = 50, type = "transport" }
}

MACHINES = {
  -- Producer machines (generano item senza input)
  TreeFarm = { 
    name = "TreeFarm", 
    type = "producer", 
    outputItem = "Log", 
    outputRate = 1, 
    outputFrequency = 5, -- ogni 5 secondi
    powerRequired = 10 
  }
  MineEntrance = { 
    name = "MineEntrance", 
    type = "producer", 
    outputItem = "IronOre", 
    outputRate = 1, 
    outputFrequency = 6,
    powerRequired = 15 
  }
  
  -- Processor machines (trasformano item)
  Sawmill = { 
    name = "Sawmill", 
    type = "processor", 
    inputItem = "Log", 
    outputItem = "Plank", 
    conversionRate = 1, 
    powerRequired = 8 
  }
}

NPCS = {
  Mira = { 
    name = "Mira", 
    title = "Falegname", 
    icon = "👨", 
    specialization = "wood", 
    buysItems = { "Plank", "Beam", "Crate" },
    baseReputationReward = 5,
    basePriceMultiplier = 1.0,
    unlocksAt = { reputation = 0 } -- Unlocked from start
  }
  Bront = { 
    name = "Bront", 
    title = "Muratore", 
    icon = "👷", 
    specialization = "stone", 
    buysItems = { "StoneBlock", "Brick", "Glass" },
    baseReputationReward = 5,
    basePriceMultiplier = 1.0,
    unlocksAt = { reputation = 0 }
  }
  Elrik = { 
    name = "Elrik", 
    title = "Fabbro", 
    icon = "⚒️", 
    specialization = "iron", 
    buysItems = { "IronIngot", "IronPlate", "Gear" },
    baseReputationReward = 5,
    basePriceMultiplier = 1.0,
    unlocksAt = { reputation = 0 }
  }
  Mayor = { 
    name = "Sindaco", 
    title = "Gestione Città", 
    icon = "👔", 
    specialization = "prestige", 
    collectsContributions = true
  }
}

TOWN_PRESTIGE_STAGES = {
  { 
    stage = 1, 
    name = "Outpost", 
    requirements = { totalContribution = 0 },
    rewards = { powerCapacity = 50, newShopItems = {} }
  }
  { 
    stage = 2, 
    name = "Village", 
    requirements = { totalContribution = 500, miraReputation = 50 },
    rewards = { powerCapacity = 100, newShopItems = {} }
  }
}

CURRENCIES = {
  Money = { symbol = "💵", type = "earneable", source = "selling" }
  Diamond = { symbol = "💎", type = "earneable", source = "achievements" }
  Robux = { symbol = "Ⓡ", type = "premium", source = "gamepasses" }
}
```

### Specifiche di Implementazione

1. **Modulare:** Le definizioni devono essere **immutabili** (read-only dopo il caricamento)
2. **Accessible:** Qualunque script possa fare `local Defs = require(game.ReplicatedStorage.Shared.Definitions)`
3. **Funzione Helper:** Includere funzioni per:
   - `GetItem(itemName) -> table or nil`
   - `GetMachine(machineName) -> table or nil`
   - `GetNPC(npcName) -> table or nil`
   - `IsProduction(itemName) -> boolean` (distingue item da vendere da item piazzabili)
   - `IsMachine(itemName) -> boolean`
4. **Validazione:** Quando carica, controlla che non ci siano conflitti di nome tra ITEMS, MACHINES, NPCS

### Cosa Verificare
- [ ] Il file carica senza errori
- [ ] `require(game.ReplicatedStorage.Shared.Definitions)` funziona
- [ ] Tutte le funzioni helper funzionano
- [ ] Puoi accedere a qualunque definizione senza errori
- [ ] Se aggiungi un item nuovo a ITEMS, la mappa interna si aggiorna

### File Modificati
- ✅ **Nuovo:** `src/Shared/Definitions.luau`

### File Toccati (per importare)
- `src/ServerScriptService/InventoryManager.server.luau` (lo importerà più tardi)
- `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau` (lo importerà più tardi)

---

## 📝 PROMPT 2 - Sistema di Valute e Progressione del Player

### Contesto
Hai il Data Model, ora devi implementare il **salvataggio della progressione** del player:
- Denaro (Money)
- Reputazione con ogni NPC
- Town Prestige level
- Statistiche di vendita (LifetimeSold, NpcSold, MayorContribution)

Tutto deve essere salvato in DataStore e recaricato al ritorno del player.

### Obiettivo
Creare un modulo server `PlayerProgress.lua` che gestisca tutta la progressione del player, e integarlo in `InventoryManager.server.luau`.

### Dettagli Tecnici

**File da creare:** `src/ServerScriptService/PlayerProgress.luau`

Deve gestire:

```lua
PlayerProgress = {
  money = 0,
  npcReputation = {
    Mira = 0,
    Bront = 0,
    Elrik = 0
  },
  townPrestige = {
    stage = 1,
    contributions = 0
  },
  statistics = {
    lifetimeSold = {
      -- Item -> count
      Log = 0,
      Plank = 0,
      ...
    },
    npcSold = {
      -- NPC -> { Item -> count }
      Mira = { Plank = 10, Beam = 5 },
      Bront = { StoneBlock = 20 },
      ...
    },
    mayorContribution = {
      -- Item -> count (totali contribuiti al sindaco)
      Log = 100,
      ...
    }
  }
}
```

### Funzioni da Implementare

1. **`GetPlayerProgress(player) -> table`**
   - Carica il salvataggio DataStore del player
   - Se non esiste, ritorna i valori di default
   - Se DataStore fallisce, usa fallback in memoria

2. **`SavePlayerProgress(player, progressData)`**
   - Salva la progressione su DataStore
   - Funziona anche se il player ha appena venduto item
   - Se salva, ritorna `(success, error_message)`

3. **`AddMoney(player, amount)`**
   - Aggiunge denaro, salva immediatamente
   - Ritorna il nuovo balance
   - Se amount < 0, controlla che il player abbia abbastanza

4. **`AddReputation(player, npcName, amount)`**
   - Aumenta reputazione con un NPC
   - Automaticamente controlla se sblocca nuovo Town Prestige
   - Ritorna { newReputation, leveledUp, newUnlocks }

5. **`RecordSale(player, itemName, npcName, quantity)`**
   - Registra una vendita nelle statistiche
   - Aggiorna `lifetimeSold`, `npcSold`, `mayorContribution`
   - Ritorna le nuove statistiche

6. **`CheckTownPrestigeUpgrade(player) -> boolean`**
   - Controlla se il player soddisfa i requisiti per il prossimo stage
   - Se sì, effettua l'upgrade e ritorna true
   - Altrimenti ritorna false

### Specifiche di Implementazione

1. **Schema DataStore:** 
   ```lua
   Key: "PlayerData_" .. userId
   Value: {
     money = X,
     npcReputation = {...},
     townPrestige = {...},
     statistics = {...},
     lastSaved = tick()
   }
   ```

2. **Fallback in Memoria:** Se DataStore è downato, i dati rimangono in memoria durante la sessione

3. **Auto-Salva:** Ogni modifica importante (soldi, reputazione) viene salvata immediatamente per evitare perdi

4. **Server-side Only:** Questo modulo **non** è in ReplicatedStorage, è solo nel ServerScriptService

### Cosa Verificare
- [ ] Quando un player join, i suoi dati vengono caricati/creati
- [ ] Quando aggiungi denaro, il DataStore viene aggiornato
- [ ] Quando il player esce, i dati sono salvati
- [ ] Se fai rejoin, i dati sono uguali
- [ ] Le funzioni ritornano i valori corretti

### File Modificati
- ✅ **Nuovo:** `src/ServerScriptService/PlayerProgress.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau` (integra PlayerProgress per salvare i plot)

---

## 📝 PROMPT 3 - Migliorare l'Inventario per Supportare Valute e Item Limits

### Contesto
Hai il salvataggio della progressione. Ora devi migliorare il sistema di inventario per:
- Riflettere il denaro del player nell'inventario
- Riflettere la reputazione con gli NPC
- Limitare il numero di item piazzabili per plot (es. max 20 macchine)
- Integrare le definizioni in modo che non devi aggiungere manualmente nuovi item

### Obiettivo
Aggiornare `InventoryManager.server.luau` per usare le Definitions e supportare valute, e creare il corrispondente client `CurrencyUI.client.luau`.

### Dettagli Tecnici

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau`

**File da creare:**
- `src/StarterPlayer/StarterPlayerScripts/CurrencyUI.client.luau`

### Changes nel Server

1. **Importa Definitions e PlayerProgress:**
   ```lua
   local Definitions = require(game.ReplicatedStorage.Shared.Definitions)
   local PlayerProgress = require(game.ServerScriptService.PlayerProgress)
   ```

2. **Aggiungi RemoteFunctions:**
   - `GetMoney` -> ritorna il denaro del player
   - `GetReputation` -> ritorna { npcName -> reputationValue }
   - `GetPlacedItems` -> ritorna lista di item piazzati nel plot

3. **Upgrade PlaceItem:**
   - Controlla che il player abbia abbastanza soldi
   - Sottrai il costo immediatamente
   - Registra l'item piazzato nella lista plot del player
   - Se il player ha max item (20), rifiuta il placement

4. **Upgrade DeleteItem:**
   - Quando cancella un item, rimborsa il 50% del costo al player

### Changes nel Client

Crea `CurrencyUI.client.luau`:

1. **Mostra HUD in alto a sinistra:**
   ```
   💵 Money: 1,250
   😊 Mira Rep: 50
   😊 Bront Rep: 30
   ⚒️ Elrik Rep: 10
   ```

2. **Update in Real-Time:**
   - Connetti a RemoteFunction `GetMoney` ogni 0.5 secondi
   - Mostra le variazioni di denaro con animazione (verde per +, rosso per -)

3. **Mostra Town Prestige:**
   ```
   🏛️ Stage 1: Outpost (0 / 500 contributi)
   ```

### Cosa Verificare
- [ ] L'HUD mostra correttamente i soldi
- [ ] Quando piazzi un item, i soldi scendono
- [ ] Quando cancelli un item, i soldi aumentano (50% rimborso)
- [ ] Se non hai soldi, non puoi piazzare
- [ ] Se hai 20 item, non puoi piazzare il 21°
- [ ] L'HUD si aggiorna in real-time

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- ✅ **Nuovo:** `src/StarterPlayer/StarterPlayerScripts/CurrencyUI.client.luau`

---

## 📝 PROMPT 4 - Implementare il Sistema di Shop Base

### Contesto
Hai il denaro e il piazzamento. Ora i player devono poter comprare item di base dal shop, non trovare i soldi dal nulla.

Lo shop deve vendere:
- Macchine base (TreeFarm 100💵, MineEntrance 150💵, Sawmill 75💵)
- Conveyor (25💵 l'uno)
- Decorazioni

### Obiettivo
Creare una UI di shop (con `ScreenGui` su StarterGui) dove il player può cliccare su item per aggiungerli all'inventario con il denaro che scende.

### Dettagli Tecnici

**File da creare:**
- `src/StarterGui/ShopUI.lua` (ScreenGui con frame dei pulsanti shop)
- `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau` (aggiungi RemoteEvent `BuyItem`)

### Server Changes

Aggiungi RemoteEvent `BuyItem`:
```lua
local buyItemRemote = Instance.new("RemoteEvent")
buyItemRemote.Name = "BuyItem"
buyItemRemote.Parent = ReplicatedStorage

buyItemRemote.OnServerEvent:Connect(function(player, itemName)
  local Definitions = require(game.ReplicatedStorage.Shared.Definitions)
  local item = Definitions.GetItem(itemName)
  
  if not item then return end
  if not item.cost then return end -- Non è un item piazzabile
  
  local currentMoney = PlayerProgress.GetPlayerProgress(player).money
  if currentMoney < item.cost then return end -- Insufficiente denaro
  
  -- Sottrai i soldi
  PlayerProgress.AddMoney(player, -item.cost)
  
  -- Aggiungi all'inventario
  AddItemToInventory(player, itemName, 1)
end)
```

### Client Changes

Crea `ShopClient.client.luau`:

1. **Mostra UI negozio:** Quando player preme "S" (o un bottone), apri una ScreenGui con griglia di item
   
2. **Mostra item comprabili:**
   - Per ogni item in Definitions con `cost`, mostra un bottone con:
     - Icona dell'item
     - Nome
     - Prezzo (💵 100)
   
3. **Click per comprare:**
   - Quando player clicca su item, invia `BuyItem` al server
   - Se successo, anima l'aggiunta all'inventario
   - Se fallisce (soldi insufficienti), mostra errore rosso

4. **Filtri (opzionale per quest'ora):**
   - Puoi filtrar e lo per categoria (Machines, Transport, Decorations)

### Cosa Verificare
- [ ] Shop si apre quando premi "S"
- [ ] Vedi tutti gli item comprabili con prezzo
- [ ] Quando clicchi su item e hai soldi, viene aggiunto all'inventario
- [ ] I soldi scendono immediatamente
- [ ] Se non hai soldi, non puoi comprare e vedi errore
- [ ] Shop si chiude quando premi Esc

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- ✅ **Nuovo:** `src/StarterGui/ShopUI.lua` (ScreenGui)
- ✅ **Nuovo:** `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`

---

## 📝 PROMPT 5 - Implementare il Sistema di Rotazione per Item Piazzati

### Contesto
Player piazza gli item ma sono sempre con la stessa rotazione. Devi permettere di rotare gli item:
- Prima del piazzamento (preview mostra rotazione)
- Dopo il piazzamento (click destro per rotare i 4 angoli)

### Obiettivo
Estendere il sistema di placement e deletion per supportare rotazione libera (0°, 90°, 180°, 270°).

### Dettagli Tecnici

**File da modificare:**
- `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau` (placement e preview)
- `src/ServerScriptService/InventoryManager.server.luau` (salva rotazione)

### Changes nel Client

1. **Durante Placement (preview):**
   - Premi "R" per rotare il preview di 90°
   - Il ghost item ruota visivamente
   - La griglia di placement si aggiorna in base alla nuova rotazione

2. **Mouse Raycast:**
   - Il raycast nel placement deve considerare la rotazione dell'item
   - Conveyor dritto: occcupa 1 cella (1x1)
   - Conveyor curvo: occupa 2 celle (2x1) in base a rotazione

3. **Dopo Placement:**
   - Click destro su item piazzato per aprire menu
   - Opzione "Rotate" ruota di 90° e salva sul server
   - L'item si ruota visivamente e salva la rotazione nel DataStore

### Changes nel Server

1. **Salva Rotazione nel Plot:**
   ```lua
   plot[position] = {
     name = "Conveyor",
     rotation = 0, -- 0, 1, 2, 3 (rappresentano 0°, 90°, 180°, 270°)
     placedAt = tick()
   }
   ```

2. **Aggiungi RemoteEvent `RotateItem`:**
   ```lua
   rotateItemRemote.OnServerEvent:Connect(function(player, position)
     local plot = GetPlayerPlot(player)
     if plot[position] then
       plot[position].rotation = (plot[position].rotation + 1) % 4
       SavePlayerPlot(player, plot)
     end
   end)
   ```

3. **Nel caricamento del plot**, applica CFrame con la rotazione giusta:
   ```lua
   local rotationAngles = {
     0 * math.pi / 2, -- 0°
     1 * math.pi / 2, -- 90°
     2 * math.pi / 2, -- 180°
     3 * math.pi / 2   -- 270°
   }
   item.CFrame = CFrame.new(position) * CFrame.Angles(0, rotationAngles[plot[position].rotation + 1], 0)
   ```

### Cosa Verificare
- [ ] Durante placement, premi "R" e il preview ruota
- [ ] La griglia si aggiorna correttamente per item che occupano multiple celle
- [ ] Piazzi un item e gli assegni una rotazione
- [ ] Al logout e login, l'item mantiene la rotazione
- [ ] Click destro su item e lo ruoti con menu

### File Modificati
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`

---

# 🟡 FASE 2: Core Gameplay Loop (Prompt 6-10)

## 📝 PROMPT 6 - Implementare il Sistema di Conveyor Dritto

### Contesto
Fino ad ora, hai solo il piazzamento di item. Ora inizia il vero gioco: il movimento dei production item sui conveyor.

Gli step:
1. Una macchina produce un Log
2. Il Log compare fisicamente su una cella del Conveyor
3. Il Log si muove lungo il Conveyor verso la destinazione

### Obiettivo
Creare un modulo server `ConveyorSystem.luau` che:
- Crea item fisici quando una macchina produce
- Muove i production item **fisicamente** su conveyors dritti
- Distrugge gli item che escono da conveyor invalidi
- Limita il numero di item per cella

### Dettagli Tecnici

**File da creare:**
- `src/ServerScriptService/ConveyorSystem.luau`
- `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua` (gestisce modelli dei production item)

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau` (aggiungi RemoteFunction `SpawnProductionItem`)

### Server Implementation

Nel ConveyorSystem:

```lua
local ConveyorSystem = {}

-- Configurazione
local PRODUCTION_ITEM_SPEED = 16 -- studs per secondo
local MAX_ITEMS_PER_CELL = 5
local GRID_UNIT_SIZE = 8

function ConveyorSystem.SpawnProductionItem(player, itemName, cellX, cellZ, conveyor)
  -- Crea un'istanza di production item
  -- Posiziona alla cella di inizio del conveyor
  -- Aggiunge alla lista di item attivi
  
  local plotInfo = GetPlayerPlot(player)
  local item = CreateProductionItemInstance(itemName, cellX, cellZ)
  
  -- Aggiungi la posizione e il prossimo movimento
  local activeItem = {
    model = item,
    itemName = itemName,
    cellX = cellX,
    cellZ = cellZ,
    player = player,
    startTime = tick(),
    totalDistance = GRID_UNIT_SIZE,
    isMoving = true
  }
  
  table.insert(activeItems, activeItem)
  return activeItem
end

function CreateProductionItemInstance(itemName, cellX, cellZ)
  -- Crea un'istanza piccolina dell'item
  -- Posiziona nella griglia
  -- Ritorna il modello
end

-- Main Loop ogni frame
RunService.Heartbeat:Connect(function(deltaTime)
  for i, activeItem in ipairs(activeItems) do
    if activeItem.isMoving then
      MoveItemAlongConveyor(activeItem, deltaTime)
    end
  end
end)

function MoveItemAlongConveyor(activeItem, deltaTime)
  -- Calcola la distanza percorsa
  local distanceTraveled = PRODUCTION_ITEM_SPEED * deltaTime
  local percentProgress = distanceTraveled / activeItem.totalDistance
  
  -- Aggiorna CFrame
  local currentPos = activeItem.model.Position
  local nextCellX = activeItem.cellX + 1 -- conveyor dritto va a destra
  local nextCellWorldPos = GridToWorldPosition(nextCellX, activeItem.cellZ)
  
  activeItem.model.CFrame = activeItem.model.CFrame:Lerp(
    CFrame.new(nextCellWorldPos),
    percentProgress
  )
  
  -- Se ha raggiunto la prossima cella
  if percentProgress >= 1 then
    activeItem.cellX = nextCellX
    activeItem.startTime = tick()
    
    -- Controlla cosa c'è nella prossima cella
    local nextCell = plotInfo[activeItem.cellX][activeItem.cellZ]
    if nextCell and nextCell.type == "conveyor" then
      -- Continua
    elseif nextCell and nextCell.type == "machine" then
      -- Input della macchina
      FeedMachine(nextCell, activeItem)
    elseif nextCell and nextCell.type == "sell_zone" then
      -- Sell zone, vendi l'item
      SellItem(activeItem)
    else
      -- Cella vuota o invalida, distruggi
      activeItem.model:Destroy()
      table.remove(activeItems, i)
    end
  end
end
```

### Specifiche

1. **Movimento Smooth:** Gli item si muovono fluidamente, non saltano da cella a cella
2. **Collisioni:** Max 5 item per cella, gli altri aspettano
3. **Distruzione:** Se un item esce da una mappa invalida, pop-out e scompare
4. **Modello Item:** Sono `Part` piccolini (0.5x0.5x0.5), colorati per tipo
5. **Performance:** Usa un'unica lista di activeItems, non create liste per ogni player

### Cosa Verificare
- [ ] Quando piazzi un Conveyor e lo collechi alla macchina, gli item appaiono fisicamente
- [ ] I Log si muovono lungo il conveyor in modo smooth
- [ ] Se il conveyor è pieno (5 item), i nuovi aspettano
- [ ] Se item esce da una cella invalida, scompare con animazione
- [ ] Performance rimane buona anche con 50+ item in movimento

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- ✅ **Nuovo:** `src/ServerScriptService/ConveyorSystem.luau`
- ✅ **Nuovo:** `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

---

## 📝 PROMPT 7 - Implementare il Sistema di Macchine Produttrici Base

### Contesto
Hai il conveyor e i production item si muovono. Ma non hai nessuna macchina che produce item!

Devi implementare le macchine produttrici base:
- **TreeFarm:** Produce Log ogni 5 secondi
- **MineEntrance:** Produce IronOre ogni 6 secondi

### Obiettivo
Creare un modulo server `MachineSystem.luau` che:
- Tiene traccia di quali macchine sono attive nel plot
- Ogni N secondi, une macchina genera un production item
- L'item appare nella cella di output della macchina
- La macchina richiede energia (semplice per ora, basta verificare che il generatore sia acceso)

### Dettagli Tecnici

**File da creare:**
- `src/ServerScriptService/MachineSystem.luau`

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau` (integra MachineSystem al caricamento plot)

### Implementation

```lua
local MachineSystem = {}
local Definitions = require(game.ReplicatedStorage.Shared.Definitions)

-- Tracked machines per player
local activeMachines = {} -- player -> { cellX, cellZ -> { machine data, lastProducedTime } }

function MachineSystem.RegisterMachine(player, cellX, cellZ, machineName)
  if not activeMachines[player] then
    activeMachines[player] = {}
  end
  
  local machineData = Definitions.GetMachine(machineName)
  if not machineData then return end
  
  activeMachines[player][cellX .. "_" .. cellZ] = {
    name = machineName,
    cellX = cellX,
    cellZ = cellZ,
    lastProducedTime = tick(),
    productionProgress = 0,
    isPowered = true
  }
end

function MachineSystem.UnregisterMachine(player, cellX, cellZ)
  if activeMachines[player] then
    activeMachines[player][cellX .. "_" .. cellZ] = nil
  end
end

-- Main loop
RunService.Heartbeat:Connect(function()
  for player, machines in pairs(activeMachines) do
    for key, machine in pairs(machines) do
      UpdateMachineProduction(player, machine)
    end
  end
end)

function UpdateMachineProduction(player, machine)
  if not machine.isPowered then return end
  
  local machineData = Definitions.GetMachine(machine.name)
  if not machineData then return end
  
  local timeSinceLastProduction = tick() - machine.lastProducedTime
  
  if timeSinceLastProduction >= machineData.outputFrequency then
    -- Produci un item
    local itemName = machineData.outputItem
    local outputCellX = machine.cellX + 1 -- Output cella a destra (da definire per macchina)
    local outputCellZ = machine.cellZ
    
    ConveyorSystem.SpawnProductionItem(player, itemName, outputCellX, outputCellZ)
    
    machine.lastProducedTime = tick()
  end
end
```

### Specifiche

1. **Rilevamento Macchine:** Quando un player piazza una macchina, registrala in MachineSystem
2. **Generazione Item:** Usa la frequenza di output da Definitions
3. **Energia Semplice:** Per ora, basta un bool `isPowered` che è sempre true (dopo faremo il sistema di generatori)
4. **Output Placement:** L'item esce dalla cella immediatamente a destra della macchina (specificare per macchina quando necessario)

### Cosa Verificare
- [ ] Piazzi una TreeFarm
- [ ] Ogni 5 secondi, un Log appare nella cella a destra
- [ ] I Log si muovono sul conveyor se c'è
- [ ] Se non c'è conveyor, il Log scompare
- [ ] Piazzi una MineEntrance, produce IronOre ogni 6 secondi
- [ ] Performance è buona anche con 10+ macchine che producono

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- ✅ **Nuovo:** `src/ServerScriptService/MachineSystem.luau`

---

## 📝 PROMPT 8 - Implementare il Sistema di Macchine Processatrici Base

### Contesto
Hai macchine che producono (TreeFarm -> Log). Ora devi macchine che processano (Sawmill: Log -> Plank).

Una macchina processatrice:
1. Aspetta un Log sulla sua cella di input
2. Quando riceve un Log, lo consuma
3. Dopo N secondi di "lavorazione", produce un Plank
4. Il Plank esce dalla cella di output

### Obiettivo
Estendere `MachineSystem.luau` per supportare macchine con input/output.

### Dettagli Tecnici

**File da modificare:**
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/ConveyorSystem.luau` (aggiungi hook per input macchina)

### Implementation Changes

In MachineSystem, aggiungereggiungi tracking per macchine processatrici:

```lua
activeMachines[player][key] = {
  name = "Sawmill",
  cellX = 5,
  cellZ = 3,
  type = "processor",
  inputQueue = {}, -- Coda di item in elaborazione
  lastProducedTime = tick(),
  isPowered = true,
  processingTime = {} -- item_id -> start_time
}
```

Modifiche:

1. **ConveyorSystem:** Quando un item raggiunge una macchina processatrice:
   ```lua
   function FeedMachine(machine, productionItem)
     table.insert(machine.inputQueue, {
       itemName = productionItem.itemName,
       receivedAt = tick()
     })
     productionItem.model:Destroy() -- Consuma l'item
   end
   ```

2. **MachineSystem:** Nel loop di produzione:
   ```lua
   function UpdateMachineProduction(player, machine)
     if machine.type == "processor" then
       -- Controlla se ci sono item in coda
       for i, inputItem in ipairs(machine.inputQueue) do
         local timeSinceAdded = tick() - inputItem.receivedAt
         local machineData = Definitions.GetMachine(machine.name)
         
         if timeSinceAdded >= machineData.processingTime then
           -- Produce output
           local outputItem = machineData.outputItem
           ConveyorSystem.SpawnProductionItem(player, outputItem, machine.cellX + 1, machine.cellZ)
           table.remove(machine.inputQueue, i)
         end
       end
     elseif machine.type == "producer" then
       -- Logica di prima...
     end
   end
   ```

3. **Visualizzazione:** Mostra sulla macchina qual quanti item sta processando (es. 2/3 slot pieni)

### Aggiorna Definitions

Aggiungi ai MACHINES:

```lua
Sawmill = {
  name = "Sawmill",
  type = "processor",
  inputItem = "Log",
  outputItem = "Plank",
  processingTime = 3, -- 3 secondi per trasformare
  inputQueueSize = 2, -- Massimo 2 Log in coda
  powerRequired = 8
}
```

### Cosa Verificare
- [ ] Piazzi una TreeFarm -> Conveyor -> Sawmill
- [ ] TreeFarm produce Log
- [ ] Log si muove sul conveyor
- [ ] Log raggiunge Sawmill e viene consumato
- [ ] Dopo 3 secondi, Plank esce da Sawmill
- [ ] Se Sawmill ha 2 Log in coda, il 3° aspetta
- [ ] Performance rimane buona

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/ConveyorSystem.luau`

---

## 📝 PROMPT 9 - Implementare il Sistema di Sell Zones e Vendita

### Contesto
Hai la produzione (TreeFarm -> Conveyor -> Sawmill -> Plank). Ma dove vendono i Plank?

Devi creare **Sell Zones** - celle speciali dove i player mettono gli item per venderli agli NPC.

Ogni plot ha zone di vendita dedicate a ogni NPC:
- Mira's Sell Zone
- Bront's Sell Zone
- Elrik's Sell Zone

### Obiettivo
Implementare un sistema di **Sell Zones** che:
1. Sono celle speciali piazzabili dal player (no cost, solo UI)
2. Quando un production item raggiunge una Sell Zone, viene venduto automaticamente
3. Il player riceve denaro + reputazione + contributi cittadini

### Dettagli Tecnici

**File da creare:**
- `src/ServerScriptService/SellSystem.luau`

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau` (aggiungi UI per piazzare Sell Zones)
- `src/ServerScriptService/ConveyorSystem.luau` (hook per Sell Zones)

### Implementation

In SellSystem:

```lua
local SellSystem = {}
local PlayerProgress = require(game.ServerScriptService.PlayerProgress)
local Definitions = require(game.ReplicatedStorage.Shared.Definitions)

-- Tracked sell zones per player
local sellZones = {} -- player -> { cellX, cellZ -> npcName }

function SellSystem.CreateSellZone(player, cellX, cellZ, npcName)
  if not sellZones[player] then
    sellZones[player] = {}
  end
  
  local npcData = Definitions.GetNPC(npcName)
  if not npcData then return false end
  
  sellZones[player][cellX .. "_" .. cellZ] = npcName
  return true
end

function SellSystem.SellItem(player, itemName, cellX, cellZ)
  local sellZoneKey = cellX .. "_" .. cellZ
  if not sellZones[player] or not sellZones[player][sellZoneKey] then
    return false
  end
  
  local npcName = sellZones[player][sellZoneKey]
  local itemData = Definitions.GetItem(itemName)
  local npcData = Definitions.GetNPC(npcName)
  
  -- Controlla che l'NPC accetti questo item
  if not table.find(npcData.buysItems, itemName) then
    return false
  end
  
  -- Calcola il prezzo
  local basPrice = itemData.value
  local npcMultiplier = npcData.basePriceMultiplier
  local sellingPrice = math.floor(basePrice * npcMultiplier)
  
  -- Aggiungi soldi al player
  PlayerProgress.AddMoney(player, sellingPrice)
  
  -- Registra la vendita
  PlayerProgress.RecordSale(player, itemName, npcName, 1)
  
  -- Aggiungi reputazione
  PlayerProgress.AddReputation(player, npcName, npcData.baseReputationReward)
  
  return true
end
```

Nel ConveyorSystem, modifica il movimento:

```lua
function MoveItemAlongConveyor(activeItem, deltaTime)
  -- ... movimento ...
  
  -- Controlla la destinazione
  local nextCell = plotInfo[activeItem.cellX .. "_" .. activeItem.cellZ]
  if nextCell and nextCell.type == "sell_zone" then
    local success = SellSystem.SellItem(activeItem.player, activeItem.itemName, activeItem.cellX, activeItem.cellZ)
    if success then
      activeItem.model:Destroy()
      table.remove(activeItems, i)
    end
  end
end
```

### Specifiche

1. **UI Sell Zone:** Nel placement, aggiungi un'opzione per selezionare una Sell Zone e quale NPC
2. **Visualizzazione:** Sell Zones sono celle colorate (verde per Mira, marrone per Bront, grigio per Elrik)
3. **Automatico:** Quando un item raggiunge, vende automaticamente (no click necessario)
4. **Feedback:** Mostra pop-up verde con "+100💵 +5 Rep (Mira)"

### Cosa Verificare
- [ ] Puoi piazzare una Sell Zone e scegliere NPC
- [ ] Quando item raggiunge Sell Zone, viene venduto
- [ ] Ricevi denaro + reputazione
- [ ] Se item non è accettato da NPC, scompare (o rimane?)
- [ ] L'HUD mostra aggiornamenti di denaro e reputazione

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/ConveyorSystem.luau`
- ✅ **Nuovo:** `src/ServerScriptService/SellSystem.luau`

---

## 📝 PROMPT 10 - Implementare il Sistema di Splitter e Merger Base

### Contesto
Fino ad ora, il conveyor è solo lineare (va sempre a destra). Devi aggiungere **Splitter e Merger** per creare reti di produzione complesse:

- **Splitter:** 1 input, 2 output. Divide gli item in due flussi
- **Merger:** 2 input, 1 output. Combina item da due fonti

### Obiettivo
Estendere il sistema di conveyor per supportare Splitter e Merger, permettendo al player di creare reti più complesse.

### Dettagli Tecnici

**File da modificare:**
- `src/ServerScriptService/ConveyorSystem.luau`

### Implementation

Modifica il sistema di movimento:

```lua
-- Invece di "nextCellX = cellX + 1", leggi da una tabella di connessioni
local CELL_CONNECTIONS = {
  -- cellX_cellZ -> { direction -> { nextCellX, nextCellZ } }
  -- direction: "right", "top", "bottom"
}

function RouteItem(player, cellX, cellZ, itemName)
  local cellKey = cellX .. "_" .. cellZ
  local cell = GetCell(player, cellX, cellZ)
  
  if cell.type == "splitter" then
    -- Dividi l'item tra due output
    -- Es: se il numero dell'item è pari, vai a destra, altrimenti in basso
    if itemName:byte() % 2 == 0 then
      return { cellX + 1, cellZ }
    else
      return { cellX, cellZ + 1 }
    end
  elseif cell.type == "merger" then
    -- Merger ha 2 input, 1 output
    -- L'item va sempre a destra (output unico)
    return { cellX + 1, cellZ }
  elseif cell.type == "conveyor" then
    -- Conveyor semplice: dipende dalla rotazione
    if cell.rotation == 0 then
      return { cellX + 1, cellZ } -- Destra
    elseif cell.rotation == 1 then
      return { cellX, cellZ + 1 } -- Basso
    elseif cell.rotation == 2 then
      return { cellX - 1, cellZ } -- Sinistra
    elseif cell.rotation == 3 then
      return { cellX, cellZ - 1 } -- Su
    end
  end
  
  return nil
end
```

### Specifiche

1. **Splitter:** 
   - Ha 1 cella di input (a sinistra)
   - Ha 2 celle di output (destra e basso)
   - Alterna gli item tra i due output per bilanciare il flusso

2. **Merger:**
   - Ha 2 celle di input (sinistra e basso)
   - Ha 1 cella di output (destra)
   - Combina i flussi in ordine di arrivo

3. **Performance:** Tutti gli item usano lo stesso sistema di routing, nessuno è speciale

### Cosa Verificare
- [ ] Piazzi un Splitter tra una macchina e due Conveyor
- [ ] Gli item si dividono tra i due percorsi
- [ ] Piazzi un Merger che riceve da due Conveyor
- [ ] Gli item si combinano correttamente
- [ ] Performance rimane buona anche con network complesse

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/ConveyorSystem.luau`

---

# ✅ Primi 10 Prompt Completati!

A questo punto hai:
- ✅ Data Model strutturato
- ✅ Sistema di salvataggio dati
- ✅ Inventario e shop
- ✅ Rotazione item
- ✅ Conveyor lineare
- ✅ Macchine produttrici
- ✅ Macchine processatrici
- ✅ Sell system
- ✅ Splitter e Merger

**Il core loop è funzionante!** Player può:
1. Comprare macchine dal shop
2. Piazzarle e collegarle con conveyor
3. Le macchine producono item
4. Item si muovono sui conveyor
5. Splitter divide il flusso
6. Merger combina i flussi
7. Item raggiungono Sell Zone e vengono venduti
8. Player riceve denaro + reputazione

---

# 🟠 FASE 3: Consolidamento Core Loop & MVP Systems (Prompt 11-20)

## 📝 PROMPT 11 - Implementare Conveyor Curvi e Routing a 4 Direzioni

### Contesto
Il core loop funziona con conveyor dritti, splitter e merger. Però il GDD richiede anche conveyor curvi/turn, altrimenti le fabbriche diventano troppo rigide e difficili da organizzare.

Il sistema attuale usa rotazione e direzione dei conveyor, quindi bisogna estenderlo senza rompere:
- Conveyor dritti
- Splitter
- Merger
- Machine input
- Sell zone

### Obiettivo
Aggiungere un item piazzabile **CurvedConveyor** che cambia direzione agli item di 90°, rispettando la rotazione del player.

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/ConveyorSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau`

### Changes in Definitions

Aggiungi un item:

```lua
CurvedConveyor = {
  name = "CurvedConveyor",
  icon = "↪",
  category = "transportation",
  cost = 35,
  type = "curved_conveyor",
  isMachine = false,
  isProduction = false
}
```

### Changes in ConveyorSystem

Estendi il routing:

```lua
function RouteCurvedConveyor(cell, previousCellX, previousCellZ)
  -- La curva ha 1 input e 1 output
  -- rotation 0: input da sinistra -> output in alto
  -- rotation 1: input dal basso -> output a destra
  -- rotation 2: input da destra -> output in basso
  -- rotation 3: input dall'alto -> output a sinistra
end
```

Regole:
- Se l'item entra dal lato corretto, viene instradato verso l'output
- Se entra dal lato sbagliato, viene distrutto con animazione pop-out
- La curva deve funzionare in tutte le 4 rotazioni
- Il routing deve restare deterministico tile-to-tile

### Specifiche

1. **Template Fallback:** Se non esiste modello `.rbxm`, crea un modello semplice via script con base + freccia curva
2. **Rotazione:** Deve usare lo stesso sistema di rotazione degli altri item
3. **Salvataggio:** Salva `rotation`, `cellX`, `cellZ`, `scaleFactor`
4. **Compatibilità:** Deve poter connettere conveyor -> curva -> conveyor, oppure curva -> macchina/sell zone

### Cosa Verificare
- [ ] Puoi comprare e piazzare CurvedConveyor
- [ ] Premi R e la curva ruota correttamente
- [ ] Un Log entra nella curva e cambia direzione
- [ ] La curva funziona in tutte e 4 le rotazioni
- [ ] Se un item entra dal lato sbagliato, scompare con pop-out
- [ ] Logout/login mantiene curva e rotazione

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/ConveyorSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau`

---

## 📝 PROMPT 12 - Creare Preview Visiva del Flusso Conveyor

### Contesto
Il player può piazzare conveyor e macchine, ma non ha feedback chiaro sul percorso degli item finché la fabbrica non parte. Questo rende difficile capire errori di direzione, curve girate male o sell zone non collegate.

### Obiettivo
Creare una preview client-side che mostri il flusso previsto degli item sulla griglia quando il player sta piazzando o selezionando elementi di trasporto.

### Dettagli Tecnici

**File da modificare:**
- `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau`

**Eventuale file helper da creare:**
- `src/StarterPlayer/StarterPlayerScripts/FlowPreview.client.luau` oppure modulo locale dentro `InventoryClient`

### Funzionalità

Quando il player è in placement mode con:
- Conveyor
- CurvedConveyor
- Splitter
- Merger

mostrare piccole frecce sopra le celle interessate.

Colori:
- Verde: prossimo tile valido
- Rosso: percorso finisce nel vuoto o in tile invalido
- Giallo: prossimo tile è macchina o sell zone
- Azzurro: split/merge valido

### Implementazione

1. **Calcolo preview locale:**
   - Leggi gli item piazzati nel folder `PlayerItems_<UserId>`
   - Simula massimo 20 tile di percorso
   - Ferma la simulazione se incontra loop, sell zone o macchina

2. **Rendering frecce:**
   - Usa `Part` piccoli Neon ancorati sopra il plot
   - Distruggi e ricrea la preview quando il mouse si muove o ruota il ghost item
   - Non usare RemoteEvent per decidere il gameplay, è solo visuale

3. **Pulizia:**
   - Rimuovi preview quando esci da placement mode
   - Rimuovi preview quando apri delete mode

### Cosa Verificare
- [ ] Mentre piazzi Conveyor, vedi la direzione del flusso
- [ ] CurvedConveyor mostra output corretto dopo rotazione
- [ ] Splitter mostra due possibili output
- [ ] Percorso invalido diventa rosso
- [ ] La preview non crea oggetti permanenti nel workspace
- [ ] La preview non modifica il routing server

### File Modificati
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau`
- ✅ **Opzionale Nuovo:** `src/StarterPlayer/StarterPlayerScripts/FlowPreview.client.luau`

---

## 📝 PROMPT 13 - Implementare il Power System Base

### Contesto
Le macchine in `Definitions` hanno già `powerRequired`, ma `MachineSystem` usa ancora `isPowered = true`. Il GDD dice che l'energia deve limitare l'espansione del player e il Town Prestige deve aumentare la capacità.

### Obiettivo
Creare un sistema server autoritativo per calcolare:
- Power Capacity del player
- Power Used dalle macchine piazzate
- Generatori piazzati nel plot
- Stato acceso/spento delle macchine

### Dettagli Tecnici

**File da creare:**
- `src/ServerScriptService/PowerSystem.luau`

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/PlayerProgress.luau`

### Changes in Definitions

Aggiungi nuovi item:

```lua
SmallGenerator = {
  name = "SmallGenerator",
  icon = "⚡",
  category = "power",
  cost = 250,
  type = "generator",
  powerProvided = 20,
  isMachine = false,
  isProduction = false
}
```

Aggiungi default power negli stage:

```lua
TOWN_PRESTIGE_STAGES = {
  {
    stage = 1,
    name = "Outpost",
    requirements = { totalContribution = 0 },
    rewards = { powerCapacity = 50, newShopItems = {} }
  },
  {
    stage = 2,
    name = "Village",
    requirements = { totalContribution = 500, Mira = 50 },
    rewards = { powerCapacity = 100, newShopItems = { "SmallGenerator" } }
  }
}
```

### PowerSystem API

```lua
PowerSystem.GetBaseCapacity(player) -> number
PowerSystem.GetGeneratorCapacity(player) -> number
PowerSystem.GetPowerUsed(player) -> number
PowerSystem.GetPowerStatus(player) -> {
  used = number,
  capacity = number,
  available = number
}
PowerSystem.CanPlaceMachine(player, itemName) -> boolean
PowerSystem.RegisterPlacedItem(player, item)
PowerSystem.UnregisterPlacedItem(player, item)
```

### Specifiche

1. **Base Capacity:** Dipende dal Town Prestige attuale
2. **Generatori:** Aumentano la capacity
3. **Macchine:** Consumano power solo se hanno `powerRequired`
4. **Conveyor:** Non consumano power
5. **Splitter/Merger:** Non consumano power al lancio
6. **Decorazioni:** Non consumano power

### Cosa Verificare
- [ ] Stage 1 ha power capacity base
- [ ] Piazzare TreeFarm aumenta power used
- [ ] Piazzare Sawmill aumenta power used
- [ ] Piazzare SmallGenerator aumenta capacity
- [ ] Rimuovere SmallGenerator diminuisce capacity
- [ ] `GetPowerStatus` ritorna valori corretti

### File Modificati
- ✅ **Nuovo:** `src/ServerScriptService/PowerSystem.luau`
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`

---

## 📝 PROMPT 14 - Bloccare Piazzamento se Manca Energia + HUD Power

### Contesto
Hai PowerSystem, ma ora deve avere effetto reale sul gameplay. Il player non deve poter piazzare infinite macchine se supera la capacità energetica.

### Obiettivo
Integrare PowerSystem nel placement server e mostrare lo stato energia nella HUD.

### Dettagli Tecnici

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/StarterPlayer/StarterPlayerScripts/CurrencyUI.client.luau`

### Server Changes

1. **RemoteFunction `GetPowerStatus`:**

```lua
local getPowerStatusRemote = Instance.new("RemoteFunction")
getPowerStatusRemote.Name = "GetPowerStatus"
getPowerStatusRemote.Parent = ReplicatedStorage

getPowerStatusRemote.OnServerInvoke = function(player)
  return PowerSystem.GetPowerStatus(player)
end
```

2. **Blocco Placement:**

Nel `PlaceItem`:

```lua
if Definitions.GetMachine(itemName) then
  local canPlace, message = PowerSystem.CanPlaceMachine(player, itemName)
  if not canPlace then
    return false, message
  end
end
```

3. **Machine Powered State:**

Quando una macchina viene registrata:
- Se c'è power, `isPowered = true`
- Se manca power per qualche motivo, `isPowered = false`

### Client Changes

In `CurrencyUI.client.luau`, aggiungi:

```text
⚡ Power: 28 / 50
```

Colore:
- Verde se available > 10
- Giallo se available tra 1 e 10
- Rosso se available <= 0

### Cosa Verificare
- [ ] Se superi la capacity, il server rifiuta il piazzamento
- [ ] Il player riceve messaggio "Not enough Power"
- [ ] Piazzare generatore permette nuove macchine
- [ ] HUD mostra power usata/capacità
- [ ] Delete di una macchina libera power
- [ ] Delete di un generatore aggiorna capacity

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/CurrencyUI.client.luau`

---

## 📝 PROMPT 15 - Rendere Robusto Salvataggio e Caricamento Plot

### Contesto
Il progetto salva inventario e oggetti piazzati, ma il GDD richiede salvataggio affidabile per una release pubblicabile. Bisogna consolidare schema, migrazioni e retry, senza salvare production item o stati temporanei.

### Obiettivo
Migliorare il salvataggio plot per supportare in modo sicuro:
- Inventory
- Placed objects
- Rotazioni
- Generator state
- Sell zones
- Versioning schema
- Retry/fallback

### Dettagli Tecnici

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ServerScriptService/PlayerProgress.luau`

### Schema Save Plot

Aggiorna il save data:

```lua
{
  version = 2,
  plotId = 1,
  inventory = {
    { itemName = "TreeFarm", count = 1 }
  },
  placedItems = {
    {
      itemName = "Conveyor",
      cellX = 4,
      cellZ = 2,
      rotation = 1,
      scaleFactor = 1,
      cellsX = 1,
      cellsZ = 1,
      npcName = nil
    }
  },
  lastSaved = tick()
}
```

### Specifiche

1. **Versioning:** Aggiungi `version` al salvataggio plot
2. **Migrazione:** Se mancano `cellX/cellZ`, ricostruiscili da `position`
3. **Retry:** Salva con massimo 3 tentativi
4. **Fallback:** Se DataStore fallisce, usa cache in memoria
5. **Non Salvare:**
   - Production item attivi
   - Input interni delle macchine
   - Craft progress
   - Stuck state conveyor

### Cosa Verificare
- [ ] Logout/login mantiene tutti gli item piazzati
- [ ] Rotazioni restano corrette
- [ ] Sell zone tornano registrate
- [ ] Generator torna registrato nel PowerSystem
- [ ] Macchine tornano registrate nel MachineSystem
- [ ] Conveyor sono vuoti al rientro
- [ ] Se un save vecchio non ha `version`, viene migrato

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`

---

## 📝 PROMPT 16 - Creare UI Statistiche Vendite e Menu NPC Base

### Contesto
Le vendite aggiornano Money, Reputation e statistiche, ma il player non vede chiaramente:
- Cosa compra ogni NPC
- Quanti item ha venduto
- Quanta reputazione ha
- Quanto manca al prossimo Town Prestige

### Obiettivo
Creare una UI base per NPC e Sindaco con statistiche leggibili.

### Dettagli Tecnici

**File da creare:**
- `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ServerScriptService/PlayerProgress.luau`

### Server Changes

Aggiungi RemoteFunction:

```lua
GetSalesStats -> {
  lifetimeSold = {},
  npcSold = {},
  mayorContribution = {},
  npcReputation = {},
  townPrestige = {}
}
```

Aggiungi helper in PlayerProgress:

```lua
PlayerProgress.GetPublicProgressSnapshot(player)
```

Deve ritornare solo dati sicuri per il client.

### Client UI

Creare pulsanti top-left:
- Mira
- Bront
- Elrik
- Sindaco

Ogni menu NPC mostra:
- Nome NPC + titolo
- Reputation attuale
- Item accettati
- Prezzo base per item
- Quantità venduta per item

Menu Sindaco mostra:
- Stage attuale
- Contributi totali
- Requisiti prossimo stage
- Ricompense prossimo stage

### Cosa Verificare
- [ ] Click su Mira apre menu Mira
- [ ] Mira mostra Plank/Beam/Crate come item accettati
- [ ] Dopo vendita Plank, le statistiche aumentano
- [ ] Sindaco mostra contributi aggiornati
- [ ] UI non decide soldi/reputazione, legge solo snapshot server

### File Modificati
- ✅ **Nuovo:** `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`

---

## 📝 PROMPT 17 - Aggiungere Macchine Specializzate MVP per Legno, Pietra e Ferro

### Contesto
Il gioco ha già TreeFarm, MineEntrance e Sawmill, ma il GDD prevede tre linee produttive iniziali: Legno, Pietra e Ferro. Serve almeno una macchina specializzata per ogni NPC per rendere il loop più profondo.

### Obiettivo
Aggiungere macchine e recipe MVP per vendere item significativi a Mira, Bront ed Elrik.

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

### Nuovi Production Items

```lua
Beam = { name = "Beam", category = "wood", value = 25, isProduction = true }
StoneBlock = { name = "StoneBlock", category = "stone", value = 18, isProduction = true }
IronIngot = { name = "IronIngot", category = "iron", value = 30, isProduction = true }
```

### Nuove Macchine

```lua
BeamCutter = {
  type = "processor",
  inputItem = "Plank",
  outputItem = "Beam",
  processingTime = 4,
  inputQueueSize = 2,
  powerRequired = 12
}

StoneCutter = {
  type = "processor",
  inputItem = "Stone",
  outputItem = "StoneBlock",
  processingTime = 3,
  inputQueueSize = 2,
  powerRequired = 10
}

Furnace = {
  type = "processor",
  inputItem = "IronOre",
  outputItem = "IronIngot",
  processingTime = 5,
  inputQueueSize = 2,
  powerRequired = 15
}
```

### Note Importanti

- Se manca un modello `.rbxm`, crea template fallback semplice in `InventoryManager`
- Non aggiungere ancora recipe multiple
- Non aggiungere input multipli in questa fase
- Ogni macchina deve usare il sistema processor già esistente

### Cosa Verificare
- [ ] BeamCutter trasforma Plank in Beam
- [ ] StoneCutter trasforma Stone in StoneBlock
- [ ] Furnace trasforma IronOre in IronIngot
- [ ] Mira compra Beam
- [ ] Bront compra StoneBlock
- [ ] Elrik compra IronIngot
- [ ] Nessuna macchina duplica output

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

---

## 📝 PROMPT 18 - Decorazioni Base e Pulizia dello Shop

### Contesto
Lo shop vende item funzionali, ma la UI diventerà confusa man mano che si aggiungono macchine, generatori e decorazioni. Inoltre il GDD prevede decorazioni come contenuto secondario, non bloccante.

### Obiettivo
Aggiungere decorazioni base e migliorare la navigazione dello shop con filtri per categoria.

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/StarterGui/ShopUI.lua`
- `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`
- `src/ServerScriptService/InventoryManager.server.luau`

### Nuove Decorazioni

Aggiungi item:

```lua
DecorTree = {
  name = "DecorTree",
  icon = "🌳",
  category = "decoration",
  cost = 20,
  type = "decoration",
  isMachine = false,
  isProduction = false
}

FactorySign = {
  name = "FactorySign",
  icon = "🪧",
  category = "decoration",
  cost = 35,
  type = "decoration",
  isMachine = false,
  isProduction = false
}

StreetLamp = {
  name = "StreetLamp",
  icon = "💡",
  category = "decoration",
  cost = 50,
  type = "decoration",
  isMachine = false,
  isProduction = false
}
```

### Shop UI

Aggiungi filtri:
- All
- Machines
- Transport
- Power
- Decorations

Regole:
- Sell Zone non deve apparire nello shop
- Production item non devono apparire nello shop
- Gli item vanno ordinati per categoria e costo

### Specifiche

1. **Template fallback:** Se non esiste modello, crea modelli semplici via script
2. **Power:** Le decorazioni non consumano energia
3. **Placement:** Le decorazioni si piazzano, ruotano, cancellano e salvano come gli altri item
4. **UI:** Il filtro selezionato deve restare evidenziato

### Cosa Verificare
- [ ] DecorTree si compra e piazza
- [ ] FactorySign si compra e piazza
- [ ] StreetLamp si compra e piazza
- [ ] Filtri shop funzionano
- [ ] Sell zone non appaiono nello shop
- [ ] Decorazioni non consumano power
- [ ] Decorazioni restano dopo rejoin

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/StarterGui/ShopUI.lua`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`

---

## 📝 PROMPT 19 - Hardening Multiplayer, Ownership e Cleanup

### Contesto
Il gioco deve supportare 6 player con plot separati. Il server deve impedire exploit o interferenze tra player:
- Piazzare su plot altrui
- Cancellare item altrui
- Vendere item altrui
- Lasciare production item attivi dopo logout

### Obiettivo
Rendere robusta la separazione tra player, plot e item prodotti.

### Dettagli Tecnici

**File da modificare:**
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ServerScriptService/ConveyorSystem.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/SellSystem.luau`

### Requisiti Server

Ogni placed item deve avere:

```lua
Owner = player.UserId
PlotId = plotId
ItemName = itemName
CellX = cellX
CellZ = cellZ
```

Ogni production item deve avere:

```lua
Owner = player.UserId
PlotId = plotId
ItemName = itemName
ItemId = uniqueId
SpawnedAt = tick()
```

### Regole

1. **Placement:** Il server rifiuta se la cella non appartiene al plot del player
2. **Delete:** Il server rifiuta se `Owner ~= player.UserId`
3. **Rotate:** Il server rifiuta se `Owner ~= player.UserId`
4. **Sell:** SellSystem vende solo item con owner e plot corretti
5. **Logout:** Rimuovi tutti i production item del player
6. **Limiti:** Max 100 active production item per plot
7. **Debounce vendita:** Max 20 sell events/sec per player

### Cosa Verificare
- [ ] Player A non può cancellare item di Player B
- [ ] Player A non può piazzare sul plot di Player B
- [ ] Item prodotti da Player A non vengono venduti da Player B
- [ ] Quando un player lascia, spariscono i suoi production item
- [ ] 6 player possono giocare senza errori di owner
- [ ] Il limite active item evita accumuli infiniti

### File Modificati
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/ConveyorSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/SellSystem.luau`

---

## 📝 PROMPT 20 - Tutorial Onboarding e Bilanciamento Primo Loop

### Contesto
Il core loop è giocabile, ma un nuovo player deve capire cosa fare senza leggere documentazione esterna. Il GDD dice che il tutorial deve introdurre un sistema alla volta e portare il player verso i 3 NPC entro circa 20 minuti.

Per ora implementiamo solo il primo tratto: dalla prima macchina alla prima vendita a Mira.

### Obiettivo
Creare un tutorial salvabile che guida il player nel primo loop:
TreeFarm -> Conveyor -> Sawmill -> Mira Sell Zone -> prima vendita Plank.

### Dettagli Tecnici

**File da creare:**
- `src/ServerScriptService/TutorialSystem.luau`
- `src/StarterPlayer/StarterPlayerScripts/TutorialClient.client.luau`

**File da modificare:**
- `src/ServerScriptService/PlayerProgress.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ServerScriptService/SellSystem.luau`

### Tutorial State

Aggiungi in PlayerProgress:

```lua
tutorial = {
  currentStep = 1,
  completed = false,
  completedSteps = {}
}
```

### Step Tutorial

1. **Compra TreeFarm**
   - Obiettivo: "Buy a TreeFarm from the Shop"
   - Completa quando inventory contiene TreeFarm

2. **Piazza TreeFarm**
   - Completa quando TreeFarm è piazzata nel plot

3. **Compra e piazza Conveyor**
   - Completa quando almeno un Conveyor è piazzato

4. **Compra e piazza Sawmill**
   - Completa quando Sawmill è piazzata

5. **Piazza MiraSellZone**
   - Completa quando MiraSellZone è piazzata

6. **Vendi un Plank a Mira**
   - Completa quando `npcSold.Mira.Plank >= 1`

### Client UI

Creare un piccolo Objective Tracker:

```text
Objective
Buy a TreeFarm from the Shop
```

Regole:
- Non blocca input del player
- Si aggiorna quando il server conferma avanzamento
- Scompare quando il tutorial è completato

### Bilanciamento Iniziale

Controllare:
- Money iniziale sufficiente per completare il tutorial
- Costi TreeFarm/Conveyor/Sawmill non creano grind
- Primo loop completabile in pochi minuti

### Cosa Verificare
- [ ] Nuovo player vede il primo obiettivo
- [ ] Comprare TreeFarm avanza step
- [ ] Piazzare TreeFarm avanza step
- [ ] Vendere Plank a Mira completa tutorial
- [ ] Tutorial state viene salvato
- [ ] Dopo rejoin, il tutorial riparte dallo step corretto
- [ ] Player non può completare step tramite client spoofing

### File Modificati
- ✅ **Nuovo:** `src/ServerScriptService/TutorialSystem.luau`
- ✅ **Nuovo:** `src/StarterPlayer/StarterPlayerScripts/TutorialClient.client.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/SellSystem.luau`

---

# ✅ Prompt 11-20 Completati!

A questo punto hai:
- ✅ Conveyor dritti, curvi, splitter e merger
- ✅ Preview visuale del flusso conveyor
- ✅ Power system con generatori
- ✅ HUD power e blocco placement se manca energia
- ✅ Salvataggio plot più robusto
- ✅ UI statistiche NPC e Sindaco
- ✅ Prime macchine specializzate per legno, pietra e ferro
- ✅ Decorazioni base e shop più ordinato
- ✅ Multiplayer più sicuro tra 6 plot
- ✅ Tutorial iniziale fino alla prima vendita a Mira

**Il gioco ora entra nella fase MVP vera.** Player può:
1. Comprare e piazzare macchine
2. Collegarle con conveyor dritti/curvi/splitter/merger
3. Gestire energia con generatori
4. Vedere statistiche NPC e progressi Sindaco
5. Seguire un tutorial iniziale
6. Salvare e ricaricare una fabbrica più completa

---

# 🟠 FASE 4: MVP Production Lines, Progressione e Polish Release (Prompt 21-30)

## 📝 PROMPT 21 - Completare Linea Legno con Crate Assembler

### Contesto
La linea legno ora produce Log, Plank e Beam, ma il GDD prevede che Mira accetti anche **Crate**. Serve una macchina finale che renda la linea legno più lunga e più interessante prima di introdurre pietra e ferro completi.

Questa feature deve restare semplice: una macchina in più, un output in più, nessuna recipe multipla complessa.

### Obiettivo
Aggiungere **CrateAssembler** e l'item **Crate**, completando la linea:
TreeFarm -> Sawmill -> BeamCutter -> CrateAssembler -> Mira Sell Zone.

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/SellSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

### Nuovo Production Item

```lua
Crate = {
  name = "Crate",
  icon = "📦",
  category = "wood",
  value = 45,
  rarity = "common",
  isProduction = true
}
```

### Nuova Macchina

```lua
CrateAssembler = {
  name = "CrateAssembler",
  type = "processor",
  inputItem = "Beam",
  inputCount = 2,
  outputItem = "Crate",
  processingTime = 6,
  inputQueueSize = 4,
  powerRequired = 18,
  outputRotationOffset = 0
}
```

### Shop Item

```lua
CrateAssembler = {
  name = "CrateAssembler",
  icon = "📦",
  category = "machine",
  cost = 350,
  type = "processor",
  isMachine = true,
  isProduction = false
}
```

### Aggiornamenti NPC

Mira deve comprare:
- Plank
- Beam
- Crate

Prezzo e reputazione:
- Plank: basso valore, rep base
- Beam: valore medio, rep media
- Crate: valore alto, rep alta

Se il sistema ha ancora un solo `baseReputationReward`, aggiungi supporto opzionale:

```lua
itemRewards = {
  Plank = { money = 15, reputation = 5 },
  Beam = { money = 25, reputation = 8 },
  Crate = { money = 45, reputation = 12 }
}
```

### Specifiche

1. **Input multiplo semplice:** CrateAssembler richiede 2 Beam prima di craftare
2. **No recipe multiple:** La macchina ha una sola recipe
3. **Output buffer:** Se il conveyor in uscita è bloccato, la macchina si ferma
4. **Fallback modello:** Se manca modello `.rbxm`, crea base + cubo/crate visuale via script
5. **Salvataggio:** CrateAssembler viene salvato come gli altri placeable item

### Cosa Verificare
- [ ] CrateAssembler si compra e piazza
- [ ] Accetta solo Beam
- [ ] Richiede 2 Beam per produrre 1 Crate
- [ ] Crate viene emesso sul conveyor
- [ ] Mira vende Crate con Money + Reputation maggiori di Beam
- [ ] Crate non entra nell'inventario player
- [ ] Nessuna duplicazione se output è bloccato

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/SellSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

---

## 📝 PROMPT 22 - Completare Linea Pietra con Quarry e Brick Kiln

### Contesto
Bront deve diventare un NPC realmente giocabile, non solo una tab nella UI. La linea pietra deve permettere al player di produrre e vendere materiali da costruzione con un loop completo.

Il GDD prevede:
- Stone
- Stone Block
- Brick
- Bront Sell Zone

### Obiettivo
Aggiungere **Quarry** e **BrickKiln**, completando la linea:
Quarry -> StoneCutter -> BrickKiln -> Bront Sell Zone.

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/SellSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

### Nuovi / Confermati Production Items

```lua
Stone = {
  name = "Stone",
  icon = "🪨",
  category = "stone",
  value = 12,
  rarity = "common",
  isProduction = true
}

StoneBlock = {
  name = "StoneBlock",
  icon = "🧱",
  category = "stone",
  value = 24,
  rarity = "common",
  isProduction = true
}

Brick = {
  name = "Brick",
  icon = "🧱",
  category = "stone",
  value = 42,
  rarity = "common",
  isProduction = true
}
```

### Nuove Macchine

```lua
Quarry = {
  name = "Quarry",
  type = "producer",
  outputItem = "Stone",
  outputRate = 1,
  outputFrequency = 6,
  powerRequired = 14
}

BrickKiln = {
  name = "BrickKiln",
  type = "processor",
  inputItem = "StoneBlock",
  inputCount = 2,
  outputItem = "Brick",
  processingTime = 7,
  inputQueueSize = 4,
  powerRequired = 20
}
```

### Shop Items

```lua
Quarry = {
  name = "Quarry",
  icon = "⛏️",
  category = "machine",
  cost = 220,
  type = "producer",
  isMachine = true,
  isProduction = false
}

BrickKiln = {
  name = "BrickKiln",
  icon = "🔥",
  category = "machine",
  cost = 420,
  type = "processor",
  isMachine = true,
  isProduction = false
}
```

### Aggiornamenti Bront

Bront deve comprare:
- StoneBlock
- Brick

Regole:
- Stone grezzo non viene venduto a Bront nel loop MVP
- Se Stone arriva nella BrontSellZone, viene distrutto con feedback "Bront wants refined stone"
- Brick deve dare più Money e Reputation di StoneBlock

### Specifiche

1. **Compatibilità:** StoneCutter già esistente deve trasformare Stone -> StoneBlock
2. **Producer separato:** Quarry produce Stone, non IronOre
3. **MineEntrance legacy:** Se esiste già `MineEntrance`, non romperlo; può restare alias/vecchio producer ferro fino al prompt ferro
4. **Fallback modello:** Quarry e BrickKiln devono avere modelli base se mancano asset
5. **Power:** La linea pietra deve consumare abbastanza energia da spingere il player verso generatori

### Cosa Verificare
- [ ] Quarry produce Stone
- [ ] StoneCutter trasforma Stone in StoneBlock
- [ ] BrickKiln richiede 2 StoneBlock
- [ ] BrickKiln produce Brick
- [ ] Bront compra StoneBlock e Brick
- [ ] Bront non compra Stone grezzo
- [ ] La linea pietra salva e ricarica correttamente

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/SellSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

---

## 📝 PROMPT 23 - Completare Linea Ferro con Plate Press e Gear Maker

### Contesto
Elrik deve diventare il terzo NPC produttivo completo. Il ferro serve anche come ponte verso generatori migliori e componenti industriali, quindi la linea deve produrre almeno:
- Iron Ingot
- Iron Plate
- Gear

### Obiettivo
Aggiungere **IronMine**, **PlatePress** e **GearMaker**, completando la linea:
IronMine -> Furnace -> PlatePress -> GearMaker -> Elrik Sell Zone.

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/SellSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

### Production Items

```lua
IronOre = {
  name = "IronOre",
  icon = "⛓️",
  category = "iron",
  value = 20,
  rarity = "common",
  isProduction = true
}

IronIngot = {
  name = "IronIngot",
  icon = "⚙️",
  category = "iron",
  value = 35,
  rarity = "common",
  isProduction = true
}

IronPlate = {
  name = "IronPlate",
  icon = "▣",
  category = "iron",
  value = 55,
  rarity = "common",
  isProduction = true
}

Gear = {
  name = "Gear",
  icon = "⚙️",
  category = "iron",
  value = 85,
  rarity = "common",
  isProduction = true
}
```

### Macchine

```lua
IronMine = {
  name = "IronMine",
  type = "producer",
  outputItem = "IronOre",
  outputRate = 1,
  outputFrequency = 7,
  powerRequired = 18
}

PlatePress = {
  name = "PlatePress",
  type = "processor",
  inputItem = "IronIngot",
  inputCount = 1,
  outputItem = "IronPlate",
  processingTime = 6,
  inputQueueSize = 3,
  powerRequired = 22
}

GearMaker = {
  name = "GearMaker",
  type = "processor",
  inputItem = "IronPlate",
  inputCount = 2,
  outputItem = "Gear",
  processingTime = 8,
  inputQueueSize = 4,
  powerRequired = 28
}
```

### Shop Items

Aggiungi placeable item per:
- IronMine
- PlatePress
- GearMaker

Costi consigliati:
- IronMine: 300
- PlatePress: 500
- GearMaker: 750

### Aggiornamenti Elrik

Elrik deve comprare:
- IronIngot
- IronPlate
- Gear

Regole:
- IronOre non viene comprato
- Gear dà ricompensa alta
- Gear deve contribuire ai requisiti del Sindaco

### Specifiche

1. **MineEntrance legacy:** Se `MineEntrance` produce già IronOre, mantienilo compatibile ma rendi `IronMine` il nome standard per il futuro
2. **Power check:** La linea ferro deve essere impossibile da espandere molto senza generatori
3. **No componenti combinati ancora:** HouseKit/WorkshopKit/GeneratorKit arrivano dopo
4. **UI:** NPCProgressUI deve mostrare IronPlate e Gear nei dati di Elrik
5. **Salvataggio:** I nuovi placeable si salvano come le altre macchine

### Cosa Verificare
- [ ] IronMine produce IronOre
- [ ] Furnace produce IronIngot
- [ ] PlatePress produce IronPlate
- [ ] GearMaker richiede 2 IronPlate
- [ ] GearMaker produce Gear
- [ ] Elrik compra IronIngot, IronPlate e Gear
- [ ] IronOre non viene venduto direttamente
- [ ] Nessun item ferro resta bloccato infinito

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/SellSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua`

---

## 📝 PROMPT 24 - Unlock Progressivi via Reputazione NPC

### Contesto
Ora ci sono molte macchine nello shop. Se tutto è disponibile subito, il player viene sommerso e salta la progressione. Il GDD richiede unlock progressivi tramite reputazione NPC.

Il server deve decidere cosa è sbloccato. Il client può solo mostrare stato locked/unlocked.

### Obiettivo
Implementare un sistema di unlock automatici basato su:
- Reputazione Mira
- Reputazione Bront
- Reputazione Elrik
- Eventuali requisiti Town Prestige

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/PlayerProgress.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/StarterGui/ShopUI.lua`
- `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`

### Data Model Unlock

Aggiungi in PlayerProgress:

```lua
unlocks = {
  machines = {
    TreeFarm = true,
    Sawmill = true,
    Conveyor = true,
    CurvedConveyor = true,
    Splitter = true,
    Merger = true,
    SmallGenerator = true,
    MiraSellZone = true
  },
  discoveredItems = {}
}
```

### Definitions Unlock Requirements

Ogni shop item può avere:

```lua
unlock = {
  npc = "Mira",
  reputation = 25,
  townStage = 1
}
```

Schema consigliato:

```lua
BeamCutter = { unlock = { npc = "Mira", reputation = 15 } }
CrateAssembler = { unlock = { npc = "Mira", reputation = 40 } }

Quarry = { unlock = { npc = "Mira", reputation = 30 } }
StoneCutter = { unlock = { npc = "Bront", reputation = 10 } }
BrickKiln = { unlock = { npc = "Bront", reputation = 35 } }
BrontSellZone = { unlock = { npc = "Mira", reputation = 30 } }

IronMine = { unlock = { npc = "Bront", reputation = 30 } }
Furnace = { unlock = { npc = "Bront", reputation = 30 } }
PlatePress = { unlock = { npc = "Elrik", reputation = 20 } }
GearMaker = { unlock = { npc = "Elrik", reputation = 45 } }
ElrikSellZone = { unlock = { npc = "Bront", reputation = 30 } }
```

### Server Rules

1. **On reputation change:** Ricalcola unlock disponibili
2. **On purchase:** Rifiuta acquisto di item locked
3. **On placement:** Rifiuta piazzamento di item locked anche se il client prova a spoofare
4. **On load:** Ricostruisci unlock da reputazione + dati salvati
5. **No downgrade:** Se una definizione cambia, non rimuovere item già posseduti/piazzati dal player

### Client UI

Shop:
- Mostra item locked con overlay scuro
- Mostra requisito: `Mira Rep 40`
- Il bottone Buy è disabilitato se locked

NPCProgressUI:
- Mostra rewards per livello reputazione
- Evidenzia reward appena sbloccati

### Cosa Verificare
- [ ] Nuovo player vede solo item starter acquistabili
- [ ] BeamCutter si sblocca con reputazione Mira
- [ ] CrateAssembler si sblocca dopo BeamCutter
- [ ] Bront ed Elrik entrano progressivamente nel loop
- [ ] Client spoof non può comprare item locked
- [ ] Unlock persistono dopo rejoin
- [ ] Item già piazzati non spariscono se cambiano requisiti

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/StarterGui/ShopUI.lua`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`

---

## 📝 PROMPT 25 - Town Prestige Stage 2 e Ricompense Reali

### Contesto
Il Sindaco esiste già nei dati/UI base, ma il Town Prestige deve diventare una progressione reale. Stage 2 deve dare una ricompensa concreta e visibile, senza resettare la fabbrica.

Il GDD dice chiaramente: Town Prestige **non è un rebirth**.

### Obiettivo
Implementare il passaggio da Stage 1 **Outpost** a Stage 2 **Village**, con requisiti, claim server-authoritative e reward reali.

### Dettagli Tecnici

**File da modificare:**
- `src/ReplicatedStorage/Shared/Definitions.luau`
- `src/ServerScriptService/PlayerProgress.luau`
- `src/ServerScriptService/PowerSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`

### Stage Data

Aggiorna `TOWN_PRESTIGE_STAGES`:

```lua
{
  stage = 1,
  name = "Outpost",
  requirements = {},
  rewards = {
    basePowerCapacity = 50
  }
},
{
  stage = 2,
  name = "Village",
  requirements = {
    npcReputation = {
      Mira = 50,
      Bront = 20
    },
    mayorContribution = {
      Plank = 25,
      Beam = 10,
      StoneBlock = 10
    },
    totalSold = 75
  },
  rewards = {
    powerCapacityBonus = 50,
    unlocks = { "Windmill", "VillageLamp", "VillageBanner" },
    townVisualStage = 2
  }
}
```

### Nuove Ricompense

Aggiungi almeno:

```lua
Windmill = {
  name = "Windmill",
  icon = "🌬️",
  category = "power",
  cost = 600,
  type = "generator",
  powerProvided = 40,
  unlock = { townStage = 2 },
  isMachine = false,
  isProduction = false
}
```

Decorazioni ricompensa:
- VillageLamp
- VillageBanner

### Server Rules

1. **CanAdvanceTownStage(player):** controlla requisiti da PlayerProgress
2. **AdvanceTownStage(player):** applica stage + reward una sola volta
3. **Power:** Stage 2 aggiunge `powerCapacityBonus`
4. **Unlock:** Reward item vengono sbloccati nello shop/inventory rules
5. **Save:** Stage e reward claimed vengono salvati

### Visual Stage

Se il plot ha municipio o elementi città:
- Cambia colore/label del municipio a "Village"
- Aggiungi banner/lampioni semplici
- Se non esiste modello, usa fallback via script

### Cosa Verificare
- [ ] Requisiti Stage 2 leggono dati reali
- [ ] Il player non può avanzare se manca requisito
- [ ] Il player può avanzare quando i requisiti sono completi
- [ ] Stage 2 aumenta Power Capacity
- [ ] Windmill si sblocca solo a Stage 2
- [ ] Stage 2 resta dopo rejoin
- [ ] Advance non può essere reclamato due volte

### File Modificati
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PowerSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`

---

## 📝 PROMPT 26 - Mayor UI Completa con Requisiti, Reward e Claim

### Contesto
Il Town Prestige ora ha requisiti e reward reali, ma il player deve capire chiaramente cosa manca per avanzare. Il Sindaco deve diventare un menu centrale della progressione MVP.

### Obiettivo
Creare una UI Sindaco più completa con:
- Stage attuale
- Prossimo stage
- Requisiti dettagliati
- Reward
- Pulsante Claim/Advance

### Dettagli Tecnici

**File da modificare:**
- `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`
- `src/ServerScriptService/PlayerProgress.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ReplicatedStorage/Shared/Definitions.luau`

### UI Layout

Menu Sindaco con tab:

```text
Sindaco
[Overview] [Requirements] [Rewards]

Stage 1: Outpost
Next: Stage 2 Village

Progress:
Mira Reputation     42 / 50
Bront Reputation    12 / 20
Plank Delivered     25 / 25
Beam Delivered       8 / 10
StoneBlock Delivered 4 / 10

Rewards:
+50 Power Capacity
Unlock Windmill
Village decorations

[Advance Town] -- disabled until ready
```

### Server Remote

Aggiungi RemoteFunction/RemoteEvent sicuri:

```lua
GetMayorSnapshot(player)
RequestTownAdvance(player)
```

Snapshot deve includere:
- stage corrente
- prossimo stage
- requisiti normalizzati
- progress attuale
- reward
- `canAdvance`

### Regole UI

1. Il client non calcola se può avanzare, mostra `canAdvance` dal server
2. Ogni requisito ha progress bar o checkmark
3. Se non esiste prossimo stage, mostra "Max stage for MVP"
4. Il claim mostra feedback chiaro:
   - Success
   - Missing requirements
   - Already claimed
5. Deve funzionare su mouse, touch e gamepad basic navigation

### Cosa Verificare
- [ ] UI Sindaco mostra Stage 1 e prossimo Stage 2
- [ ] Ogni requisito mostra progress corretto
- [ ] Reward Stage 2 sono visibili prima del claim
- [ ] Pulsante Advance si abilita solo quando server dice `canAdvance`
- [ ] Claim aggiorna UI senza rejoin
- [ ] Client spoof del Remote non salta requisiti
- [ ] UI non rompe i menu NPC esistenti

### File Modificati
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`

---

## 📝 PROMPT 27 - Machine UI Interattiva e Overhead Status

### Contesto
Le macchine craftano, ma il player deve capire cosa sta succedendo senza guardare il codice. Il GDD richiede una Machine UI con recipe, input, output buffer, progress e power.

Questo prompt deve rendere le macchine leggibili e interattive, senza introdurre ancora recipe multiple avanzate.

### Obiettivo
Creare UI macchina:
- Overhead status quando il player è vicino
- Interazione `E` / tap / gamepad per aprire pannello
- Snapshot server-authoritative dello stato macchina

### Dettagli Tecnici

**File da creare:**
- `src/StarterPlayer/StarterPlayerScripts/MachineUI.client.luau`

**File da modificare:**
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ReplicatedStorage/Shared/Definitions.luau`

### Machine State Snapshot

Il server deve poter restituire:

```lua
{
  machineId = "playerId_cellX_cellZ",
  itemName = "CrateAssembler",
  displayName = "Crate Assembler",
  recipe = {
    inputItem = "Beam",
    inputCount = 2,
    outputItem = "Crate",
    processingTime = 6
  },
  inputStorage = {
    Beam = 1
  },
  outputBuffer = {
    Crate = 0
  },
  craftProgress = 0.45,
  isPowered = true,
  isBlocked = false
}
```

### Overhead UI

Mostra sopra ogni macchina:
- Nome macchina
- Input richiesto: `Beam 1/2`
- Output: `Crate`
- Barra progresso
- Icona power se non alimentata
- Icona blocco se output bloccato

Regole:
- Visibile solo entro distanza ragionevole
- Non deve coprire troppo lo schermo
- Aggiornamento leggero, non ogni frame se non serve

### Interfaccia Macchina

Pannello:
- Modello/nome macchina
- Recipe corrente
- Input storage
- Output buffer
- Craft progress
- Stato Power
- Stato Output

Per ora:
- Recipe non cambiabile se la macchina contiene input/output
- Se esiste una sola recipe, mostra solo quella

### Server Authority

1. Il client chiede snapshot
2. Il server verifica owner e plot
3. Il client non può svuotare storage o cambiare output
4. Nessuna modifica a soldi/reputazione passa dalla Machine UI

### Cosa Verificare
- [ ] Avvicinandosi a una macchina compare overhead UI
- [ ] L'overhead mostra input/progress/output corretti
- [ ] Premendo E si apre pannello macchina
- [ ] Touch apre pannello senza tastiera
- [ ] Gamepad può selezionare/chiudere pannello
- [ ] Player non può aprire macchine di altri plot
- [ ] UI non causa lag con 30+ macchine

### File Modificati
- ✅ **Nuovo:** `src/StarterPlayer/StarterPlayerScripts/MachineUI.client.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`

---

## 📝 PROMPT 28 - Almanacco Base per Item, Macchine, NPC e Prestige

### Contesto
Con tre linee produttive, unlock e Town Prestige, il player ha bisogno di una guida interna. Il GDD prevede un Almanacco semplice come should-have. Questo è importante per la deadline perché riduce confusione senza aggiungere nuove meccaniche.

### Obiettivo
Creare un Almanacco base consultabile dalla UI, con informazioni scoperte progressivamente.

### Dettagli Tecnici

**File da creare:**
- `src/StarterPlayer/StarterPlayerScripts/AlmanacUI.client.luau`

**File da modificare:**
- `src/ServerScriptService/PlayerProgress.luau`
- `src/ServerScriptService/SellSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`
- `src/ReplicatedStorage/Shared/Definitions.luau`

### Data Model

Aggiungi in PlayerProgress:

```lua
almanac = {
  discoveredItems = {},
  discoveredMachines = {},
  discoveredNPCs = {
    Mira = true,
    Mayor = true
  },
  viewedEntries = {}
}
```

### Discovery Rules

Segna come scoperto quando:
- Production item viene prodotto
- Production item viene venduto
- Macchina viene comprata o sbloccata
- NPC viene sbloccato o visitato
- Town stage viene raggiunto

### UI Tabs

```text
[Items] [Machines] [NPC] [Town]
```

Items:
- Nome
- Categoria
- Valore base
- Chi lo compra
- Da quale macchina viene prodotto

Machines:
- Nome
- Input
- Output
- Power
- Unlock requirement

NPC:
- Cosa compra
- Reputation rewards
- Unlock importanti

Town:
- Stage disponibili MVP
- Requisiti
- Reward

### Locked Entries

Prima della scoperta:
- Mostra `???`
- Mostra categoria se utile
- Non rivelare tutto l'albero produttivo troppo presto

### Specifiche

1. **Read-only:** Almanacco non modifica gameplay
2. **Server snapshot:** Il client riceve solo dati che può vedere/scoprire
3. **No grind blocker:** Non serve aprire l'Almanacco per progredire
4. **Mobile:** Tab grandi abbastanza per touch
5. **Gamepad:** Navigazione base tra tab e lista

### Cosa Verificare
- [ ] Pulsante Almanacco apre/chiude UI
- [ ] Mira e Sindaco sono visibili da nuovo player
- [ ] Crate appare dopo produzione/vendita/scoperta
- [ ] Machine locked mostra requisito senza rompere layout
- [ ] Almanacco persiste dopo rejoin
- [ ] UI resta leggibile su mobile
- [ ] Il client non vede dati locked non autorizzati

### File Modificati
- ✅ **Nuovo:** `src/StarterPlayer/StarterPlayerScripts/AlmanacUI.client.luau`
- 🔄 **Modificato:** `src/ServerScriptService/PlayerProgress.luau`
- 🔄 **Modificato:** `src/ServerScriptService/SellSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`
- 🔄 **Modificato:** `src/ReplicatedStorage/Shared/Definitions.luau`

---

## 📝 PROMPT 29 - Performance Test e Cleanup Item Attivi

### Contesto
La deadline richiede una build pubblicabile. Il rischio più grande ora è che gli item fisici/conveyor causino lag, accumuli infiniti o duplicazioni. Il GDD dice che 6 player devono giocare senza lag grave e che gli item non devono accumularsi.

### Obiettivo
Aggiungere strumenti di test e hardening performance per active production item, conveyor e macchine.

### Dettagli Tecnici

**File da creare:**
- `src/ServerScriptService/PerformanceTest.server.luau`

**File da modificare:**
- `src/ServerScriptService/ConveyorSystem.luau`
- `src/ServerScriptService/MachineSystem.luau`
- `src/ServerScriptService/SellSystem.luau`
- `src/ServerScriptService/InventoryManager.server.luau`

### Metriche da Tracciare

Per plot:

```lua
{
  activeItems = 0,
  activeMachines = 0,
  itemsSpawnedPerMinute = 0,
  itemsDestroyedPerMinute = 0,
  itemsSoldPerMinute = 0,
  averageItemLifetime = 0,
  blockedMachines = 0,
  lastCleanupAt = 0
}
```

### Limiti Runtime

Conferma/implementa:
- Max 100 active production item per plot
- Max item lifetime 60 sec
- Max stuck time 2 sec
- Max sell events/sec per player
- Cleanup production item al logout
- Cleanup item orphan senza owner/plot

### Test Harness

`PerformanceTest.server.luau` deve poter essere abilitato solo in Studio/dev:

```lua
local ENABLE_PERF_TEST = RunService:IsStudio()
```

Funzioni:
- Spawn controllato di item test
- Simulazione 6 plot con flusso alto
- Log metriche ogni 10 secondi
- Warning se un plot supera soglie

### Ottimizzazioni

1. Evita loop pesanti per ogni frame se possibile
2. Raggruppa update item in heartbeat controllato
3. Non fare `GetDescendants()` continuo sui modelli
4. Cacha riferimenti macchina/conveyor per cella
5. Distruggi item invalidi in modo deterministico

### Cosa Verificare
- [ ] Con 100 item su un plot il gioco resta stabile
- [ ] Con 6 plot simulati non ci sono errori server
- [ ] Item oltre lifetime vengono rimossi
- [ ] Item stuck vengono rimossi
- [ ] Logout rimuove item del player
- [ ] Metriche mostrano active item corretti
- [ ] Il test non gira in produzione se disabilitato

### File Modificati
- ✅ **Nuovo:** `src/ServerScriptService/PerformanceTest.server.luau`
- 🔄 **Modificato:** `src/ServerScriptService/ConveyorSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/MachineSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/SellSystem.luau`
- 🔄 **Modificato:** `src/ServerScriptService/InventoryManager.server.luau`

---

## 📝 PROMPT 30 - Polish Mobile, Touch e Input Gamepad

### Contesto
Il gioco deve essere pubblicabile su Roblox, quindi mouse/tastiera non basta. Le UI principali e il placement devono funzionare anche su mobile e con gamepad, almeno a livello MVP.

Questo prompt non aggiunge nuove feature produttive: serve a rendere giocabile quello che già esiste.

### Obiettivo
Rifinire input e UI per:
- Mobile/touch
- Gamepad
- Schermi piccoli
- Safe area
- Placement, rotate, delete, shop, NPC, Mayor, Machine UI, Almanacco

### Dettagli Tecnici

**File da modificare:**
- `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/MachineUI.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/AlmanacUI.client.luau`
- `src/StarterPlayer/StarterPlayerScripts/TutorialClient.client.luau`
- `src/StarterGui/ShopUI.lua`

### Mobile Placement Controls

Aggiungi controlli touch visibili solo su mobile:

```text
[Rotate] [Confirm] [Cancel] [Delete]
```

Regole:
- Bottoni grandi e distanziati
- Non coprire hotbar/money/power
- Conferma placement con tap su bottone, non solo tap nel mondo
- Delete mode richiede conferma

### Gamepad Controls

Mapping consigliato:

```text
A = Confirm / Buy / Open
B = Cancel / Close
X = Rotate
Y = Toggle Inventory/Shop
LB/RB = Cambia tab
DPad = Navigazione UI
```

### UI Scaling

Controllare:
- HUD Money/Diamond/Power non si sovrappone
- Objective Tracker non copre shop
- NPC menu leggibile su mobile
- Mayor UI scrollabile
- Machine UI chiudibile sempre
- Almanacco scrollabile con touch/gamepad

### Accessibilità MVP

1. Tutti i menu hanno bottone close chiaro
2. I bottoni disabilitati hanno motivazione
3. Errori placement/power/unlock sono leggibili
4. Nessun testo importante esce dai frame
5. Nessuna UI blocca permanentemente input

### Test Manuale

Creare una checklist interna o commentata:

```text
Mobile:
- Compra TreeFarm
- Piazza e ruota
- Compra conveyor
- Apri shop
- Apri NPC
- Apri Mayor
- Apri Machine UI

Gamepad:
- Naviga shop
- Compra item
- Piazza/ruota/cancella
- Apri/chiudi menu
```

### Cosa Verificare
- [ ] Placement funziona su touch
- [ ] Rotate funziona su touch
- [ ] Delete mode funziona su touch con conferma
- [ ] Shop navigabile con gamepad
- [ ] NPC/Mayor/Machine/Almanac UI chiudibili con B
- [ ] HUD non si sovrappone su schermi piccoli
- [ ] Tutorial resta leggibile su mobile
- [ ] Nessun input client bypassa validazioni server

### File Modificati
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/NPCProgressUI.client.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/MachineUI.client.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/AlmanacUI.client.luau`
- 🔄 **Modificato:** `src/StarterPlayer/StarterPlayerScripts/TutorialClient.client.luau`
- 🔄 **Modificato:** `src/StarterGui/ShopUI.lua`

---

# ✅ Prompt 21-30 Completati!

A questo punto hai:
- ✅ Linea Legno completa con Crate
- ✅ Linea Pietra completa con Brick
- ✅ Linea Ferro completa con Plate e Gear
- ✅ Unlock progressivi basati su reputazione NPC
- ✅ Town Prestige Stage 2 con ricompense reali
- ✅ Mayor UI con requisiti e claim
- ✅ Machine UI interattiva
- ✅ Almanacco base
- ✅ Performance test per active item
- ✅ Polish mobile e gamepad

**Il gioco ora è vicino alla vertical slice MVP.** Player può:
1. Seguire tre linee produttive complete
2. Sbloccare macchine tramite reputazione
3. Avanzare il Town Prestige senza reset
4. Capire macchine, NPC e requisiti dal gioco
5. Giocare meglio su mobile e gamepad
6. Restare entro limiti performance controllati

---

# 🟠 Continua con...

Prossimi 10 prompt (31-40) dovranno coprire:
- Tutorial completo fino a Bront, Elrik, Power e Sindaco
- Bilanciamento Money/Reputation/Power per 60-120 minuti
- Kit combinati per Sindaco: House Kit, Workshop Kit, Generator Kit
- Visual stage città più riconoscibile
- Save/load QA con fallback corruzione dati
- Leaderboard base
- Diamond reward rare non bloccanti
- Bugfix pass conveyor/machine/sell zone
- Thumbnail, descrizione e metadata Roblox
- Release checklist per publish candidate
