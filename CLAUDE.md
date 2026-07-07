# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Farleyworld — notes for agents

Rails 8.1 (Ruby 3.4.2 via rbenv — 3.3 breaks actionview 8.1), importmap +
Propshaft, SQLite, ActionCable (async adapter in dev). No Node build step.
PS1-era MMO lounge: fixed cameras, pre-rendered backgrounds, low-poly
characters on a walkmesh (see README for the full write-up).

## Commands

- `bin/rails db:prepare db:seed` — set up / reseed the database.
- `bin/rails server` (or `bin/dev`, same thing) — run at localhost:3000.
- `bin/ci` — runs setup + security audits (bundler-audit, importmap audit).
  There is **no test suite** (no test/ directory); verification is manual —
  see "Verify after changes" below.
- Deploy: `kamal deploy` (`kamal setup` first time). Shares an EC2 host and
  kamal-proxy with farleyrace; GHCR token is read from
  `~/.config/kamal/ghcr-token` (mode 600), see `.kamal/secrets` and
  `config/deploy.yml`.

## Architecture in one breath

Server: `Room` (JSON `data` column holds walkmesh/props/camera/interactables/
exits), `Player` (room + x/z/heading), `RoomChannel` validates moves against
`Room#contains?` and rebroadcasts (`roster`, `player_moved`, `interaction`,
`room_change`, join/leave). Client: `app/javascript/game/*` — Three.js scene
built from room JSON, static geometry pre-rendered once to a color+depth
target, characters composited over it each frame (see README for the trick).

**Rooms are pure data**: everything (spawn, camera, lights, walkmesh via
`grid_walkmesh`, props, interactables, exits) lives in `Room#data`, seeded
from `db/seeds.rb`. Adding a room = adding a seed entry; no client or server
code changes. Client and server run the same point-in-mesh test — keep
`game/walkmesh.js` and `Room#contains?` in agreement.

## Gotchas learned the hard way

- **three.js is vendored** at `vendor/javascript/three.js` (0.160.1, the last
  single-file build). Do NOT re-run `bin/importmap pin three` — jspm serves a
  chunked build whose relative chunk imports 404 under Propshaft digests.
  Newer three (≥0.167) splits into three.module.js + three.core.js: same
  problem.
- The background-quad shader gamma-encodes (`pow(c, 1/2.2)`) because render
  targets skip three's output color-space conversion. If backgrounds look
  washed out or crushed, look there.
- Light intensities in seeds look high (2–5); that's physical-lights mode +
  sRGB→linear albedo crush. Calibrate by screenshot, not by intuition.
- After adding new files under `app/javascript/game/`, restart the dev server
  if the importmap JSON renders empty (it caches hard).
- Testing: headless Windows Chrome works from WSL for screenshots
  (`--headless=new --user-data-dir=<fresh> --virtual-time-budget=15000
  --screenshot=...`), but WebSockets never complete under virtual time — use
  `/play?preview=1` (offline staged players) for visuals, and Node's built-in
  WebSocket (`scratchpad cable tests`) for protocol checks against
  `ws://localhost:PORT/cable`.
- Dev login shortcuts: `/?as=Name`, `&room=<slug>`, `&preview=1`
  (sessions#new, development only). `?touch=1` forces mobile touch controls
  on desktop.

## Verify after changes

1. `bin/rails db:seed` succeeds and prints triangle counts.
2. `bin/rails runner` geometry sanity: spawns/exits/interactables on-mesh
   (see git history for the snippet).
3. Screenshot `/?as=X&preview=1` (both rooms) — characters standing on the
   ground, occlusion behind pillars intact.
4. Node WS client: subscribe → roster → move → broadcast; off-mesh move
   (99,99) must be silently ignored; `use_exit` round-trips lounge⇄courtyard.
