# 谷歌服务恢复 / Google Services Restore

在手机重启并重新获取临时 Root 后，手动恢复谷歌服务部署的 Android App。

## v1.1.0 实验兼容版

移除机型和系统构建号白名单；旧版没有内核版本白名单。App仍支持SDK26起安装，启动及部署前显示兼容性提示。

内置组件最低需要Android14/SDK34和arm64-v8a，部署时检查Root、KernelSU配套工具、全局挂载空间及OverlayFS。不满足实际依赖时说明原因并停止，不能靠提示代替必要条件。撤销不受组件SDK/ABI检查阻挡。

只有HONOR LSA-AN00 Android14 8.0.0.221(C00E220R8P3)有历史实测。其他设备和固件未经验证，内核相近不代表兼容；厂商联网接口、权限和挂载可能不同，请先检查状态并保留恢复方式。没有增加提权功能，不保证其他Root管理器兼容。

## 下载和使用

到本仓库 Releases 下载 `GoogleRestore.apk`。

1. 手机重启后，先自行获取临时 Root，确保 KernelSU 能正常授权。
2. 打开“谷歌服务恢复”，允许 Root 授权。
3. 保存其他应用的工作，点击“一键恢复”并确认。
4. 若需重新挂载组件，Android 服务会重启、App 会关闭。等待约 1–3 分钟，再打开 App 检查状态，通过 Play 商店验证登录和下载。

App 不提供提权功能，不设置开机自动运行。恢复可能短暂黑屏并关闭应用；异常情况下可能需要人工重启并重新获取临时 Root。首次准备约需 1.5 GB 可用存储，部署前要求至少 1 GB 可用内存。

## 功能和原理

- 一键恢复：校验内置组件，以只读 OverlayFS 临时挂载系统应用和权限配置；已部署时只修复配置。
- 检查状态：查看 Root、组件注册、挂载和已知厂商联网限制。
- 仅修复联网与下载：解除谷歌组件的已知厂商联网限制，为 Play 商店配置所需电池白名单；动态查询 UID。
- 撤销本 App 的更改：撤销自身挂载和有记录的配置，保留账号、应用数据和缓存，不撤销外部工具的挂载。

校验后的文件保存在 `/data/adb/google-restore/payload.*`，普通重启后仍在。系统应用挂载在内存中，重启后需重建。不写入原始系统分区，不关闭 SELinux，不整体禁用厂商防火墙。

## 验证和已知限制

2026-10-20，在上述机型验证了安装、Root 授权、文件校验、重复恢复、联网和商店下载。使用者确认整机重启、重新获取临时 Root 后恢复成功，以及 Google 账号登录可用。

已修复撤销后仍等待被移除组件就绪而超时、服务重启后 Java 启动 Root 入口失败、重复撤销产生多余网络规则错误的问题。另在隔离挂载空间内复现挂载点被占用，验证先移除两个挂载再启动服务。

厂商策略可能再次限制联网，遇到登录失败可先点击“仅修复联网与下载”，长期稳定性仍待验证。恢复三件套不保证通过 Play Integrity、设备认证或所有第三方应用的登录要求；不会修改或伪造完整性验证结果。

日志位于 `/data/adb/google-restore/status`、`operation.log`。不要直接公开含账号或设备信息的完整日志。卸载 App 前建议先撤销其部署。

## 从源码构建

需要 Windows PowerShell、JDK、Python 3.10+、Android SDK Build Tools 36.0.0 和 Android 35 平台，无需 Gradle。

源码不包含谷歌 APK 和原生库。自行准备与测试版本一致的组件目录，路径和 SHA-256 参见 `config/expected-payload.sha256`。将 APK、商店拆分包及其 `lib/arm64-v8a/*.so` 提取到清单中的对应位置；权限 XML 使用 `config/privapp-permissions-google-lsa.xml`。测试版本：

| 组件 | 测试版本 |
| --- | --- |
| Google Services Framework | 14-13361510 |
| Google Play services | 26.40.32，190400-995630914，arm64 |
| Google Play Store | 53.5.48-24，拆分安装包 |

可使用准备脚本自动组装并校验本地安装包，再构建：

```powershell
python prepare-payload.py --gsf "路径\gsf.apk" --gms "路径\gms.apk" --store "路径\store.apkm"
.\build.ps1 -AndroidSdk "路径\Android\Sdk" -JavaRoot "路径\jdk" -Python python
```

也可用 `-Payload "路径\system"` 指定外部目录。构建必须逐文件匹配测试清单；不同版本需重新审查兼容性。输出 `out/GoogleRestore.apk`。

本地 `.signing/` 保存签名密钥，请自行备份、勿上传。自己的签名与 Release 签名不同，不能直接覆盖安装。`test-rollback.py` 生成维护用的隔离撤销测试脚本，不是用户安装步骤。

## 许可

本仓库自行编写的 App、脚本和配置采用 Apache-2.0。Google 组件属于各自权利人，不因打包而变成 Apache-2.0 软件。Release 为本机测试的部署安装包，含对应 Google 组件；本项目不代表 Google 或 HONOR，不承诺其他设备兼容性。参见 `NOTICE`。
