import AppKit
import SwiftUI
import TimerCore

let ACCENT = Color(red: 0.67, green: 0.30, blue: 0.76)

func clockText(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "zh_CN")
  formatter.dateFormat = Calendar.current.isDateInToday(date) ? "ah:mm" : "M月d日 ah:mm"
  return formatter.string(from: date)
}

struct PanelView: View {
  @ObservedObject var store: ReminderStore
  @State var editing: Bool
  @State var minutes: Double
  @State private var title = ""
  @State private var mode = 0
  @State private var chosenTime = Date().addingTimeInterval(1800)
  @State private var settings = false
  @State private var saving = false
  @FocusState private var titleFocused: Bool
  let dismiss: () -> Void

  private var deadline: Date {
    mode == 0 ? Date().addingTimeInterval(minutes * 60) : TimerMath.nextOccurrence(of: chosenTime, now: Date())
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      if settings { settingsContent }
      else if editing { editor }
      else { reminderList }
      if let error = store.errorMessage {
        HStack(alignment: .top) {
          Text(error).font(.caption).foregroundStyle(.orange)
          Spacer()
          Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }.padding(14)
      }
    }
    .frame(width: 360)
    .background(.ultraThinMaterial)
    .preferredColorScheme(.dark)
    .tint(ACCENT)
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "hourglass").foregroundStyle(ACCENT).font(.system(size: 19, weight: .semibold))
      Text(settings ? "偏好设置" : editing ? "新的提醒" : "手势计时器").font(.system(size: 15, weight: .semibold))
      Spacer()
      if !editing && !settings {
        Button { minutes = 30; editing = true } label: { Image(systemName: "plus") }
          .help("添加提醒").accessibilityLabel("添加提醒")
      }
      Menu {
        Button("新建提醒") { settings = false; editing = true; minutes = 30 }
        Button("清除已完成提醒") { store.clearCompleted() }.disabled(store.completed.isEmpty)
        Divider()
        Button("退出手势计时器") { NSApp.terminate(nil) }
      } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
      Button { settings.toggle() } label: { Image(systemName: settings ? "xmark" : "gearshape") }
        .help(settings ? "返回" : "偏好设置").accessibilityLabel(settings ? "返回" : "偏好设置")
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white.opacity(0.8))
    .padding(20)
    .background(.black.opacity(0.22))
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 18) {
      Picker("提醒方式", selection: $mode) {
        Text("倒计时").tag(0)
        Text("指定时间").tag(1)
      }.pickerStyle(.segmented).labelsHidden()
      VStack(alignment: .leading, spacing: 6) {
        Text(TimerMath.duration(mode == 0 ? minutes * 60 : deadline.timeIntervalSinceNow))
          .font(.system(size: 32, weight: .light))
        Text(clockText(deadline)).font(.system(size: 23, weight: .light)).foregroundStyle(.secondary)
      }
      if mode == 0 {
        HStack {
          Text("时长").foregroundStyle(.secondary)
          Spacer()
          TextField("分钟", value: $minutes, format: .number).frame(width: 68).multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .onChange(of: minutes) { value in minutes = min(1440, max(1, value.isFinite ? value : 30)) }
          Text("分钟").foregroundStyle(.secondary)
          Stepper("分钟", value: $minutes, in: 1...1440).labelsHidden()
        }
        HStack(spacing: 8) {
          ForEach([5, 15, 30, 60], id: \.self) { value in
            Button { minutes = Double(value) } label: {
              Text(value == 60 ? "1 小时" : "\(value) 分钟").font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(minutes == Double(value) ? ACCENT.opacity(0.4) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
          }
        }
      } else {
        DatePicker("提醒时间", selection: $chosenTime, displayedComponents: .hourAndMinute)
          .datePickerStyle(.field)
        Text("已过的时间会安排在明天").font(.caption).foregroundStyle(.secondary)
      }
      TextField("添加描述，例如：休息一下", text: $title)
        .textFieldStyle(.plain).padding(11).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
        .focused($titleFocused).onSubmit { save() }
        .accessibilityLabel("提醒描述")
      if !store.notificationAllowed {
        Text("首次保存时会请求通知权限；未授权时使用 App 内提醒。").font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: 10) {
        Button { editing = false; title = "" } label: { Text("取消").frame(maxWidth: .infinity).padding(.vertical, 9) }
          .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
          .keyboardShortcut(.cancelAction)
        Button(action: save) { Text(saving ? "保存中…" : "保存").frame(maxWidth: .infinity).padding(.vertical, 9) }
          .background(ACCENT, in: RoundedRectangle(cornerRadius: 8)).disabled(saving)
          .keyboardShortcut(.defaultAction)
      }.buttonStyle(.plain)
    }
    .padding(22)
    .onAppear { titleFocused = true }
  }

  private func save() {
    guard !saving else { return }
    saving = true
    let target = deadline
    Task {
      if await store.add(title: title, deadline: target) { title = ""; editing = false }
      saving = false
    }
  }

  private var reminderList: some View {
    VStack(spacing: 0) {
      HStack {
        Text("当前提醒事项").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        Spacer()
        Text("\(store.active.count)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(ACCENT)
      }.padding(.horizontal, 22).padding(.vertical, 12).background(.black.opacity(0.12))
      if store.active.isEmpty && store.completed.isEmpty {
        VStack(spacing: 14) {
          Image(systemName: "hourglass").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(ACCENT)
          Text("留一点时间，给重要的事").font(.system(size: 16, weight: .medium))
          Text("从菜单栏图标向外拖动\n设置时长，松开后添加描述")
            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
          Button("创建第一个提醒") { editing = true }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(.vertical, 34)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(store.active) { reminder in reminderRow(reminder) }
            if !store.completed.isEmpty {
              HStack {
                Text("已完成").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清除") { store.clearCompleted() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
              }.padding(.top, 18).padding(.bottom, 4)
              ForEach(store.completed.prefix(10)) { reminder in reminderRow(reminder) }
            }
          }.padding(.horizontal, 22)
        }.frame(maxHeight: 420)
      }
      HStack {
        Circle().fill(ACCENT).frame(width: 5, height: 5)
        Text("拖离菜单栏图标，快速计时").font(.system(size: 10)).foregroundStyle(.secondary)
        Spacer()
      }.padding(14).background(.black.opacity(0.12))
    }
  }

  private func reminderRow(_ reminder: Reminder) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Text(reminder.completedAt == nil ? TimerMath.countdown(reminder.remaining(at: store.now), showSeconds: store.showSeconds) : "时间到了")
          .font(.system(size: 27, weight: .light)).foregroundStyle(reminder.completedAt == nil ? .white : .secondary)
        Spacer()
        Button { store.remove(reminder) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
          .buttonStyle(.plain).help("删除提醒").accessibilityLabel("删除\(reminder.title)")
      }
      Text(clockText(reminder.deadline)).font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
      Text(reminder.title).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
      if reminder.completedAt == nil {
        ProgressView(value: max(0, min(1, 1 - reminder.remaining(at: store.now) / max(1, reminder.deadline.timeIntervalSince(reminder.createdAt)))))
          .tint(ACCENT).padding(.top, 6)
      }
      Divider().padding(.top, 12)
    }.padding(.top, 20)
  }

  private var settingsContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      Toggle("菜单栏显示最近提醒的倒计时", isOn: $store.showCountdown).onChange(of: store.showCountdown) { _ in store.saveSettings() }
      VStack(alignment: .leading, spacing: 5) {
        Toggle("显示秒钟", isOn: $store.showSeconds).onChange(of: store.showSeconds) { _ in store.saveSettings() }
        Text("应用于菜单栏和提醒列表的倒计时").font(.caption).foregroundStyle(.secondary)
      }
      Toggle("通知声音", isOn: $store.playSound).onChange(of: store.playSound) { _ in store.saveSettings() }
      Divider()
      HStack {
        Label(store.notificationAllowed ? "系统通知已开启" : "系统通知未开启", systemImage: store.notificationAllowed ? "bell.badge" : "bell.slash")
          .font(.system(size: 13))
        Spacer()
        Button("设置") {
          Task { await store.requestPermission() }
          if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        }
      }
      Text("拖动时按住 Shift 可精细调整；按 Esc 取消。最长支持 24 小时。提醒自动保存在本机。").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
      Divider()
      HStack { Text("手势计时器").fontWeight(.medium); Spacer(); Text("1.0.0").foregroundStyle(.secondary) }.font(.caption)
      Button("退出手势计时器") { NSApp.terminate(nil) }.foregroundStyle(.secondary)
    }.padding(22).onAppear { Task { await store.refreshPermission() } }
  }
}
