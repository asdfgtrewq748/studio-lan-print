# studio-lan-print

一台 Windows 主机把已经装好的本地 USB 打印机共享给同一局域网上的其他电脑（IPP + mDNS）。  
A Windows host shares a locally installed USB printer with other PCs on the same LAN (IPP + mDNS).

[中文](#中文) · [English](#english)

---

<a id="readme-zh"></a>

## 中文

主机是一台常开的 Windows 电脑。USB 打印机的驱动已经装好，本机可以出纸。本仓库在这台电脑上提供 IPP，并用 mDNS 广播一个名字。其他电脑用 Windows 自带的 **Microsoft IPP Class Driver** 添加后即可打印，不必把文件拷到主机，也不必安装厂商套件。

常见的、已经在 Windows 里装好的 USB 打印机都可以这样共享。主机按配置选择本机队列，不把某一种型号写死在脚本里。

`printerName` 写成 `Get-Printer` 里的准确队列名，就固定用这一台。留空则自动选择：本机有 **HP LaserJet Professional P1108** 时优先用它；否则用第一台合适的本地打印机（先看 USB 端口名，再看其他本地非虚拟队列）。一台都选不中时，服务退出，并在日志里列出已安装的打印机。

### 工作室参考环境

下面这组值是已经跑通的工作室环境。配置与此一致（或还没有配置文件、且本机装着 P1108）时，行为和原来的工作室版相同。

- 打印机：HP LaserJet Professional P1108
- IPP 端口：**8631**
- 示例地址：`http://10.4.81.41:8631/ipp/print`
- mDNS：`Studio-HP-LAN._ipp._tcp.local`
- 客户端显示名：**Studio-HP-LAN**
- 示例 SSID：`李杨老师学生_5G`（以现场网名为准）

```text
其他电脑 -- IPP/HTTP :8631 --> Windows 主机 -- 本机队列 --> USB 打印机
              mDNS UDP 5353     <serviceInstance>._ipp._tcp.local
```

P1108 是主机型激光机。同学提交的 PDF 在主机本机队列上渲染，再从 USB 出纸。其他已安装的 USB 打印机走同一条 SumatraPDF 路径：主机上的 Windows 驱动负责真正出纸。

### 使用场景

- **在自己的电脑上打到主机那台打印机。** 文件留在自己电脑上。客户端用 Windows 自带的 **Microsoft IPP Class Driver**。
- **同一 Wi-Fi，组播能通。** 在「添加设备」里选择 mDNS 名字。默认名字是 **Studio-HP-LAN**。家里或工作室自建 AP 上通常走这条路径。
- **校园网或企业网拦了组播。** 「添加设备」列表里一直没有发现名是常见情况。改跑 [`client/`](client/) 里的 bat，按主机 IP 添加同一队列。
- **打印机接在主机上，Windows 里已经能本地打印。** PDF 在主机队列上渲染后出纸。
- **同一受信局域网里的人来打印。** 这一版没有登录，也没有 TLS。能访问主机 IPP 端口的设备都可以投递任务。公网和不可信的访客网不在使用范围内。

### 功能

- **可配置的本机队列。** 配置文件是 `%ProgramData%\StudioLanPrint\config.json`。安装时会放一份起步配置，已有文件不会被覆盖。环境变量可以盖过文件：`STUDIO_LAN_PRINTER`、`STUDIO_LAN_PORT`、`STUDIO_LAN_SERVICE`、`STUDIO_LAN_DISPLAY`、`STUDIO_LAN_FALLBACK_IP`。
- **IPP 打印服务。** 默认监听 TCP **8631**，队列地址 `http://<主机IP>:<端口>/ipp/print`（同时接受 `/ipp/printer`）。Windows 添加打印机和投递任务依赖的 **Get-Printer-Attributes** 与 **Print-Job** 会真正处理；默认文档格式是 PDF。
- **mDNS 发现。** 默认广播 `Studio-HP-LAN._ipp._tcp.local`（UDP **5353**）。`serviceInstance` 改成别的 DNS 标签后，发现名跟着变。启动时探测本机局域网 IPv4（优先 `10.*`），探测失败时回落到 `fallbackLanIp`（默认 `10.4.81.41`）。
- **按 IP 添加。** [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) 与 [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat) 会请求管理员权限，调用 [`client/Add-StudioPrinter.ps1`](client/Add-StudioPrinter.ps1)。仓库里的 [`client/config.json`](client/config.json) 仍是工作室参考地址 `http://10.4.81.41:8631/ipp/print`、显示名 **Studio-HP-LAN**。换主机时改这个文件，或传 `-HostIp` / `-PrinterUrl` / `-DisplayName`。添加前会先访问 `/health`。
- **主机出纸。** PDF 优先用 **SumatraPDF** 静默打到选中的本机队列（`-print-to`、`-silent`、`-exit-when-done`）。本机没有 Sumatra 时回退 Acrobat，路径用环境变量 `STUDIO_LAN_ACROBAT` 覆盖。可执行文件留在本机，下载位置见 [`vendor/README.md`](vendor/README.md)。
- **安装与保活。** [`ps/Install-StudioLanPrint.ps1`](ps/Install-StudioLanPrint.ps1) 把服务复制到 `%ProgramData%\StudioLanPrint\`，写入起步配置，注册 URL ACL，打开入站防火墙（默认 TCP 8631、UDP 5353），并写入当前用户的开机启动。[`ps/Deploy-StudioLanPrint-mdns.ps1`](ps/Deploy-StudioLanPrint-mdns.ps1) 在此基础上部署并拉起。[`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1) 执行 `powercfg /hibernate off`。主机进入睡眠后打印同样会停，电源计划里不要让它自动睡眠。
- **排查入口。** `http://127.0.0.1:8631/health`（或主机局域网 IP；`/healthz` 相同）返回 JSON，其中 `mdns` 为 `on` 表示发现广播已启动，`printer` 是实际队列名。日志在 `%ProgramData%\StudioLanPrint\logs\service.log`。
- **生产入口是 PowerShell。** 部署使用 [`ps/StudioLanPrint.ps1`](ps/StudioLanPrint.ps1)。[`studio_lan_print/`](studio_lan_print/) 是实验性 Python 原型，默认端口 **631**，仍留着最初的 P1108 示例字符串，只作对照。

