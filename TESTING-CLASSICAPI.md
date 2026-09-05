# Guda ClassicAPI — Runtime Test Checklist

Target: WoW 1.12.1 / Turtle WoW with ClassicAPI loaded.

## 1. Clean load
- Enable Lua errors.
- Log in with Guda ClassicAPI enabled.
- Confirm no Lua error during login and no error after `/reload`.
- Run `/gudatest` with the bank closed. Expected: ClassicAPI fast path ACTIVE and zero container mismatches.

## 2. Bags
- Open/close bags repeatedly.
- Loot several different items and stackable items.
- Move items between backpack and bags.
- Split/merge a stack.
- Equip/replace a bag.
- Verify counts, icons, quality borders, junk/unusable markers and empty-slot counts stay correct.

## 3. Tooltip counts
- Mouse over items in bags repeatedly.
- Verify total/bags/bank/mail/equipped counts.
- Move an item, then immediately mouse over it again.
- Send or loot mail, wait for the mailbox update, then verify the tooltip count changes.
- Toggle a character inventory/gold blacklist entry and verify tooltip counts update without `/reload`.

## 4. Quest and tracked bars
- Verify QuestItemBar updates after looting/using a quest item.
- Alt-click an item to track/untrack it.
- Move tracked items between bags and change their stack count.
- Disable `showTrackedItems` and verify the tracked bar remains hidden.

## 5. Drag/drop and category view
- Switch bags to category view.
- Drag items between normal slots.
- Drag an item onto an empty-category drop target.
- Verify the green drop glow pulses correctly.
- Close the bags and verify there is no visible/functional cursor polling side effect.

## 6. Sorting
- Sort bags in single view.
- Sort/restack in category view.
- Verify pinned/protected items are respected.
- Verify no duplicated, missing or visually stale items after sorting.

## 7. Bank
- Open the NPC bank.
- Run `/gudatest` again while the bank is open. Expected: zero bank/container mismatches.
- Move items between main bank, bank bags and player bags.
- Split/merge stacks in the bank.
- Equip/replace a bank bag.
- Test bank sort/restack in single and category views.
- Close/reopen the bank and verify saved bank data remains correct.

## 8. Mail
- Open a mailbox with multiple mails/attachments if possible.
- Take an attachment and verify inventory tooltip counts update.
- Send an item to another locally known character and verify cross-character counts after the send completes.

## 9. Performance sanity
- Run `/guda perf` before and after normal bag use.
- Expected scheduler frame budget: about 3 ms.
- Watch for visible freezes when opening bags, looting, mouse-overing many items, sorting and opening the bank.
- Compare the same actions against upstream Guda if a regression is suspected.

## Pass criteria
- No Lua errors.
- `/gudatest` reports zero mismatches with bags and bank.
- No missing/duplicated/stale items.
- Tooltip counts remain correct after inventory/mail/blacklist changes.
- Drag/drop, category assignment, sorting and bank operations behave like upstream Guda.
