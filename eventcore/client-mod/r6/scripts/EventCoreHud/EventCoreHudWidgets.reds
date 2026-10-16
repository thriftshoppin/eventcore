// EventCore native HUD — inkWidget spawn ladder + host (pipeline only).

@addMethod(inkHUDGameController)
public func EventCoreSpawnLocal(parent: ref<inkWidget>, libraryId: CName) -> wref<inkWidget> {
  return this.SpawnFromLocal(parent, libraryId);
}

@addMethod(inkHUDGameController)
public func EventCoreSpawnExternal(parent: ref<inkWidget>, libraryId: CName) -> wref<inkWidget> {
  return this.SpawnFromExternal(parent, r"eventcore\\gui\\eventcore_bar.inkwidget", libraryId);
}

public class EventCoreStyleProbe extends IScriptable {
  public let anchor: inkEAnchor;
  public let anchorPoint: Vector2;
  public let margin: inkMargin;
  public let size: Vector2;
  public let scale: Vector2;
  public let bottomAnchored: Bool;
}

public static func EventCoreProbeStyle(root: ref<inkWidget>) -> ref<EventCoreStyleProbe> {
  let probe: ref<EventCoreStyleProbe> = new EventCoreStyleProbe();
  probe.anchor = root.GetAnchor();
  probe.anchorPoint = root.GetAnchorPoint();
  probe.margin = root.GetMargin();
  probe.size = root.GetSize();
  probe.scale = root.GetScale();
  if probe.size.Y < 10.0 { probe.size.Y = EventCoreHudFallbackRootHeight(); }
  probe.bottomAnchored = Equals(probe.anchor, inkEAnchor.BottomLeft)
    || Equals(probe.anchor, inkEAnchor.BottomCenter)
    || Equals(probe.anchor, inkEAnchor.BottomRight);
  return probe;
}

public class EventCoreBar extends IScriptable {
  public let id: String;
  public let root: ref<inkWidget>;
  public let fill: ref<inkWidget>;
  public let label: ref<inkText>;
  public let order: Int32;
}

public static func EventCoreAdoptTemplate(w: wref<inkWidget>, id: String) -> ref<EventCoreBar> {
  if !IsDefined(w) { return null; }
  let bar: ref<EventCoreBar> = new EventCoreBar();
  bar.id = id; bar.root = w;
  w.SetName(StringToName("ec_" + id));
  let compound: ref<inkCompoundWidget> = w as inkCompoundWidget;
  if IsDefined(compound) {
    bar.fill = compound.GetWidgetByPathName(n"fill");
    bar.label = compound.GetWidgetByPathName(n"label") as inkText;
  }
  return bar;
}

public static func EventCoreBuildProcedural(parent: ref<inkCompoundWidget>, id: String, order: Int32) -> ref<EventCoreBar> {
  if !IsDefined(parent) { return null; }
  let bar: ref<EventCoreBar> = new EventCoreBar();
  bar.id = id; bar.order = order;
  let root: ref<inkCanvas> = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
  root.SetName(StringToName("ec_" + id));
  root.SetInteractive(false);
  root.SetSize(EventCoreHudBarWidth(), EventCoreHudBlockHeight());
  root.SetAnchor(inkEAnchor.TopLeft);
  root.SetMargin(0.0, Cast<Float>(order) * (EventCoreHudBlockHeight() + 4.0), 0.0, 0.0);
  bar.root = root;
  let track: ref<inkRectangle> = root.AddChild(n"inkRectangleWidget") as inkRectangle;
  track.SetName(n"track");
  track.SetAnchor(inkEAnchor.CenterLeft);
  track.SetSize(EventCoreHudBarWidth(), EventCoreHudBarThickness());
  track.SetMargin(0.0, 10.0, 0.0, 0.0);
  track.SetTintColor(new HDRColor(0.15, 0.15, 0.15, 0.7));
  let fill: ref<inkRectangle> = root.AddChild(n"inkRectangleWidget") as inkRectangle;
  fill.SetName(n"fill");
  fill.SetAnchor(inkEAnchor.CenterLeft);
  fill.SetSize(EventCoreHudBarWidth(), EventCoreHudBarThickness());
  fill.SetMargin(0.0, 10.0, 0.0, 0.0);
  fill.SetTintColor(EventCoreHudColorDefault());
  bar.fill = fill;
  let label: ref<inkText> = root.AddChild(n"inkTextWidget") as inkText;
  label.SetName(n"label");
  label.SetAnchor(inkEAnchor.TopLeft);
  label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  label.SetFontSize(16);
  label.SetTintColor(EventCoreHudColorDefault());
  label.SetText(id);
  bar.label = label;
  return bar;
}

public class EventCoreBarHost extends IScriptable {
  public let owner: wref<inkHUDGameController>;
  public let container: ref<inkCanvas>;
  public let bars: array<ref<EventCoreBar>>;
  public let probe: ref<EventCoreStyleProbe>;

  public func IsMounted() -> Bool { return IsDefined(this.container); }

