# DisplayDial 简体中文版

基于 [Grab-Connected-Tech/DisplayDial](https://github.com/Grab-Connected-Tech/DisplayDial) 的个人使用汉化版本。感谢原作者 Grab Connected Tech，项目采用 MIT 许可。

- **中文范围**：菜单栏面板、显示器硬件调节、输入源选择、显示模式、色彩预设、个人方案、键盘媒体键设置、授权说明、屏幕提示、更新检查。
- **保留原协议**：DDC/CI、MCCS VCP 控制码、显示器能力查询、存储键、HDR API 均未更改。
- **独立身份**：`DisplayDial-CN.app` / `com.xppxpp.displaydialcn`，与上游英文版 `DisplayDial.app` / `local.displaydial` 独立，不会覆盖原版或复用其 macOS 辅助功能授权。
- **支持设备**：Apple Silicon Mac、macOS 14 及以上；显示器需要具备并开启 DDC/CI。能控制哪些项目由显示器自身上报的能力决定。

## 从 GitHub Actions 下载

1. 打开本仓库的 [Actions](https://github.com/xppxpp-cn/DisplayDial-cn/actions)，选择 **「构建 DisplayDial 中文版」**。
2. 打开最近一次成功的构建，在 **Artifacts** 下下载 `DisplayDial-CN-macOS-AppleSilicon`。
3. 解压 GitHub 下载的压缩包，取得 `DisplayDial-CN.dmg` 或 `DisplayDial-CN.zip`。只需二选一；DMG 打开后将 `DisplayDial-CN.app` 拖入「应用程序」即可。
4. 如果仍在运行原版，请先退出原版，以免它与中文版同时响应亮度和音量键。
5. 启动中文版；如果启用键盘亮度/音量控制，需要在「系统设置 → 隐私与安全性 → 允许辅助应用程序控制电脑」（macOS 27 的名称）中授予 **DisplayDial 中文版** 权限。

> GitHub Actions 使用本地 ad-hoc 签名、**未经 Apple 公证**。只有确认下载文件来自自己的仓库时，才考虑在 macOS 安全拦截后按系统提示允许启动。若应用被隔离标记阻止，并且你已确认构建来源，可在终端执行：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/DisplayDial-CN.app
> ```
>
> 之后重新打开应用即可。重新编译后如果 macOS 因代码签名变化撤销了辅助功能权限，需要针对本中文版重新授权。

## 使用提醒

- **硬件亮度**：真正调节显示器背光，不是软件遮罩；部分显示器在 HDR 模式下会锁定亮度、对比度和色彩预设。
- **输入源切换**：切到 Windows、HDMI 或另一个输入源后，Mac 可能失去 DDC 通道，**无法再从 Mac 软件里切回**；请预先确认能通过显示器实体按键恢复 USB-C/DP 输入。
- **色彩配置**：为了视频剪辑时色彩稳定，建议使用一致的 sRGB 或合适的显示预设。应用的配置方案是硬件设置快照，**不是 macOS ICC 色彩配置文件**。
- **键盘控制**：如启用原生亮度键、音量键映射，不建议同时运行其他会拦截媒体键的显示器管理应用。
- **显示器测试**：自动构建只验证代码可编译、应用签名及 DMG/ZIP 包有效，**无法代替本机 DDC/CI 硬件测试**。

## 构建与发布

在 Apple Silicon Mac 上安装 Xcode Command Line Tools 后执行：

```bash
./build.sh          # 构建 build/DisplayDial-CN.app
./build.sh dmg      # 生成 build/DisplayDial-CN.dmg 与 .zip
./build.sh install  # 安装至 /Applications/DisplayDial-CN.app
```

自动构建：每次 PR、推送到 `main` 或手动运行 Actions 自动编译并上传产物。

正式发布：推送 `cn-v*` 标签会在**当前 fork** 创建 GitHub Release，不会修改上游仓库。编译需要 macOS 环境；Windows 可以编辑源码，但不能直接生成原生 macOS 应用。

上游原作者及 MIT 许可声明均保留；此 fork 非上游官方发布。
