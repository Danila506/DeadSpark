# LAN Regression Checklist

Use this checklist after any multiplayer/network code change.

## Environment
- 2 clients minimum (Host + Client), ideally 3 peers.
- Same build version on all devices.
- Same LAN/Wi-Fi subnet.
- Host firewall allows UDP port `2456`.

## Core Flow
1. Host starts LAN session from menu.
2. Client joins by IPv4 + port.
3. Client reaches `network_test_world` without stuck loading.
4. Host and client both see each other moving.

## Connection Reliability
1. Join invalid IP and confirm failure is shown in UI.
2. Force timeout and verify one automatic reconnect attempt is performed.
3. Disconnect host while client is in-game and verify client returns to stable state (no spam errors).
4. Re-host and reconnect from menu without app restart.

## Multiplayer Integrity
1. Join/leave peers several times in sequence.
2. Verify no duplicated player nodes after reconnect.
3. Verify removed peer disappears on remaining peers.
4. Verify authority camera is only active on local controlled player.

## Basic Anti-Cheat Guards
1. Verify remote movement still interpolates smoothly.
2. Verify extreme position jumps are clamped.
3. Verify extreme velocity values are clamped.
4. Verify RPC sender validation still blocks mismatched `peer_id`.

## Protocol Compatibility
1. Connect a client with mismatched protocol version.
2. Verify connection is rejected with readable reason.
3. Verify session continues normally for already connected valid peers.

## Smoke Log Rules
- Any runtime error in network scripts is a failed check.
- Any duplicate scene load, duplicate player spawn, or endless reconnect loop is a failed check.
