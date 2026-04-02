# Claude Handoff

这份文档给后续接手 `myAppleHealthyBridge` 的 Claude Code / Codex。长期说明看 [README.md](./README.md)，这里只保留执行层信息。

## 当前状态

- 客户端已经能在真机上跑通
- UI 文案已改成中文
- 已接通服务端增量同步接口
- 已支持服务端游标恢复、`从现在开始`、手动同步、最近 7 天回填、最近同步数据概览
- 自动同步已接上 `HKObserverQuery` + `enableBackgroundDelivery`
- 已补齐一批历史库里实际存在、之前 bridge 未覆盖的 sample 类型

本轮新增覆盖：

- `HKQuantityTypeIdentifierPhysicalEffort`
- `HKQuantityTypeIdentifierStairAscentSpeed`
- `HKQuantityTypeIdentifierStairDescentSpeed`
- `HKQuantityTypeIdentifierEnvironmentalSoundReduction`
- `HKQuantityTypeIdentifierBodyMassIndex`
- `HKCategoryTypeIdentifierAppleStandHour`
- `HKCategoryTypeIdentifierShortnessOfBreath`
- `HKCategoryTypeIdentifierFatigue`

当前数据库历史类型与 bridge 支持清单对照后，剩余未覆盖项只剩：

- `HKDataTypeSleepDurationGoal`

说明：

- 这不是当前 `sample ingest` 链路里常规处理的 quantity / category 类型
- 本轮没有把它强行塞进 `POST /ingest` 的现有 schema

## 当前关键同步规则

- 启动时会尝试静默恢复服务端游标
- 如果本地和服务端都没有游标，`手动同步` 不允许直接扫全历史
- 这时必须先执行 `从现在开始`
- `上传最近 7 天` 只做历史回填，不改当前增量游标
- `设备编号` 是稳定同步流标识，改动后会清空本地游标和基线

## 当前主要页面和操作

- `请求健康数据权限`
- `保存设置`
- `恢复服务端游标`
- `从现在开始`
- `手动同步`
- `上传最近 7 天`
- `查看最近同步数据`
- `上传内容预览`

## 服务端契约

客户端当前依赖这些接口：

- `POST /ingest`
- `GET /api/device-sync-state/anchors`
- `GET /api/records/recent`

服务端仓库在：

- `/Users/liulin/programHost/vibe-coding/myAppleHealthyServer`

服务端详细契约看：

- `/Users/liulin/programHost/vibe-coding/myAppleHealthyServer/backend/IOS_CLIENT_API.md`

## 关键文件

- [myAppleHealthyBridge/ContentView.swift](./myAppleHealthyBridge/ContentView.swift)
- [myAppleHealthyBridge/SyncCoordinator.swift](./myAppleHealthyBridge/SyncCoordinator.swift)
- [myAppleHealthyBridge/HealthKitManager.swift](./myAppleHealthyBridge/HealthKitManager.swift)
- [myAppleHealthyBridge/SyncStore.swift](./myAppleHealthyBridge/SyncStore.swift)
- [myAppleHealthyBridge/IngestClient.swift](./myAppleHealthyBridge/IngestClient.swift)
- [myAppleHealthyBridge/RecentSyncedDataView.swift](./myAppleHealthyBridge/RecentSyncedDataView.swift)

## 真机验证顺序

1. 配好签名和 `HealthKit` capability
2. 真机安装运行
3. 填 `服务端地址`
4. 填稳定的 `设备编号`
5. 点 `保存设置`
6. 点 `请求健康数据权限`
7. 点 `恢复服务端游标`
8. 如果服务端没有游标，再点 `从现在开始`
9. 点 `手动同步`
10. 如需补历史，再点 `上传最近 7 天`
11. 通过 `查看最近同步数据` 检查服务端明细
12. 最后再验证 `开启自动同步`

## 当前已知边界

- 自动同步不是完整的后台补偿方案
- 用户强杀应用后，不应假设还能继续稳定后台拉起
- observer 事件可能被系统延迟或合并
- 还没有 workout / correlation / clinical records 支持
- `HKDataTypeSleepDurationGoal` 仍未纳入当前 sample ingest

## 常用命令

构建：

```bash
xcodebuild -scheme myAppleHealthyBridge -project myAppleHealthyBridge.xcodeproj -configuration Debug -destination 'generic/platform=iOS' build
```

## 接手时优先原则

- 先验证现有链路，不要先大改结构
- 如果服务端和客户端行为不一致，以线上接口和真机现象为准
- 改完后要把文档一起更新，避免 README 和实现再次脱节
- 默认以“改动已推到远程仓库”为结束标准，不停在本地 commit
