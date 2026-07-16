## v2.1.1 (211)

- 全面代码审计修复: 消除重复代码、补充边界条件、增强健壮性
- device_get/set_prop/del_prop 提取到 common_func.sh，消除 vbmeta_spoof.sh 与 prop_unify.sh 中的重复定义
- service.sh Phase 1: 移除 17 个重复的 vbmeta 属性设置，改为调用 vbmeta_spoof.sh + prop_unify.sh 统一管理
- action.sh: 修复 _gevt 未定义 Bug（keybox 菜单在 event0 不可用时崩溃）
- vbmeta_spoof.sh: 增加 3 个块设备路径（vbmeta_b/platform/vbmeta_system_a），digest 增加长度校验
- service.sh: Phase 2 $SED toybox 兼容 fallback，hot reload 增加 daemon_hot_reload 配置开关
- service.sh: Phase 3 增加 device.conf 存在性守卫，防止 bootstrap 失败后空跑
- common_func.sh: 新增 sed_inplace 便携式行内编辑函数

## v2.1.0 (210)

- 阻断级修复: uninstall.sh source顺序、status_json.sh键名、hotinstall.sh复制目标、update.json版本
- 中等修复: rom_fp_cleanup.sh config_get_bool、build_target_txt.sh TRICKY_DIR、post-fs-data.sh注释、security_patch.sh安装列表
- 并发修复: daemon_manager.c restarting标志位、service.sh bootstrap守卫、logcat_cleanup.sh PID锁文件

## v1.4.9

- action.sh: Step 1 改为音量键交互菜单（自动/生成证书链/修改证书链），音量+/-切换，电源键确认

## v1.4.8

### 全量 P1/P2/P3 审计修复
- common_func.sh: 新增 6 共享函数 + TIEJIA_CONFIG_DIR 常量
- P1: keybox_rotate.sh source+find_sed、keybox_fetch.sh/sync_patch.sh lowercase()、service.sh CONFIG_DIR 后备、conflict_scan.sh IFS read
- P2: target_cleanup.sh ensure_trailing_newline()、boot_state_props.sh set -e、action.sh 按键 dot、autopif4.sh wget 优先、prop_unify.sh 指纹增强校验
- P3: action.sh APK PK 魔数校验、mount_isolation.sh target.txt 随机盐、service.sh hourly 并行化、autopif.sh LEGACY FALLBACK、8 脚本 CONFIG_DIR 收敛

## v1.4.9

- action.sh: Step 1 改为音量键交互菜单（自动/生成证书链/修改证书链），音量+/-切换，电源键确认

## v1.4.8

### 全量 P1/P2/P3 审计修复
- common_func.sh: 新增 6 共享函数 + TIEJIA_CONFIG_DIR 常量
- P1: keybox_rotate.sh source+find_sed、keybox_fetch.sh/sync_patch.sh lowercase()、service.sh CONFIG_DIR 后备、conflict_scan.sh IFS read
- P2: target_cleanup.sh ensure_trailing_newline()、boot_state_props.sh set -e、action.sh 按键 dot、autopif4.sh wget 优先、prop_unify.sh 指纹增强校验
- P3: action.sh APK PK 魔数校验、mount_isolation.sh target.txt 随机盐、service.sh hourly 并行化、autopif.sh LEGACY FALLBACK、8 脚本 CONFIG_DIR 收敛

## v1.4.7

### P1 修复
- keybox_fetch.sh: 内联 resolve_asfetch/resolve_bb（修复死代码）
- prop_unify.sh: 指纹格式校验，防止空 brand 写入
- action.sh: dl_out/dl_to 支持 http_proxy/ALL_PROXY 代理
- keybox_rotate.sh: 多条目源保留备份，支持后续继续旋转

### P2 修复
- target_cleanup.sh: 防换行累积
- logcat_cleanup.sh: 移除破坏性 buffer 清空
- action.sh: am force-stop 后台化
- keybox_rotate.sh: 支持单行 XML Keybox 解析
- autopif4.sh: 全部 wget 增加 30s 超时
- service.sh: 首启 bootstrap 增加 target_cleanup
- security_patch.sh: MODDIR 动态检测
- boot_state_props.sh: 增加文件内容扫描
