# myAppleHealthyBridge

`myAppleHealthyBridge` 是一个真机可运行的 iPhone HealthKit 同步客户端，用来把 Apple 健康数据按增量方式上传到服务端。

当前实现重点不是“本地展示健康数据”，而是把这条链路跑通并稳定下来：

- HealthKit 授权
- 按类型增量查询样本
- 本地持久化 `HKQueryAnchor`
- 服务端恢复同步游标
- `Start From Now` 建立基线
- 手动同步与自动同步
- 最近 7 天历史回填
- `/ingest` 上传
- `/api/records/recent` 最近同步数据概览

## 当前界面

客户端首页目前包含这些操作：

- `请求健康数据权限`
- `保存设置`
- `恢复服务端游标`
- `从现在开始`
- `手动同步`
- `上传最近 7 天`
- `查看最近同步数据`
- `上传内容预览`

其中同步行为已经收口为：

- 启动时会尝试静默恢复服务端游标
- 如果本地和服务端都没有游标，`手动同步` 不会直接扫全量历史
- 这时必须先执行 `从现在开始`
- `上传最近 7 天` 只做一次性回填，不会改写当前增量游标
- `设备编号` 被视为稳定同步流标识，改动后会清空本地游标和基线

## 打开方式

```bash
open myAppleHealthyBridge.xcodeproj
```

## 首次运行

1. 在 Xcode 中打开 `myAppleHealthyBridge.xcodeproj`
2. 选择 target `myAppleHealthyBridge`
3. 在 `Signing & Capabilities` 中配置你的 Apple Team
4. 确认 `HealthKit` capability 已开启
5. 连接真机运行

## 服务端配置

设置页字段含义如下：

- `服务端地址`
  - 填服务端根地址，不要带 `/ingest`
  - 示例：`https://health.liulin.work`
- `接口令牌`
  - 服务端启用了 `INGEST_API_TOKEN` 时再填写
  - 直接填原始 token，不要手动加前缀
- `基础认证用户名` / `基础认证密码`
  - 仅在公网入口启用了 Basic Auth 时填写
  - 当前客户端优先发送 Basic Auth；只有未配置 Basic Auth 时，才发送 Bearer Token
- `设备编号`
  - 代表一个长期稳定的同步流
  - 正式开始同步后不要随意改
- `开启自动同步`
  - 建议先关闭，先把手动链路验证通过
  - 验证稳定后再开启

客户端当前会访问这些服务端接口：

- `POST <Base URL>/ingest`
- `GET <Base URL>/api/device-sync-state/anchors`
- `GET <Base URL>/api/records/recent`

## 推荐联调顺序

1. 填写 `服务端地址`
2. 填写稳定的 `设备编号`
3. 点 `保存设置`
4. 点 `请求健康数据权限`
5. 点 `恢复服务端游标`
6. 如果服务端没有游标，再点 `从现在开始`
7. 点 `手动同步`
8. 如果要补历史数据，再点 `上传最近 7 天`
9. 通过 `查看最近同步数据` 检查服务端最近明细
10. 确认链路稳定后，再打开 `开启自动同步`

## 自动同步说明

自动同步当前依赖：

- `HKObserverQuery`
- `enableBackgroundDelivery`
- 后台 `URLSession uploadTask`
- `BGTaskScheduler`

这意味着它已经能在系统投递健康数据变更时自动触发同步，但仍有这些边界：

- 不是完整的 `BGTaskScheduler` 补偿方案
- 用户强杀应用后，不应假设还能继续稳定后台拉起
- 系统可能延迟或合并 observer 回调
- 后台同步会主动缩小单批负载，优先保证“后台能把一小批数据传出去”
- 如果后台上传完成时本地游标还没来得及更新，下次启动会优先尝试从服务端恢复 anchor

## 最近同步数据页

客户端内置了一个基于服务端的概览页，会调用：

```text
GET /api/records/recent?device_id=<设备编号>&limit=50
```

这个页面目前会展示：

- 服务端该设备的总记录数
- 最近批次时间
- 最近 50 条记录的类型分布
- 最近记录明细，包括类型、数值、单位、时间、来源

## 当前支持的数据类型

当前优先支持这些 quantity / category 类型：

