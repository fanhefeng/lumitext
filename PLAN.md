# Lumitext — macOS Tahoe 自定义文字屏保 · 技术选型与执行计划

> 状态：计划定稿，所有者决策已收口（2026-06-04）。基于 14-agent 设计工作流（6 路技术核实 + 3 架构提案 + 3 评审对抗打分 + 综合）。
> 目标：发布给公众使用的、可自定义文字内容/字体/颜色/大小的 macOS 屏保。仅支持 macOS Tahoe (26.x)。
>
> **所有者已确认**：产品名 **Lumitext**；GitHub 公开开源 `fanhefeng/lumitext`；bundle ID
> `io.github.fanhefeng.lumitext`（宿主）/ `io.github.fanhefeng.lumitext.saver`（appex）；
> App Group `group.io.github.fanhefeng.lumitext`。**Apple Developer Program 暂不注册** ⇒
> M1–M4 用本地签名完成完整自用版；M5/M6 的公证、DMG 公开分发、Homebrew cask 延后到注册之时
> （架构与脚本照常备好，到时只换签名身份）。

## 进度（2026-06-04，单次自治执行）

| 里程碑 | 状态 |
|---|---|
| M1 私有 API + App Group 尖兵 | ✅ 真机验证（ADR-0001） |
| M2 LumitextCore 共享包 + 渲染器 | ✅ 17 单测通过 + ImageRenderer 快照验证 |
| M3 屏保读 App Group 配置渲染 | ✅ **真机端到端验证通过**：沙箱 saver 从共享 App Group 容器读到 host 写入的精确配置（日志 `applied config … size=234`）。仅多显示器待验（docs/POST-REBOOT-CHECKLIST.md） |
| M4 宿主配置 GUI + 实时预览 + 激活 | ✅ 窗口截图验证（docs/images/） |
| M5 发布工具链 | ✅ sign/make-dmg 实测可用；公证/Sparkle 待 Developer ID（RELEASE.md） |
| M6 加固/评审/本地化 | ✅ 两轮多 agent 对抗评审 + zh-Hans 本地化 |

仓库：https://github.com/fanhefeng/lumitext （公开）。两处遗留均为重启即清除的开发态副作用，非产品缺陷。

## 一、最终架构（评审一致胜出）

**一个 Developer-ID 签名 + 公证的宿主 App（Lumitext.app），内嵌一个现代 ExtensionKit 屏保扩展（LumitextSaver.appex）。不用 legacy `.saver`。**

```
Lumitext.app（宿主，非沙箱，SwiftUI 配置界面 + 实时预览 + 一键激活 + Sparkle 更新）
└── Contents/PlugIns/LumitextSaver.appex（沙箱内屏保扩展，纯配置读取者）
        二者通过 App Group 容器共享一份 Codable JSON 配置
        渲染视图来自共享 SPM 包 LumitextCore → 保证预览与屏保所见即所得
```

### 关键事实（已在本机 26.5 实测验证）
1. Apple 全部第一方屏保都是 `/System/Library/ExtensionKit/Extensions/*.appex`，
   `NSExtensionPointIdentifier=com.apple.screensaver`，`CFBundlePackageType=XPC!`。
2. 私有类 `ScreenSaverExtension` / `ScreenSaverViewController` 的符号在 26.5 SDK 的
   `ScreenSaver.tbd` 中导出，可经 bridging header 解析（Aerial v4 同款做法，可正常公证）。
3. Apple 自家 saver 的 entitlements = `app-sandbox=true` + 自授 `temporary-exception
   files.absolute-path.read-only=/`。第三方拿不到该豁免 ⇒ **沙箱 appex 不能免费读
   /Users/Shared**。⇒ 配置通道必须用 **App Group 容器**（自家签名 appex 默认可读，Apple 正道）。
4. legacy `.saver` 在 Tahoe 的 bug（FB19201567 isPreview、FB19206021 多显示器、FB19204084
   实例堆积、Options 按钮失灵）至今未修，appex 路线在结构上全部规避。
