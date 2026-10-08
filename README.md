EventCore is a lightweight Open77 event foundation for server resources and future plugins. It provides priority-ordered local event dispatch, middleware, cancellable event contexts, and a controlled client-to-server event relay. Server resources explicitly allow the client event names they accept; client relays that are not allowed are rejected.

This beta is an early communication layer intended for future Open77 tools. It does not yet include SQL or durable persistence, and the event state stored in memory does not survive a resource or server restart. It does not interpret gameplay outcomes or grant rewards.

The API and network behavior are experimental and have not been verified in a live Open77 session. Install only on a test server, review the requested permission and load rules in Warden, and report issues with the EventCore version, server build, reproduction steps, and sanitized logs.

To send a client event, a trusted server resource must first allow that event name through EventCore. It can then register a server-side listener. Client events are associated with the authenticated player's server source.

