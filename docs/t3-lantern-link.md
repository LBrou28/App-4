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

## Protocol

Messages are JSON objects. Every successful request broadcasts a message whose
`snapshot` contains the authoritative lobby, party assignment, exploration
state, and (while active) battle state.

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

If a player disconnects during play, the server pauses the room. Reconnecting
with the same player ID restores the prior party assignment and resumes it only
when every assigned player is present. This is T3's safe disconnect fallback.

## Current integration boundary

The server uses the production C5 encounter factory and C4 party data. It owns
lobby state, command authorization, battle resolution, rewards, and shared
return state. B's collision and map logic still run in the elected host game;
the host may publish resulting exploration snapshots while joined players are
read-only. A browser lobby/game client should use this documented protocol as a
follow-up UI slice; it does not need server-side combat logic.
