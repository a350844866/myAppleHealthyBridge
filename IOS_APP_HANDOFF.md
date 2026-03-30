# iOS App Handoff

这个文档给 Mac 上的 Codex，用来启动 `myAppleHealthy` 的 iPhone HealthKit bridge App 开发。

## 项目背景

当前项目是一个个人健康管理系统：

- 历史数据来源于 Apple Health 导出 XML
- 后端是 `FastAPI + PyMySQL + MySQL 8`
- 前端是同源 dashboard
- 长期方向已经明确，不再依赖手动导出
- 目标路线是：
  - iPhone 侧 HealthKit bridge App
  - 增量同步到自建后端
  - 服务端做健康告警

参考文档：

- [NEXT_STEPS.md](/programHost/vibe-coding/myAppleHealthy/NEXT_STEPS.md)
- [backend/INCREMENTAL_SYNC.md](/programHost/vibe-coding/myAppleHealthy/backend/INCREMENTAL_SYNC.md)

## 当前服务端状态

已经完成：

- MySQL 后端可运行
- Apple Health XML 导入器已实现
- `health_records` 表已存在，且依赖 hash 做幂等
- dashboard 已支持同源访问
- 新增了轻量导入状态接口 `/api/import-status`

尚未完成：

- iOS App
- 服务端 `/ingest`
- `device_sync_state`
- `alert_rules`
- `alert_events`

## 现在要做的不是

不要做这些：

- 不要回到“手动导出 XML 为主”的方向
- 不要依赖固定 IP 写死前端或 App
- 不要先做复杂 UI
- 不要先做告警系统全套
- 不要先做 Apple Watch 独立 App

## iOS 侧第一阶段目标

先做一个最小可运行版本，目标只有这几件事：

1. 请求 HealthKit 权限
2. 拉取一小批高价值健康数据
3. 做一次全量初始同步
4. 保存本地 anchor
5. 使用 `HKObserverQuery + HKAnchoredObjectQuery` 做增量同步
6. 把 JSON 发到后端预留的 `/ingest`

第一阶段优先数据类型：

- `HKQuantityTypeIdentifierHeartRate`
- `HKQuantityTypeIdentifierOxygenSaturation`
- `HKQuantityTypeIdentifierRespiratoryRate`
- `HKQuantityTypeIdentifierStepCount`
- `HKCategoryTypeIdentifierSleepAnalysis`
- 可选：
  - `HKWorkoutType.workoutType()`

## 建议的 iOS 技术选型

- Swift
- SwiftUI
- HealthKit
- `URLSession`
- `BackgroundTasks` 只做补充，不要把它当成唯一同步机制

最低可接受结构：

- `HealthKitManager`
- `SyncStore`
- `IngestClient`
- `SyncCoordinator`
- 一个极简设置页

## 建议的数据模型

手机侧发给服务端的 payload 建议先统一成这种形状：

```json
{
  "device_id": "iphone-xxx",
  "bundle_id": "your.bundle.id",
  "sent_at": "2026-03-30T09:30:00Z",
  "items": [
    {
      "source": "healthkit",
      "kind": "sample",
      "type": "HKQuantityTypeIdentifierHeartRate",
      "uuid": "sample-uuid",
      "start_at": "2026-03-30T09:20:00Z",
      "end_at": "2026-03-30T09:20:00Z",
      "value": 72,
      "unit": "count/min",
      "metadata": {
        "source_name": "Apple Watch",
        "source_version": "11.0"
      }
    }
  ],
  "anchors": {
    "HKQuantityTypeIdentifierHeartRate": "base64-anchor"
  }
}
```

注意：

- 先保证字段稳定、可重试、可幂等
- 每条 sample 尽量带 `uuid`
- anchor 按类型分别存

## 建议的本地存储

至少保存这些内容：

- HealthKit 授权状态
- 每个类型的最新 anchor
- 最近一次同步时间
- 最近一次同步结果
- 设备标识
- 服务端 base URL
- token 或 API key

本地持久化可先用：

- `UserDefaults` 存简单状态
- 如果 anchor 处理不方便，再上 `Codable + file storage`

## 服务端接口假设

当前后端还没有真正实现 `/ingest`，所以 iOS 侧先按下面契约准备：

- `POST /ingest`
- `Content-Type: application/json`
- 支持重复提交同一批数据
- 服务端未来会负责幂等去重

预期成功响应可以先假定为：

```json
{
  "ok": true,
  "accepted": 120,
  "deduplicated": 30
}
```

Mac 上 Codex 如果愿意，也可以顺手先生成一个本地 mock `IngestClient`，把网络层和 HealthKit 层解耦。

## 与现有后端的关系

当前服务端历史库的核心事实：

- `health_records` 是历史主表
- 重复导入依赖 hash 和唯一索引处理
- 现在 XML importer 还在补历史数据

所以 iOS App 第一阶段不要假设：

- 服务端已经完成实时 ingest
- 服务端已经有告警引擎
- 服务端 schema 已为 iOS 增量同步定稿

App 先把“可靠采集 + 本地 anchor + 统一 payload + 可重试上传”做对。

## 交付优先顺序

Mac 上 Codex 建议按这个顺序推进：

1. 创建 iOS 项目骨架
2. 接入 HealthKit 权限申请
3. 完成 1 到 2 个类型的 anchored query
4. 落本地 anchor
5. 做统一 JSON 编码
6. 做 `IngestClient`
7. 做最小设置页：
   - 服务端 URL
   - token
   - 手动同步按钮
   - 最近同步结果
8. 再扩展到剩余类型

## 最小验收标准

第一版只要满足这些就算合格：

- App 能成功请求 HealthKit 权限
- 能拉到心率样本
- 能保存并复用 anchor
- 能把样本编码成统一 JSON
- 能发送到可配置服务端地址
- 能在界面上看到最近一次同步成功或失败

## 发给 Mac 上 Codex 的一句话

你可以直接把这句发给 Mac 上的 Codex：

```text
继续 myAppleHealthy 项目，开始做 iPhone HealthKit bridge App。请按 IOS_APP_HANDOFF.md 执行，先做最小可运行版本：HealthKit 授权、anchored query、anchor 持久化、统一 JSON payload、可配置 /ingest 上传、一个简单设置页。
```