### 配置

| 字段 | 含义 | 默认 |
|------|------|------|
| `printerName` | Windows 队列名。空则自动选择 | 空 |
| `port` | IPP 端口 | `8631` |
| `serviceInstance` | mDNS 实例名（一个 DNS 标签） | `Studio-HP-LAN` |
| `displayName` | 可选的展示文字。空则用内置文案 | 空 |
| `fallbackLanIp` | 探测不到局域网地址时写入通告 | `10.4.81.41` |

模板：[`ps/config.example.json`](ps/config.example.json)。改完重启服务。改端口后重新运行安装脚本，URL ACL 和防火墙才会更新。开机启动读配置文件，不保留当前窗口里的临时环境变量。

### 开始使用

主机是 Windows，USB 打印机已经能本地打印，客户端和主机在同一局域网。安装需要管理员权限（一次）。

**主机**

1. 下载 SumatraPDF 便携版 `SumatraPDF.exe`，放到 `%ProgramData%\StudioLanPrint\`，或 `%USERPROFILE%\Documents\studio-lan-print\`。见 [`vendor/README.md`](vendor/README.md)。
2. 要固定某一台打印机时，先看队列名：`Get-Printer | Select-Object Name, PortName`。安装后把它写入 `%ProgramData%\StudioLanPrint\config.json` 的 `printerName`。留空则按上面的规则自动选择。
3. 管理员 PowerShell：

```powershell
cd ps
.\Install-StudioLanPrint.ps1
# 部署并拉起：
.\Deploy-StudioLanPrint-mdns.ps1
```

4. 打开 `http://127.0.0.1:8631/health`，确认 JSON 里 `"mdns":"on"`，`printer` 是预期队列。
5. 主机若会自动休眠，运行 [`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1)。

步骤和停止方法见 [`ps/README-PS.md`](ps/README-PS.md)。

**其他电脑**

- 组播通：**设置 → 蓝牙和设备 → 打印机和扫描仪 → 添加设备** → 发现名（工作室参考是 **Studio-HP-LAN**）→ 驱动选 **Microsoft IPP Class Driver**。
- 列表里没有：双击 [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) 或 [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat)。说明见 [`client/README.md`](client/README.md)。工作室参考地址连不上时，先确认同一局域网、主机已开机，以及 `http://10.4.81.41:8631/health` 有响应；换了主机就改 `client/config.json`。

### 这一版的边界

服务面向受信局域网，明文 HTTP，认证方式是 `none`。防火墙放行的是配置里的 IPP 端口和 mDNS，并不是访问控制。换 IP 后，mDNS 通告跟着探测结果变。客户端默认地址在 `client/config.json`，可以用参数覆盖。

校园网组播、URL ACL、休眠，以及为什么不用 Windows 自带的打印机共享，写在 [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md)。

### 目录

| 路径 | 内容 |
|------|------|
| [`ps/`](ps/) | 生产路径：IPP + mDNS 服务、配置、安装、部署、休眠、自检 |
| [`client/`](client/) | 按地址添加打印机的 bat / PowerShell，以及客户端 `config.json` |
| [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) | 踩坑记（含工作室参考环境） |
| [`studio_lan_print/`](studio_lan_print/) | 实验性 Python 原型 |
| [`vendor/`](vendor/) | 空目录；SumatraPDF 下载说明 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | 范围与补丁约定 |

### 许可

[MIT](LICENSE)。版权 2026 Jackey Liu (刘浩天) / asdfgtrewq748。

[English](#english)

---

<a id="readme-en"></a>

## English

The host is a Windows PC that stays on. The USB printer’s driver is installed and local printing already works. This repository serves IPP on the LAN and advertises a name over mDNS. Other PCs add that printer with the built-in **Microsoft IPP Class Driver**. The file stays on their PC, and they do not install a vendor suite.

Common USB printers that Windows already has installed can be shared this way. The host picks the local queue from config instead of a model name hard-coded in the script.

Set `printerName` to the exact queue from `Get-Printer` to pin one. Leave it empty to auto-select: **HP LaserJet Professional P1108** when that queue exists, otherwise the first suitable local printer (lowest USB port name, then any other local non-virtual queue). If none qualifies, the service exits and lists the installed printers.

### Studio reference setup

These values are the setup that was validated in the studio. When config matches them — or when there is no config file and the P1108 queue is installed — behavior matches that original setup.

- Printer: HP LaserJet Professional P1108
- IPP port: **8631**
- Example URL: `http://10.4.81.41:8631/ipp/print`
- mDNS: `Studio-HP-LAN._ipp._tcp.local`
- Client display name: **Studio-HP-LAN**
- Example SSID: `李杨老师学生_5G` (use the name the room actually broadcasts)

```text
other PC -- IPP/HTTP :8631 --> Windows host -- local queue --> USB printer
             mDNS UDP 5353     <serviceInstance>._ipp._tcp.local
```

The P1108 is a host-based laser printer. Submitted PDFs are rendered on the host queue, then sent out over USB. Other installed USB printers use the same SumatraPDF path; the Windows driver on the host performs the device output.

### Use cases

- **Print from another PC to the host’s printer.** The file stays on that PC. The client uses the built-in **Microsoft IPP Class Driver**.
- **Same Wi-Fi, multicast works.** Pick the mDNS name in Windows “Add device”. The default name is **Studio-HP-LAN**. That is the usual path on a home network or a studio access point.
- **Campus or enterprise Wi-Fi filters multicast.** An empty “Add device” list is common. Run the bat files in [`client/`](client/) and add the same queue by the host IP.
- **The printer is installed on the host and already prints locally.** PDFs are rendered on that host queue.
- **People on a trusted LAN send jobs.** This version has no login and no TLS. Any device that can reach the host’s IPP port can submit a job. The public internet and an untrusted guest network are outside this scope.

### Features

- **Configurable local queue.** The file is `%ProgramData%\StudioLanPrint\config.json`. Install writes a starter and does not overwrite an existing file. Environment variables override the file: `STUDIO_LAN_PRINTER`, `STUDIO_LAN_PORT`, `STUDIO_LAN_SERVICE`, `STUDIO_LAN_DISPLAY`, `STUDIO_LAN_FALLBACK_IP`.
- **IPP print service.** Listens on TCP **8631** by default. Queue URL: `http://<host-ip>:<port>/ipp/print` (also accepts `/ipp/printer`). **Get-Printer-Attributes** and **Print-Job** — the operations Windows uses to add the queue and submit a job — are handled. The default document format is PDF.
- **mDNS discovery.** Announces `Studio-HP-LAN._ipp._tcp.local` by default (UDP **5353**). Set `serviceInstance` to another DNS label to change the discovered name. On start the service looks up a local LAN IPv4 address (preferring `10.*`). If that lookup fails, it uses `fallbackLanIp` (default `10.4.81.41`).
- **Add by IP.** [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) and [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat) ask for administrator rights and run [`client/Add-StudioPrinter.ps1`](client/Add-StudioPrinter.ps1). The shipped [`client/config.json`](client/config.json) is still the studio reference `http://10.4.81.41:8631/ipp/print` with display name **Studio-HP-LAN**. For another host, edit that file or pass `-HostIp` / `-PrinterUrl` / `-DisplayName`. The script checks `/health` before adding.
- **Printing on the host.** PDFs go to **SumatraPDF** first, silent, to the selected local queue (`-print-to`, `-silent`, `-exit-when-done`). If Sumatra is missing, the host falls back to Acrobat; set `STUDIO_LAN_ACROBAT` to that executable’s full path. Keep the binaries on the machine. Download notes: [`vendor/README.md`](vendor/README.md).
- **Install and stay up.** [`ps/Install-StudioLanPrint.ps1`](ps/Install-StudioLanPrint.ps1) copies the service to `%ProgramData%\StudioLanPrint\`, writes the starter config, registers the URL ACL, opens inbound firewall rules (TCP 8631 and UDP 5353 by default), and adds a startup shortcut for the current user. [`ps/Deploy-StudioLanPrint-mdns.ps1`](ps/Deploy-StudioLanPrint-mdns.ps1) deploys and starts it. [`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1) runs `powercfg /hibernate off`. Sleep stops printing the same way; keep the power plan from sleeping the host.
- **Where to look when it fails.** `http://127.0.0.1:8631/health` (or the host’s LAN IP; `/healthz` is the same) returns JSON. `"mdns":"on"` means the discovery announcement started. `printer` is the queue actually selected. Logs: `%ProgramData%\StudioLanPrint\logs\service.log`.
- **PowerShell is the supported deploy.** Installs run [`ps/StudioLanPrint.ps1`](ps/StudioLanPrint.ps1). [`studio_lan_print/`](studio_lan_print/) is an experimental Python prototype on default port **631**. It still has the original P1108 sample strings and is kept for reference.

### Config

| Field | Meaning | Default |
|-------|---------|---------|
| `printerName` | Windows queue name. Empty auto-selects | empty |
| `port` | IPP port | `8631` |
| `serviceInstance` | mDNS instance name (one DNS label) | `Studio-HP-LAN` |
| `displayName` | Optional label. Empty uses built-in text | empty |
| `fallbackLanIp` | Address used in announcements when no LAN IPv4 is detected | `10.4.81.41` |

Template: [`ps/config.example.json`](ps/config.example.json). Restart after edits. Re-run the installer after changing the port so the URL ACL and firewall follow. The logon shortcut reads the file; it does not keep a temporary shell variable.

### Get started

The host is Windows, the USB printer already prints locally, and client PCs are on the same LAN. Install needs administrator rights once.

**Host**

1. Download the portable `SumatraPDF.exe` and place it in `%ProgramData%\StudioLanPrint\` or `%USERPROFILE%\Documents\studio-lan-print\`. See [`vendor/README.md`](vendor/README.md).
2. To pin a printer, list queues with `Get-Printer | Select-Object Name, PortName`, then set `printerName` in `%ProgramData%\StudioLanPrint\config.json` after install. Leave it empty to use the auto-select rule above.
3. Administrator PowerShell:

```powershell
cd ps
.\Install-StudioLanPrint.ps1
# deploy and start:
.\Deploy-StudioLanPrint-mdns.ps1
```

4. Open `http://127.0.0.1:8631/health` and confirm `"mdns":"on"` and the expected `printer`.
5. If the host hibernates on its own, run [`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1).

Steps and how to stop the service: [`ps/README-PS.md`](ps/README-PS.md).

**Other PCs**

- Multicast works: **Settings → Bluetooth & devices → Printers & scanners → Add device** → the mDNS name (studio reference: **Studio-HP-LAN**) → driver **Microsoft IPP Class Driver**.
- The list stays empty: double-click [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) or [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat). Notes: [`client/README.md`](client/README.md). If the studio reference address does not answer, check that you are on the same LAN, the host is awake, and `http://10.4.81.41:8631/health` responds. For a different host, edit `client/config.json`.

### Scope of this version

The service is for a trusted LAN, plain HTTP, authentication `none`. The firewall rules open the configured IPP port and mDNS; they are not an access control list. After the host IP changes, the mDNS announcement follows the detected address. The client’s default address lives in `client/config.json` and can be overridden with parameters.

Campus multicast filtering, the URL ACL, hibernate, and why Windows printer sharing was a poor fit here are written up in [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md).

### Layout

| Path | What it is |
|------|------------|
| [`ps/`](ps/) | Supported path: IPP + mDNS service, config, install, deploy, hibernate, checks |
| [`client/`](client/) | Bat / PowerShell that add the printer by address, plus client `config.json` |
| [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) | Pitfalls from the studio rollout, including the reference setup |
| [`studio_lan_print/`](studio_lan_print/) | Experimental Python prototype |
| [`vendor/`](vendor/) | Empty in git; where to put SumatraPDF |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Scope and patch notes |

### License

[MIT](LICENSE). Copyright 2026 Jackey Liu (刘浩天) / asdfgtrewq748.

[中文](#中文)
