import AppKit
import SwiftUI
import TimerCore

private let PURPLE = NSColor(srgbRed: 0.63, green: 0.26, blue: 0.71, alpha: 1)

@MainActor
final class StatusController: NSObject {
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  let popover = NSPopover()
  private let store: ReminderStore
  private let statusView = StatusView(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
  private(set) var overlay: NSPanel?
  private(set) var overlayPanels: [NSPanel] = []
  private(set) var selectedMinutes: Int?
  private var dragStart: NSPoint?
  private var dragScreen: NSScreen?
  private var isDragging = false
  private var pointerTimer: Timer?
  private var escapeMonitor: Any?

  init(store: ReminderStore) {
    self.store = store
    super.init()
    if let button = item.button {
      statusView.frame = button.bounds
      statusView.autoresizingMask = [.width, .height]
      button.addSubview(statusView)
      button.target = self
      button.action = #selector(handleButtonPress)
      // 系统菜单栏可能使用按钮的代理视图，必须从原生按钮接收按下事件。
      button.sendAction(on: [.leftMouseDown, .rightMouseDown])
      button.setAccessibilityLabel("手势计时器")
      button.toolTip = "手势计时器 · 点击查看，拖离菜单栏创建提醒"
    }
    popover.behavior = .transient
    popover.animates = true
    store.onChange = { [weak self] in self?.update() }
    update()
  }

  @objc private func handleButtonPress() {
    guard let event = NSApp.currentEvent else {
      togglePopover()
      return
    }
    if event.type == .rightMouseDown {
      let menu = NSMenu()
      let quit = NSMenuItem(title: "退出手势计时器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
      quit.target = NSApp
      menu.addItem(quit)
      NSMenu.popUpContextMenu(menu, with: event, for: item.button!)
    } else if event.type == .leftMouseDown {
      beginGesture(at: NSEvent.mouseLocation)
    } else {
      togglePopover()
    }
  }

  private func togglePopover() {
    if popover.isShown { popover.close() } else { show() }
  }

  func update() {
    let text = store.showCountdown ? store.active.first.map { TimerMath.countdown($0.remaining(at: store.now), showSeconds: store.showSeconds) } : nil
    statusView.countdown = text
    item.button?.setAccessibilityValue(text ?? "没有待办提醒")
    let width = text.map { ($0 as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]).width + 37 } ?? 30
    item.length = width
    statusView.needsDisplay = true
  }

  func show(minutes: Int? = nil) {
    guard let button = item.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    selectedMinutes = minutes
    if popover.isShown { popover.close() }
    let controller = NSHostingController(rootView: PanelView(store: store, editing: minutes != nil, minutes: Double(minutes ?? 30), dismiss: { [weak self] in self?.popover.close() }))
    controller.sizingOptions = [.preferredContentSize]
    let size = NSSize(width: 360, height: max(200, controller.view.fittingSize.height))
    controller.view.setFrameSize(size)
    popover.contentViewController = controller
    popover.contentSize = size
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  func beginGesture(at location: NSPoint) {
    cancelGesture()
    dragStart = location
    dragScreen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    selectedMinutes = nil
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return event }
      self?.cancelGesture()
      return nil
    }
    // 只在按住按钮期间读取鼠标位置。跨出菜单栏后仍能跟踪，不需要全局监听权限。
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.advanceGesture(
          to: NSEvent.mouseLocation,
          pressed: NSEvent.pressedMouseButtons & 1 != 0,
          precise: NSEvent.modifierFlags.contains(.shift)
        )
      }
    }
    pointerTimer = timer
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.add(timer, forMode: .eventTracking)
  }

  func advanceGesture(to location: NSPoint, pressed: Bool, precise: Bool) {
    guard let start = dragStart, let screen = dragScreen else { return }
    let distance = hypot(location.x - start.x, location.y - start.y)
    let menuHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top, item.button?.window?.frame.height ?? 0)
    let menuBottom = screen.frame.maxY - menuHeight
    let insideMenuBar = location.x >= screen.frame.minX && location.x <= screen.frame.maxX
      && location.y >= menuBottom && location.y <= screen.frame.maxY
    let canDrag = distance > 7 && !insideMenuBar
    if canDrag && !isDragging {
      isDragging = true
      popover.close()
      NSApp.activate(ignoringOtherApps: true)
    }
    if canDrag {
      selectedMinutes = precise ? max(1, min(1440, Int(max(0, distance) / 12))) : TimerMath.dragMinutes(distance: distance)
      if pressed { drawOverlay(start: start, end: location, screen: screen, minutes: selectedMinutes!) }
    }
    if !canDrag {
      selectedMinutes = nil
      overlayPanels.forEach { $0.orderOut(nil) }
    }
    guard !pressed else { return }
    let minutes = selectedMinutes
    let shouldOpenEditor = canDrag
    let isClick = !isDragging && distance <= 7
    cancelGesture()
    // 等原生按钮结束 tracking，再打开编辑面板，避免面板被 mouseUp 立即关闭。
    DispatchQueue.main.async { [weak self] in
      if shouldOpenEditor { self?.show(minutes: minutes) }
      else if isClick { self?.togglePopover() }
    }
  }

  func cancelGesture() {
    pointerTimer?.invalidate()
    pointerTimer = nil
    if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    escapeMonitor = nil
    overlayPanels.forEach { $0.orderOut(nil) }
    overlayPanels.removeAll()
    overlay = nil
    dragStart = nil
    dragScreen = nil
    isDragging = false
  }

  private func drawOverlay(start: NSPoint, end: NSPoint, screen: NSScreen, minutes: Int) {
    let screens = NSScreen.screens
    // 独立 Spaces 下，跨屏大窗口会被系统裁掉；每个屏幕必须有自己的窗口。
    if overlayPanels.map(\.frame) != screens.map(\.frame) {
      overlayPanels.forEach { $0.orderOut(nil) }
      overlayPanels = screens.map { display in
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: display.frame.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: display)
        panel.setFrame(display.frame, display: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = DragView(frame: NSRect(origin: .zero, size: display.frame.size))
        return panel
      }
    }
    let endScreen = screens.first { NSMouseInRect(end, $0.frame, false) } ?? screen
    for (panel, display) in zip(overlayPanels, screens) {
      guard let view = panel.contentView as? DragView else { continue }
      // 统一使用屏幕逻辑坐标，交给各窗口处理自己的 Retina 缩放。
      view.start = NSPoint(x: start.x - display.frame.minX, y: start.y - display.frame.minY)
      view.end = NSPoint(x: end.x - display.frame.minX, y: end.y - display.frame.minY)
      view.tooltipBounds = view.bounds
      view.showsTooltip = display == endScreen
      view.minutes = minutes
      panel.orderFrontRegardless()
      view.display()
    }
    overlay = overlayPanels.first { $0.frame == endScreen.frame }
  }

}

