# Lumitext 项目全貌

> 一份用来快速了解整个项目的概览。架构细节与决策来源见 `PLAN.md`、`docs/adr/`、`CLAUDE.md`。

---

## 1. 这是什么

**Lumitext** 是一个 **macOS Tahoe(26.x)专用的自定义文字屏保**。用户在宿主 app 里编辑一段文字(字体、字号、颜色、对齐、行距、背景),保存后这段文字就会作为屏保全屏显示。

核心卖点:**所见即所得**——宿主 app 里的实时预览和真正的屏保用的是**同一套渲染代码**,字节级一致。

**平台限制**:只支持 Tahoe。它走的是现代 ExtensionKit 屏保扩展点(`com.apple.screensaver`),不是传统 `.saver` bundle——后者在新系统上已是历史包袱。

---

## 2. 整体架构

三个产物 + 两个依赖包:

```
Lumitext.app                         ← 宿主 app(非沙箱),用户配置界面
└── Contents/PlugIns/
    └── LumitextSaver.appex          ← 屏保扩展(沙箱),系统在空闲时运行
                                        每个屏幕一个独立 XPC 进程

         共享:LumitextCore(本地 SPM 包)── 配置模型 / 渲染器 / 日志 / 目录
         宿主依赖:PaperSaverKit(远程包)── 屏保激活 API + CLI
```

| 产物 | bundle id | 类型 | 沙箱 | 职责 |
|---|---|---|---|---|
| `Lumitext.app` | `io.github.fanhefeng.lumitext` | application | 否 | 配置 GUI、实时预览、注册/激活屏保、写配置、文件日志 |
| `LumitextSaver.appex` | `io.github.fanhefeng.lumitext.saver` | app-extension | **是** | 读配置、全屏渲染文字。每个屏幕独立进程 |
| `LumitextAppTests` | `…lumitext.apptests` | unit-test | — | 宿主层逻辑的单元测试(以 app 为 test host) |

**关键设计:host 和 saver 都依赖 `LumitextCore`,且一起以同一构建配置编译**,所以两者对"用什么配置、渲染成什么样、用哪套目录"永远一致,无需运行时握手。

---

## 3. 数据流:配置如何从 host 流到 saver

这是整个项目的中枢。host 是**唯一写者**,saver 是**只读者**,通过一个共享文件跨进程通信:

```
┌─────────────┐   写(原子+目录信任校验)   ┌──────────────────────────┐   读(精确路径)   ┌──────────────┐
│ Lumitext.app│ ──────────────────────► │ /Users/Shared/Lumitext/  │ ◄────────────── │ LumitextSaver│
│  AppModel   │   debounced autosave    │      config.json         │   scoped 沙箱例外 │   .appex     │
└─────────────┘                         └──────────────────────────┘                  └──────────────┘
   生产:/Users/Shared/Lumitext/config.json
   开发:/Users/Shared/Lumitext/dev/config.json   (#if DEBUG,dev/prod 互不干扰)
```

**为什么是 `/Users/Shared` 而不是 App Group 容器**:Tahoe 的 TCC 拒绝 App Group 容器访问,除非 group id 带 Team-ID 前缀——ad-hoc 签名做不到。`/Users/Shared`(world-writable 1777)+ saver 的 scoped read-only temporary-exception entitlement,是 Aerial v4 已验证的出货模式。详见 `docs/adr/0001`。

**沙箱端的纪律**:saver 只做**精确路径**文件读,**绝不做目录枚举**(Tahoe 下枚举共享容器会卡死 `containermanagerd`)。

---

## 4. 模块与文件地图

### LumitextCore(共享包)— `Packages/LumitextCore/Sources/LumitextCore/`

纯 Foundation / SwiftUI,无平台特定外壳,所以可单测、可在 host 与 saver 间共享。

