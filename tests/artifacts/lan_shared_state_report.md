# LAN shared state verification — 2026-09-21

Godot 4.6.2 stable, two headless Windows processes, localhost ENet.

## Changes

- Shared container contents are generated on the host. Opening a container fetches its authoritative contents; reliable updates refresh other viewers.
- Container drag operations use a host-granted exclusive edit token. Repeated requests cannot take the same item twice.
- Host clock snapshots drive the client HUD; the client no longer advances a separate clock.
- Equipment changes use reliable delivery, including empty slots when clothing is removed.
- Dropped inventory items spawn on the host and are replicated with their runtime data, including durability and contents.
- Container and pickup proximity UI ignores remote players. Background container updates preserve a closed inventory.
- Direct consumption, ammunition loading and attachment modification from shared containers require first moving the item to personal inventory.

## Verification

`tools/lan_smoke.ps1 -GodotPath D:\personal_D\godot\Godot_v4.6.2-stable_win64_console.exe -Port 2475 -RunSeconds 75 -HostReadyTimeoutSec 8 -PickupAfterSec 0 -SharedStateProbe -GameplayProbe`

Observed PASS for:

- Matching contents in the same chest on host and client.
- Client moves a three-item stack into its bag; a duplicate request does not duplicate it.
- The authoritative chest and both open panels show the item removed.
- Client clock matches host time 21:37.
- Host jacket equip and removal appear on the remote character.
- Dropped jacket appears on the client and can be picked up, retaining durability 37.
- Movement, position synchronization and enemy damage synchronization.

Editor parse/import passed without script errors.

Offline regression markers: LOOT_UI_DRAG_TEST=PASS, CONSUMABLE_ACTION_TEST=PASS, ALPHA_GAMEPLAY_FLOW_TEST=PASS, LOOT_ALL_PROVIDERS_PERSISTENCE_RELOAD_TEST=PASS. The consumable and provider persistence test processes report one resource still in use at shutdown; their assertions pass, but those two runs are not clean shutdowns.

This verifies two local game processes. A physical Android device was not retested. Re-export Android and restart the host using the updated project; network protocol is now 3.
