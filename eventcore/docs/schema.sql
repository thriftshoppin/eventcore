-- =============================================================================
-- EventCore persistence schema (MySQL / MariaDB, server-side only)
-- =============================================================================
--
-- You do NOT need to run this file. EventCore creates these tables itself on
-- server start (server/persistence.lua, CREATE_* constants) once the Open77
-- database bridge is enabled and `database.access` is approved in Warden for
-- EventCore. This file is the reference copy of what that code creates, kept
-- here so the data model can be read without running the server.
--
-- If you edit a CREATE TABLE in server/persistence.lua, update this file too.
--
-- All statements are idempotent (CREATE TABLE IF NOT EXISTS), so applying this
-- file by hand to the same database is harmless.
--
-- Conventions
--   * Engine InnoDB, utf8mb4 / utf8mb4_unicode_ci.
--   * JSON payloads are stored as LONGTEXT and guarded by CHECK (JSON_VALID()).
--     Each value is capped at 48 KiB by the Lua layer before insert.
--   * `revision` starts at 1 and increments on every upsert.
--   * All SQL issued by EventCore uses bound parameters; consumers never send
--     SQL, table names, or an owner name.
--   * Connection credentials come from the OP77_DATABASE_CONNECTION environment
--     variable on the server process. They are never stored in this repository.
--
-- Tables
--   eventcore_events                 Append-only history of dispatched events.
--   eventcore_player_state           Per-player state keyed by account identity
--                                    (trusted-caller / legacy compatibility API).
--   eventcore_resource_state         Isolated per-resource key/value storage.
--   eventcore_resource_player_state  Isolated per-resource, per-player storage.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- eventcore_events
-- One row per EventCore.DispatchLocal completed on the server, written through
-- a bounded asynchronous queue (max 1000 queued, 3 attempts per record).
--   source_id    session id of the originating player, or 0 for server events
--   source_kind  'player' or 'server'
--   event_data   JSON payload
--   cancelled    1 if a listener cancelled the event, with cancel_reason
--   occurred_ms  process-monotonic event timestamp in ms (0 if unavailable);
--                created_at is the SQL server's timestamp
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS eventcore_events (
  event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_name VARCHAR(128) NOT NULL,
  source_id INT NOT NULL DEFAULT 0,
  source_kind VARCHAR(16) NOT NULL,
  event_data LONGTEXT NOT NULL,
  cancelled TINYINT(1) NOT NULL DEFAULT 0,
  cancel_reason VARCHAR(255) NOT NULL DEFAULT '',
  occurred_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (event_id),
  KEY idx_eventcore_name_id (event_name, event_id),
  KEY idx_eventcore_source_id (source_id, event_id),
  CONSTRAINT chk_eventcore_event_data_json CHECK (JSON_VALID(event_data))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- eventcore_player_state
-- Authoritative JSON state for a player, written only by the server.
--   identity_type  'license' (account-level, follows linked devices) or
--                  'userId' (installation-scoped fallback on older runtimes)
--   identity_id    the stable identifier for that type; never the temporary
--                  numeric session id
--   namespace      logical group, e.g. 'inventory', 'outfit_codes'
--   state_key      key inside the namespace
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS eventcore_player_state (
  identity_type VARCHAR(16) NOT NULL,
  identity_id VARCHAR(64) NOT NULL,
  namespace VARCHAR(64) NOT NULL,
  state_key VARCHAR(128) NOT NULL,
  state_json LONGTEXT NOT NULL,
  revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (identity_type, identity_id, namespace, state_key),
  KEY idx_eventcore_state_updated (updated_at),
  CONSTRAINT chk_eventcore_state_json CHECK (JSON_VALID(state_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- eventcore_resource_state
-- Structured storage isolated by resource. resource_name is captured from the
-- invoking resource by the server, so a mod cannot read or write another mod's
-- rows. A resource must be listed in EventCore.Whitelist (server/whitelist.lua)
-- and declare `dependency "eventcore"` in its manifest to use it.
--   collection  logical group, 1-64 chars matching ^[A-Za-z0-9][A-Za-z0-9_.-]*$
--   state_key   key inside the collection (max 128 chars)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS eventcore_resource_state (
  resource_name VARCHAR(64) NOT NULL,
  collection VARCHAR(64) NOT NULL,
  state_key VARCHAR(128) NOT NULL,
  state_json LONGTEXT NOT NULL,
  revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (resource_name, collection, state_key),
  KEY idx_eventcore_resource_state_updated (resource_name, updated_at),
  CONSTRAINT chk_eventcore_resource_state_json CHECK (JSON_VALID(state_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- -----------------------------------------------------------------------------
-- eventcore_resource_player_state
-- Same isolation as eventcore_resource_state, additionally scoped to a player
-- by stable account identity (see eventcore_player_state for identity_type).
-- Supports the StoragePutPlayer / GetPlayer / DeletePlayer / ListPlayer exports
-- and per-player operations inside StorageTransaction (max 32 operations and
-- 48 KiB of payload per transaction).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS eventcore_resource_player_state (
  resource_name VARCHAR(64) NOT NULL,
  identity_type VARCHAR(16) NOT NULL,
  identity_id VARCHAR(64) NOT NULL,
  collection VARCHAR(64) NOT NULL,
  state_key VARCHAR(128) NOT NULL,
  state_json LONGTEXT NOT NULL,
  revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (resource_name, identity_type, identity_id, collection, state_key),
  KEY idx_eventcore_resource_player_updated (resource_name, updated_at),
  CONSTRAINT chk_eventcore_resource_player_state_json CHECK (JSON_VALID(state_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
