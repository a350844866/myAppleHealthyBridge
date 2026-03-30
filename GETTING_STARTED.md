# Getting Started

这个仓库现在还没有 iOS 工程文件。

要继续开发这个 App，你先做下面几件事。

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

## 为什么这几步是必须的

- 没有完整 Xcode，当前机器不能创建和构建 iOS App
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

等 Xcode 可用后，我会按这个顺序推进：

1. 创建 SwiftUI iOS App 工程
2. 接入 HealthKit entitlement 和权限申请
3. 实现心率的 anchored query
4. 实现 anchor 本地持久化
5. 实现统一 JSON payload
6. 实现可配置的 `/ingest` 上传
7. 做一个最小设置页和手动同步按钮
