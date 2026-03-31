# Background Sync Handoff

本文件记录 `myAppleHealthyBridge` 在 `2026-03-31` 这一轮针对“退到后台后不再同步”问题所做的改造，供下次在 Mac + Xcode 真机环境中继续验证。

## 这轮修改的核心判断

当前最主要的问题，不是“没付苹果 99 美元年费”，而是客户端后台同步链路本身不够适合 iOS 的后台执行模型。

改造前的主要风险：

- `POST /ingest` 使用普通 `URLSession.data(for:)`
- observer / BGTask 触发后会直接跑一整轮增量抓取 + 编码 + 上传
- 后台任务完成状态一律标记为 success
- 后台调度提交失败被直接吞掉，缺少可观测性

这会导致：

- App 退到后台后，网络上传容易被系统挂起打断
- 单次后台同步负载太大，容易超出系统给的执行窗口
- 很难判断是 observer 没触发、BGTask 没调度，还是上传链路被系统中断

## 这轮已经完成的改造

### 1. ingest 上传改成后台 URLSession

文件：

- [myAppleHealthyBridge/IngestClient.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/IngestClient.swift)
- [myAppleHealthyBridge/myAppleHealthyBridgeApp.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/myAppleHealthyBridgeApp.swift)

改动：

- `POST /ingest` 不再直接使用前台 `session.data(for:)`
- 改为后台 `URLSessionConfiguration.background(...)`
- 上传方式改成 `uploadTask(with:fromFile:)`
- 增加后台 URLSession 完成事件回调接线
- 上传 body 会先落到临时文件，再交给后台会话处理

目的：

- 即使 App 已经退到后台，系统也更有机会继续完成上传
- 避免“前台 async 请求一退后台就直接没了”

### 2. 后台触发路径缩成更小批次

文件：

- [myAppleHealthyBridge/SyncCoordinator.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/SyncCoordinator.swift)

改动：

- 手动增量同步预算：
  - `maxPerType = 200`
  - `maxTotal = 1000`
- observer / BGTask / 自动重试 / 前台恢复预算：
  - `maxPerType = 40`
  - `maxTotal = 240`
- 最近 7 天回填预算：
  - `maxPerType = 120`
  - `maxTotal = 500`
- 全量历史回填预算保持小批量：
  - `maxPerType = 50`
  - `maxTotal = 200`

目的：

- 后台路径优先保证“小批量先传出去”
- 不再试图在一次 observer 回调里吃掉太多 HealthKit 数据
- 降低后台执行时间过长被系统中断的概率

### 3. BGTaskScheduler 返回真实完成状态

文件：

- [myAppleHealthyBridge/BackgroundTaskManager.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/BackgroundTaskManager.swift)

改动：

- `registerTasks` 现在要求同步动作返回 `Bool`
- `task.setTaskCompleted(success:)` 不再固定写死 `true`
- 提交 refresh / processing task 时先取消旧请求，避免重复堆积
- `scheduleAll()` / `scheduleRefresh()` / `scheduleProcessing()` 现在有布尔返回值

目的：

- 避免后台任务“明明没做好也上报 success”
- 让后续如果要做更细日志时，能继续扩展

## 这轮没有彻底解决的边界

以下问题仍然存在，这是 iOS 模型本身决定的，不是这轮代码就能完全抹平：

- 用户强杀 App 后，不能假设还能稳定后台拉起
- `HKObserverQuery` 可能延迟、合并，或者不按预期频率触发
- `BGTaskScheduler` 不是定时器，系统不会按你设的时间点精确执行
- 后台上传完成后，如果 App 很快再次被挂起，本地 anchor 可能还没来得及持久化

这一点已经通过“下次启动优先从服务端恢复 anchor”部分缓解，但不是绝对消除。

## 明天在 Mac 上优先验证什么

### 验证 1：observer + 后台上传是否真的能工作

步骤建议：

1. 在 Xcode 真机运行 App
2. 配好服务端地址、鉴权、设备编号
3. 请求 HealthKit 权限
4. 先点一次 `恢复服务端游标`，如果服务端没有游标，再点 `从现在开始`
5. 开启自动同步
6. 把 App 切到后台
7. 在系统里制造一个新样本
   - 最容易测的是步数、心率、体重等
8. 观察服务端 `POST /ingest` 是否收到请求
9. 观察服务端 `GET /api/device-sync-state` 是否推进

重点不是 UI 文案，而是：

- 后台时是否真的发起了上传
- 上传是否在 App 不回前台的情况下完成

### 验证 2：BGTask 是否能补偿漏掉的 observer

步骤建议：

1. 保持自动同步开启
2. 让 App 退到后台一段时间
3. 如果 observer 没及时触发，观察后续是否仍有补偿同步
4. 重点看服务端时间线是否出现较晚到达的一小批增量样本

### 验证 3：被挂起后重新打开，是否能继续接上

步骤建议：

1. 先完成至少一次成功后台同步
2. 让 App 在后台停留更久，甚至被系统回收
3. 重新打开 App
4. 看是否还能继续同步，而不是出现游标丢失或重复从头扫描

## 下次回来建议继续做的事

优先顺序建议：

1. 在 Xcode 里直接跑真机验证本轮改动
2. 给客户端补更明确的运行时日志
   - observer 触发时间
   - BGTask 被调度时间
   - 后台上传开始/完成/失败
3. 视验证结果决定要不要继续拆 observer 回调
   - 例如只标记 dirty type
   - 真正抓取和上传放到更明确的补偿执行路径
4. 如果后台仍不稳定，再考虑是否要把“待上传批次”持久化到本地文件或本地数据库

## 当前仓库中本轮涉及的文件

- [myAppleHealthyBridge/IngestClient.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/IngestClient.swift)
- [myAppleHealthyBridge/BackgroundTaskManager.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/BackgroundTaskManager.swift)
- [myAppleHealthyBridge/SyncCoordinator.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/SyncCoordinator.swift)
- [myAppleHealthyBridge/myAppleHealthyBridgeApp.swift](/programHost/vibe-coding/myAppleHealthyBridge/myAppleHealthyBridge/myAppleHealthyBridgeApp.swift)
- [README.md](/programHost/vibe-coding/myAppleHealthyBridge/README.md)

## 当前环境限制

这次修改是在 Linux 环境中完成的，当前机器没有 `swift` / Xcode 工具链，因此：

- 没有在本地直接完成编译
- 没有做真机运行验证

本轮产出属于：

- 代码改造已完成
- 需要你明天在 Mac + Xcode + iPhone 真机环境中做第一轮验证