private final class StatusView: NSView {
  var countdown: String?
  // 绘制层不参与命中测试，所有输入交给 NSStatusBarButton。
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) {
    if countdown != nil {
      PURPLE.setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 7, yRadius: 7).fill()
      NSColor.white.withAlphaComponent(0.6).setStroke()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 2.5), xRadius: 6, yRadius: 6).stroke()
    }
    let color: NSColor = countdown != nil ? .white : .labelColor
    let icon = NSBezierPath()
    icon.appendOval(in: NSRect(x: 11, y: bounds.midY + 1, width: 7, height: 7))
    icon.appendOval(in: NSRect(x: 11, y: bounds.midY - 8, width: 7, height: 7))
    icon.appendRoundedRect(NSRect(x: 12.5, y: bounds.midY - 5, width: 4, height: 10), xRadius: 2, yRadius: 2)
    color.setFill()
    icon.fill()
    if let countdown {
      let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
      let size = (countdown as NSString).size(withAttributes: [.font: font])
      (countdown as NSString).draw(at: NSPoint(x: 27, y: (bounds.height - size.height) / 2), withAttributes: [.font: font, .foregroundColor: NSColor.white])
    }
  }
}

final class DragView: NSView {
  var start = NSPoint.zero
  var end = NSPoint.zero
  var minutes = 1
  var tooltipBounds = NSRect.zero
  var showsTooltip = true
  override func draw(_ dirtyRect: NSRect) {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(1, hypot(dx, dy))
    let offset = NSPoint(x: -dy / length * 2, y: dx / length * 2)
    let line = NSBezierPath()
    line.move(to: NSPoint(x: start.x + offset.x, y: start.y + offset.y))
    line.line(to: NSPoint(x: end.x + offset.x, y: end.y + offset.y))
    line.line(to: NSPoint(x: end.x - offset.x, y: end.y - offset.y))
    line.line(to: NSPoint(x: start.x - offset.x, y: start.y - offset.y))
    line.close()
    NSGradient(starting: PURPLE.withAlphaComponent(0.12), ending: PURPLE)?.draw(in: line, angle: atan2(dy, dx) * 180 / .pi)
    PURPLE.setFill()
    NSBezierPath(ovalIn: NSRect(x: end.x - 8, y: end.y - 8, width: 16, height: 16)).fill()
    NSColor.white.withAlphaComponent(0.85).setStroke()
    NSBezierPath(ovalIn: NSRect(x: start.x - 7, y: start.y - 7, width: 14, height: 14)).stroke()
    guard showsTooltip else { return }
    let duration = TimerMath.duration(Double(minutes * 60))
    let textWidth = (duration as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 21, weight: .light)]).width
    let width = max(162, textWidth + 32)
    let visible = tooltipBounds.isEmpty ? bounds : tooltipBounds
    let x = end.x - visible.minX > width + 28 ? end.x - width - 20 : end.x + 20
    let box = NSRect(x: min(visible.maxX - width - 10, max(visible.minX + 10, x)), y: min(visible.maxY - 94, max(visible.minY + 10, end.y - 40)), width: width, height: 84)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 15
    shadow.set()
    NSColor(srgbRed: 0.20, green: 0.19, blue: 0.22, alpha: 0.94).setFill()
    NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16).fill()
    NSGraphicsContext.restoreGraphicsState()
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 21, weight: .light), .foregroundColor: NSColor.white]
    (TimerMath.duration(Double(minutes * 60)) as NSString).draw(at: NSPoint(x: box.minX + 16, y: box.minY + 46), withAttributes: attrs)
    (clockText(Date().addingTimeInterval(Double(minutes * 60))) as NSString).draw(at: NSPoint(x: box.minX + 16, y: box.minY + 15), withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .light), .foregroundColor: NSColor.white.withAlphaComponent(0.75)])
  }
}
