# Native Linux player observations

This extends the opt-in observer from PR #1. It uses the same exact Mach-O SHA256
`1e8dd6dd3d19019cbaa29270f4abfb04960fcf1ce5d341fa520863b0d640d177`, i386 Linux ABI,
and the existing owning game lock after ServerGameLoop and before game_unlock.
Other image bytes refuse the bindings. No game assets are committed.

## Actual native results

Two independent fresh realm-factory Sorceresses were created without save edits,
cloning, UI, movement or combat. Each episode returned four pre-spawn unknown
observations followed by 60 actual engine frames 5..64. Both clients exited 0 and
all five containers per episode stopped. See native-player-stats-result.json for
source pins, ELF hashes, native game IDs, raw wire bytes and evidence hashes.

The first source afdb0ce read native stat ids 0..15 twice:
`[10,35,25,10,0,0,10240,10240,8960,8960,18944,18944,1,0,0,0]`.
Thus attribute and skill point pools are genuinely observed zero, not absence of
network deltas. Current/max HP, mana and stamina retain raw Q8 units. Native
packet 0x95 independently agrees on HP40 and MP35. Stat ids match the existing
BMBot player_state.cpp observation contract; no hard-coded character estimate is
substituted for a native getter result.

The second source 1ae56d0 also read all Sorceress skills 36..65: hard ranks all 0;
effective Charged Bolt 36 is 1 from the starting staff, other effective ranks 0.
The actual native selected hands are Attack 0 and Charged Bolt 36, both with
ordinary/non-charge owner FFFFFFFF. Wire packet 0x21 independently reports
Charged Bolt base0/bonus1. Native hand proof does not fall back to the later wire
0x23 zero-owner cache. Final source additionally rechecks BOTH hands after all
reads, matching the existing NativeCurrentHands algorithm; this additional
consistency check is unit tested but was not part of the executed 1ae56d0 ELF.

## Qualified Mac bindings

`0x1949e8` remains the previously qualified cdecl native stat getter
(unit, stat, layer), now invoked for all ids 0..15 with layer0. Each result is
read twice and the actual actor pointer/header/stats pointer/native frame are
rechecked after skills. Failed reads refuse this slice; missing is never zero.

`0x18693f` is cdecl (unit, skill id, owner) -> skill pointer. Exact disassembly:
unit+A8 loads the skill list; list+4 its first node; node+4 the next node;
node+0 its skills.txt row with signed16 id; node+34 its owner. It compares BOTH
requested id and owner, returns the matching pointer or zero, and ends in plain
RET at18697c. Native setters at186f78/187010 use this same function with owner
FFFFFFFF before writing node+28. This replaces the REFUTED name-only address
0x2aa334 from the historical address map.

`0x18608e` is cdecl (unit, skill pointer, include bonuses) -> rank. It reads
node+28, adds the bonus helper187a9a ONLY for include-bonuses and ordinary owner
FFFFFFFF, clamps nonnegative and to the native global limit, then plain RET.
This is dataflow and actual native execution qualification of the previously
unconfirmed name-only candidate. No guessed Windows calling convention is used.

Selected hand pointers at list+8/+C are independently corroborated by native
selection setters186b3c and186bd2. Those setters traverse the skill nodes matching
row and owner, then store the selected pointer at precisely these fields. The
capture follows existing tools/d2host/native_current_hands.h: pointer, row/id,
owner and native lookup must agree, with final rereads. A mismatched hand remains
unknown. A missing list invalidates the skill slice instead of making all ranks
zero. These class-rank arrays apply only to Sorceress class1; other classes keep
the skill slice unavailable while their actual stats remain observable.

Exact disassemblies, both episode raw logs, command manifests, cleanup receipts,
and mutation controls are retained locally under
`E:/git/ibm-compute-probes/linux-player-stats-20261022`.

## Tests and limits

10 production capture tests pass, including missing/zero points, changed mana,
foreign actor, frame change, death, foreign skill owner, missing list and late
hand changes. Three compiled causal mutants fail: mana-stability removal,
hand-owner lookup removal and final hand-reread removal. ReleaseSafe x86 Linux
musl builds succeed. No pacing/input changes or guard relaxation are included.

This is a bounded 64-record diagnostic producer, NOT gameplay permission.
There is still no typed controller ingestion, complete player/corpse or item
census, inventory properties, skill use state/mana costs, animation timing or
active-state census. Broader production session/owner correlation is also
unimplemented; the two isolated episodes independently correlate native GUID1
with their own actual named wire0x59 actor. Do not synthesize a complete FC/F7
snapshot from these partial records.

The next consumer should use a separate typed native-player receipt with explicit
availability, source/game/actor/frame binding, independent named-wire ownership
and stale-record rejection. Keep the current vanilla packet rejection intact;
these are additional native observations, not vanilla network packets.
