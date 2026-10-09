resource "eventcore"
version "0.6.2"
description "Experimental event, service, and persistence foundation for Open77 resources"
author "EventCore Project"
auto_start true
shared_script "shared/eventcore.lua"
server_script "server/whitelist.lua"
server_script "server/persistence.lua"
server_script "server/runtime_api.lua"
server_script "server/access.lua"
server_script "server/chat.lua"
server_script "server/admin.lua"
server_script "server/state_feed.lua"
server_script "server/eventcore_server.lua"
client_script "client/eventcore_client.lua"
client_script "client/chat.lua"
client_script "client/admin.lua"
web_files { "web/admin/**", "web/chat/**" }
permissions { "network.events", "input.actions", "database.access", "players.read", "acl.read" }
