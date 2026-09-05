# Guda ClassicAPI

A comprehensive **bag and bank management addon** for **World of Warcraft 1.12.1 / Turtle WoW**, adapted and optimized for **ClassicAPI**.

Guda ClassicAPI keeps the same familiar Guda experience with unified bags and bank, sorting, item tracking, multi-character support and quality-of-life tools, while aiming for smoother and lighter inventory updates.

Based on the original **Guda** by **Vati**.

---

## ⚙️ Requirements

- **World of Warcraft 1.12.1 / Turtle WoW**
- **ClassicAPI** installed and loaded
- Do not run the original Guda addon at the same time

---

## 📦 Features

### 🎒 Bag Management

- **Unified Bag View** – All bags displayed in one window
- **Category View** – Group items by category for easier organization
- **Smart Sorting** – Sort by quality, name, or item type
- **Search Box** – Quickly find items
- **Quality Borders** – Items are visually color-coded based on rarity

### 🏦 Bank Management

- **Remote Bank Viewing** – View cached bank contents from anywhere
- **One-Click Sorting** – Organize your bank easily
- **Category View** – Group bank items by category
- **Persistent Storage** – Bank data saved between sessions

### 📊 Tracked Item Bar

- **Item Tracking** – Alt + Left-Click on any bag item to track it
- **Stack Display** – Shows tracked items as a single stack with total count
- **Farm Counter** – Displays how many items you currently have in your bags
- **Grinding Helper** – Perfect for tracking materials while farming
- **Draggable** – Shift + Left-Click to drag the bar anywhere on screen

### 📜 Quest Item Bar

- **Quest Item Display** – Shows usable quest items in up to 2 dedicated bars
- **Quick Swap** – Hover over a quest item bar slot to see available quest items
- **One-Click Replace** – Click a popup item to swap it into the bar slot
- **Keybindable** – Set custom keybindings for quick quest item use
- **Draggable** – Shift + Left-Click to drag the bar anywhere on screen

### 👥 Multi-Character Support

- **Cross-Character Viewing** – View bags & banks of any character
- **Money Tracking** – See total gold across all characters, grouped by account and realm
- **Character Selector** – Switch characters quickly
- **Faction Filtering** – Shows only characters from the same faction
- **Global Item Counting** – Item totals across all characters, including bags, banks and equipped items
- **Tooltip Breakdown** – See where your items are stored across characters
- **Character Management** – Right-click the money frame to show/hide characters or remove deleted ones

### 💰 Money Display

- **Current Character Money**
- **Total Money Across All Characters**
- **Per-Character Overview** in the selector

### 🔗 Cross-Account Sharing (Optional)

Share character data (gold, bags, bank, mail, equipped items) between different WoW accounts on the same PC. Requires the companion [GudaIO](https://github.com/vatichild/GudaIO) DLL.

**Setup:**
1. Download `GudaIO.dll` from [GudaIO releases](https://github.com/vatichild/GudaIO/releases)
2. Place it in your TurtleWoW folder (next to `WoW.exe`)
3. Add `GudaIO.dll` on a new line in `dlls.txt`
4. Log into each account at least once and log out properly
5. Restart the game

Without GudaIO, the addon works normally with single-account data only.

---

## 📝 Slash Commands

| Command | Description |
|---------|-------------|
| `/guda` or `/gn` | Toggle bags |
| `/guda bank` | Toggle bank view |
| `/guda sort` | Sort your bags |
| `/guda sortbank` | Sort your bank (must be at bank) |
| `/guda debug` | Toggle debug mode |
| `/guda cleanup` | Remove characters not seen in 90 days |
| `/guda help` | Show help |

---

## 🚀 How to Use

### Basic Usage

1. Press **B** or type `/guda` to open your bags
2. Click **Characters** to switch characters
3. Click **Bank** to view your cached bank
4. Click **Sort** to organize your bags

### Sorting

- **Sort Bags**: Press **Sort** or use `/guda sort`
- **Sort Bank**: Use **Sort Bank** or `/guda sortbank`
- Sorting modes:
  - **Quality** (Epic → Rare → Uncommon → Common)
  - **Name** (A → Z)
  - **Type** (Item class & subclass)

### Category View

- Toggle category view in bags or bank to group items by type
- Easily find items organized by their category

### Tracked Item Bar

1. Open your bags
2. Hold **Alt** and **Left-Click** on any item to start tracking it
3. The item appears in the Tracked Item Bar with total count
4. Use **Shift + Left-Click** on the bar to drag it to your preferred location

![Tracked Item Bar](https://github.com/user-attachments/assets/81a2a86f-f35e-4437-ae89-906ade98716d)

### Quest Item Bar

1. Quest items automatically appear in the Quest Item Bar
2. Set keybindings via **Esc → Key Bindings → Guda** for quick use
3. Hover over a bar slot to see other available quest items
4. Click a popup item to swap it into that slot
5. Use **Shift + Left-Click** on the bar to drag it to your preferred location

![Quest Item Bar](https://i.imgur.com/orMsS06.png)

---

## ⚠️ Known Limitations

| Area | Limitation |
|------|------------|
| Bank Access | Must open the bank at least once to cache contents |
| Faction Restriction | Only shows characters from the same faction |

---

## 🖼️ Screenshots

| Guda Settings | Bag Single View | Bag Category View | Bank View |
|---------------|-----------------|-------------------|-----------|
| ![Settings](https://github.com/user-attachments/assets/9ab1b985-1280-4c14-a733-3a1fffdaa7e4) | ![Bags](https://github.com/user-attachments/assets/1150de97-7db7-4267-b1cd-99c6267c4669) | ![Category](https://github.com/user-attachments/assets/825ada16-da49-400e-8b1b-4ae203786f0f) | ![Bank](https://github.com/user-attachments/assets/7a198526-85c8-4309-8b1b-4ae203786f0f) |

---

## 🐞 Common Issues

### Cannot open bags using B

Set the keybinding: **Esc → Key Bindings → Guda → Toggle Bags**

![Keybindings Fix](https://i.imgur.com/IJv36Lg.png)

### Issues after updating the addon

Delete outdated saved variables:

```
WTF/Account/<ACCOUNT_NAME>/SavedVariables/Guda.lua
WTF/Account/<ACCOUNT_NAME>/SavedVariables/Guda.lua.bak
```

---

## 📢 Support

For bugs or feature requests, please open an issue on this repository.
