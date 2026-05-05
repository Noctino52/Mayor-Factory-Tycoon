# Dove Mettere i Modelli

## 📋 Quick Reference

| Cosa | Dove | Comando |
|------|------|---------|
| Item piazzabili | `src/ReplicatedStorage/Shared/ItemTemplates/` | Export as Model |
| Terreni plot | `src/Workspace/Models/Plots/` | Export as Model |
| Mondo (terreno, strade) | `src/Workspace/Models/World/` | Export as Model |

## 🔄 Flusso Corretto

1. Crea/modifica modello in Studio
2. Tasto destro → **Export as Model** → `NomeItem.rbxm`
3. Salva nel path giusto (vedi tabella sopra)
4. Rojo sincronizza automaticamente in Studio

## ➕ Aggiungi Nuovo Item

1. Esporta modello → `src/ReplicatedStorage/Shared/ItemTemplates/NuovoItem.rbxm`
2. Aggiungi a `default.project.json`:
   ```json
   "NuovoItem": {"$path": "src/ReplicatedStorage/Shared/ItemTemplates/NuovoItem.rbxm"}
   ```
3. Aggiungi a `InventoryManager.server.luau` (DEFAULT_INVENTORY):
   ```lua
   {itemName = "NuovoItem", count = X}
   ```
4. Aggiungi icona a `InventoryClient.client.luau` (ITEM_ICONS):
   ```lua
   NuovoItem = "🎯"
   ```

## ⚠️ Ricorda
- **Filesystem = source of truth**
- Se cambi in Studio → esporta e sovrascrivi
- Se cambi il file → Rojo sincronizza

