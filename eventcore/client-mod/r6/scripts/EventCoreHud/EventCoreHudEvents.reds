// EventCore native HUD — typed UI events (queue on UI frame).

public class EventCoreBarDefineEvent extends Event {
  public let id: String;
  public let label: String;
  public let order: Int32;
  public let color: HDRColor;
  public let ticks: array<Float>;
}
public class EventCoreBarValueEvent extends Event {
  public let id: String;
  public let label: String;
  public let visible: Bool;
  public let value: Float;
  public let maxValue: Float;
}
public class EventCoreBarRemoveEvent extends Event {
  public let id: String;
}
public class EventCoreHudResetEvent extends Event {}

public static func EventCoreHudDispatch(game: GameInstance, evt: ref<Event>) -> Bool {
  let ui: ref<UISystem> = GameInstance.GetUISystem(game);
  if !IsDefined(ui) || !IsDefined(evt) { return false; }
  ui.QueueEvent(evt);
  return true;
}
