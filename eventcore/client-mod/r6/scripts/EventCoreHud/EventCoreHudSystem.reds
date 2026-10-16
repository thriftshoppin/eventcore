// EventCore native HUD — store + RTTI entry points only (no widget mutation here).

public class EventCoreBarState extends IScriptable {
  public let id: String;
  public let label: String;
  public let order: Int32;
  public let color: HDRColor;
  public let ticks: array<Float>;
  public let visible: Bool;
  public let value: Float;
  public let maxValue: Float;
  public let defRev: Int32;
  public let valRev: Int32;
  public let removed: Bool;
}

public class EventCoreHudSystem extends ScriptableSystem {
  public let bars: array<ref<EventCoreBarState>>;
  public let revision: Int32;
  public let resetRev: Int32;
  public let cleared: Bool;
  public let attached: Bool;
  public let generation: Int32;
  public let tickCounter: Int32;
}

public static func EventCoreHudSystemGet() -> ref<EventCoreHudSystem> {
  return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"EventCoreHudSystem") as EventCoreHudSystem;
}

public static func EventCoreParseFloats(csv: String) -> array<Float> {
  let out: array<Float>;
  if StrLen(csv) == 0 { return out; }
  let parts: array<String> = StrSplit(csv, ",");
  let i: Int32 = 0;
  while i < ArraySize(parts) { ArrayPush(out, StringToFloat(parts[i])); i += 1; }
  return out;
}

public static func EventCoreParseColor(csv: String) -> HDRColor {
  if StrLen(csv) == 0 { return EventCoreHudColorDefault(); }
  let parts: array<String> = StrSplit(csv, ",");
  if ArraySize(parts) < 3 { return EventCoreHudColorDefault(); }
  let a: Float = ArraySize(parts) >= 4 ? StringToFloat(parts[3]) : 1.0;
  return new HDRColor(StringToFloat(parts[0]), StringToFloat(parts[1]), StringToFloat(parts[2]), a);
}

private static func EventCoreFindBar(system: ref<EventCoreHudSystem>, id: String) -> ref<EventCoreBarState> {
  let i: Int32 = 0;
  while i < ArraySize(system.bars) {
    if Equals(system.bars[i].id, id) { return system.bars[i]; }
    i += 1;
  }
  return null;
}

private static func EventCoreEnsureBar(system: ref<EventCoreHudSystem>, id: String) -> ref<EventCoreBarState> {
  let bar: ref<EventCoreBarState> = EventCoreFindBar(system, id);
  if IsDefined(bar) { bar.removed = false; return bar; }
  if ArraySize(system.bars) >= EventCoreHudMaxBars() { return null; }
  bar = new EventCoreBarState();
  bar.id = id; bar.label = id; bar.order = ArraySize(system.bars);
  bar.color = EventCoreHudColorDefault(); bar.visible = true; bar.value = 0.0; bar.maxValue = 100.0;
  ArrayPush(system.bars, bar);
  return bar;
}

public static func EventCoreHudPing() -> Bool { return IsDefined(EventCoreHudSystemGet()); }

public static func EventCoreHudDefineBar(id: String, label: String, order: Int32, colorCsv: String, ticksCsv: String) -> Bool {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) || StrLen(id) == 0 { return false; }
  let bar: ref<EventCoreBarState> = EventCoreEnsureBar(system, id);
  if !IsDefined(bar) { return false; }
  bar.label = StrLen(label) > 0 ? label : id; bar.order = order;
  bar.color = EventCoreParseColor(colorCsv); bar.ticks = EventCoreParseFloats(ticksCsv);
  system.revision += 1; bar.defRev = system.revision; system.cleared = false;
  return true;
}

public static func EventCoreHudSetBar(id: String, visible: Bool, value: Float, maxValue: Float) -> Bool {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) || StrLen(id) == 0 { return false; }
  let bar: ref<EventCoreBarState> = EventCoreEnsureBar(system, id);
  if !IsDefined(bar) { return false; }
  bar.visible = visible; bar.value = value; bar.maxValue = maxValue > 0.0 ? maxValue : 100.0;
  system.revision += 1; bar.valRev = system.revision; system.cleared = false;
  return true;
}

public static func EventCoreHudRemoveBar(id: String) -> Bool {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) || StrLen(id) == 0 { return false; }
  let bar: ref<EventCoreBarState> = EventCoreFindBar(system, id);
  if !IsDefined(bar) { return false; }
  bar.removed = true; system.revision += 1;
  return true;
}

public static func EventCoreHudClear() -> Bool {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) { return false; }
  let i: Int32 = 0;
  while i < ArraySize(system.bars) { system.bars[i].removed = true; i += 1; }
  system.revision += 1; system.resetRev = system.revision; system.cleared = true;
  return true;
}

public static func EventCoreHudHeartbeat() -> Bool {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) { return false; }
  system.tickCounter += 1;
  return true;
}

public static func EventCoreHudStatus() -> String {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) { return "attached=0;bars=0"; }
  return "attached=" + (system.attached ? "1" : "0") + ";bars=" + ToString(ArraySize(system.bars))
    + ";rev=" + ToString(system.revision) + ";gen=" + ToString(system.generation);
}