| 文件 | 职责 |
|---|---|
| `Identifiers.swift` | 共享常量:os.log subsystem(`io.github.fanhefeng.lumitext`) |
| `LumitextConfig.swift` | **配置模型**。`LumitextConfig`(Codable)、`RGBAColor`、对齐/字重枚举。**所有数值在模型边界 clamp**(init/decode/didSet 三路径),`schemaVersion` 门控、文本三预算(grapheme/scalar/line) |
| `ConfigStore.swift` | **跨进程配置读写**。原子写、串行队列、**目录信任校验**(防 `/Users/Shared` 抢占 squat)、文件大小上限(防 DoS)、`LoadResult`(loaded/missing/failed 三态) |
| `AppDirectories.swift` | **环境感知路径**。`AppEnvironment`(`#if DEBUG` → dev)决定所有路径走 `Lumitext` 还是 `Lumitext-Dev`;共享配置 dev 走 `/Users/Shared/Lumitext/dev` 子目录 |
| `LumitextTextView.swift` | **共享渲染器 `LumitextTextView`**(host 预览与 saver 共用,WYSIWYG 的根)。对齐枚举 → SwiftUI 桥接;按 1080pt 参考屏高缩放实现分辨率无关 |
| `FontResolution.swift` | 字重桥接;字体按描述符解析 + 缓存;`FontPathPolicy`(判断字体在 saver 沙箱里是否可解析) |
| `ColorBridging.swift` | `RGBAColor` ↔ SwiftUI `Color` / AppKit `NSColor` 桥接(pattern/catalog 等异常颜色安全回退,绝不崩溃) |
| `ColorContrast.swift` | WCAG 相对亮度对比度(保存前警告"看不见的文字") |
| `AppLog.swift` | host 日志门面:每条同时进 os.log 和轮转文件 |
| `FileLog.swift` | 轮转文件日志(单活动文件 + 一个 `.1` 备份,容量封顶,失败永不崩溃/阻塞) |
| `SaveOutcomeGate.swift` | 异步保存结果的**单调乱序门**(旧结果不能覆盖新结果的 UI 状态) |

### 宿主 app — `App/`

| 文件 | 职责 |
|---|---|
| `LumitextApp.swift` | `@main` 入口,持有 AppModel/ActivationManager,菜单(About、Open Folder) |
| `AppModel.swift` | **view-model**。持有可编辑 config,**debounced autosave** 到 ConfigStore,持久化失败警告横幅 |
| `Activation/ActivationManager.swift` | **激活流程**:pluginkit 注册 → 轮询发现 → PaperSaver 设为活动屏保;搬移到 `/Applications`(stage-then-swap 带回滚);kind-scoped 错误槽 |
| `FolderActions.swift` | "Open Folder" 菜单:在 Finder 里打开 logs/config/caches/app-support |
| `SnapshotDumper.swift` | (DEBUG)把渲染器 dump 成 PNG,免引擎验证 saver 输出 |
| `Views/` | SwiftUI 界面:`MainView`(布局)、`ConfigPanel`(文字/字体/颜色/对齐编辑)、`ActivationBar`(激活+空闲时间)、`PreviewPane`(实时预览,NSHostingView 托管共享渲染器)、`MultilineTextField`(NSTextView 多行编辑,CJK 输入法组合安全)、`FontCatalog`(标记 saver 沙箱读不到的字体)、`ColorBinding`、`Theme`、`ThemePresets` |

### 沙箱屏保 — `Saver/`

| 文件 | 职责 |
|---|---|
| `LumitextExtension.swift` | principal class(`ScreenSaverExtension`),极简,框架驱动生命周期 |
| `LumitextViewController.swift` | `ScreenSaverViewController`,`loadView()` 装配 saver view(带降级 fallback) |
| `LumitextSaverView.swift` | `ScreenSaverView`,用 `NSHostingView` 托管共享 `LumitextTextView`;后台线程读 config → 主线程 apply;读失败显示双语诊断提示而非用户文字 |
| `Bridging-Header.h` | ScreenSaver ObjC 互操作桥接头 |

---

## 5. 渲染:为什么预览能保证 WYSIWYG

