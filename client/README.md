工作室局域网打印机一键安装（studio 版默认）
========================

前置：电脑连上与工作室同一 Wi-Fi（示例校园网 SSID：`李杨老师学生_5G`，以你现场网名为准），工作室电脑开机且打印服务在跑。

安装：
1. 解压本压缩包（或克隆仓库后进入 `client/`）
2. 双击 `Connect-StudioPrinter.bat`（或 `连接工作室打印机.bat`）
3. 弹出管理员确认时点「是」
4. 装好后打印机列表出现 **Studio-HP-LAN**

说明（本仓库 v0.1 工作室默认）：
- 打印机：HP LaserJet Professional P1108（经工作室电脑转发）
- 地址：`http://10.4.81.41:8631/ipp/print`
- 驱动：Windows 自带 **Microsoft IPP Class Driver**，不用另装 HP 驱动
- 学校 / 企业 Wi-Fi 常拦组播（mDNS），设置里搜不到「Studio-HP-LAN」是正常的，用本脚本按 IP 添加即可

故障：
- 提示连不上 `10.4.81.41` → 检查是否同一局域网、工作室电脑是否开机、服务是否在跑（`http://10.4.81.41:8631/health`）
- 有打印机但不出纸 → 看工作室主机缺纸 / 卡纸 / 休眠，以及 `%ProgramData%\StudioLanPrint\logs\service.log`
