# 踩坑记：把工作室 USB 打印机变成「设置里能搜到」的局域网打印机

> 本文记录 studio-lan-print v0.1 在真实校园/工作室环境里跑通的过程。事实优先，不写鸡汤。
>
> 下文里的 P1108、`10.4.81.41` 和 `Studio-HP-LAN` 是当时已经验证的工作室参考环境。当前服务可以把队列、端口和发现名配成其他本机已安装的 Windows 打印机；配置与这些参考值一致时，原来的路径仍然可用。

## 背景

工作室有一台 USB 连接的 **HP LaserJet Professional P1108**，接在一台常开的 Windows 主机上。同学想在自己笔记本上直接打印，不想每次拷文件、也不想装一整套厂商套件。

Windows 自带的「共享打印机」（SMB/打印机共享）在这套网络里并不省心：账号权限、驱动推送、访客 Wi‑Fi、发现失败叠在一起，排查成本高。我们最后做的是：

**在主机上跑一个局域网 IPP 网关（TCP 8631）+ mDNS 广播（Studio-HP-LAN），客户端用系统自带的 Microsoft IPP Class Driver 添加。**

## 误区一：代理软件「占了带宽/端口」

排查初期有人怀疑本机 Clash / FlClash 之类代理影响打印或发现。实测：**代理是否开启与 IPP/mDNS 是否工作基本无关**。打印走的是局域网直连 IP 和组播，不是系统 HTTP 代理路径。把时间花在关代理上，只会延误真正问题。

## 误区二：以为「加了防火墙就够」

HttpListener 监听 `http://+:8631/` 时，Windows 还要求 **URL ACL**（`netsh http add urlacl url=http://+:8631/ user=Everyone`）。只开防火墙、不加 URLACL，会出现「本机 curl 都别扭 / 非提升进程绑不上」一类症状。安装脚本里应同时处理：

- 入站：TCP **8631**（IPP）、UDP **5353**（mDNS）
- URL ACL：`http://+:8631/`

## 为什么不直接用 Windows 打印机共享

简要对比我们踩过的点：

| | 系统共享打印机 | 自建 IPP + mDNS |
|--|----------------|-----------------|
| 客户端驱动 | 常要匹配厂商驱动或 Point-and-Print 策略 | 可用 **IPP Class Driver**，同学机几乎零安装 |
| 发现 | 依赖计算机浏览/WS-Discovery 等，校园网上更碎 | 标准 `_ipp._tcp`，失败时还能用 URL/IP 兜底 |
| 权限 | 共享权限、访客、凭证 | 当前无认证（仅适合受信局域网） |
| 可控性 | 黑盒 | 日志、health、任务落盘都在自己目录 |

对「工作室受信网 + 不想给每人装 HP 驱动」这个目标，IPP 网关更合适。**无认证是有意取舍**：v0.1 假设同一工作室 Wi‑Fi 里的人都可信；上公网或不可信访客网前必须加鉴权，否则谁都能打纸。

## 校园网会杀 mDNS

mDNS 使用 **UDP 5353 → 224.0.0.251**。很多学校/企业 AP 打开了：

- 客户端隔离（client isolation）
- 组播/广播过滤

结果是：服务端日志里明明在 `mdns announce Studio-HP-LAN._ipp._tcp.local`，同学「添加设备」列表里却永远没有它。这不是服务挂了，是**网络策略不允许组播穿越**。

对策：

1. 保留 mDNS——在能通的网络上体验最好（家里、工作室自建 AP）。
2. **必须提供按 IP 添加的客户端脚本**（本仓库 `client/*.bat` → `Add-Printer -IppURL http://10.4.81.41:8631/ipp/print`）。
3. 文档里写清楚：搜不到是正常的，跑 bat。

工作室默认 IP `10.4.81.41` 仍写在 `client/config.json` 里，是为了「零填写」。换网段时改这份配置，或传 `-HostIp` / `-PrinterUrl`，不必改脚本。

## IPP Class Driver 是客户端体验的关键

Windows 10/11 带的 **Microsoft IPP Class Driver** 让同学不必安装 HP 官方包。添加时用 IPP URL（或 mDNS 发现后的同一队列）即可。我们踩过的细节：

- 优先 `Add-Printer -IppURL`；个别系统再用 `-DeviceURL` 兜底。
- 服务端 `Get-Printer-Attributes` 要返回够用的属性（文档格式、颜色、media 等），否则添加成功也可能行为怪异。
- P1108 是主机型（host-based）激光机：服务端收到 PDF 后，在**主机本机队列**上渲染出纸，而不是把原始 PCL 直接扔给对端。

## PDF 怎么出纸：Sumatra 优先，Acrobat 备选

曾用 Acrobat `/t` 静默打印，路径绑死在工作室盘符（如 `E:\Adobe acrobat DC\...`），换机器就碎。后来改为：

1. **SumatraPDF** `-print-to <打印机名> -silent -exit-when-done`（推荐，体积小、行为稳）
2. 找不到 Sumatra 再回退 Acrobat（可用环境变量覆盖路径）

**不要把 Sumatra/Acrobat 可执行文件推进 git**（体积与再分发协议都不合适）。安装说明里写清「自行下载放到 ProgramData」。

## 休眠会让整条链路假死

主机一休眠，USB 打印机、监听端口、mDNS 全停。同学侧表现为「连不上 10.4.81.41」或任务队列卡住。工作室场景建议：

- `powercfg /hibernate off`（仓库提供 `ps/disable-hibernate.ps1`）
- 电源计划避免定时睡眠；或接受「有人打印前先唤醒主机」

磁盘上的 `hiberfil.sys` 占空间是另一回事；对打印可用性来说，**别睡**比省电更重要。

## mDNS 与按 IP 添加的分工

- **mDNS**：零配置、名字好看（Studio-HP-LAN）、换 IP 后（DHCP）仍可能被发现——前提是组播通。
- **按 IP 添加的 bat**：对抗校园网。默认地址仍是工作室参考 `10.4.81.41`；换地址改 `client/config.json` 或参数。

服务端启动时会探测本机局域网 IPv4（偏好 `10.*`），写入 mDNS 通告；客户端 bat 仍指向工作室当前固定地址。两边不一致时，以 bat/文档里的地址为准做连通性检查（`/health`）。

## 生产路径选 PowerShell 的原因

先写过 Python 原型（`studio_lan_print/`，一度默认 631）。真实部署收敛到 **单文件 PowerShell + 内嵌 C# mDNS**：

- 工作室主机不一定有维护良好的 Python 环境
- 安装只要「管理员跑一次 ps1」
- 依赖面更小：HttpListener、winspool、自写 DNS-SD 包

Python 目录仍留在仓库里，标成实验性，避免有人当成正式入口。

## 小结清单（给后来者）

1. 先确认主机本机能打出一页，再谈局域网。  
2. URLACL + 防火墙 + 开机启动一次配齐。  
3. 准备好 SumatraPDF，再开服务。  
4. `/health` 与 `service.log` 是第一诊断面。  
5. 发现失败先怀疑组播策略，立刻试 IP bat。  
6. 关掉休眠。  
7. 不要把无认证 IPP 暴露到不可信网络。  

经验开源在本仓库。主机队列、端口、发现名和客户端地址可以在配置里改；认证和 TLS 仍然不做。