host 的 `PreviewPane` 和 saver 的 `LumitextSaverView` 都用 `NSHostingView` 托管**同一个** `LumitextCore.LumitextTextView`,喂**同一个** `LumitextConfig`。所以预览不是"模拟",它就是屏保本身。

**分辨率无关**:字号/行距以 1080pt 参考屏高表达,渲染时按 `实际高度 / 1080` 缩放。于是一份配置在笔记本、6K 屏、系统设置里的小缩略图上都成比例一致——缩放只看高度,宽度参与的是换行而非字号。

---

## 6. 激活流程(host 如何让系统用上这个屏保)

1. **必须从 `/Applications` 运行**:pluginkit 缓存发现位置且偏好 `/Applications`,从别处运行会加载错误副本。app 提供"搬移到 /Applications"(stage-then-swap,失败回滚,搬完用 watchdog 重启)。
2. `pluginkit -a <appex 路径>` 注册扩展。**注意**:该命令永远退出 0,即使被静默过滤(缺 sandbox entitlement 时);真正的确认靠之后的发现轮询。
3. 轮询系统发现(`PaperSaver().listAvailableScreensavers()`)直到 saver 可见。
4. `PaperSaver().setScreensaverEverywhere(...)` 设为所有屏幕的活动屏保。
5. 空闲时间通过 `PaperSaver().setIdleTime(...)` 设置。

---

## 7. 环境隔离(dev / prod)

由 `#if DEBUG` 在**编译期**决定,host 与其内嵌 saver 同配置编译,所以自动一致:

| 用途 | 生产 | 开发(DEBUG) |
|---|---|---|
| 共享配置 | `/Users/Shared/Lumitext/config.json` | `/Users/Shared/Lumitext/dev/config.json` |
| 日志 | `~/Library/Logs/Lumitext/` | `~/Library/Logs/Lumitext-Dev/` |
| 缓存 | `~/Library/Caches/Lumitext/` | `…/Lumitext-Dev/` |
| App 数据 | `~/Library/Application Support/Lumitext/` | `…/Lumitext-Dev/` |

dev 配置用 `/Users/Shared/Lumitext` 的**子目录**(不是兄弟目录),这样 saver 的单条读例外前缀 `/Users/Shared/Lumitext/` 仍覆盖它。这些目录都能从 app 的 **Lumitext ▸ Open Folder** 菜单打开。

---

## 8. 安全模型

- **沙箱 saver**:只读 scoped 例外路径,精确路径读、不枚举、不写文件(诊断只进 os.log)。
- **目录信任校验**(`ConfigStore`):`/Users/Shared` 是 world-writable(1777),别的本地账户可能抢先创建 `/Users/Shared/Lumitext` 并占有它(经典 squat)。写之前从配置根到叶逐级校验:真目录(非符号链接)、当前用户拥有、group/other 不可写、无授予写权限的 ACL。
- **恶意 config 防御**:文件大小上限(防 saver 被迫读入巨型文件)、`schemaVersion` 门(拒绝未来/损坏版本)、所有值在模型边界 clamp(文本三预算、数值范围、颜色 gamut、背景强制不透明)。
- **签名**:dev 用 ad-hoc(`-`),内嵌 appex 后置签名带 debug entitlements(含 `disable-library-validation`,ad-hoc 无 Team ID 必需);release 用 Developer ID + hardened entitlements(不含该豁免)+ 公证。

---

## 9. 构建 / 安装 / 发布

**工程是生成的**——`.xcodeproj` 由 XcodeGen 从 `project.yml` 生成,**绝不手改或提交**。改了 `project.yml` 后:

```bash
xcodegen generate
```

**开发循环**(别用裸 `xcodebuild + cp`):

```bash
scripts/dev-build-install.sh     # 构建 + 后置签名(debug entitlements)+ 装到 /Applications + 注册
```

**测试**:

```bash
# Core 包
cd Packages/LumitextCore && swift test
# 宿主层(注意 scheme 是 LumitextAppTests)
xcodebuild -project Lumitext.xcodeproj -scheme LumitextAppTests test SYMROOT=$PWD/build
```

