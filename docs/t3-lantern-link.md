# Lantern Link local co-op server

T3 adds the project's server component. The host runs a Dart WebSocket server;
the game remains browser-first and other devices on the same local network join
the server instead of calculating their own battle outcomes.

## Start a room

From the repository root, run:

```sh
dart run bin/lantern_link_server.dart --room bellwether --port 8088
```

The server prints a WebSocket address such as
`ws://192.168.1.42:8088/lantern-link`. Give that address and the chosen player
name to the other local players. It binds to the local network intentionally;
use a trusted classroom/home network only.

## Join from the game

Run the Flutter game in Chrome, choose **Lantern Link** from the title screen
or the group icon in the app bar, then enter the server address and a player
name. The first player is the host. After everyone joins, the host selects two
or four players and uses **Assign heroes and begin exploration**. The default
two-player selection works without toggling it: assignment first configures
the mode and waits for the server acknowledgement.

The host starts a New Game and explores; guests mirror the host without local
movement authority. The app-bar Training battle uses a server-supported shared
encounter while connected, rather than sending the offline fixture encounter.
Each player selects Attack/Defend for their own heroes. Shared combat gates
local movement, encounters and saves until its authoritative terminal result.

## Protocol

Messages are JSON objects. Every successful request broadcasts a message whose
`snapshot` contains the authoritative lobby, party assignment, exploration
state, and (while active) battle state.

Requests carry a client-local integer `requestId`. Successful broadcasts echo
that ID and `requesterId`; errors echo the request ID only to its sender.
Clients match both the sender and ID, and wait for exploration publications to
be acknowledged before sending `battleStart`. Rejected starts release the
pending local gate so the next attempt remains usable.

Snapshots retain `encounterId`, `encounterDefinitionId` and `outcome` after
combat. A new encounter clears its outcome and allocates a new identity.
The host applies quest victory flags/followup once, independently of the
combat reward snapshot. A promoted guest can reconcile a missing quest flag
without granting combat rewards again.

1. Connect to `/lantern-link`, then send `{"type":"hello","playerId":"host"}`.
   The first player is the host.
2. The host configures `{"type":"configure","mode":"two"}` or `"four"`.
3. The host sends `assignments`, for example:

```json
{
  "type": "assign",
  "assignments": {
    "host": ["hero.ada", "hero.ren"],
    "guest": ["hero.iona", "hero.tavi"]
  }
}
```

4. Once the room is ready, only the host may publish an exploration snapshot or
start an encounter. The server broadcasts both.
5. During battle, each player sends `command` with the server's current `round`
and a command for one of their assigned heroes. After every living hero has
locked a command, the server resolves exactly one existing C battle round and
broadcasts the result. Duplicate, stale, and unauthorized submissions return
an error without changing the room.

Invalid owned commands are checked before locking, including reservations of
shared items. They can be corrected in the same round. A resolved failed
`flee` publishes the enemy response and new round, or the terminal defeat.

If a player disconnects during play, the room pauses. Reconnecting with the
same player ID restores their assignment; play resumes only when every assigned
player is present. The elected host gains exploration authority after that
gate clears. **Leave room** returns the departing client to a usable title
screen and invalidates pending remote loads.

Defeat is the separate `gameOver` phase, not a disconnect pause. Both clients
apply the final party/resources. The host's **New Game** sends `restart`, which
restores the room's original party/world state while preserving assignments
and monotonic encounter identities. Restart requires all assigned players.

## Current integration boundary

The server uses the production C5 encounter factory and C4 party data. It owns
lobby state, command authorization, battle resolution, rewards, and shared
return state. B's collision and map logic still run in the elected host game;
the host may publish resulting exploration snapshots while joined players are
read-only. The server starts at the same collision-clear artwork entry as the
local game. Android release builds request Internet access; macOS debug and
release sandboxes grant outgoing network access. The server is still a trusted
LAN prototype, not an authenticated public hosting service.
