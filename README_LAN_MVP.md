# LAN Multiplayer MVP (PC + Android in one Wi-Fi/LAN)

## Scope
This is only LAN MVP based on ENet and Godot 4 high-level multiplayer API.
No VPS, no dedicated server, no Steam/WebRTC/NAT traversal, no auth/account system.

## Test flow
1. Open `res://Menu/Menu.tscn` and press `LAN MVP`.
2. In LAN menu:
   - Host PC presses `Host LAN` (default port `2456`).
   - Client PC / Android enters Host IPv4 + port and presses `Join LAN`.
3. Scene switches to `res://World/network_test_world.tscn`.
4. Players are spawned and can move; movement is visible on all peers.

## Autoload
Add in Project Settings -> Autoload:
- Name: `NetworkManager`
- Path: `res://Autoloads/NetworkManager.gd`

(Already added in `project.godot` for this repository.)

## Android export permissions
In Android export preset enable:
- `INTERNET` (required)
- `ACCESS_NETWORK_STATE` (recommended)
- `ACCESS_WIFI_STATE` (recommended)

Without `INTERNET`, Android may block connection attempts even to local Wi-Fi IPs.

## Windows Firewall and host port
Host must accept inbound UDP on port `2456`.

PowerShell (Run as Administrator):
```powershell
New-NetFirewallRule -DisplayName "Godot LAN Server 2456 UDP" -Direction Inbound -Protocol UDP -LocalPort 2456 -Action Allow
```

## Troubleshooting
If second PC or phone cannot connect:
1. Confirm both devices are in the same local network / same Wi-Fi.
2. On Host PC, run `ipconfig` and find IPv4 address.
3. Use exactly that IPv4 on client side.
4. Ensure Firewall allows the game app on Private networks.
5. Ensure UDP 2456 inbound is open on host.
6. Ensure both devices run the same game build/version.

## TODO for next phase
- Full server-authoritative movement with client prediction + reconciliation.
- Pickup item synchronization.
- Inventory synchronization.
- Shooting synchronization.
- Enemy synchronization.
- VPS dedicated server architecture.
