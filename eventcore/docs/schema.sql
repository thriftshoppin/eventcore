-- EventCore persistence schema (MySQL/MariaDB; server-side only)

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

-- Structured storage is isolated by resource identity, then optional player identity.
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
