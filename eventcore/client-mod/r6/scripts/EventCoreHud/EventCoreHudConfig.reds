// EventCore native HUD — layout / spawn knobs only (inkWidget pipeline).

public static func EventCoreHudBarWidth() -> Float { return 260.0; }
public static func EventCoreHudBarThickness() -> Float { return 8.0; }
public static func EventCoreHudBlockHeight() -> Float { return 30.0; }
public static func EventCoreHudGap() -> Float { return 14.0; }
public static func EventCoreHudOffsetX() -> Float { return 0.0; }
public static func EventCoreHudFallbackRootHeight() -> Float { return 60.0; }
public static func EventCoreHudMaxBars() -> Int32 { return 12; }
public static func EventCoreHudPumpSeconds() -> Float { return 0.1; }
public static func EventCoreHudSpawnLocalId() -> String { return ""; }
public static func EventCoreHudExternalEnabled() -> Bool { return false; }
public static func EventCoreHudColorDefault() -> HDRColor { return new HDRColor(0.9, 0.9, 0.9, 1.0); }
public static func EventCoreHudColorWarn() -> HDRColor { return new HDRColor(1.2, 0.8, 0.25, 1.0); }
public static func EventCoreHudColorCritical() -> HDRColor { return new HDRColor(1.4, 0.25, 0.2, 1.0); }
