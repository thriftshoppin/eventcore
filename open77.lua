resource "eventcore"
version "0.3.0-beta.1"
description "Experimental event, service, and persistence foundation for Open77 resources"
author "EventCore Project"
auto_start true
shared_script "shared/eventcore.lua"
server_script "server/persistence.lua"
server_script "server/runtime_api.lua"
server_script "server/eventcore_server.lua"
client_script "client/eventcore_client.lua"
permissions { "network.events", "database.access" }
