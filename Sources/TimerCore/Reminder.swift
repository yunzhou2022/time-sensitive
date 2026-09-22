import Foundation

public struct Reminder: Codable, Identifiable, Equatable {
  public let id: UUID
  public var title: String
  public let createdAt: Date
  public var deadline: Date
  public var completedAt: Date?

  public init(id: UUID = UUID(), title: String, createdAt: Date = Date(), deadline: Date) {
    self.id = id
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "时间到了，休息一下" : title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.createdAt = createdAt
    self.deadline = deadline
  }

  public func remaining(at now: Date) -> TimeInterval {
    max(0, deadline.timeIntervalSince(now))
  }
}

public enum TimerMath {
  // 前一小时每 6 点对应 1 分钟，之后每 6 点对应 5 分钟。
  public static func dragMinutes(distance: Double) -> Int {
    let distance = max(0, distance)
    if distance <= 360 { return max(1, Int((distance / 6).rounded())) }
    return min(1440, 60 + Int(((distance - 360) / 6).rounded()) * 5)
  }

  public static func duration(_ seconds: TimeInterval) -> String {
    let seconds = max(0, Int(ceil(seconds)))
    if seconds < 60 { return "\(seconds)秒" }
    let minutes = Int(ceil(Double(seconds) / 60))
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return "\(minutes)分钟" }
    return rest == 0 ? "\(hours)小时" : "\(hours)小时\(rest)分钟"
  }

  public static func countdown(_ interval: TimeInterval, showSeconds: Bool) -> String {
    let seconds = max(0, Int(ceil(interval)))
    guard showSeconds else {
      if seconds == 0 { return "0分钟" }
      if seconds < 60 { return "不足1分钟" }
      return duration(Double(seconds))
    }
    if seconds < 60 { return "\(seconds)秒" }
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let rest = seconds % 60
    let prefix = hours > 0 ? "\(hours)小时" : ""
    return "\(prefix)\(minutes)分钟\(rest)秒"
  }

  public static func nextOccurrence(of time: Date, now: Date, calendar: Calendar = .current) -> Date {
    let parts = calendar.dateComponents([.hour, .minute], from: time)
    return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
  }
}
