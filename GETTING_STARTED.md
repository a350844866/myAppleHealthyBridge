# Getting Started

这个仓库已经包含可打开的 iOS 工程文件。

要在真机上跑通当前版本，你先做下面几件事。

## 你现在需要做的事

1. 在 Mac App Store 安装 Xcode
2. 首次打开 Xcode，接受 license，等它把必要组件装完
3. 把命令行开发目录切到 Xcode

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

4. 验证命令行工具正常

```bash
xcodebuild -version
```

5. 准备一台自己的 iPhone，并打开这些能力
   - 登录 Apple ID
   - 开启开发者模式
   - 用数据线连到这台 Mac
6. 打开工程

```bash
open myAppleHealthyBridge.xcodeproj
```

7. 在 Xcode 中配置
   - target `myAppleHealthyBridge`
   - `Signing & Capabilities` 里设置 Team
   - 确认 `HealthKit` capability 已开启
8. 在 App 设置页填写服务端
   - `Base URL`: 服务端根地址，例如 `http://192.168.31.66:18000`
   - `API Token`: 默认可留空；只有服务端设置了 `INGEST_API_TOKEN` 才需要填写
   - `Enable Auto Sync`: 调试阶段先关闭，先用手动同步验证 payload 和服务端写入

## 为什么这几步是必须的

- 没有完整 Xcode，当前机器不能构建和签名 iOS App
- HealthKit 真机验证比模拟器更可靠
- App 需要签名后才能装到手机上测试权限和同步流程

## 现阶段不需要你先做的事

- 不需要先注册付费开发者账号
- 不需要先买服务器
- 不需要先做 App Store 发布准备
- 不需要先设计复杂 UI

## 你完成后告诉我什么

完成后把下面两项结果发我：

1. `xcodebuild -version` 的输出
2. 你是否已经有可连接测试的 iPhone

## 我接下来会负责做什么

当前仓库已经包含这些能力：

1. SwiftUI iOS App 工程
2. HealthKit entitlement 和权限申请
3. anchored query
4. anchor 本地持久化
5. 统一 JSON payload
6. 可配置的 `/ingest` 上传
7. 最小设置页和手动同步按钮
