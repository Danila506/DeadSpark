# LAN death synchronization — 2026-09-21

Fix: the host sends a reliable final vitals event when Player.die transitions to dead. Repeated calls are ignored. Dead players remain in periodic state snapshots, including for clients that become ready later. Clients reject vitals from non-host peers and ignore stale alive health updates after death. Network protocol version: 4.

Verification: Godot 4.6.2, two headless Windows processes, localhost ENet.

Command: tools/lan_smoke.ps1 -GodotPath D:\personal_D\godot\Godot_v4.6.2-stable_win64_console.exe -Port 2477 -RunSeconds 75 -HostReadyTimeoutSec 8 -PickupAfterSec 0 -DeathProbe

Observed LAN_GAMEPLAY_PROBE=PASS and LAN_DEATH_PROBE=PASS. The client receives dead=true and health=0 despite a later reliable alive/100 HP update. The death-screen entry point runs; the test substitutes the screen controller to prevent changing scenes or deleting the local save. Rendering of the screen and a physical Android device are not covered.

Isolated audit recheck: dead ticks now send snapshots (alive_sent=1, dead_sent=1). ALPHA_GAMEPLAY_FLOW_TEST=PASS.

The other audit findings (armor, healing, doors, container transaction recovery) remain pending.
