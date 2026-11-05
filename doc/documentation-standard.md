---
title: 文档规范
summary: 写或改 doc/ 文档时读；本文件同时是 tool/new_doc.sh 复制的模板。
group: convention
applies_to: tool/docs.py, tool/build_doc_index.sh, tool/new_doc.sh, .githooks/pre-commit
---
## 适用场景

准备新建或修改 `doc/` 下的文档时。只改代码、不碰文档时不需要读。

## 操作

新建文档直接复制本文件：

```bash
tool/new_doc.sh calendar-export "日历导出"
```

复制后替换标题、摘要和正文。正文只写代码里读不出来的东西：

- 跨系统契约、版本约束的因果、负知识、无法自动化的人工流程、代价高昂的验证。
- 删掉这段内容如果没人会犯错，就说明它不该存在。
- 仓库里已有的命令和事实直接链接过去，不要复制。
- 正文不写 H1，层级从 H2 起。第一节是「适用场景」，最后两节是「验证」和「常见故障」。
- 单篇超过 80 行时拆分。
- frontmatter 只认单行 `key: value`：不加引号、不用多行块、不嵌套，值里可以有冒号。
- `applies_to` 同时驱动索引反查和提交时的过期检查：它覆盖的路径被改动而文档没动，hook 会要求确认。写得太宽会让每次提交都被拦；`doc/` 内部的改动不参与这项检查，只由上面的 title/summary 漂移检查覆盖。

## 验证

```bash
tool/build_doc_index.sh --check
```

输出为空即通过。`doc/index.md` 由脚本生成，不要手改。

## 常见故障

- **索引里出现半句话** → `summary` 写成了正文开头，改成「什么时候该读」。
- **提交被 hook 拦下，提示 title/summary 未变** → 正文改了但摘要没跟上，确认后更新，或用 `DOC_REVIEWED=1 git commit ...` 显式放行。
- **提交被 hook 拦下，提示声明的路径被改动** → `applies_to` 覆盖的代码变了。更新文档；如果确认文档仍然准确，用 `DOC_REVIEWED=1` 放行。
- **报 `applies_to declared by more than one document`** → 路径前缀重复，把其中一条写得更具体。
- **文档里的命令跑不通** → 多半是从 README 抄来的副本，改成链接，只保留 README 没写的约束和原因。
