# studio-lan-print

工作室版 v0.1：一台 Windows 主机把 USB 打印机共享给同一局域网上的其他电脑（IPP + mDNS）。  
Studio edition v0.1: a Windows host shares its USB printer with other PCs on the same LAN (IPP + mDNS).

[中文](#中文) · [English](#english)

---

<a id="readme-zh"></a>

## 中文

工作室有一台常开的 Windows 电脑，USB 接 **HP LaserJet Professional P1108**（本机驱动已装好，能本地出纸）。本仓库是这套环境里已经跑通的 **v0.1**：主机在局域网提供 IPP（默认端口 **8631**），并用 mDNS 广播名称 **Studio-HP-LAN**。同学在自己的电脑上添加这台打印机即可打印。

`10.4.81.41`、端口 8631、打印机型号和发现名，都是**这一版工作室的默认值**。换机房或换网段时，改客户端脚本和文档里的地址。

```text
同学的电脑 -- IPP/HTTP :8631 --> 工作室 Windows 主机 -- USB --> HP P1108
                 mDNS UDP 5353    Studio-HP-LAN._ipp._tcp.local
```

### 使用场景

- **同学在自己的笔记本上直接打到工作室打印机。** 文件留在自己电脑上，不必拷到主机，也不必在每台电脑安装 HP 套件。客户端用 Windows 自带的 **Microsoft IPP Class Driver**。
- **同一 Wi-Fi，组播能通。** 在「添加设备」里选择 **Studio-HP-LAN**。家里或工作室自建 AP 上通常走这条路径。本工作室示例 SSID 是 `李杨老师学生_5G`，以现场网名为准。
- **校园网或企业网拦了组播。** 「添加设备」列表里一直没有 Studio-HP-LAN 是常见情况。改跑 [`client/`](client/) 里的 bat，按工作室 IP 添加同一队列。
- **打印机只接在主机 USB 上。** P1108 是主机型激光机。同学提交的 PDF 在主机本机队列上渲染，再从 USB 出纸。
- **同一受信局域网里的人来打印。** v0.1 没有登录，也没有 TLS。能访问主机 `:8631` 的设备都可以投递任务。公网和不可信的访客网不在这一版的使用范围内。

### 功能

- **IPP 打印服务。** 监听 TCP **8631**，队列地址 `http://<主机IP>:8631/ipp/print`（同时接受 `/ipp/printer`）。Windows 添加打印机和投递任务依赖的 **Get-Printer-Attributes** 与 **Print-Job** 会真正处理；默认文档格式是 PDF。
- **mDNS 发现。** 广播 `Studio-HP-LAN._ipp._tcp.local`（UDP **5353**）。启动时探测本机局域网 IPv4（优先 `10.*`），探测失败时回落到工作室默认 `10.4.81.41`，并写入通告。
- **按 IP 添加。** [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) 与 [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat) 会请求管理员权限，调用 [`client/Add-StudioPrinter.ps1`](client/Add-StudioPrinter.ps1)，把名为 **Studio-HP-LAN** 的打印机加到本机。脚本里的地址是 `http://10.4.81.41:8631/ipp/print`。添加前会先访问 `/health`。
- **主机出纸。** PDF 优先用 **SumatraPDF** 静默打到本机队列 `HP LaserJet Professional P1108`（`-print-to`、`-silent`）。本机没有 Sumatra 时回退 Acrobat，路径用环境变量 `STUDIO_LAN_ACROBAT` 覆盖。可执行文件留在本机，下载位置见 [`vendor/README.md`](vendor/README.md)。
- **安装与保活。** [`ps/Install-StudioLanPrint.ps1`](ps/Install-StudioLanPrint.ps1) 把服务复制到 `%ProgramData%\StudioLanPrint\`，注册 URL ACL `http://+:8631/`、入站防火墙（TCP 8631、UDP 5353），并写入当前用户的开机启动。[`ps/Deploy-StudioLanPrint-mdns.ps1`](ps/Deploy-StudioLanPrint-mdns.ps1) 在此基础上部署并拉起。[`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1) 执行 `powercfg /hibernate off`。主机进入睡眠后打印同样会停，电源计划里不要让它自动睡眠。
- **排查入口。** `http://127.0.0.1:8631/health`（或主机局域网 IP；`/healthz` 相同）返回 JSON，其中 `mdns` 为 `on` 表示发现广播已启动。日志在 `%ProgramData%\StudioLanPrint\logs\service.log`。
- **生产入口是 PowerShell。** 工作室部署使用 [`ps/StudioLanPrint.ps1`](ps/StudioLanPrint.ps1)。[`studio_lan_print/`](studio_lan_print/) 是实验性 Python 原型，默认端口 **631**，留作对照。

### 开始使用

主机是 Windows，USB 打印机已经能本地打印，客户端和主机在同一局域网。安装需要管理员权限（一次）。

**主机**

1. 下载 SumatraPDF 便携版 `SumatraPDF.exe`，放到 `%ProgramData%\StudioLanPrint\`，或 `%USERPROFILE%\Documents\studio-lan-print\`。见 [`vendor/README.md`](vendor/README.md)。
2. 管理员 PowerShell：

```powershell
cd ps
.\Install-StudioLanPrint.ps1
# 部署并拉起：
.\Deploy-StudioLanPrint-mdns.ps1
```

3. 打开 `http://127.0.0.1:8631/health`，确认 JSON 里 `"mdns":"on"`。
4. 主机若会自动休眠，运行 [`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1)。

步骤和停止方法见 [`ps/README-PS.md`](ps/README-PS.md)。

**其他电脑**

- 组播通：**设置 → 蓝牙和设备 → 打印机和扫描仪 → 添加设备** → **Studio-HP-LAN** → 驱动选 **Microsoft IPP Class Driver**。
- 列表里没有：双击 [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) 或 [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat)。说明见 [`client/README.md`](client/README.md)。连不上 `10.4.81.41` 时，先确认同一局域网、主机已开机，以及 `http://10.4.81.41:8631/health` 有响应。

### 这一版的边界

服务面向受信局域网，明文 HTTP，认证方式是 `none`。防火墙放行的是工作室需要的入站端口，并不是访问控制。换 IP 后，mDNS 通告跟着探测结果变；客户端 bat 里的 `10.4.81.41` 要手动改。

校园网组播、URL ACL、休眠，以及为什么不用 Windows 自带的打印机共享，写在 [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md)。

### 目录

| 路径 | 内容 |
|------|------|
| [`ps/`](ps/) | 生产路径：IPP + mDNS 服务、安装、部署、休眠、自检 |
| [`client/`](client/) | 按 IP 添加打印机的 bat / PowerShell |
| [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) | 踩坑记 |
| [`studio_lan_print/`](studio_lan_print/) | 实验性 Python 原型 |
| [`vendor/`](vendor/) | 空目录；SumatraPDF 下载说明 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | v0.1 范围与补丁约定 |

### 许可

[MIT](LICENSE)。版权 2026 Jackey Liu (刘浩天) / asdfgtrewq748。

[English](#english)

---

<a id="readme-en"></a>

## English

A studio Windows PC stays on with a USB **HP LaserJet Professional P1108** (driver installed, local printing already works). This repository is **studio edition v0.1** of that setup: the host serves IPP on the LAN (default port **8631**) and advertises the name **Studio-HP-LAN** over mDNS. Classmates add that printer on their own PCs and print.

`10.4.81.41`, port 8631, the printer model, and the discovery name are **defaults for this studio edition**. On another site or subnet, change the address in the client scripts and in the docs.

```text
classmate PC -- IPP/HTTP :8631 --> studio Windows host -- USB --> HP P1108
                  mDNS UDP 5353    Studio-HP-LAN._ipp._tcp.local
```

### Use cases

- **Print from a classmate’s laptop to the studio printer.** The file stays on their PC. They do not copy it to the host, and they do not install the HP suite. The client uses the built-in **Microsoft IPP Class Driver**.
- **Same Wi-Fi, multicast works.** Pick **Studio-HP-LAN** in Windows “Add device”. That is the usual path on a home network or a studio access point. This studio’s example SSID is `李杨老师学生_5G`; use whatever the room actually broadcasts.
- **Campus or enterprise Wi-Fi filters multicast.** An empty “Add device” list, with no Studio-HP-LAN, is common. Run the bat files in [`client/`](client/) and add the same queue by the studio IP.
- **The printer is USB-only on the host.** The P1108 is a host-based laser printer. PDFs submitted by classmates are rendered on the host’s local queue, then sent out over USB.
- **People on a trusted LAN send jobs.** v0.1 has no login and no TLS. Any device that can reach port `:8631` on the host can submit a job. The public internet and an untrusted guest network are outside this edition’s scope.

### Features

- **IPP print service.** Listens on TCP **8631**. Queue URL: `http://<host-ip>:8631/ipp/print` (also accepts `/ipp/printer`). **Get-Printer-Attributes** and **Print-Job** — the operations Windows uses to add the queue and submit a job — are handled. The default document format is PDF.
- **mDNS discovery.** Announces `Studio-HP-LAN._ipp._tcp.local` (UDP **5353**). On start the service looks up a local LAN IPv4 address (preferring `10.*`). If that lookup fails, it falls back to the studio default `10.4.81.41` and puts that address in the announcement.
- **Add by IP.** [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) and [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat) ask for administrator rights and run [`client/Add-StudioPrinter.ps1`](client/Add-StudioPrinter.ps1), which creates a local printer named **Studio-HP-LAN**. The script’s URL is `http://10.4.81.41:8631/ipp/print`. It checks `/health` before adding.
- **Printing on the host.** PDFs go to **SumatraPDF** first, silent, to the local queue `HP LaserJet Professional P1108` (`-print-to`, `-silent`). If Sumatra is missing, the host falls back to Acrobat; set `STUDIO_LAN_ACROBAT` to that executable’s full path. Keep the binaries on the machine. Download notes: [`vendor/README.md`](vendor/README.md).
- **Install and stay up.** [`ps/Install-StudioLanPrint.ps1`](ps/Install-StudioLanPrint.ps1) copies the service to `%ProgramData%\StudioLanPrint\`, registers the URL ACL `http://+:8631/`, opens inbound firewall rules (TCP 8631, UDP 5353), and adds a startup shortcut for the current user. [`ps/Deploy-StudioLanPrint-mdns.ps1`](ps/Deploy-StudioLanPrint-mdns.ps1) deploys and starts it. [`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1) runs `powercfg /hibernate off`. Sleep stops printing the same way; keep the power plan from sleeping the host.
- **Where to look when it fails.** `http://127.0.0.1:8631/health` (or the host’s LAN IP; `/healthz` is the same) returns JSON. `"mdns":"on"` means the discovery announcement started. Logs: `%ProgramData%\StudioLanPrint\logs\service.log`.
- **PowerShell is the supported deploy.** Studio installs run [`ps/StudioLanPrint.ps1`](ps/StudioLanPrint.ps1). [`studio_lan_print/`](studio_lan_print/) is an experimental Python prototype on default port **631**, kept for reference.

### Get started

The host is Windows, the USB printer already prints locally, and client PCs are on the same LAN. Install needs administrator rights once.

**Host**

1. Download the portable `SumatraPDF.exe` and place it in `%ProgramData%\StudioLanPrint\` or `%USERPROFILE%\Documents\studio-lan-print\`. See [`vendor/README.md`](vendor/README.md).
2. Administrator PowerShell:

```powershell
cd ps
.\Install-StudioLanPrint.ps1
# deploy and start:
.\Deploy-StudioLanPrint-mdns.ps1
```

3. Open `http://127.0.0.1:8631/health` and confirm `"mdns":"on"` in the JSON.
4. If the host hibernates on its own, run [`ps/disable-hibernate.ps1`](ps/disable-hibernate.ps1).

Steps and how to stop the service: [`ps/README-PS.md`](ps/README-PS.md).

**Other PCs**

- Multicast works: **Settings → Bluetooth & devices → Printers & scanners → Add device** → **Studio-HP-LAN** → driver **Microsoft IPP Class Driver**.
- The list stays empty: double-click [`client/Connect-StudioPrinter.bat`](client/Connect-StudioPrinter.bat) or [`client/连接工作室打印机.bat`](client/连接工作室打印机.bat). Notes: [`client/README.md`](client/README.md). If `10.4.81.41` does not answer, check that you are on the same LAN, the host is awake, and `http://10.4.81.41:8631/health` responds.

### Scope of this edition

The service is for a trusted LAN, plain HTTP, authentication `none`. The firewall rules open the inbound ports this studio needs; they are not an access control list. After the host IP changes, the mDNS announcement follows the detected address. The `10.4.81.41` baked into the client bat files has to be edited by hand.

Campus multicast filtering, the URL ACL, hibernate, and why Windows printer sharing was a poor fit here are written up in [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md).

### Layout

| Path | What it is |
|------|------------|
| [`ps/`](ps/) | Supported path: IPP + mDNS service, install, deploy, hibernate, checks |
| [`client/`](client/) | Bat / PowerShell that add the printer by IP |
| [`docs/EXPERIENCE.md`](docs/EXPERIENCE.md) | Pitfalls from the studio rollout |
| [`studio_lan_print/`](studio_lan_print/) | Experimental Python prototype |
| [`vendor/`](vendor/) | Empty in git; where to put SumatraPDF |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | v0.1 scope and patch notes |

### License

[MIT](LICENSE). Copyright 2026 Jackey Liu (刘浩天) / asdfgtrewq748.

[中文](#中文)