5. 锁屏真相（DTS thread 654383）：macOS 进入安全锁定后由 loginwindow 接管屏幕，任何第三方
   屏保都无法在其上渲染。产品诚实定位：**空闲→安全锁定之前的时段**显示自定义文字（与
   Aerial/Fliqlo 同一窗口期），并帮用户对齐 idleTime 与 askForPasswordDelay 以最大化展示时间。

## 二、关键决策表

| 主题 | 决策 | 理由 |
|---|---|---|
| 打包格式 | ExtensionKit .appex 内嵌于宿主 .app | 规避全部 legacy Tahoe bug；Apple 与 Aerial v4 同路线 |
| 配置共享 | App Group 容器（唯一生产通道）；/Users/Shared JSON 仅作调试镜像 | 沙箱 appex 默认可读自家 App Group；拒绝 ScreenSaverDefaults（ByHost 容器陷阱） |
| 配置界面 | 100% 在宿主 App（SwiftUI）；`SSEHasConfigureSheet=false` | 系统设置 Options 按钮是未修复 OS bug，绕开 |
| 渲染 | SwiftUI + NSHostingView（appex 每屏一个干净进程实例，安全）；`SSENeedsAnimationTimer=false` | 与 Apple Hello/Drift 同配置；共享视图保证 WYSIWYG |
| isPreview | 帧宽启发式（<400pt），不信任 OS 值 | FB19201567 |
| 字体 | v1 系统字体（NSFont(name:)）；v2 用户字体拷贝至 App Group + CTFontManager 进程级注册 | 沙箱内可靠；避免字体许可证再分发问题 |
| 激活 | PaperSaverKit.setScreensaverEverywhere() + 首启 `pluginkit -a`；深链回退 Wallpaper 设置页 | 不手写 com.apple.wallpaper 的 Index.plist 黑盒 |
| 更新 | Sparkle 2（appcast 放 GitHub Releases）；更新后重跑 pluginkit 注册 | 一次更新同时覆盖 App 与 appex |
| 分发 | 签名+公证+双重 staple 的 DMG（主）+ Homebrew cask（辅）。**不上 Mac App Store** | 私有 API + 安装扩展均不容于 MAS；DMG 拖装避开 quarantine 弹窗 |
| 开发安装 | 仅装 /Applications；App 检测非该路径时拒绝注册并提示自移 | pluginkit 缓存位置，混装会加载错误构建 |

## 三、里程碑（每个里程碑完成后做 code review + 真机验证）

- **M0 — 所有者前置项（已收口，剩余两项）**
  - ✅ 产品名 Lumitext / 仓库 fanhefeng/lumitext (public) / bundle ID 前缀 io.github.fanhefeng
  - ⏳ **接受 Xcode 许可（唯一硬阻塞）**：`sudo xcodebuild -license accept`（实测 `-checkFirstLaunchStatus` exit=69）+ `sudo xcodebuild -runFirstLaunch`；可顺带 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`（不切则全程用 DEVELOPER_DIR 环境变量，已验证可行）
  - ⏳（推荐，可选）Xcode → Settings → Accounts 登录任意免费 Apple ID 启用 Personal Team——若 M1 实测 ad-hoc 签名下 App Group 容器不通，这是唯一备援，提前做掉可保证执行期零打扰
  - ⏸ 延后（发布时）：Apple Developer Program（$99/年）→ Team ID → Developer ID Application 证书 → notarytool 凭据
  - 验证：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -checkFirstLaunchStatus` exit=0
- **M1 — 私有 API 技术尖兵（1 天，阻塞）**
  - 最小 appex 通过 bridging header 子类化私有类，在系统设置出现并全屏渲染纯色
  - App Group 读取实测成功；/Users/Shared 读取失败实测留档（坐实通道决策）
  - 验证：`log stream --predicate 'process == "LumitextSaver"'` 捕获沙箱拒绝日志
- **M2 — 工程脚手架 + 共享核心**
  - 双 target 工程（参考 AerialScreensaver/AppexSaverMinimal, MIT）
  - LumitextCore SPM 包：Codable 配置模型 + ConfigStore（原子写、串行队列、schemaVersion）+ SwiftUI 文字视图
  - 缩略图 thumbnail.imageset（107×65 / 214×130，缺失则不显示在系统设置——必备）
  - 验证：ConfigStore round-trip 单测通过；appex Info.plist 与 Apple 模板逐键比对
