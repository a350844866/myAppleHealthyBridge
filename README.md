# myAppleHealthyBridge

最小可运行的 iPhone HealthKit bridge App 骨架。

当前版本已经包含：

- SwiftUI iOS App 工程
- HealthKit 权限申请
- 心率、血氧、呼吸频率、步数、睡眠的 anchored query 读取
- `HKQueryAnchor` 本地持久化
- 统一 JSON payload 编码
- `/ingest` 上传客户端
- 一个最小设置页和手动同步按钮

## 打开方式

```bash
open myAppleHealthyBridge.xcodeproj
```

## 首次运行前要做

1. 在 Xcode 里选中 target `myAppleHealthyBridge`
2. 把 `Signing & Capabilities` 里的 Team 设置成你的 Apple ID
3. 确认 `HealthKit` capability 已开启
4. 连接真机运行

## 当前限制

- 还没有 `HKObserverQuery`
- 还没有后台任务补偿同步
- 还没有 workout 支持
- `/ingest` 仍然依赖你的服务端后续实现
