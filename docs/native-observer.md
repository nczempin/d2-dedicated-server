# Native observer qualification (source only)

Pinned host: b661cace6e861b16211310312b55273ccfa753d2, Zig 0.16.0, i386 Linux/musl.
Pinned locally owned image: ghcr.io/jaenster/d2gs@sha256:e3fb9163060ab1e41c937dee339bb7d4331df5d6098674d7194bb3f44fbcbefa.
Mac executable: 4167552 bytes, SHA256 1e8dd6dd3d19019cbaa29270f4abfb04960fcf1ce5d341fa520863b0d640d177.
No executable asset is included in this repository.

The optional observer is OFF unless D2GS_OBSERVE_PLAYER_GUID is an explicit nonzero decimal GUID. It emits at most 64 diagnostic records after the existing native ServerGameLoop call, BEFORE existing game_unlock. It does not change game pacing, run inputs, expose a network protocol, or grant controller readiness. No wrapper counter is reported as an engine frame. A requested GUID is a filter, NOT ownership or name proof; clients must independently join it to their actual 0x59 identity/session. Class, mode, GUID, raw HP and actual native frame are the only reported facts. Name, complete census, hard ranks, equipped staff/current hands and inventory remain unknown.

## Exact-image bindings derived from machine code

These addresses apply ONLY to the whole-image SHA above. They are NOT copied from classic 1.12. Runtime configuration rejects all other bytes and non-i386 Linux ABIs. The historical guessed GetStatUnsignedValue 0x28660d and GetPlayerFromClient 0x28c553 are NOT used.

* 0x1949e8: cdecl (unit u32, stat i32, layer u16) -> i32. Prologue 55 89 e5; stack args ebp+8/C/10; unit stats pointer +0x5c; binary search key combines stat<<16 and layer; raw signed value returned in EAX, plain RET at194b07. Actual native PLAYER/PlrMsg function1ff012 calls this with stat6/layer0 at1ff08b, shifts result right8 at1ff0ac, then sends life packet0x95 via1b1768 at1ff561. Other actual callsites use stat8 MP/stat10 stamina and stat12 level. Thus stat6 is HP Q8, not an invented health estimate.
* 0x27905c: cdecl (game u32, unitType u32, guid u32) -> native unit pointer. Native type0 hash offset table at3337e4 contains1120/1320/1520/1920/1720/0; buckets indexed guid&0x7f; compares native GUID at+0xC, traverses next+0xE4. Observer requests ONLY type0 then rereads native type/class/GUID/mode.
* Engine game+0xA8: ServerGameLoop entry1ae017 loads actual game at1ae034 then increments [game+0xA8] at1ae037. Observer reads this actual engine field before and after getters under the existing game lock. Same pointer/header/frame and two equal rawHP reads required. Dead mode17/HP0 is observed death, never action permission.

The exact-image disassemblies and independent byte/hash controls are retained in E:/git/ibm-compute-probes/linux-gs-observer-20261022-063851Z. Native pointer access follows the existing engine lock and exact-image native lookup; it is not a fault-isolated external memory reader. Engine corruption/process death is outside this observer's safety scope.

## Qualification limits

Unit tests execute production capture logic with memory/getter adapters, including foreign/incomplete/changing data, known death and actual stat/layer arguments. They establish decision logic, NOT native function execution. Build proves ABI compilation, NOT live efficacy. Any native observer episode must separately record exact host/image/source, game/actor/session, raw output and cleanup. No native gameplay/input qualification follows from this producer.
