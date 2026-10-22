# Native Linux owned inventory membership

This extends PR #2's locked observer. Exact image/ABI restrictions and bounded
64-record opt-in behavior are unchanged. No new inputs, save edits or controller
admission are included.

The observer now captures **the current actor's complete top-level inventory
chain**, independently of vanilla packet coverage. This scope is deliberately
smaller than a complete global loaded-item census or complete item properties.
Nested/socket inventories and nonempty cursor custody remain unsupported; a
nonempty cursor makes this slice unavailable.

## Actual execution

Source 9b3181bca244670e016526e59a47ac6072bb9600, ELF
`ae452006698e27fcb872816a73b048ca55d179678748d0fee237874a71af3935`.
A fresh normal factory-created IBMInventory Sorceress joined one isolated native
game. Actual frames5..62 yielded 58 consistent owned-inventory records:

* one equipped class63 starting staff, mode1/body4;
* four class587 potions in belt, mode2;
* class529 and530 scrolls in bag, mode0/page0.

All seven items have proven owner1 from the native parent inventory. Cursor is
observed empty. The client exited normally after its two-second dwell, before
the diagnostic64-record budget was exhausted. Total setup/dwell/cleanup was
12.062 seconds. All five owned containers stopped. There were no movement or
combat inputs, D2R access or UI. See native-owned-inventory-result.json for the
exact native game, source, raw output hashes and sample record.

## Version qualification and existing algorithms

This ports the existing checked inventory ownership/linked-list ideas from
`tools/d2host/native_player_census.h` and `Scripts/ShieldItemSnapshot.cs`; it does
not copy D2R pointer widths or offsets. The native i386 layouts were independently
checked against this exact Mach-O, not accepted from the historical symbol DB.

* Inventory constructor1673ea writes magic01020304, owner pointer at+8, binds
  actor+60 to this inventory, and copies actor GUID+C to inventory+24.
* Native chain insertion helper1676b1 checks item type4 and item data+14. It
  links the old last item's data+64 to the new unit, sets new data+60 to the
  previous unit, writes inventory+C/+10 first/last, and data+5C parent inventory.
  Caller167691 increments inventory+28 count. This qualifies parent, previous,
  next, first, last and count together through their actual native producer.
* Removal1672d9..16733a updates neighboring data+60/+64 and inventory+C/+10,
  decrements inventory+28, clears parent data+5C. Its separate cursor branch
  clears inventory+20. Cursor custody is explicitly refused here rather than
  inferred from ordinary chain parenting.
* Native save-reader176483/1764a0 reads a4-bit body location and writes item
  data+44. Native item page getters/setters16fca*/16fcd4 use byte data+45.
  The corresponding data+14 access and item-type checks are present in these
  native functions. Raw page255 on equipped/belt items is retained unchanged.

These disassemblies remain locally at
`E:/git/ibm-compute-probes/linux-player-stats-20261022/inventory-1670b9.txt` and
`E:/git/ibm-compute-probes/linux-owned-inventory-20261022/body-page-anchors.txt`.

Capture requires exact inventory magic, owning actor pointer and GUID, count
<=128, observed empty cursor, all links/parent ownership, unique pointers/GUIDs,
valid unit type/mode and exact terminal/last agreement. It rereads every item and
all inventory roots/count/actor binding. The enclosing observer also rereads the
actual actor and native engine frame while still holding the game's lock. A
cycle, truncation, changed view, foreign parent or missing read yields unknown,
never partial completeness. Empty inventories are not inferred from missing
pointers. No item property/stat array is claimed complete by this module.

12 combined production tests and ReleaseSafe x86 Linux musl build pass. Three
causal mutants separately remove parent ownership, terminal-chain checking and
final count stability; each fails the production inventory tests.

## Next consumer

A typed native observation transport still needs to bind this slice to the same
native game/actor/frame as the player stats and independent named wire actor.
Current BMBot guards stay closed until their actual complete observation
requirements are met. Do not label these JSON records vanilla network packets,
a global loaded item census, socket custody, item stats or gameplay permission.
