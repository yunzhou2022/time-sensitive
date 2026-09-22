import AppKit
import UserNotifications
import TimerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private var store: ReminderStore!
  private var status: StatusController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    UNUserNotificationCenter.current().delegate = self
    if let index = CommandLine.arguments.firstIndex(of: "--self-test"), CommandLine.arguments.count > index + 1 {
      Task {
        await DevelopmentChecks.run(outputPath: CommandLine.arguments[index + 1])
        NSApp.terminate(nil)
      }
      return
    }
    store = ReminderStore()
    status = StatusController(store: store)
    store.onDue = { [weak self] reminder in
      let alert = NSAlert()
      alert.messageText = "时间到了"
      alert.informativeText = reminder.title
      alert.addButton(withTitle: "知道了")
      NSApp.activate(ignoringOtherApps: true)
      if self?.store.playSound == true { NSSound(named: "Glass")?.play() }
      // 异步显示窗口，避免多个提醒同时到期时阻塞计时器。
      alert.window.level = .floating
      guard let window = self?.reminderWindow() else { return }
      alert.beginSheetModal(for: window) { _ in window.close() }
    }
    DispatchQueue.main.async {
      if CommandLine.arguments.contains("--show") { self.status.show() }
      if CommandLine.arguments.contains("--new") { self.status.show(minutes: 30) }
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    guard let store else { return }
    Task { await store.refreshPermission() }
  }

  private func reminderWindow() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 1), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "手势计时器"
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    return window
  }

  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound])
  }

  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    Task { @MainActor in self.status.show() }
    completionHandler()
  }
}

MainActor.assumeIsolated {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  withExtendedLifetime(delegate) { app.run() }
}
