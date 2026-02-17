---
name: extract-photos
description: 从 Apple 照片应用中按月份或日期范围提取照片到当前目录
---

# Extract Photos

从 Apple Photos 照片库中提取指定时间段的照片，转换为 JPG 格式，保存到当前目录下以月份命名的文件夹中。

## Quick Start

```bash
bash scripts/extract-photos.sh 2025-03
```

## Options

### 按月份提取

```bash
bash scripts/extract-photos.sh <YYYY-MM>
```

### 按日期范围提取

```bash
bash scripts/extract-photos.sh <YYYY-MM-DD> <YYYY-MM-DD>
```

### 按人物提取

```bash
bash scripts/extract-photos.sh --person <人物名> <YYYY-MM>
bash scripts/extract-photos.sh --person <人物名> <YYYY-MM-DD> <YYYY-MM-DD>
```

### 列出所有人物

```bash
bash scripts/extract-photos.sh --list-persons
```

### 帮助

```bash
bash scripts/extract-photos.sh -h
```

## Complete Examples

1. 提取 2025年3月全部照片：
```bash
bash scripts/extract-photos.sh 2025-03
```

2. 提取日期范围内的照片：
```bash
bash scripts/extract-photos.sh 2025-03-01 2025-03-15
```

3. 提取赵铁柱在 2025年12月的照片：
```bash
bash scripts/extract-photos.sh --person 赵铁柱 2025-12
```

## How It Works

- 只读方式访问 Photos 数据库（复制副本，包含 WAL 文件确保数据完整）
- 查询指定时间段内的照片（支持按人脸识别筛选）
- 将 HEIC/PNG 等格式转换为 JPG（使用 macOS 内置 sips 工具）
- 视频文件直接复制（保留原格式）
- 输出到当前目录下以月份命名的文件夹（如 `2025-03/`）
- 按人物提取时文件夹格式为 `人物名_月份`（如 `赵铁柱_2025-03/`）

## Important Notes

- 绝不删除 Photos 库中的原始照片，只执行复制操作
- iCloud 云端未下载到本地的照片会被跳过（提示"文件不存在"）
- 同名文件采用覆盖策略
