import AppKit
import SwiftUI
import UserNotifications
import TimerCore

@MainActor
final class ReminderStore: ObservableObject {
  @Published private(set) var reminders: [Reminder] = []
  @Published var now = Date()
  @Published var notificationAllowed = false
  @Published var errorMessage: String?
  @Published var playSound = UserDefaults.standard.object(forKey: "playSound") as? Bool ?? true
  @Published var showCountdown = UserDefaults.standard.object(forKey: "showCountdown") as? Bool ?? true
  @Published var showSeconds = UserDefaults.standard.object(forKey: "showSeconds") as? Bool ?? false
  var onChange: (() -> Void)?
  var onDue: ((Reminder) -> Void)?
  private var ticker: Timer?
  private let systemNotifications: Bool
  private var failedNotifications: Set<UUID> = []
  private let center = UNUserNotificationCenter.current()
  private let storageURL: URL

  var active: [Reminder] { reminders.filter { $0.completedAt == nil }.sorted { $0.deadline < $1.deadline } }
  var completed: [Reminder] { reminders.filter { $0.completedAt != nil }.sorted { $0.deadline > $1.deadline } }

  init(storageURL customURL: URL? = nil, systemNotifications: Bool = true) {
    self.systemNotifications = systemNotifications
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TimeSensitive")
    storageURL = customURL ?? folder.appendingPathComponent("reminders.json")
    do {
      try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: storageURL.path) {
        reminders = try JSONDecoder().decode([Reminder].self, from: Data(contentsOf: storageURL))
      }
    } catch { errorMessage = "无法读取提醒：\(error.localizedDescription)" }
    ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    Task { await refreshPermission() }
  }

  func refreshPermission() async {
    guard systemNotifications else { return }
    let settings = await center.notificationSettings()
    notificationAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
  }

  func requestPermission() async {
    guard systemNotifications else { return }
    do {
      notificationAllowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      if notificationAllowed {
        for reminder in active where reminder.deadline > Date() { await schedule(reminder) }
      }
    } catch { errorMessage = "通知授权失败：\(error.localizedDescription)" }
  }

  func add(title: String, deadline: Date) async -> Bool {
    guard deadline > Date() else { errorMessage = "请选择未来的提醒时间"; return false }
    now = Date()
    let reminder = Reminder(title: title, createdAt: now, deadline: deadline)
    reminders.append(reminder)
    guard persist() else { reminders.removeAll { $0.id == reminder.id }; return false }
    if !notificationAllowed { await requestPermission() }
    await schedule(reminder)
    onChange?()
    return true
  }

  private func schedule(_ reminder: Reminder) async {
    guard notificationAllowed, reminder.deadline > Date() else { return }
    let content = UNMutableNotificationContent()
    content.title = "提醒"
    content.body = reminder.title
    if playSound { content.sound = .default }
    content.interruptionLevel = .timeSensitive
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.deadline.timeIntervalSinceNow), repeats: false)
    do {
      try await center.add(UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger))
      failedNotifications.remove(reminder.id)
    } catch {
      failedNotifications.insert(reminder.id)
      errorMessage = "系统通知安排失败，App 运行时仍会提醒：\(error.localizedDescription)"
    }
  }

  func remove(_ reminder: Reminder) {
    let old = reminders
    reminders.removeAll { $0.id == reminder.id }
    guard persist() else { reminders = old; return }
    center.removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
    center.removeDeliveredNotifications(withIdentifiers: [reminder.id.uuidString])
    onChange?()
  }

  func clearCompleted() {
    let old = reminders
    reminders.removeAll { $0.completedAt != nil }
    if !persist() { reminders = old }
  }

  func saveSettings() {
    UserDefaults.standard.set(playSound, forKey: "playSound")
    UserDefaults.standard.set(showCountdown, forKey: "showCountdown")
    UserDefaults.standard.set(showSeconds, forKey: "showSeconds")
    onChange?()
    Task { for reminder in active { await schedule(reminder) } }
  }

  func tick() {
    now = Date()
    var changed = false
    for index in reminders.indices where reminders[index].completedAt == nil && reminders[index].deadline <= now {
      reminders[index].completedAt = now
      changed = true
      if !notificationAllowed || failedNotifications.contains(reminders[index].id) { onDue?(reminders[index]) }
    }
    if changed { _ = persist() }
    onChange?()
  }

  @discardableResult
  private func persist() -> Bool {
    do {
      try JSONEncoder().encode(reminders).write(to: storageURL, options: .atomic)
      return true
    } catch {
      errorMessage = "无法保存提醒：\(error.localizedDescription)"
      return false
    }
  }
}
