# 设备诊断

开发设备页面会列出当前 Mac 可见的模拟器和受信任 Apple 开发设备。

## 设备发现

T-Local 会检查：

- Xcode `devicectl`
- CoreDevice 设备列表
- `simctl` iOS 模拟器
- 可选的 `pymobiledevice3` 运行时
- 可选的 `idevicesetlocation` fallback

## 健康检查报告

健康面板会报告：

- Xcode / `xcrun` 是否可用
- CoreDevice / `devicectl` 是否可用
- `simctl` 是否可用
- 设备配对和信任状态
- 连接路径
- Developer Mode 是否可见
- Developer Disk Image 是否可见
- `pymobiledevice3` 是否可用
- CoreDevice tunnel 和 RSD port
- DVT location 能力

每个检查项包含：

- 状态：通过、警告、失败或未知
- 详细原因
- 修复建议
- 可用时提供修复命令
- 是否阻断定位模拟

## 复制报告

可以使用：

- **复制 Markdown**：适合发给 QA 或研发排障。
- **复制 JSON**：适合自动化、日志或内部支持工具。

## 常用修复命令

刷新设备：

```bash
xcrun devicectl list devices --timeout 5
```

列出模拟器：

```bash
xcrun simctl list devices available
```

使用自定义 Xcode 路径：

```bash
sudo xcode-select -s /Volumes/Build/dowl/Xcode.app/Contents/Developer
```

恢复可选 Python 运行时：

```bash
python3 -m venv .venv-pymobiledevice3
.venv-pymobiledevice3/bin/python -m pip install pymobiledevice3
```

## 边界

健康检查是只读检测。它不会自动安装依赖、挂载开发镜像，也不会自动修改设备设置。
