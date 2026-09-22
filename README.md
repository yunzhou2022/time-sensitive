# 手势计时器

按原型实现的 macOS 原生菜单栏提醒工具，使用 SwiftUI + AppKit，无第三方依赖。支持 macOS 13 及以上。

## 构建与运行

```sh
git clone git@github.com:yunzhou2022/time-sensitive.git
cd time-sensitive
./scripts/build.sh
open dist/手势计时器.app
```

也可以将 `dist/手势计时器.app` 拖到「应用程序」。App 不显示 Dock 图标，启动后常驻菜单栏；右键图标可退出。构建脚本使用本机架构并进行临时签名，面向本机使用；对外分发需自行配置 Developer ID 签名和公证。

## 使用

- 从菜单栏图标向外拖动，显示紫色时间线、时长和预计到达时间；松开后填写描述并保存。
- 拖动前 360 点按每 6 点 1 分钟计算，之后每 6 点 5 分钟；按 Shift 精细调整，Esc 取消，最长 24 小时。
- 点击图标查看所有提醒；「+」添加更多提醒，支持快捷时长、输入分钟或指定时刻。指定时刻已过时，会安排到明天。
- 菜单栏紫色胶囊显示最近一个提醒的剩余时间，到期的提醒移入「已完成」。
- 首次保存时请求系统通知权限。通知获准后交由 macOS 安排；提醒显示仍受系统通知设置及专注模式影响。
- 未获准系统通知时，App 运行期间显示原生提醒窗口。退出 App 后，此兜底窗口不可用。
- 齿轮可设置倒计时显示、显示秒钟及通知声音；“显示秒钟”默认关闭，同时控制菜单栏和提醒列表，关闭时不足一分钟显示“不足1分钟”，设置会自动保存；更多菜单可清除已完成提醒或退出。

提醒保存在 `~/Library/Application Support/TimeSensitive/reminders.json`。使用绝对截止时间，重启后继续计时；睡眠期间到期的提醒会在恢复运行时归入已完成。普通通知的具体投递由 macOS 负责。

## 开发

```sh
swift build
swift test
```

本机 Xcode 未接受许可，同时 Command Line Tools 的最新预览 SDK 缺少 SwiftUI 宏插件，因此构建脚本使用已安装的 macOS 15.5 SDK（存在时）和 SwiftPM native 构建器。也可在完整、已初始化的 Xcode 环境直接打开 `Package.swift`。

代码结构：

- `TimerCore/Reminder.swift`：提醒模型、时长映射和时间计算。
- `TimeSensitive/ReminderStore.swift`：本地持久化、倒计时与通知调度。
- `TimeSensitive/StatusController.swift`：菜单栏绘制、原生拖动预览与弹出面板。
- `TimeSensitive/Views.swift`：提醒列表、编辑器与偏好设置。
- `scripts/build.sh`：构建 App 包、生成图标和本机签名。

本机环境可运行：

```sh
./scripts/test.sh
./dist/手势计时器.app/Contents/MacOS/TimeSensitive --self-test /tmp/time-sensitive-verification
```

`test.sh` 直接运行相同的 4 项 XCTest，解决本机预览版工具链自动测试入口与旧 SDK 的兼容问题。`--self-test` 使用独立临时数据，验证创建、恢复、删除、到期只触发一次及持久化，并检查原生菜单栏按钮的事件订阅和命中路径，以控制器输入回放验证拖动预览、松开编辑、Shift 精调、取消及普通点击，输出拖动预览、编辑器和列表的原生渲染 PNG、`results.txt`。它不会申请通知权限，也不会修改真实提醒。

测试覆盖拖动边界、剩余时间格式、数据序列化以及跨天指定时刻。系统通知横幅需在本机允许通知后实际验证，自动检查不代替系统投递验证。

菜单栏拖动由 `NSStatusBarButton` 的鼠标按下事件启动，绘制子视图不拦截鼠标；按住期间以 60 Hz 读取鼠标位置及按键状态，并在 tracking run loop 中持续工作。松开后停止跟踪、移除预览，再打开编辑面板。

拖动时长按鼠标到起点的直线距离计算，支持斜向及向上、向下拖动。菜单栏区域内的左右移动不触发计时；拖回菜单栏后松开取消本次创建。预览线跟随鼠标方向，提示框保持在鼠标所在屏幕内。

多显示器使用每屏独立的透明轨迹窗口，兼容“显示器具有单独的空间”。每个窗口按本屏逻辑坐标绘制和缩放；跨屏拖动时轨迹分段显示，时间提示只出现在鼠标所在屏幕。自检会逐屏验证窗口归属、当前空间、坐标转换、取消清理及跨屏提示，并生成每屏预览。
