## v2.3.1

- ReZygisk 真正集成：runtime symlink（不产生额外 Magisk 模块）
- WebUI 路径指回 tricky_store（module.prop / lang 不再依赖 rezygisk）
- 清理 v2.3.0 的 compat stub 残留逻辑

## v2.2.2

- 修复 WebUI 空白问题：customize.sh 现在提取完整 webroot 目录（CSS/JS/fonts/assets/lang 共 72 个文件），之前只提取了 index.html
- ReZygisk 集成保持与 integrated_v2 一致