  public func Mount(owner: ref<inkHUDGameController>) -> Bool {
    if this.IsMounted() { return true; }
    let root: ref<inkWidget> = owner.GetRootWidget();
    if !IsDefined(root) { return false; }
    this.owner = owner;
    this.probe = EventCoreProbeStyle(root);
    let parent: ref<inkCompoundWidget> = root.parentWidget as inkCompoundWidget;
    let asChild: Bool = false;
    if !IsDefined(parent) { parent = owner.GetRootCompoundWidget(); asChild = true; }
    if !IsDefined(parent) { return false; }
    this.container = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.container.SetName(n"EventCoreHudBars");
    this.container.SetInteractive(false);
    this.container.SetVisible(false);
    this.container.SetSize(EventCoreHudBarWidth(), EventCoreHudBlockHeight() * Cast<Float>(EventCoreHudMaxBars()));
    this.container.SetScale(this.probe.scale);
    let step: Float = this.probe.size.Y + EventCoreHudGap();
    if asChild {
      this.container.SetAnchor(inkEAnchor.TopLeft);
      this.container.SetAnchorPoint(new Vector2(0.0, 0.0));
      this.container.SetMargin(EventCoreHudOffsetX(), step, 0.0, 0.0);
    } else {
      let margin: inkMargin = this.probe.margin;
      this.container.SetAnchor(this.probe.anchor);
      this.container.SetAnchorPoint(this.probe.anchorPoint);
      if this.probe.bottomAnchored { margin.bottom += step; } else { margin.top += step; }
      margin.left += EventCoreHudOffsetX();
      this.container.SetMargin(margin);
    }
    return true;
  }

  public func Find(id: String) -> ref<EventCoreBar> {
    let i: Int32 = 0;
    while i < ArraySize(this.bars) {
      if Equals(this.bars[i].id, id) { return this.bars[i]; }
      i += 1;
    }
    return null;
  }

  private func Spawn(id: String, order: Int32) -> ref<EventCoreBar> {
    let localId: String = EventCoreHudSpawnLocalId();
    if StrLen(localId) > 0 {
      let fromLocal: wref<inkWidget> = this.owner.EventCoreSpawnLocal(this.container, StringToName(localId));
      if IsDefined(fromLocal) {
        let adopted: ref<EventCoreBar> = EventCoreAdoptTemplate(fromLocal, id);
        if IsDefined(adopted) { adopted.order = order; return adopted; }
      }
    }
    if EventCoreHudExternalEnabled() {
      let fromExternal: wref<inkWidget> = this.owner.EventCoreSpawnExternal(this.container, n"Root");
      if IsDefined(fromExternal) {
        let adopted: ref<EventCoreBar> = EventCoreAdoptTemplate(fromExternal, id);
        if IsDefined(adopted) { adopted.order = order; return adopted; }
      }
    }
    return EventCoreBuildProcedural(this.container, id, order);
  }

  public func Ensure(id: String, order: Int32) -> ref<EventCoreBar> {
    let existing: ref<EventCoreBar> = this.Find(id);
    if IsDefined(existing) { return existing; }
    if !this.IsMounted() { return null; }
    let bar: ref<EventCoreBar> = this.Spawn(id, order);
    if IsDefined(bar) { ArrayPush(this.bars, bar); this.container.SetVisible(true); }
    return bar;
  }

  public func ApplyDefine(evt: ref<EventCoreBarDefineEvent>) -> Void {
    let bar: ref<EventCoreBar> = this.Ensure(evt.id, evt.order);
    if !IsDefined(bar) { return; }
    if IsDefined(bar.label) { bar.label.SetText(evt.label); }
    if IsDefined(bar.fill) { bar.fill.SetTintColor(evt.color); }
  }

  public func ApplyValue(evt: ref<EventCoreBarValueEvent>) -> Void {
    let bar: ref<EventCoreBar> = this.Ensure(evt.id, 0);
    if !IsDefined(bar) { return; }
    if IsDefined(bar.root) { bar.root.SetVisible(evt.visible); }
    if IsDefined(bar.fill) {
      let maxV: Float = evt.maxValue > 0.0 ? evt.maxValue : 100.0;
      let ratio: Float = ClampedF(evt.value / maxV, 0.0, 1.0);
      bar.fill.SetSize(EventCoreHudBarWidth() * ratio, EventCoreHudBarThickness());
    }
    if IsDefined(bar.label) && StrLen(evt.label) > 0 { bar.label.SetText(evt.label); }
  }

  public func Remove(id: String) -> Void {
    let i: Int32 = 0;
    while i < ArraySize(this.bars) {
      if Equals(this.bars[i].id, id) {
        if IsDefined(this.bars[i].root) {
          let parent: ref<inkCompoundWidget> = this.bars[i].root.parentWidget as inkCompoundWidget;
          if IsDefined(parent) { parent.RemoveChild(this.bars[i].root); }
        }
        ArrayErase(this.bars, i);
        return;
      }
      i += 1;
    }
  }

  public func Reset() -> Void {
    let i: Int32 = ArraySize(this.bars) - 1;
    while i >= 0 { this.Remove(this.bars[i].id); i -= 1; }
    if IsDefined(this.container) { this.container.SetVisible(false); }
  }
}
