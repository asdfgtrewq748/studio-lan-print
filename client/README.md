工作室局域网打印机：按地址添加
========================

前置：电脑和主机在同一局域网（示例校园网 SSID：`李杨老师学生_5G`，以现场网名为准），主机已开机且打印服务在跑。

安装：

1. 进入 `client/`（或只拷贝这一目录）
2. 双击 `Connect-StudioPrinter.bat`（或 `连接工作室打印机.bat`）
3. 弹出管理员确认时点「是」
4. 装好后，打印机列表里出现配置的显示名。工作室参考默认是 **Studio-HP-LAN**

默认值写在 [`config.json`](config.json)，对应已经跑通的工作室环境，不是唯一可用地址：

- 主机队列示例：HP LaserJet Professional P1108（实际打哪一台由主机 `config.json` 决定）
- 地址：`http://10.4.81.41:8631/ipp/print`
- 显示名：`Studio-HP-LAN`
- 驱动：Windows 自带 **Microsoft IPP Class Driver**，不用另装厂商驱动
- 学校 / 企业 Wi-Fi 常拦组播（mDNS）。设置里搜不到发现名是正常的，用本脚本按地址添加

换一台主机或改了端口 / 发现名时，编辑 `config.json` 的 `host`、`port`、`printerUrl`、`displayName`。`printerUrl` 非空时忽略 `host` 和 `port`。也可以不改文件，把参数传给 bat（管理员提示前后都会保留这些参数）：

```bat
Connect-StudioPrinter.bat -HostIp 192.168.1.20
Connect-StudioPrinter.bat -Port 9000 -DisplayName Lab-Printer
Connect-StudioPrinter.bat -PrinterUrl http://192.168.1.20:8631/ipp/print -DisplayName Lab-Printer
```

带空格的显示名写进 `config.json`。环境变量 `STUDIO_LAN_HOST`、`STUDIO_LAN_PORT`、`STUDIO_LAN_PRINTER_URL`、`STUDIO_LAN_DISPLAY` 也会覆盖文件；直接运行 `Add-StudioPrinter.ps1` 时，当前窗口里的变量有效。用户级环境变量对 bat 的管理员进程同样有效。只在当前 cmd 里 `set` 一下再双击 bat，管理员窗口不一定看得到，这时改 `config.json` 或把参数写在命令行上。

优先级：命令行参数，然后环境变量，然后 `config.json`，最后才是上面的工作室参考默认值。

故障：

- 提示连不上健康检查地址 → 确认同一局域网、主机已开机、服务在跑。工作室参考是 `http://10.4.81.41:8631/health`
- 有打印机但不出纸 → 看主机缺纸 / 卡纸 / 休眠，以及 `%ProgramData%\StudioLanPrint\logs\service.log`

## English

Double-click `Connect-StudioPrinter.bat`. It adds an IPP printer with the Windows **Microsoft IPP Class Driver**.

[`config.json`](config.json) ships the studio reference: `http://10.4.81.41:8631/ipp/print`, display name **Studio-HP-LAN**. Edit `host`, `port`, `printerUrl`, or `displayName` for another host. A non-empty `printerUrl` wins over `host` and `port`. Command-line `-HostIp`, `-Port`, `-PrinterUrl`, and `-DisplayName` override the file and are forwarded across the admin prompt. Put display names that contain spaces in `config.json`.

Environment overrides: `STUDIO_LAN_HOST`, `STUDIO_LAN_PORT`, `STUDIO_LAN_PRINTER_URL`, `STUDIO_LAN_DISPLAY`.

Which physical printer receives the job is chosen on the host (`%ProgramData%\StudioLanPrint\config.json`), not in this client.