- **M3 — 屏保渲染用户文字**
  - startAnimation 时读 App Group 配置 → NSHostingView 渲染
  - 多显示器各屏独立视图、只读配置、无可变静态量
  - 验证：双显示器真机触发；重复激活无实例堆积、CPU/内存稳定
- **M4 — 宿主配置 GUI + 实时预览 + 一键激活**
  - 多行文本、字体族+字重选择器、颜色选择器、字号滑杆、对齐/位置
  - 实时预览（同一渲染视图）；"设为屏保（所有显示器）"按钮；/Applications 强制 + 自移提示
  - idleTime/askForPasswordDelay 展示与一键对齐（规避 Tahoe 锁屏闪图 bug）
  - 验证：GUI 改动 → 预览与真实屏保输出一致（WYSIWYG 抽查）
- **M5 — 签名、公证、DMG、Sparkle、Homebrew**
  - 由内向外签名（Sparkle → appex → app，hardened runtime + timestamp）
  - 公证 app → staple → 打 DMG → 公证 DMG → staple（双重）
  - 验证：`spctl -a -vvv -t install` = Notarized Developer ID；干净账户拖装零弹窗；Sparkle 测试更新后屏保仍工作
- **M6 — v1 发布加固**
  - 诚实的 README/产品文案（锁屏真相、安装步骤、多显示器说明）；zh-Hans 本地化
  - GitHub Release（DMG + cask + appcast）
  - 验证：干净账户端到端全流程；`/code-review` 全量过一遍；公证早提交防私有符号拒绝

## 四、风险登记册（摘要）

| 风险 | 缓解 |
|---|---|
| 私有 API 未来 macOS 变动 | 仅支持 Tahoe；LumitextCore 与外壳解耦，换壳成本低；每个 beta 重跑 M1 尖兵 |
| App Group 读取在 appex 内失败（载荷未知数） | M1 第一天实测定生死，再继续投入 |
| 用户无开发者账号期间 | Personal Team 本地签名完成 M1–M4 |
| pluginkit 注册缓存（最长 ~12h 延迟/错位） | 只装 /Applications；内置 Re-register 按钮 |
| 缩略图缺失 → 设置里不可见 | M2 第一天加入；M3 验证显示 |
| 锁屏预期落差 | 产品文案诚实 + 时间对齐助手（信任风险，非技术风险） |
| 私有符号影响公证 | Aerial v4/Apple 同路线已验证可过；M5 提早做公证演练 |

## 五、仓库结构（目标形态）

```
Lumitext/
├── Lumitext.xcodeproj/
├── App/            # 宿主：ConfigGUI / LivePreview / Activation / Onboarding / Updates / Resources
├── Saver/          # appex：私有类子类 ×2 + ScreenSaverView + PrivateHeaders/ScreenSaverPrivate.h
│   └── Assets.xcassets/thumbnail.imageset/   # 必备
├── Packages/LumitextCore/   # 配置模型 + ConfigStore + 共享 SwiftUI 渲染视图 + 单测
├── scripts/        # sign.sh / notarize.sh / make-dmg.sh
├── distribution/   # Homebrew cask + Sparkle appcast
├── docs/adr/       # 每个关键决策一份 ADR
├── CLAUDE.md
└── README.md
```

## 六、需要所有者提供（M0 清单，2026-06-04 收口）

| 事项 | 状态 |
|---|---|
| 产品名 Lumitext / 公开仓库 fanhefeng/lumitext / bundle ID io.github.fanhefeng.* | ✅ 已确认 |
| Xcode 许可接受 + runFirstLaunch（sudo，唯一硬阻塞） | ⏳ 待用户执行 |
| Xcode 登录免费 Apple ID（Personal Team，App Group 备援） | ⏳ 推荐可选 |
| Apple Developer Program / Developer ID 证书 / notarytool 凭据 | ⏸ 发布时再补（用户已决定暂不注册） |

执行模式（用户要求）：开工后免打扰，一切分叉按最佳实践自决并记录 ADR；每个里程碑结束做严格
code review（/code-review）+ 26.5 真机验证后再进下一个；可使用任何工具（MCP/skills/CLI）。
