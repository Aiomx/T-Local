# 遥测 Payload 预览

遥测预览用于在发送到遥测后端之前查看 QA 事件的字段形态。

## 包含字段

预览包含：

- `is_simulated=true`
- `source=qa_sdk`
- `scenario_id`
- `scenario_name`
- 路线点 index 和路线时间
- 纬度和经度
- 海拔
- 水平和垂直精度
- 速度
- 方向
- VPN 节点 ID、名称和区域
- 可用时显示公网 IP 和期望 IP 国家
- 可用时显示 DNS 泄漏状态
- 自定义场景 tags

## 场景 Payload

场景 payload 基于当前选中场景和时间轴预览位置生成。如果时间轴处在两个点之间，坐标可以来自插值结果。

## 设备状态 Payload

如果已经向设备应用过定位，Studio 会额外展示设备状态 payload，使用最后一次应用到设备的坐标和路线进度。

## 复制操作

- **复制字段**：复制简单的 `key=value` 字段列表。
- **复制 JSON**：复制场景 payload 的 pretty JSON。
- **复制设备 JSON**：复制最后一次设备状态 payload 的 pretty JSON。

## 安全边界

预览是只读的，不会把数据发送到生产遥测。