**发布脚本**(`scripts/`):`sign.sh`(inside-out 签名)、`notarize.sh`(公证,用 `status: Accepted` 判断而非退出码)、`make-dmg.sh`、`make-share-zip.sh`;`make-thumbnail.swift` / `make-appicon.swift` 生成资源。

**日志查看**(用 `/usr/bin/log`,zsh 的 `log` 内建会破坏 predicate):

```bash
/usr/bin/log show --last 3m --predicate 'subsystem == "io.github.fanhefeng.lumitext"' --info --debug
```

---

## 10. 测试

- **Core 包**(`Packages/LumitextCore/Tests/`):配置 clamp、目录信任、ConfigStore 三态、SaveOutcomeGate 乱序、渲染冒烟 + 对齐像素断言。约 112 个用例。注释多为 mutation-testing 导向("哪个 mutant 会挂")。
- **宿主层**(`AppTests/`):AppModel 决策表、stage-then-swap 算法、`/Applications` gate、leftover 清理逻辑。约 27 个用例。
- 渲染像素测试依赖 GUI 会话,headless 下优雅 `XCTSkip`。

---

## 11. 关键陷阱与红线(踩过坑的经验)

> 这些在 `CLAUDE.md` 有完整记录,违反会导致需重启/重登才能恢复的系统级卡死。

- **绝不 `pkill`/`kill` ScreenSaverEngine 或运行中的 saver**:会卡死 loginwindow 的 `SACScreenSaverIsRunning` 标志和 App Group 容器租约,需登出/重启。日常验证用 host 的**内嵌实时预览**,不要去捅引擎。
- **appex 缺 `com.apple.security.app-sandbox` 会被 pkd 静默过滤**:`pluginkit -a` 退出 0 但啥也没注册。签名脚本必须验证这个 key。
- **`pluginkit -a` 永远退出 0**:真相只能靠 `pluginkit -m` 查询 + pkd 日志。
- **必须从 `/Applications` 运行**:否则 pluginkit 加载错误副本。
- **系统设置 "Options…" 按钮在 Tahoe 失效**(`SSEHasConfigureSheet` 恒 false):所有配置都在 host app 里。
- **缩略图 imageset 必需**,否则屏保不出现在系统设置里。
- `ScreenSaverDefaults` 是 ByHost 容器陷阱,绝不使用。
- **`isPreview` 在 Tahoe 不可靠**(FB19201567):渲染器对 preview 无感(按容器高度缩放),saver 传常量即可。

---

## 12. 当前状态

里程碑 **M1–M6 全部完成**(见 `PLAN.md`):私有 API 尖兵、共享核心包、屏保渲染真机端到端验证、宿主 GUI + 实时预览 + 一键激活、发布工具链、加固 + 两轮多 agent 对抗评审 + zh-Hans 本地化。

**待所有者前置项**:Developer ID(用于公证 + Sparkle 自动更新 + DMG 公开分发,M5/M6 的公开发布部分延后到注册之时)。当前以本地签名完成完整自用版。

---

## 13. 快速上手路径

想读懂这个项目,建议顺序:

1. `PLAN.md` — 架构决策与里程碑(为什么这样设计)
2. `docs/adr/0001` — 为什么用 `/Users/Shared` 而非 App Group(最关键的决策)
3. `LumitextCore/LumitextConfig.swift` — 数据模型(一切的中心)
4. `LumitextCore/LumitextTextView.swift` — 共享渲染器(WYSIWYG 的根)
5. `LumitextCore/ConfigStore.swift` — 跨进程通道(安全模型的集中体现)
6. `Saver/LumitextSaverView.swift` — 沙箱端如何消费配置
7. `App/AppModel.swift` + `App/Activation/ActivationManager.swift` — 宿主端的写入与激活
8. `CLAUDE.md` — 操作纪律与踩坑清单(动手前必读)
