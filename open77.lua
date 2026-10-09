resource "eventcore"
version "0.3.1"
description "Experimental event, service, and persistence foundation for Open77 resources"
author "EventCore Project"
auto_start true
shared_script "shared/eventcore.lua"
server_script "server/persistence.lua"
server_script "server/runtime_api.lua"
server_script "server/access.lua"
server_script "server/state_feed.lua"
server_script "server/eventcore_server.lua"
client_script "client/eventcore_client.lua"
permissions { "network.events", "database.access", "players.read", "acl.read" }
