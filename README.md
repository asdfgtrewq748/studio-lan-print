# studio-lan-print

**把工作室 USB 打印机变成局域网 IPP 打印机（含 mDNS 发现）**  
*Share a USB printer on your studio Windows PC over LAN via IPP + mDNS — studio edition v0.1.*

本仓库开源的是**已经在工作室跑通的那一版**：主机 USB 接 **HP LaserJet Professional P1108**，对局域网暴露 `http://10.4.81.41:8631/ipp/print`，并用 Bonjour/mDNS 广播 **Studio-HP-LAN**。下一版再做通用配置；当前先把能用的东西交出去。

## 它是什么 / Architecture

```text
[同学的笔记本] --IPP/HTTP--> [工作室 Windows 主机] --USB--> [HP P1108]
                     :8631
                 + mDNS UDP 5353  (Studio-HP-LAN._ipp._tcp.local)
```

- **服务端**：`ps/StudioLanPrint.ps1` 自建轻量 IPP（Print-Job / Get-Printer-Attributes 等）+ 内嵌 mDNS 应答。
- **出纸**：PDF 优先交给 **SumatraPDF** 静默打印到本机队列；没有 Sumatra 时才回退 Acrobat（路径因机器而异）。
- **客户端**：同一局域网下可在「添加打印机」里点 **Studio-HP-LAN**；校园网常拦组播时，改跑 `client/*.bat` 按固定 IP 添加。

## 要求

- 工作室一台 **Windows** 电脑，USB 打印机已在本机装好驱动、能本地打印
- 客户端与主机在**同一局域网**（示例校园网 SSID：`李杨老师学生_5G`，以你现场为准）
- 管理员权限（一次）：URL ACL、防火墙、开机启动
- **不要**把 SumatraPDF / Acrobat 二进制提交进仓库；自行下载后放到 `%ProgramData%\StudioLanPrint\`（见 `vendor/README.md`）

## 服务端安装

管理员 PowerShell：

```powershell
cd ps
# 先把 SumatraPDF.exe 放到 %ProgramData%\StudioLanPrint\ 或 Documents\studio-lan-print\
.\Install-StudioLanPrint.ps1
# 或一键部署并拉起：
.\Deploy-StudioLanPrint-mdns.ps1
```

检查：

- `http://127.0.0.1:8631/health` → JSON 里 `"mdns":"on"`
- 日志：`%ProgramData%\StudioLanPrint\logs\service.log`

可选：`ps/disable-hibernate.ps1` 关掉休眠，避免主机睡死后全班打不了印。

更细的说明见 `ps/README-PS.md`。

## 客户端连接

**优先（mDNS 通的时候）**  
Windows **设置 → 蓝牙和设备 → 打印机和扫描仪 → 添加设备** → 选 **Studio-HP-LAN** → 驱动用 **Microsoft IPP Class Driver**。

**校园网组播被拦时（常见）**  
双击 `client/Connect-StudioPrinter.bat` 或 `client/连接工作室打印机.bat`（会提权，按工作室默认 IP `10.4.81.41` 添加）。说明见 `client/README.md`。

## 免责声明 / Disclaimer

- **仅限受信局域网。** v0.1 **没有认证、没有 TLS**：任何能访问主机 `:8631` 的设备都能投递打印任务。
- 不要暴露到公网 / 访客隔离失败的 Wi‑Fi。
- 工作室默认 IP、打印机型号写死在客户端脚本里；换环境请先改再发。

## 仓库结构

| 路径 | 说明 |
|------|------|
| `ps/` | **生产路径**：IPP+mDNS 服务、安装/部署、自检 |
| `client/` | 一键按 IP 添加打印机 |
| `docs/EXPERIENCE.md` | 踩坑记（可当技术博文） |
| `studio_lan_print/` | **实验性** Python 原型（非生产） |
| `vendor/` | 空目录 + 下载 Sumatra 说明 |

## License

MIT © 2026 Jackey Liu (刘浩天) / asdfgtrewq748 — see `LICENSE`.

相关但不在本包核心：工作室 USB 驱动一键安装可参考旁路仓库/脚本 `StudioHP-Installer-fix`（可选）。
