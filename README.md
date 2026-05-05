# 🏭 Mayor's Factory Tycoon

A **factory/tycoon game on Roblox** where players build factories on their personal plot to produce, refine, and sell resources to city NPCs.

## 🎮 Core Concept

- **Personal Plot:** Each player has a grid-based space to build their own factory
- **Three Production Lines:** Wood (🪵 Mira), Stone (🏗️ Bront), Iron (⚒️ Elrik)
- **Physical Items:** Goods that flow on conveyors from machine to machine
- **Triple Progression:** NPC Reputation + Town Prestige + Power System
- **Persistent Saving:** Progress, inventory, and layout saved in DataStore

## 🛠️ Tech Stack

- **Engine:** Roblox + Luau scripting language
- **Version Control:** Rojo 7.7.0-rc.1 (filesystem-based sync to Studio)
- **Architecture:** Server-authoritative (RemoteEvent/RemoteFunction for client-server)
- **Data:** DataStoreService for persistence with automatic migration system

## 📁 Project Structure

```
Mayor's Factory Tycoon/
├── src/
│   ├── ServerScriptService/
│   │   └── InventoryManager.server.luau    # Server-side inventory & economy
│   ├── StarterPlayer/StarterPlayerScripts/
│   │   └── InventoryClient.client.luau     # Client UI & item placement
│   ├── ReplicatedStorage/Shared/ItemTemplates/  # Item models (.rbxm)
│   └── Workspace/Models/                   # Plot & world models
├── document/
│   ├── GDD sintetico.md       # Design overview
│   ├── GDD tecnico.md         # Technical specs
│   └── Proposta deadline.md   # 12-week roadmap
├── default.project.json       # Rojo configuration
└── aftman.toml               # Tool versions (Rojo, etc.)
```

## 🚀 Getting Started

1. **Install Rojo:** `aftman install`
2. **Start Sync:** `rojo serve` (syncs filesystem to Studio in real-time)
3. **Open in Studio:** Menu → Connect to Rojo → Connect

## 📊 Game Systems

| System | Status |
|--------|--------|
| ✅ Inventory & Hotbar | Implemented |
| ✅ Item Placement & Grid | Implemented |
| ✅ Conveyor System | Implemented |
| ✅ Machine Crafting | Implemented |
| ✅ Sell Zones (3 NPCs) | Implemented |
| ✅ NPC Reputation | Implemented |
| ✅ Town Prestige | Implemented |
| ✅ Power System | Implemented |
| ✅ Save System | Implemented |
| 🟡 Tutorial / FTUE | In Progress |

## 📅 Development Roadmap

**12-week sprint** targeting launch with core systems:
- Weeks 1-4: Core systems (inventory, conveyor, crafting, power)
- Weeks 5-7: Three production lines + NPCs
- Weeks 8-9: Town Prestige system
- Weeks 10-12: Persistence, tutorial, polish, performance

## 🎯 MVP Requirements

✅ 6 plots | ✅ Grid-based placement | ✅ Item physics | ✅ Crafting recipes  
✅ 3 specialized NPCs | ✅ Town Prestige progression | ✅ Persistent save system

## 📝 License

Personal project - All rights reserved

---

**Made with ❤️ using Rojo + Luau**
