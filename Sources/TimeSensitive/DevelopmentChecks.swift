import AppKit
import SwiftUI
import TimerCore

// 显式 --self-test 才运行，所有数据写入独立的临时目录。
@MainActor
enum DevelopmentChecks {
  static func run(outputPath: String) async {
    let output = URL(fileURLWithPath: outputPath)
    do {
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      let dataURL = output.appendingPathComponent("test-reminders-\(UUID().uuidString).json")
      let store = ReminderStore(storageURL: dataURL, systemNotifications: false)
      var results: [String] = []
      func check(_ value: Bool, _ name: String) throws {
        guard value else { throw NSError(domain: "DevelopmentChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        results.append("PASS: \(name)")
      }
      let status = StatusController(store: store)
      status.popover.animates = false
      // 等待系统完成菜单栏按钮的注册和布局。
      try await Task.sleep(nanoseconds: 500_000_000)
      guard let button = status.item.button else { throw NSError(domain: "DevelopmentChecks", code: 2) }
      let mask = NSEvent.EventTypeMask(rawValue: UInt64(button.sendAction(on: [])))
      button.sendAction(on: mask)
      try check(mask.contains(.leftMouseDown), "原生菜单栏按钮接收鼠标按下事件（实际掩码：\(mask.rawValue)）")
      let hit = button.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY))
      try check(hit === button, "绘制层不拦截原生按钮命中")
      guard let screen = NSScreen.main else { throw NSError(domain: "DevelopmentChecks", code: 3) }
      let start = NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 12)
      let end = NSPoint(x: start.x, y: start.y - 180)
      status.beginGesture(at: start)
      status.advanceGesture(to: end, pressed: true, precise: false)
      try check(status.overlay?.isVisible == true && status.selectedMinutes == 30, "拖出菜单栏 180 点显示 30 分钟预览")
      if let view = status.overlay?.contentView {
        let rect = NSRect(x: start.x - screen.frame.minX - 200, y: end.y - screen.frame.minY - 70, width: 250, height: 280)
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) {
          view.cacheDisplay(in: rect, to: bitmap)
          try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("drag-preview.png"))
        }
      }
      status.advanceGesture(to: end, pressed: false, precise: false)
      try await Task.sleep(nanoseconds: 400_000_000)
      try check(status.overlay == nil && status.popover.isShown && status.selectedMinutes == 30, "松开移除预览并打开 30 分钟编辑面板")
      status.popover.close()
      status.beginGesture(at: start)
      status.advanceGesture(to: end, pressed: true, precise: true)
      try check(status.selectedMinutes == 15, "Shift 精细拖动")
      status.cancelGesture()
      status.advanceGesture(to: end, pressed: false, precise: true)
      try await Task.sleep(nanoseconds: 50_000_000)
      try check(status.overlay == nil && !status.popover.isShown, "取消拖动后松开不创建提醒")
      status.beginGesture(at: start)
      status.advanceGesture(to: NSPoint(x: start.x, y: start.y - 2), pressed: false, precise: false)
      try await Task.sleep(nanoseconds: 400_000_000)
      try check(status.popover.isShown && status.selectedMinutes == nil, "普通点击仍打开提醒列表")
      status.popover.close()
      for (name, dx, dy) in [("左下", -108.0, -144.0), ("右下", 108.0, -144.0), ("左上", -108.0, 144.0), ("右上", 108.0, 144.0), ("向上", 0.0, 180.0)] {
        status.beginGesture(at: start)
        status.advanceGesture(to: NSPoint(x: start.x + dx, y: start.y + dy), pressed: true, precise: false)
        try check(status.overlay?.isVisible == true && status.selectedMinutes == 30, "\(name)拖动按直线距离计时")
        status.cancelGesture()
      }
      for dx in [-180.0, 180.0] {
        status.beginGesture(at: start)
        let horizontal = NSPoint(x: start.x + dx, y: start.y)
        status.advanceGesture(to: horizontal, pressed: true, precise: false)
        try check(status.overlay == nil && status.selectedMinutes == nil, "菜单栏内横向 \(dx) 点不触发计时")
        status.advanceGesture(to: horizontal, pressed: false, precise: false)
        try await Task.sleep(nanoseconds: 50_000_000)
        try check(!status.popover.isShown, "横向拖动松开不误判为点击")
      }
      status.beginGesture(at: start)
      status.advanceGesture(to: end, pressed: true, precise: false)
      let sideways = NSPoint(x: start.x + 240, y: end.y)
      status.advanceGesture(to: sideways, pressed: true, precise: false)
      try check(status.selectedMinutes == 50, "离开菜单栏后允许横向调整")
      status.advanceGesture(to: start, pressed: false, precise: false)
      try await Task.sleep(nanoseconds: 50_000_000)
      try check(status.overlay == nil && !status.popover.isShown, "拖回菜单栏松开取消创建")
      for display in NSScreen.screens {
        let displayStart = NSPoint(x: display.frame.midX, y: display.frame.maxY - 12)
        let displayEnd = NSPoint(x: displayStart.x, y: displayStart.y - 180)
        status.beginGesture(at: displayStart)
        status.advanceGesture(to: displayEnd, pressed: true, precise: false)
        try check(status.overlay?.frame == display.frame, "轨迹窗口限定在单个屏幕：\(display.localizedName)，屏幕 \(display.frame)，实际窗口 \(String(describing: status.overlay?.frame))，独立空间 \(NSScreen.screensHaveSeparateSpaces)")
        try check(status.overlayPanels.count == NSScreen.screens.count, "每块显示器创建独立轨迹窗口")
        for panel in status.overlayPanels {
          guard let owningDisplay = NSScreen.screens.first(where: { $0.frame == panel.frame }), let view = panel.contentView as? DragView else {
            throw NSError(domain: "DevelopmentChecks", code: 4, userInfo: [NSLocalizedDescriptionKey: "窗口跨屏或缺少轨迹视图"])
          }
          try check(panel.screen == owningDisplay && panel.isVisible && panel.isOnActiveSpace, "\(owningDisplay.localizedName) 的轨迹窗口位于本屏当前空间")
          try check(panel.convertPoint(toScreen: view.start) == displayStart && panel.convertPoint(toScreen: view.end) == displayEnd, "\(owningDisplay.localizedName) 起终点坐标转换正确")
          try check(view.showsTooltip == (owningDisplay == display), "时间提示仅显示在鼠标所在屏幕")
        }
        if let view = status.overlay?.contentView {
          let rect = NSRect(x: display.frame.width / 2 - 200, y: display.frame.height - 260, width: 250, height: 260)
          if let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) {
            view.cacheDisplay(in: rect, to: bitmap)
            let name = display.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("display-\(name?.stringValue ?? "unknown")-preview.png"))
          }
        }
        status.cancelGesture()
        try check(status.overlayPanels.isEmpty, "取消时清理全部显示器的轨迹窗口")
      }
      if NSScreen.screens.count > 1 {
        let source = NSScreen.screens[0]
        let destination = NSScreen.screens[1]
        let crossStart = NSPoint(x: source.frame.midX, y: source.frame.maxY - 12)
        let crossEnd = NSPoint(x: destination.frame.midX, y: destination.frame.midY)
        status.beginGesture(at: crossStart)
        status.advanceGesture(to: crossEnd, pressed: true, precise: false)
        try check(status.overlay?.frame == destination.frame, "跨屏拖动后提示跟随鼠标进入目标屏幕")
        try check(status.overlayPanels.compactMap { $0.contentView as? DragView }.filter(\.showsTooltip).count == 1, "跨屏时只有一个时间提示")
        status.cancelGesture()
      }
      await render(PanelView(store: store, editing: true, minutes: 30, dismiss: {}), height: 460, to: output.appendingPathComponent("editor.png"))
      let first = await store.add(title: "休息一下", deadline: Date().addingTimeInterval(1800))
      let second = await store.add(title: "给妈妈打电话", deadline: Date().addingTimeInterval(9000))
      try check(first && second && store.active.count == 2, "创建多个提醒")
      let restored = ReminderStore(storageURL: dataURL, systemNotifications: false)
      try check(restored.active == store.active, "重启恢复提醒")
      await render(PanelView(store: store, editing: false, minutes: 30, dismiss: {}), height: 480, to: output.appendingPathComponent("reminders.png"))
      store.remove(store.active[1])
      try check(store.active.count == 1, "删除单个提醒")
      var dueCount = 0
      store.onDue = { _ in dueCount += 1 }
      let short = await store.add(title: "到期检查", deadline: Date().addingTimeInterval(1.2))
      try check(short, "创建短时提醒")
      try await Task.sleep(nanoseconds: 1_600_000_000)
      store.tick()
      store.tick()
      try check(dueCount == 1 && store.completed.count == 1, "到期只触发一次")
      store.clearCompleted()
      try check(store.completed.isEmpty, "清除已完成提醒")
      let reloaded = ReminderStore(storageURL: dataURL, systemNotifications: false)
      try check(reloaded.active.count == 1 && reloaded.completed.isEmpty, "删除和清除持久化")
      try results.joined(separator: "\n").write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
      try FileManager.default.removeItem(at: dataURL)
    } catch {
      try? "FAIL: \(error.localizedDescription)".write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
    }
  }

  private static func render<V: View>(_ view: V, height: CGFloat, to url: URL) async {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.appearance = NSAppearance(named: .darkAqua)
    host.frame = NSRect(x: 0, y: 0, width: 360, height: height)
    host.layoutSubtreeIfNeeded()
    try? await Task.sleep(nanoseconds: 150_000_000)
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
  }
}
