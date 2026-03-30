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

## 服务端配置

设置页里的两个网络字段这样填：

- `Base URL`
  - 填服务端根地址，不要带 `/ingest`
  - 示例：`http://192.168.31.66:18000`
- `API Token`
  - 默认可以留空
  - 只有服务端设置了 `INGEST_API_TOKEN` 时才需要填写
  - 这里填 token 原文，不要手动加 `Bearer `

当前客户端会自动请求：

```text
POST <Base URL>/ingest
```

例如：

```text
POST http://192.168.31.66:18000/ingest
```

## 联调检查

- iPhone 必须能访问服务端所在局域网地址
- `Base URL` 末尾不要重复写 `/ingest`
- 如果你开启了 token 鉴权，客户端 `API Token` 必须与服务端 `INGEST_API_TOKEN` 完全一致
- 可先在浏览器打开 `http://192.168.31.66:18000/docs` 确认服务端在线

## 当前限制

- 还没有 `HKObserverQuery`
- 还没有后台任务补偿同步
- 还没有 workout 支持
- `/ingest` 仍然依赖你的服务端后续实现
