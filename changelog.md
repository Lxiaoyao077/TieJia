## v2.3.0

- 修复 ReZygisk 无法启动：二进制硬编码 /data/adb/modules/rezygisk/ 路径，安装时自动创建 compat stub 目录（symlink）
- 修复 uninstall.sh 未清理 rezygisk compat 目录

## v2.2.2

- 修复 WebUI 空白问题：customize.sh 现在提取完整 webroot 目录（CSS/JS/fonts/assets/lang 共 72 个文件），之前只提取了 index.html

## v2.2.1

- 初始云端发布
