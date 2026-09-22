import XCTest
@testable import TimerCore

final class TimerCoreTests: XCTestCase {
  func testDragMappingAndLimits() {
    XCTAssertEqual(TimerMath.dragMinutes(distance: -20), 1)
    XCTAssertEqual(TimerMath.dragMinutes(distance: 180), 30)
    XCTAssertEqual(TimerMath.dragMinutes(distance: 360), 60)
    XCTAssertEqual(TimerMath.dragMinutes(distance: 468), 150)
    XCTAssertEqual(TimerMath.dragMinutes(distance: 99999), 1440)
  }

  func testCountdownRounding() {
    XCTAssertEqual(TimerMath.duration(0), "0秒")
    XCTAssertEqual(TimerMath.duration(0.2), "1秒")
    XCTAssertEqual(TimerMath.duration(59), "59秒")
    XCTAssertEqual(TimerMath.duration(60), "1分钟")
    XCTAssertEqual(TimerMath.duration(61), "2分钟")
    XCTAssertEqual(TimerMath.duration(3600), "1小时")
    XCTAssertEqual(TimerMath.duration(8700), "2小时25分钟")
    XCTAssertEqual(TimerMath.countdown(0, showSeconds: false), "0分钟")
    XCTAssertEqual(TimerMath.countdown(59, showSeconds: false), "不足1分钟")
    XCTAssertEqual(TimerMath.countdown(61, showSeconds: false), "2分钟")
    XCTAssertEqual(TimerMath.countdown(0, showSeconds: true), "0秒")
    XCTAssertEqual(TimerMath.countdown(0.2, showSeconds: true), "1秒")
    XCTAssertEqual(TimerMath.countdown(59, showSeconds: true), "59秒")
    XCTAssertEqual(TimerMath.countdown(60, showSeconds: true), "1分钟0秒")
    XCTAssertEqual(TimerMath.countdown(61, showSeconds: true), "1分钟1秒")
    XCTAssertEqual(TimerMath.countdown(3600, showSeconds: true), "1小时0分钟0秒")
    XCTAssertEqual(TimerMath.countdown(8705, showSeconds: true), "2小时25分钟5秒")
  }

  func testReminderUsesWallClockAndSurvivesSerialization() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let reminder = Reminder(title: "  休息一下  ", createdAt: start, deadline: start.addingTimeInterval(1800))
    XCTAssertEqual(reminder.remaining(at: start.addingTimeInterval(300)), 1500)
    XCTAssertEqual(reminder.remaining(at: start.addingTimeInterval(2000)), 0)
    XCTAssertEqual(reminder.title, "休息一下")
    let decoded = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(reminder))
    XCTAssertEqual(decoded, reminder)
    XCTAssertEqual(Reminder(title: " \n", deadline: start).title, "时间到了，休息一下")
  }

  func testPastClockTimeMovesToTomorrow() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 10, minute: 30))!
    let past = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 9, minute: 15))!
    let result = TimerMath.nextOccurrence(of: past, now: now, calendar: calendar)
    let parts = calendar.dateComponents([.day, .hour, .minute], from: result)
    XCTAssertEqual(parts.day, 23)
    XCTAssertEqual(parts.hour, 9)
    XCTAssertEqual(parts.minute, 15)
    let future = now.addingTimeInterval(3600)
    XCTAssertEqual(TimerMath.nextOccurrence(of: future, now: now, calendar: calendar), future)
  }
}
