# AI Agent Skills Repository

这是一个用于管理本地 AI Agent Skills 的仓库。Skills 是指 AI Agent 可以调用的一组特定的能力或工具集。

## 目录结构

本仓库的目录结构如下：

```
pc-agent-skills/
├── README.md           # 本文件，项目说明文档
└── skills/             # 存放所有 Skills 的主目录
    └── [skill-name]/   # 单个 Skill 的文件夹
        ├── SKILL.md    # [必须] 该 Skill 的核心定义文件，包含元数据和指令
        ├── scripts/    # [可选] 该 Skill 使用的辅助脚本
        ├── resources/  # [可选] 该 Skill 需要的资源文件
        └── examples/   # [可选] 该 Skill 的使用示例
```

## Skills 列表

目前仓库中包含以下 Skills：

- **example-skill**: 一个示例 Skill，用于演示目录结构和 `SKILL.md` 的编写方式。
- **extract-photos**: 从 Apple 照片应用中按月份或日期范围提取照片到当前目录。

## 如何添加新的 Skill

1.  在 `skills/` 目录下创建一个新的文件夹，命名为你的 Skill 名称（例如 `data-analysis`）。
2.  在新建的文件夹中创建一个 `SKILL.md` 文件。
3.  `SKILL.md` 必须包含 YAML frontmatter，定义 `name` 和 `description`。
4.  在 `SKILL.md` 中编写详细的指令和说明。

### SKILL.md 模板

```markdown
---
name: [Skill Name]
description: [Short description of the skill]
---

# Instructions

[Detailed instructions on how to use this skill...]
```
