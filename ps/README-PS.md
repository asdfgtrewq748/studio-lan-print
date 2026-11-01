# Studio LAN Print (PowerShell) — IPP + mDNS

生产路径就是本目录脚本。Python 包 `studio_lan_print/` 仅为实验原型。

## 服务端（工作室电脑）

1. 下载 [SumatraPDF](https://www.sumatrapdfreader.org/) 便携版 `SumatraPDF.exe`，放到 `%ProgramData%\StudioLanPrint\`（或本仓库旁、`Documents\studio-lan-print\`）。**不要**把 exe 提交进 git。
2. 管理员 PowerShell 运行同目录下 `Install-StudioLanPrint.ps1`（或一键 `Deploy-StudioLanPrint-mdns.ps1`）
3. 会复制脚本到 `%ProgramData%\StudioLanPrint\`、加防火墙（TCP 8631 + UDP 5353）、注册 `http://+:8631/` URL ACL、开机启动
4. 健康检查：`http://127.0.0.1:8631/health`（JSON 含 `"mdns":"on"`）
5. 日志：`%ProgramData%\StudioLanPrint\logs\service.log`（应有 `mdns announce Studio-HP-LAN._ipp._tcp.local`）

PDF 渲染优先用 SumatraPDF；若缺失，会回退到本机 Acrobat（默认路径是工作室环境示例，可用环境变量 `STUDIO_LAN_ACROBAT` 覆盖）。

可选：`disable-hibernate.ps1` 关闭休眠，避免主机睡眠后局域网打印全挂。

## 客户端最简添加（自动发现）

同一 Wi-Fi（示例：`李杨老师学生_5G`）下：

1. **设置 → 蓝牙和设备 → 打印机和扫描仪 → 添加设备**
2. 等待列表出现 **Studio-HP-LAN**
3. 点选添加；驱动选 **Microsoft IPP Class Driver**（若提示）

若校园网屏蔽组播、列表里一直没有：

- 双击 `client/连接工作室打印机.bat`（一键按 IP `10.4.81.41` 添加，不依赖发现）
- 或手动 IPP：`http://10.4.81.41:8631/ipp/print`

## 校园网注意

部分 AP 开了客户端隔离 / 组播过滤时，mDNS（UDP 5353 → 224.0.0.251）到不了别的电脑。此时发现失败是网络策略，不是服务挂了——用 bat 即可。

## 停止

结束运行 `StudioLanPrint.ps1` 的 powershell 进程；或删掉 Startup 里的 `StudioLanPrint.lnk` 后注销。
