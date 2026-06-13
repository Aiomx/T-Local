# 场景工作台指南

Telemetry Scenario Studio 是 macOS 端场景编辑应用，用于创建和维护 QA 定位遥测场景。

## 场景库

场景会保存为本地 `.telemetryscenario.json` 文件，默认目录：

```text
~/Library/Application Support/TelemetryScenarioStudio/Scenarios
```

场景库支持：

- 新建场景
- 复制场景
- 重命名
- 删除
- 导入和导出
- 搜索
- 标签
- 最近打开
- 自动保存

## 地图编辑

地图编辑器支持：

- 点击地图插入路线点。
- 拖动点更新坐标。
- 右键点位删除。
- 从地图、表格或时间轴选择点。
- 互换起点和终点。
- 在手动直线模式和道路规划模式之间切换。
- 使用 MapKit 规划路线并应用到场景。

## 路线统计

地图面板会显示：

- 总距离
- 总时长
- 平均速度
- 点数
- 总停留时间
- 当前路径模式

## 时间轴预览

时间轴面板支持：

- 拖动到指定路线时间。
- 预览插值坐标。
- 播放、暂停、继续和停止路线回放。
- 调整倍速。
- 开启或关闭循环。

设备回放仍采用按路线点低频推送；时间轴预览可以在点之间插值。

## 导出格式

- GPX：用于 Xcode、Simulator 或外部工具。
- JSON：用于 Scenario Studio、QA Console 和 SDK 测试。
