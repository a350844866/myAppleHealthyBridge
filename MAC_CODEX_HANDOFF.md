# MAC Codex Handoff

这个文件给明天在 Mac 上接手 `myAppleHealthyBridge` 的 Codex。

## 当前代码已经完成的事

- 默认仍然是手动同步
- 设置页已新增 `Enable Auto Sync`
- 只有打开自动同步后，才会注册 `HKObserverQuery`
- 关闭自动同步时，会真正停掉 observer 和 background delivery
- HealthKit 采集范围已从最初的 5 类扩到一批高价值 sample 类型
- category 类型会额外带：
  - `category_value_raw`
  - `category_value_label`
- 设备信息与 HealthKit metadata 会一起放进 `metadata`
- iOS deployment target 已统一到 `17.0`

## 当前重点文件

- `myAppleHealthyBridge/HealthKitManager.swift`
- `myAppleHealthyBridge/SyncCoordinator.swift`
- `myAppleHealthyBridge/SyncStore.swift`
- `myAppleHealthyBridge/ContentView.swift`
- `myAppleHealthyBridge/Models.swift`

## 明天在 Mac 上优先做什么

1. 打开 Xcode 工程并确认可以编译
2. 配好签名和 `HealthKit` capability
3. 真机运行
4. 在设置页填服务端：
   - `Base URL`
   - `API Token`（如果服务端开启了 token）
5. 保持 `Enable Auto Sync` 关闭
6. 先请求 HealthKit 权限
7. 点击手动同步
8. 检查：
   - payload preview 是否合理
   - 服务端 `/ingest` 是否成功
   - 数据库里是否能看到新增记录
9. 手动同步验证通过后，再打开 `Enable Auto Sync`
10. 验证 observer 触发后是否会自动跑一次增量同步

## 明天要重点盯的风险

- 有些 HealthKit identifier 在当前 iPhone / iOS 版本可能不可用
- 有些类型即使可用，如果设备没有产生过数据，也会是 0 条
- Linux 上没法实际编译，所以要以 Xcode 真机结果为准
- 当前还不支持：
  - workout 明细
  - correlation 对象
  - clinical records
  - 后台任务补偿同步

## 如果编译报错，优先排查

1. 某些 `HKUnit` API 名称是否与当前 Xcode SDK 有差异
2. 某些 identifier 是否需要更高 iOS 版本
3. `HealthKitManager.swift` 里新增的类型是否有个别需要按 `#available` 单独处理

## 如果手动同步通过，下一步建议

1. 做 observer 触发后的节流 / 去抖
2. 增加后台补偿同步
3. 为 workout 设计单独 payload，而不是继续塞进当前 sample 模型
4. 继续补 `PhysicalEffort`、`BodyMassIndex` 等尚未接入的类型

## 给 Mac 上 Codex 的一句话

```text
继续 myAppleHealthyBridge。先读 MAC_CODEX_HANDOFF.md。先在 Xcode 真机验证当前桥接客户端：1）手动同步；2）服务端 ingest 写入；3）再开启 Enable Auto Sync 验证 HKObserverQuery。编译错误优先在 HealthKitManager.swift 里按当前 SDK 修正可用性和单位 API。
```
