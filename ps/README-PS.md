# Studio LAN Print (PowerShell) — IPP + mDNS

生产路径就是本目录脚本。Python 包 `studio_lan_print/` 仅为实验原型（仍带着最初的 P1108 示例字符串）。

任意一台 Windows 已安装、本机能打的本地打印机都可以共享，不限于某一型号。PDF 仍由 SumatraPDF 打到选中的本机队列（没有 Sumatra 时回退 Acrobat）。

## 配置

安装脚本第一次运行时，把 `config.example.json` 复制为：

`%ProgramData%\StudioLanPrint\config.json`

已有的 `config.json` 不会被覆盖。改完要重启服务。改了 `port` 之后再跑一次安装或部署，URL ACL 和防火墙才会跟着变。开机启动项读这个文件，不会保留当前窗口里的临时环境变量。

| 字段 | 默认 | 环境变量（覆盖文件） |
|------|------|----------------------|
| `printerName` | 空，自动选择 | `STUDIO_LAN_PRINTER` |
| `port` | `8631` | `STUDIO_LAN_PORT` |
| `serviceInstance` | `Studio-HP-LAN` | `STUDIO_LAN_SERVICE` |
| `displayName` | 空，用内置文案 | `STUDIO_LAN_DISPLAY` |
| `fallbackLanIp` | `10.4.81.41` | `STUDIO_LAN_FALLBACK_IP` |

`printerName` 必须是 `Get-Printer` 里的队列名。留空时：本机有 **HP LaserJet Professional P1108** 就用它；否则选端口名最小的 USB 本地打印机；再否则选其他本地、非虚拟队列。虚拟打印机（打印到 PDF、XPS、传真、OneNote 等）和远程连接队列不会被自动选中。一台都选不中时，服务退出，并在日志里列出已安装的打印机。写了名字但本机没有这个队列，同样退出并列出打印机，不会偷偷改选。

`serviceInstance` 是 mDNS 实例名，必须是一个 DNS 标签（字母、数字、连字符），例如 `Studio-HP-LAN`。主机名标签是它的小写形式（`studio-hp-lan`）。

### Studio reference

配置与上表默认值一致，且队列是 P1108 时，行为和原来的工作室环境相同：

- IPP `http://<LAN-IP>:8631/ipp/print`（文档里的示例地址是 `http://10.4.81.41:8631/ipp/print`）
- mDNS `Studio-HP-LAN._ipp._tcp.local`
- 探测不到局域网 IPv4 时，通告里的地址回落到 `10.4.81.41`

## English

The installer seeds `%ProgramData%\StudioLanPrint\config.json` from `config.example.json` and does not overwrite an existing file. Set `printerName` to a queue from `Get-Printer`. Leave it empty to prefer **HP LaserJet Professional P1108** when that queue exists, otherwise the first suitable local printer (lowest USB port name, then any other local non-virtual queue). If nothing qualifies, the service exits and lists the installed printers.

Restart after edits. Re-run the installer after changing `port`. The logon shortcut reads the file; a temporary shell variable applies only to a process that inherits it.

Environment overrides: `STUDIO_LAN_PRINTER`, `STUDIO_LAN_PORT`, `STUDIO_LAN_SERVICE`, `STUDIO_LAN_DISPLAY`, `STUDIO_LAN_FALLBACK_IP`.

With the defaults above and the P1108 queue installed, the service matches the validated studio reference: port **8631**, mDNS **Studio-HP-LAN**, fallback address **10.4.81.41**.

## 服务端（主机）

1. 下载 [SumatraPDF](https://www.sumatrapdfreader.org/) 便携版 `SumatraPDF.exe`，放到 `%ProgramData%\StudioLanPrint\`（或 `Documents\studio-lan-print\`）。**不要**把 exe 提交进 git。
2. 需要固定某一台打印机时，先 `Get-Printer | Select-Object Name, PortName`，把名字写入 `config.json` 的 `printerName`。
3. 管理员 PowerShell 运行同目录下 `Install-StudioLanPrint.ps1`（或一键 `Deploy-StudioLanPrint-mdns.ps1`）。
4. 脚本会复制到 `%ProgramData%\StudioLanPrint\`、按配置端口加防火墙（默认 TCP 8631 + UDP 5353）、注册 `http://+:8631/` URL ACL、写入开机启动。
5. 健康检查：`http://127.0.0.1:8631/health`（JSON 含 `"mdns":"on"`，`printer` 是实际队列名）。
6. 日志：`%ProgramData%\StudioLanPrint\logs\service.log`（默认应有 `mdns announce Studio-HP-LAN._ipp._tcp.local`）。

PDF 渲染优先用 SumatraPDF（`-print-to`、`-silent`、`-exit-when-done`）。若缺失，回退到本机 Acrobat（默认路径是工作室环境示例，可用环境变量 `STUDIO_LAN_ACROBAT` 覆盖）。

可选：`disable-hibernate.ps1` 关闭休眠，避免主机睡眠后局域网打印停掉。

## 客户端

同一 Wi-Fi（示例：`李杨老师学生_5G`）下，组播通的时候：

1. **设置 → 蓝牙和设备 → 打印机和扫描仪 → 添加设备**
2. 等待列表出现发现名（工作室参考是 **Studio-HP-LAN**）
3. 点选添加；驱动选 **Microsoft IPP Class Driver**（若提示）

校园网屏蔽组播、列表里一直没有时，用 `client/` 里的 bat 按地址添加。默认地址仍是工作室参考 `http://10.4.81.41:8631/ipp/print`，显示名 **Studio-HP-LAN**。换主机时改 `client/config.json`，或：

```bat
Connect-StudioPrinter.bat -HostIp 192.168.1.20
Connect-StudioPrinter.bat -PrinterUrl http://192.168.1.20:9000/ipp/print -DisplayName Lab-Printer
```

带空格的显示名写进 `client/config.json`。说明见 [`../client/README.md`](../client/README.md)。

## 校园网注意

部分 AP 开了客户端隔离 / 组播过滤时，mDNS（UDP 5353 → 224.0.0.251）到不了别的电脑。此时发现失败是网络策略，不是服务挂了。用 bat 按 IP 添加即可。

## 停止

结束运行 `StudioLanPrint.ps1` 的 powershell 进程；或删掉 Startup 里的 `StudioLanPrint.lnk` 后注销。
