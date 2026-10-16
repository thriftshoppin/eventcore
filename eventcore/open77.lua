resource "eventcore"
version "0.8.0"
description "Experimental event, service, and persistence foundation for Open77 resources"
author "EventCore Project"
auto_start true
shared_script "shared/eventcore.lua"
shared_script "shared/native_registry.lua"
shared_script "shared/widgets.lua"
shared_script "shared/eventview.lua"
server_script "server/whitelist.lua"
server_script "server/persistence.lua"
server_script "server/bridge.lua"
server_script "server/runtime_api.lua"
server_script "server/access.lua"
server_script "server/chat.lua"
server_script "server/admin.lua"
server_script "server/state_feed.lua"
server_script "server/hud.lua"
server_script "server/hud_bench.lua"
server_script "server/widgets.lua"
server_script "server/eventview.lua"
server_script "server/eventcore_server.lua"
client_script "client/eventcore_client.lua"
client_script "client/bridge_runtime.lua"
client_script "client/chat.lua"
client_script "client/native_hud.lua"
client_script "client/widgets.lua"
client_script "client/eventview.lua"
client_script "client/admin.lua"
web_files { "web/admin/**", "web/chat/**" }
files { "client/modules/bridge.lua" }
permissions { "network.events", "local.events", "input.actions", "database.access", "players.read", "acl.read" }

-- Client HUD is a SEPARATE Warden required mod: sibling folder eventcore-hud/
-- Zip eventcore-hud/ (archive root must contain r6/) and register that package in Warden.
-- Do not nest the client mod inside this server resource.

