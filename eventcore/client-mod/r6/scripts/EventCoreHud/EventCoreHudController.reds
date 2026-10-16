// EventCore native HUD — pump on healthbarWidgetGameController (UI frame only).

@addField(healthbarWidgetGameController)
private let m_ecHost: ref<EventCoreBarHost>;
@addField(healthbarWidgetGameController)
private let m_ecSeen: Int32;
@addField(healthbarWidgetGameController)
private let m_ecSeenReset: Int32;
@addField(healthbarWidgetGameController)
private let m_ecGen: Int32;
@addField(healthbarWidgetGameController)
private let m_ecCallback: DelayID;

@wrapMethod(healthbarWidgetGameController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  this.EventCoreHudAttach();
  return result;
}

@wrapMethod(healthbarWidgetGameController)
protected cb func OnUninitialize() -> Bool {
  this.EventCoreHudDetach();
  return wrappedMethod();
}

@addMethod(healthbarWidgetGameController)
private func EventCoreHudAttach() -> Void {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) { return; }
  system.generation += 1;
  this.m_ecGen = system.generation;
  system.attached = true;
  this.m_ecHost = new EventCoreBarHost();
  this.m_ecHost.Mount(this);
  this.m_ecSeen = 0;
  this.m_ecSeenReset = system.resetRev;
  this.EventCoreHudSchedule();
}

@addMethod(healthbarWidgetGameController)
private func EventCoreHudDetach() -> Void {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if IsDefined(system) && this.m_ecGen == system.generation { system.attached = false; }
  if this.m_ecCallback != GetInvalidDelayID() {
    GameInstance.GetDelaySystem(this.GetPlayerControlledObject().GetGame()).CancelCallback(this.m_ecCallback);
    this.m_ecCallback = GetInvalidDelayID();
  }
  if IsDefined(this.m_ecHost) { this.m_ecHost.Reset(); }
  this.m_ecHost = null;
}

@addMethod(healthbarWidgetGameController)
private func EventCoreHudSchedule() -> Void {
  let delay: ref<DelaySystem> = GameInstance.GetDelaySystem(this.GetPlayerControlledObject().GetGame());
  if !IsDefined(delay) { return; }
  if this.m_ecCallback != GetInvalidDelayID() { delay.CancelCallback(this.m_ecCallback); }
  this.m_ecCallback = delay.DelayCallback(this, n"EventCoreHudPump", EventCoreHudPumpSeconds(), false);
}

@addMethod(healthbarWidgetGameController)
private cb func EventCoreHudPump(evt: ref<DelayEvent>) -> Void {
  this.EventCoreHudTick();
  this.EventCoreHudSchedule();
}

@addMethod(healthbarWidgetGameController)
private func EventCoreHudTick() -> Void {
  let system: ref<EventCoreHudSystem> = EventCoreHudSystemGet();
  if !IsDefined(system) || !IsDefined(this.m_ecHost) { return; }
  if this.m_ecGen != system.generation { return; }
  if system.resetRev != this.m_ecSeenReset {
    this.m_ecSeenReset = system.resetRev;
    this.m_ecHost.Reset();
  }
  let i: Int32 = 0;
  while i < ArraySize(system.bars) {
    let bar: ref<EventCoreBarState> = system.bars[i];
    if bar.removed {
      this.m_ecHost.Remove(bar.id);
      ArrayErase(system.bars, i);
      continue;
    }
    if bar.defRev > this.m_ecSeen {
      let def: ref<EventCoreBarDefineEvent> = new EventCoreBarDefineEvent();
      def.id = bar.id; def.label = bar.label; def.order = bar.order;
      def.color = bar.color; def.ticks = bar.ticks;
      this.m_ecHost.ApplyDefine(def);
    }
    if bar.valRev > this.m_ecSeen && !system.cleared {
      let val: ref<EventCoreBarValueEvent> = new EventCoreBarValueEvent();
      val.id = bar.id; val.label = bar.label; val.visible = bar.visible;
      val.value = bar.value; val.maxValue = bar.maxValue;
      this.m_ecHost.ApplyValue(val);
    }
    i += 1;
  }
  this.m_ecSeen = system.revision;
}

@addMethod(healthbarWidgetGameController)
protected cb func OnEventCoreBarDefineEvent(evt: ref<EventCoreBarDefineEvent>) -> Bool {
  if IsDefined(this.m_ecHost) { this.m_ecHost.ApplyDefine(evt); }
  return true;
}
@addMethod(healthbarWidgetGameController)
protected cb func OnEventCoreBarValueEvent(evt: ref<EventCoreBarValueEvent>) -> Bool {
  if IsDefined(this.m_ecHost) { this.m_ecHost.ApplyValue(evt); }
  return true;
}
@addMethod(healthbarWidgetGameController)
protected cb func OnEventCoreBarRemoveEvent(evt: ref<EventCoreBarRemoveEvent>) -> Bool {
  if IsDefined(this.m_ecHost) { this.m_ecHost.Remove(evt.id); }
  return true;
}
@addMethod(healthbarWidgetGameController)
protected cb func OnEventCoreHudResetEvent(evt: ref<EventCoreHudResetEvent>) -> Bool {
  if IsDefined(this.m_ecHost) { this.m_ecHost.Reset(); }
  return true;
}
