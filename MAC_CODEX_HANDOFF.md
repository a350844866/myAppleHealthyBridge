# MAC Codex Handoff

这个文件给明天在 Mac 上接手 `myAppleHealthyBridge` 的 Codex。

## 今天已经做了什么

- 把最初只支持少量类型的 HealthKit bridge，扩成了“运行时探测可用类型，再尽量多收集 sample 数据”的实现
- 新增了大量 quantity / category 类型的采集支持，覆盖心率、血氧、呼吸、步数、能量、距离、步态、体成分、VO2Max、环境音频、睡眠、心脏事件等
- 不再把不支持的 HealthKit identifier 写死成强依赖；当前系统不支持时会自动跳过，避免直接因为 SDK 或设备差异崩掉
- 把 category 类型的语义补全进 metadata，尤其是：
  - `category_value_raw`
  - `category_value_label`
- 增加了自动同步开关：
  - 默认关闭
  - 只有打开后才注册 `HKObserverQuery`
  - 关闭后会真正停止 observer 和 background delivery
- 同步状态存储和协调逻辑已经跟自动同步联动，不再只是 UI 开关
- iOS deployment target 已调整到 `17.0`
- 仓库文档已收口：
  - `README.md` 是长期说明
  - 当前这个 `MAC_CODEX_HANDOFF.md` 是短期接手说明
  - 旧的阶段性 handoff 文档已经删除，避免误导

## 现在代码处在什么阶段

- 这已经不是“从 0 开始搭骨架”的阶段了
- 现在更接近“已有一版可联调的桥接客户端，但还没有在 Xcode 真机上收口验证”
- Linux 这边只能改代码、整理结构、补协议和文档，不能替代 Xcode 编译和真机 HealthKit 验证
- 所以明天在 Mac 上最重要的不是重新设计，而是先验证现有实现能不能按当前 SDK 和真机环境跑通

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

## 明天接手时要先建立的认知

- 当前目标不是做漂亮 UI，而是先把“采集 -> 编码 -> 上传 -> 服务端写入”这条链打通
- 自动同步虽然已经接上了开关和 observer，但它还不是最终稳定形态；先手动同步跑通，再开自动同步
- 如果明天出现问题，最可能不是产品逻辑错了，而是：
  - 某些 HealthKit API 在当前 Xcode SDK 名称或可用性不同
  - 某些 identifier 在当前机型 / 系统版本不可用
  - 某些单位 API 需要按当前 SDK 调整
- 现在最值钱的工作不是继续盲目加类型，而是确认已经加进去的这些类型能不能稳定编译、授权、查询、上传、落库

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
