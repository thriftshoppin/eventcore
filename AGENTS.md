# EventCore resource pack contributor handoff

This repository contains two sibling Open77 resources:

- `eventcore/` — the EventCore resource.
- `freeroam/` — the patched Freeroam resource used to prevent HUD and kill-feed interference.

Load `eventcore` before `rpcore`, and load each resource exactly once. Do not copy either resource into another sibling resource folder. Treat the resource-level `AGENTS.md` and `CHANGELOG.md` under `eventcore/` as the current EventCore implementation notes.

The Freeroam resource is included with authorization from its maintainer for server-side distribution as an Open77 patch.
