# myAppleHealthyBridge

最小可运行的 iPhone HealthKit bridge App 骨架。

当前版本已经包含：

- SwiftUI iOS App 工程
- HealthKit 权限申请
- 一批高价值 HealthKit sample 的 anchored query 读取
- 手动同步为默认模式，可选开启自动同步
- `HKQueryAnchor` 本地持久化
- 统一 JSON payload 编码
- `/ingest` 上传客户端
- 一个最小设置页和手动同步按钮

当前优先支持这些类型：

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
- `HKQuantityTypeIdentifierFlightsClimbed`
- `HKQuantityTypeIdentifierDistanceCycling`
- `HKQuantityTypeIdentifierDistanceSwimming`
- `HKQuantityTypeIdentifierDistanceWheelchair`
- `HKQuantityTypeIdentifierDistanceDownhillSnowSports`
- `HKQuantityTypeIdentifierWalkingStepLength`
- `HKQuantityTypeIdentifierWalkingAsymmetryPercentage`
- `HKQuantityTypeIdentifierWalkingDoubleSupportPercentage`
- `HKQuantityTypeIdentifierAppleWalkingSteadiness`
- `HKQuantityTypeIdentifierWalkingHeartRateAverage`
- `HKQuantityTypeIdentifierHeartRateRecoveryOneMinute`
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
- `HKQuantityTypeIdentifierSixMinuteWalkTestDistance`
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

说明：

- 实际可读到哪些类型，仍取决于 iPhone / Apple Watch 是否产生过这类数据，以及系统版本是否支持该 identifier
- 当前代码会在运行时探测类型；如果某个 identifier 当前系统不支持，会自动跳过，而不是直接崩溃

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
- `Enable Auto Sync`
  - 默认建议关闭
  - 调试期间先手动同步
  - 后期稳定后再打开自动同步

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

- 自动同步依赖 `HKObserverQuery`，但还没有后台任务补偿同步
- 还没有 workout 支持
- `HKQuantityTypeIdentifierPhysicalEffort`、`HKQuantityTypeIdentifierBodyMassIndex` 等单位或口径还需要单独确认
- 相关性对象、临床记录、workout 明细暂时还没有走当前 `/ingest` payload