- `HKQuantityTypeIdentifierHeartRate`
- `HKQuantityTypeIdentifierOxygenSaturation`
- `HKQuantityTypeIdentifierRespiratoryRate`
- `HKQuantityTypeIdentifierStepCount`
- `HKQuantityTypeIdentifierActiveEnergyBurned`
- `HKQuantityTypeIdentifierBasalEnergyBurned`
- `HKQuantityTypeIdentifierDistanceWalkingRunning`
- `HKQuantityTypeIdentifierWalkingSpeed`
- `HKQuantityTypeIdentifierAppleExerciseTime`
- `HKQuantityTypeIdentifierAppleStandTime`
- `HKQuantityTypeIdentifierHeartRateVariabilitySDNN`
- `HKQuantityTypeIdentifierRestingHeartRate`
- `HKQuantityTypeIdentifierWalkingHeartRateAverage`
- `HKQuantityTypeIdentifierHeartRateRecoveryOneMinute`
- `HKQuantityTypeIdentifierFlightsClimbed`
- `HKQuantityTypeIdentifierDistanceCycling`
- `HKQuantityTypeIdentifierDistanceSwimming`
- `HKQuantityTypeIdentifierDistanceWheelchair`
- `HKQuantityTypeIdentifierDistanceDownhillSnowSports`
- `HKQuantityTypeIdentifierWalkingStepLength`
- `HKQuantityTypeIdentifierWalkingAsymmetryPercentage`
- `HKQuantityTypeIdentifierWalkingDoubleSupportPercentage`
- `HKQuantityTypeIdentifierSixMinuteWalkTestDistance`
- `HKQuantityTypeIdentifierRunningSpeed`
- `HKQuantityTypeIdentifierRunningStrideLength`
- `HKQuantityTypeIdentifierRunningPower`
- `HKQuantityTypeIdentifierRunningGroundContactTime`
- `HKQuantityTypeIdentifierRunningVerticalOscillation`
- `HKQuantityTypeIdentifierSwimmingStrokeCount`
- `HKQuantityTypeIdentifierPushCount`
- `HKQuantityTypeIdentifierEnvironmentalAudioExposure`
- `HKQuantityTypeIdentifierHeadphoneAudioExposure`
- `HKQuantityTypeIdentifierBodyMass`
- `HKQuantityTypeIdentifierLeanBodyMass`
- `HKQuantityTypeIdentifierHeight`
- `HKQuantityTypeIdentifierBodyFatPercentage`
- `HKQuantityTypeIdentifierVO2Max`
- `HKQuantityTypeIdentifierTimeInDaylight`
- `HKQuantityTypeIdentifierAppleWalkingSteadiness`
- `HKQuantityTypeIdentifierAtrialFibrillationBurden`
- `HKQuantityTypeIdentifierBodyTemperature`
- `HKQuantityTypeIdentifierAppleSleepingWristTemperature`
- `HKCategoryTypeIdentifierSleepAnalysis`
- `HKCategoryTypeIdentifierAudioExposureEvent`
- `HKCategoryTypeIdentifierHandwashingEvent`
- `HKCategoryTypeIdentifierHighHeartRateEvent`
- `HKCategoryTypeIdentifierLowHeartRateEvent`
- `HKCategoryTypeIdentifierIrregularHeartRhythmEvent`
- `HKCategoryTypeIdentifierLowCardioFitnessEvent`

补充说明：

- 实际可读到哪些类型，取决于设备是否产生过这类数据，以及当前系统版本是否支持该类型
- 当前代码会在运行时探测类型；不支持的 identifier 会自动跳过，不会直接崩溃
- category 类型会额外把语义值写进 `metadata`，包括 `category_value_raw` 和 `category_value_label`

## 联调检查

- iPhone 必须能访问服务端地址
- `服务端地址` 不要重复带 `/ingest`
- 如果服务端启用了 token 鉴权，客户端填写的 `接口令牌` 必须完全一致
- 如果服务端启用了 Basic Auth，客户端必须填写基础认证用户名和密码
- 建议先确认服务端 `POST /ingest`、`GET /api/device-sync-state/anchors`、`GET /api/records/recent` 都可访问

## 当前限制

- 自动同步依赖 observer，没有后台补偿同步
- 还没有 workout 专用 payload
- 还没有 correlation / clinical records 支持
- `HKQuantityTypeIdentifierPhysicalEffort`、`HKQuantityTypeIdentifierBodyMassIndex` 等类型仍待单独确认单位和口径

## 文档约定

- 长期说明以这份 `README.md` 为准
- 交接执行信息见 [CLAUDE_HANDOFF.md](./CLAUDE_HANDOFF.md)
