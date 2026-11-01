# StudioLanPrint.ps1 - LAN IPP + mDNS share for a local Windows printer.
# Config: %ProgramData%\StudioLanPrint\config.json (see config.example.json).
# Empty printerName prefers "HP LaserJet Professional P1108", else the first suitable local printer.
# Studio reference: http://10.4.81.41:8631/ipp/print and Studio-HP-LAN._ipp._tcp.local.
# Logs: %ProgramData%\StudioLanPrint\logs\service.log

$ErrorActionPreference = 'Stop'
$script:BaseDir = Join-Path $env:ProgramData 'StudioLanPrint'
$script:JobsDir = Join-Path $script:BaseDir 'jobs'
$script:LogsDir = Join-Path $script:BaseDir 'logs'
$script:LogFile = Join-Path $script:LogsDir 'service.log'
$script:PrinterName = ''
$script:Port = 8631
$script:FallbackLanIp = '10.4.81.41'
$script:JobSeq = 0
# Optional PDF fallback (studio-specific path). Prefer SumatraPDF next to the install.
# Override with env STUDIO_LAN_ACROBAT if you must use Acrobat.
$script:Acrobat = if ($env:STUDIO_LAN_ACROBAT) { $env:STUDIO_LAN_ACROBAT } else { 'E:\Adobe acrobat DC\Acrobat\Acrobat.exe' }
$script:Sumatra = Join-Path $script:BaseDir 'SumatraPDF.exe'
if (-not (Test-Path -LiteralPath $script:Sumatra)) {
    $alt = Join-Path $env:USERPROFILE 'Documents\studio-lan-print\SumatraPDF.exe'
    if (Test-Path -LiteralPath $alt) { $script:Sumatra = $alt }
}
$script:Queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:ServiceInstance = 'Studio-HP-LAN'
$script:MdnsHost = 'studio-hp-lan'
$script:DisplayName = ''
$script:Identity = $null
$script:Mdns = $null
$script:StartTick = [Environment]::TickCount
$script:UuidFile = Join-Path $script:BaseDir 'printer.uuid'

foreach ($d in @($script:BaseDir, $script:JobsDir, $script:LogsDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function Get-PrinterUuid {
    if (Test-Path -LiteralPath $script:UuidFile) {
        $u = (Get-Content -LiteralPath $script:UuidFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($u -match '^urn:uuid:[0-9a-fA-F-]{36}$') { return $u }
    }
    $guid = [guid]::NewGuid().ToString()
    $u = 'urn:uuid:' + $guid
    Set-Content -LiteralPath $script:UuidFile -Value $u -Encoding ASCII -NoNewline
    return $u
}
$script:PrinterUuid = Get-PrinterUuid

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch {}
    Write-Host $line
}

$libCandidates = @()
if ($PSScriptRoot) { $libCandidates += (Join-Path $PSScriptRoot 'StudioLanPrint.Config.ps1') }
$libCandidates += (Join-Path $script:BaseDir 'StudioLanPrint.Config.ps1')
$configLib = $null
foreach ($candidate in $libCandidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { $configLib = $candidate; break }
}
if (-not $configLib) {
    throw 'StudioLanPrint.Config.ps1 not found next to StudioLanPrint.ps1. Re-run Install-StudioLanPrint.ps1.'
}
. $configLib
try {
    $script:Identity = Get-StudioLanPrintIdentity
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    throw
}
$script:PrinterName = [string]$script:Identity.PrinterName
$script:Port = [int]$script:Identity.Port
$script:ServiceInstance = [string]$script:Identity.ServiceInstance
$script:MdnsHost = [string]$script:Identity.MdnsHost
$script:DisplayName = [string]$script:Identity.DisplayName
$script:FallbackLanIp = [string]$script:Identity.FallbackLanIp
$cfgState = if ($script:Identity.ConfigPresent) { 'loaded' } else { 'defaults' }
Write-Log ("config $($script:Identity.ConfigPath) ($cfgState) printer=$($script:PrinterName) source=$($script:Identity.PrinterSource) port=$($script:Port) service=$($script:ServiceInstance) display=$($script:DisplayName)")

function Get-LanIPv4 {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -like '10.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
            Sort-Object -Property SkipAsSource |
            Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch {}
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch {}
    return $script:FallbackLanIp
}

Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

$rawPrintType = @'
using System;
using System.Runtime.InteropServices;
public static class RawPrinterHelper {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public class DOCINFOA {
    [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
  }
  [DllImport("winspool.drv", EntryPoint="OpenPrinterW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);
  [DllImport("winspool.drv", EntryPoint="ClosePrinter", SetLastError=true)]
  public static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="StartDocPrinterW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] DOCINFOA di);
  [DllImport("winspool.drv", EntryPoint="EndDocPrinter", SetLastError=true)]
  public static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="StartPagePrinter", SetLastError=true)]
  public static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="EndPagePrinter", SetLastError=true)]
  public static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="WritePrinter", SetLastError=true)]
  public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);
  public static bool SendBytesToPrinter(string printerName, byte[] bytes, string docName) {
    IntPtr hPrinter = IntPtr.Zero; IntPtr p = IntPtr.Zero; int written = 0; bool ok = false;
    try {
      if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) return false;
      DOCINFOA di = new DOCINFOA(); di.pDocName = docName; di.pDataType = "RAW";
      if (!StartDocPrinter(hPrinter, 1, di)) return false;
      if (!StartPagePrinter(hPrinter)) return false;
      p = Marshal.AllocCoTaskMem(bytes.Length);
      Marshal.Copy(bytes, 0, p, bytes.Length);
      ok = WritePrinter(hPrinter, p, bytes.Length, out written);
      EndPagePrinter(hPrinter); EndDocPrinter(hPrinter);
    } finally {
      if (p != IntPtr.Zero) Marshal.FreeCoTaskMem(p);
      if (hPrinter != IntPtr.Zero) ClosePrinter(hPrinter);
    }
    return ok && written == bytes.Length;
  }
}
'@
if (-not ('RawPrinterHelper' -as [type])) { Add-Type -TypeDefinition $rawPrintType -Language CSharp }

$mdnsType = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public class StudioMdnsPublisher : IDisposable {
  readonly string _logPath;
  readonly string _instance;   // DNS-SD instance label, default Studio-HP-LAN
  readonly string _hostLabel;  // studio-hp-lan
  readonly int _ippPort;
  string _ipv4;
  readonly string[] _txt;
  Socket _sock;
  Thread _thread;
  volatile bool _run;
  readonly object _gate = new object();
  DateTime _lastAnnounce = DateTime.MinValue;
  int _announceSec;
  static readonly IPAddress Mcast = IPAddress.Parse("224.0.0.251");
  static readonly IPEndPoint McastEp = new IPEndPoint(Mcast, 5353);

  public StudioMdnsPublisher(string logPath, string instance, string hostLabel, string ipv4, int ippPort, string[] txt, int announceSec) {
    _logPath = logPath; _instance = instance; _hostLabel = hostLabel; _ipv4 = ipv4;
    _ippPort = ippPort; _txt = txt; _announceSec = announceSec < 30 ? 90 : announceSec;
  }

  public void UpdateIPv4(string ipv4) { if (!string.IsNullOrEmpty(ipv4)) _ipv4 = ipv4; }

  void Log(string msg) {
    try {
      string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " [INFO] " + msg + Environment.NewLine;
      File.AppendAllText(_logPath, line, Encoding.UTF8);
    } catch {}
  }

  static byte[] EncName(string name) {
    var ms = new MemoryStream();
    foreach (var label in name.TrimEnd('.').Split('.')) {
      byte[] b = Encoding.ASCII.GetBytes(label);
      if (b.Length > 63) throw new ArgumentException("label too long");
      ms.WriteByte((byte)b.Length); ms.Write(b, 0, b.Length);
    }
    ms.WriteByte(0);
    return ms.ToArray();
  }

  static byte[] EncTxt(string[] pairs) {
    var ms = new MemoryStream();
    foreach (var s in pairs) {
      byte[] b = Encoding.UTF8.GetBytes(s);
      if (b.Length > 255) continue;
      ms.WriteByte((byte)b.Length); ms.Write(b, 0, b.Length);
    }
    return ms.ToArray();
  }

  static void WriteU16(MemoryStream ms, int v) { ms.WriteByte((byte)((v >> 8) & 0xFF)); ms.WriteByte((byte)(v & 0xFF)); }
  static void WriteU32(MemoryStream ms, int v) {
    ms.WriteByte((byte)((v >> 24) & 0xFF)); ms.WriteByte((byte)((v >> 16) & 0xFF));
    ms.WriteByte((byte)((v >> 8) & 0xFF)); ms.WriteByte((byte)(v & 0xFF));
  }

  static void WriteRR(MemoryStream ms, string owner, int type, int cls, int ttl, byte[] rdata) {
    byte[] on = EncName(owner);
    ms.Write(on, 0, on.Length);
    WriteU16(ms, type); WriteU16(ms, cls); WriteU32(ms, ttl);
    WriteU16(ms, rdata.Length); ms.Write(rdata, 0, rdata.Length);
  }

  byte[] BuildAnnouncement(bool goodbye) {
    string ptrIpp = "_ipp._tcp.local";
    string ptrPrn = "_printer._tcp.local";
    string svc = _instance + "._ipp._tcp.local";
    string svcPrn = _instance + "._printer._tcp.local";
    string host = _hostLabel + ".local";
    int ttl = goodbye ? 0 : 120;
    int ttlTxt = goodbye ? 0 : 4500;
    byte[] ipBytes = IPAddress.Parse(_ipv4).GetAddressBytes();

    var answers = new MemoryStream();
    // PTR _ipp._tcp -> instance
    WriteRR(answers, ptrIpp, 12, 0x0001, ttl, EncName(svc));
    // PTR _printer._tcp -> same instance name under _printer (separate instance label)
    WriteRR(answers, ptrPrn, 12, 0x0001, ttl, EncName(svcPrn));
    // SRV for ipp instance (unique / cache-flush)
    var srv = new MemoryStream();
    WriteU16(srv, 0); WriteU16(srv, 0); WriteU16(srv, _ippPort);
    byte[] hn = EncName(host); srv.Write(hn, 0, hn.Length);
    WriteRR(answers, svc, 33, 0x8001, ttl, srv.ToArray());
    // SRV for printer instance (same port/host)
    var srv2 = new MemoryStream();
    WriteU16(srv2, 0); WriteU16(srv2, 0); WriteU16(srv2, _ippPort);
    srv2.Write(hn, 0, hn.Length);
    WriteRR(answers, svcPrn, 33, 0x8001, ttl, srv2.ToArray());
    // TXT
    byte[] txt = EncTxt(_txt);
    WriteRR(answers, svc, 16, 0x8001, ttlTxt, txt);
    WriteRR(answers, svcPrn, 16, 0x8001, ttlTxt, txt);
    // A
    WriteRR(answers, host, 1, 0x8001, ttl, ipBytes);

    byte[] body = answers.ToArray();
    var pkt = new MemoryStream();
    WriteU16(pkt, 0);       // id
    WriteU16(pkt, 0x8400);  // QR + AA
    WriteU16(pkt, 0);       // qd
    WriteU16(pkt, 7);       // an = 7 records
    WriteU16(pkt, 0); WriteU16(pkt, 0);
    pkt.Write(body, 0, body.Length);
    return pkt.ToArray();
  }

  static string ReadName(byte[] buf, ref int i) {
    var parts = new List<string>();
    int jumps = 0; int save = -1;
    while (i < buf.Length) {
      int len = buf[i++];
      if (len == 0) break;
      if ((len & 0xC0) == 0xC0) {
        if (i >= buf.Length) break;
        int ptr = ((len & 0x3F) << 8) | buf[i++];
        if (save < 0) save = i;
        i = ptr;
        if (++jumps > 20) break;
        continue;
      }
      if (i + len > buf.Length) break;
      parts.Add(Encoding.ASCII.GetString(buf, i, len));
      i += len;
    }
    if (save >= 0) i = save;
    return string.Join(".", parts).ToLowerInvariant();
  }

  bool NameMatches(string q) {
    if (string.IsNullOrEmpty(q)) return false;
    string svc = (_instance + "._ipp._tcp.local").ToLowerInvariant();
    string svcPrn = (_instance + "._printer._tcp.local").ToLowerInvariant();
    string host = (_hostLabel + ".local").ToLowerInvariant();
    if (q == "_ipp._tcp.local" || q == "_printer._tcp.local") return true;
    if (q == svc || q == svcPrn || q == host) return true;
    if (q.EndsWith("._ipp._tcp.local") && q.StartsWith(_instance.ToLowerInvariant())) return true;
    return false;
  }

  byte[] BuildQueryResponse(byte[] query, out bool preferUnicast) {
    preferUnicast = false;
    if (query == null || query.Length < 12) return null;
    int flags = (query[2] << 8) | query[3];
    if ((flags & 0x8000) != 0) return null; // ignore responses
    int qd = (query[4] << 8) | query[5];
    int i = 12;
    bool hit = false;
    for (int qn = 0; qn < qd && i < query.Length; qn++) {
      string name = ReadName(query, ref i);
      if (i + 4 > query.Length) break;
      int typ = (query[i] << 8) | query[i + 1];
      int cls = (query[i + 2] << 8) | query[i + 3];
      i += 4;
      if ((cls & 0x8000) != 0) preferUnicast = true;
      int baseCls = cls & 0x7FFF;
      if (baseCls != 1 && baseCls != 255) continue;
      // PTR 12, SRV 33, TXT 16, A 1, ANY 255
      if (typ == 12 || typ == 33 || typ == 16 || typ == 1 || typ == 255) {
        if (NameMatches(name)) hit = true;
      }
    }
    if (!hit) return null;
    return BuildAnnouncement(false);
  }

  void Send(byte[] pkt, IPEndPoint dest) {
    if (_sock == null || pkt == null) return;
    try { _sock.SendTo(pkt, dest); } catch (Exception ex) { Log("mdns send err: " + ex.Message); }
  }

  void Announce(bool goodbye) {
    byte[] pkt = BuildAnnouncement(goodbye);
    Send(pkt, McastEp);
    // legacy / some stacks: also send a second copy shortly after (caller may sleep)
    _lastAnnounce = DateTime.UtcNow;
    Log(goodbye
      ? ("mdns goodbye " + _instance + " " + _ipv4 + ":" + _ippPort)
      : ("mdns announce " + _instance + "._ipp._tcp.local -> " + _ipv4 + ":" + _ippPort));
  }

  public void Start() {
    lock (_gate) {
      if (_run) return;
      _sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
      _sock.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
      try { _sock.ExclusiveAddressUse = false; } catch {}
      try {
        _sock.Bind(new IPEndPoint(IPAddress.Any, 5353));
        Log("mdns bound UDP 0.0.0.0:5353");
      } catch (Exception ex) {
        // Port busy (Windows mDNS). Bind ephemeral and still multicast announce.
        _sock.Bind(new IPEndPoint(IPAddress.Any, 0));
        var local = (IPEndPoint)_sock.LocalEndPoint;
        Log("mdns 5353 busy (" + ex.Message + "); bound ephemeral UDP " + local.Port + " (announce-only)");
      }
      try {
        _sock.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.AddMembership,
          new MulticastOption(Mcast, IPAddress.Any));
      } catch (Exception ex) { Log("mdns join mcast warn: " + ex.Message); }
      try {
        _sock.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive, 32);
      } catch {}
      try {
        _sock.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastLoopback, true);
      } catch {}
      _run = true;
      _thread = new Thread(Loop) { IsBackground = true, Name = "StudioMdns" };
      _thread.Start();
    }
  }

  void Loop() {
    try {
      // RFC 6762: initial announce, then again ~1s later
      Announce(false);
      Thread.Sleep(1000);
      if (_run) Announce(false);
      byte[] buf = new byte[2048];
      while (_run) {
        try {
          if (_sock.Poll(500000, SelectMode.SelectRead)) { // 0.5s
            EndPoint remote = new IPEndPoint(IPAddress.Any, 0);
            int n = _sock.ReceiveFrom(buf, ref remote);
            if (n > 12) {
              byte[] q = new byte[n];
              Buffer.BlockCopy(buf, 0, q, 0, n);
              bool uni;
              byte[] resp = BuildQueryResponse(q, out uni);
              if (resp != null) {
                IPEndPoint dest = McastEp;
                var r = remote as IPEndPoint;
                if (uni && r != null) dest = r;
                // small random delay 20-120ms to avoid storms
                Thread.Sleep(20 + (Environment.TickCount & 0x5F));
                Send(resp, dest);
                Log("mdns answer -> " + dest + " (" + resp.Length + " bytes)");
              }
            }
          }
        } catch (SocketException) {
          if (!_run) break;
        } catch (Exception ex) {
          if (!_run) break;
          Log("mdns loop err: " + ex.Message);
          Thread.Sleep(500);
        }
        if ((DateTime.UtcNow - _lastAnnounce).TotalSeconds >= _announceSec) {
          Announce(false);
        }
      }
    } catch (Exception ex) {
      Log("mdns thread exit: " + ex.Message);
    }
  }

  public void Stop() {
    lock (_gate) {
      if (!_run) return;
      _run = false;
      try { Announce(true); } catch {}
      try { if (_sock != null) _sock.Close(); } catch {}
      _sock = null;
      try { if (_thread != null && _thread.IsAlive) _thread.Join(2000); } catch {}
      Log("mdns stopped");
    }
  }

  public void Dispose() { Stop(); }
}
'@
if (-not ('StudioMdnsPublisher' -as [type])) { Add-Type -TypeDefinition $mdnsType -Language CSharp }

function Send-RawToPrinter([byte[]]$Bytes, [string]$DocName) {
    $ok = [RawPrinterHelper]::SendBytesToPrinter($script:PrinterName, $Bytes, $DocName)
    if (-not $ok) { throw "RAW print failed for $($script:PrinterName)" }
}

function Send-PdfToPrinter([string]$FilePath) {
    if (-not (Test-Path -LiteralPath $script:Acrobat)) { throw "Acrobat not found: $($script:Acrobat)" }
    $p = Start-Process -FilePath $script:Acrobat -ArgumentList @('/n','/t', $FilePath, $script:PrinterName) -PassThru -WindowStyle Minimized
    $ok = $p.WaitForExit(45000)
    if (-not $ok) {
        Write-Log "Acrobat still running after 45s; leaving job with spooler" 'WARN'
        return
    }
    Write-Log ("Acrobat exit=$($p.ExitCode)")
}

function Send-TextToPrinter([string]$Text, [string]$DocName) {
    $doc = New-Object System.Drawing.Printing.PrintDocument
    $doc.PrinterSettings.PrinterName = $script:PrinterName
    $doc.DocumentName = $DocName
    $script:__printText = $Text
    $doc.add_PrintPage({
        param($sender, $e)
        $font = New-Object System.Drawing.Font 'Consolas',11
        $e.Graphics.DrawString($script:__printText, $font, [System.Drawing.Brushes]::Black, 40, 40)
        $e.HasMorePages = $false
    })
    try { $doc.Print() } finally { $doc.Dispose() }
}

function Find-AttrEnd([byte[]]$Body) {
    $i = 8
    while ($i -lt $Body.Length) {
        $tag = $Body[$i]; $i++
        if ($tag -eq 0x03) { return $i }
        if ($tag -ge 0x01 -and $tag -le 0x05) { continue }
        if ($i + 2 -gt $Body.Length) { break }
        $nlen = ($Body[$i] -shl 8) -bor $Body[$i+1]; $i += 2 + $nlen
        if ($i + 2 -gt $Body.Length) { break }
        $vlen = ($Body[$i] -shl 8) -bor $Body[$i+1]; $i += 2 + $vlen
    }
    return $Body.Length
}

function New-IppResponse([int]$RequestId, [int]$Status, [byte[]]$ExtraGroups) {
    $list = New-Object System.Collections.Generic.List[byte]
    $list.Add(1); $list.Add(1)
    $list.Add([byte](($Status -shr 8) -band 0xFF)); $list.Add([byte]($Status -band 0xFF))
    $list.Add([byte](($RequestId -shr 24) -band 0xFF)); $list.Add([byte](($RequestId -shr 16) -band 0xFF))
    $list.Add([byte](($RequestId -shr 8) -band 0xFF)); $list.Add([byte]($RequestId -band 0xFF))
    $list.Add(0x01)
    # operation attrs: charset + natural-language (required)
    $nb = [Text.Encoding]::ASCII.GetBytes('attributes-charset')
    $vb = [Text.Encoding]::ASCII.GetBytes('utf-8')
    $list.Add(0x47); $list.Add(0); $list.Add([byte]$nb.Length); $list.AddRange($nb)
    $list.Add(0); $list.Add([byte]$vb.Length); $list.AddRange($vb)
    $nb = [Text.Encoding]::ASCII.GetBytes('attributes-natural-language')
    $vb = [Text.Encoding]::ASCII.GetBytes('en')
    $list.Add(0x48); $list.Add(0); $list.Add([byte]$nb.Length); $list.AddRange($nb)
    $list.Add(0); $list.Add([byte]$vb.Length); $list.AddRange($vb)
    if ($ExtraGroups -and $ExtraGroups.Length -gt 0) { $list.AddRange($ExtraGroups) }
    $list.Add(0x03)
    return $list.ToArray()
}

# IPP multi-value: first value carries the name; additional values use name-length 0.
function Add-IppNamed {
    param(
        [System.Collections.Generic.List[byte]]$List,
        [byte]$Tag,
        [string]$Name,
        [byte[]]$ValueBytes
    )
    $nb = [Text.Encoding]::ASCII.GetBytes($Name)
    $List.Add($Tag)
    $List.Add(0); $List.Add([byte]$nb.Length); $List.AddRange($nb)
    $List.Add([byte](($ValueBytes.Length -shr 8) -band 0xFF))
    $List.Add([byte]($ValueBytes.Length -band 0xFF))
    if ($ValueBytes.Length -gt 0) { $List.AddRange($ValueBytes) }
}
function Add-IppMore {
    param(
        [System.Collections.Generic.List[byte]]$List,
        [byte]$Tag,
        [byte[]]$ValueBytes
    )
    $List.Add($Tag)
    $List.Add(0); $List.Add(0)  # name-length 0 = additional value of previous attribute
    $List.Add([byte](($ValueBytes.Length -shr 8) -band 0xFF))
    $List.Add([byte]($ValueBytes.Length -band 0xFF))
    if ($ValueBytes.Length -gt 0) { $List.AddRange($ValueBytes) }
}
function Add-IppText {
    param($List, [byte]$Tag, [string]$Name, [string]$Value)
    Add-IppNamed -List $List -Tag $Tag -Name $Name -ValueBytes ([Text.Encoding]::UTF8.GetBytes($Value))
}
function Add-IppTextMore {
    param($List, [byte]$Tag, [string]$Value)
    Add-IppMore -List $List -Tag $Tag -ValueBytes ([Text.Encoding]::UTF8.GetBytes($Value))
}
function Add-IppInt {
    param($List, [byte]$Tag, [string]$Name, [int]$Value)
    $vb = New-Object byte[] 4
    $vb[0] = [byte](($Value -shr 24) -band 0xFF)
    $vb[1] = [byte](($Value -shr 16) -band 0xFF)
    $vb[2] = [byte](($Value -shr 8) -band 0xFF)
    $vb[3] = [byte]($Value -band 0xFF)
    Add-IppNamed -List $List -Tag $Tag -Name $Name -ValueBytes $vb
}
function Add-IppIntMore {
    param($List, [byte]$Tag, [int]$Value)
    $vb = New-Object byte[] 4
    $vb[0] = [byte](($Value -shr 24) -band 0xFF)
    $vb[1] = [byte](($Value -shr 16) -band 0xFF)
    $vb[2] = [byte](($Value -shr 8) -band 0xFF)
    $vb[3] = [byte]($Value -band 0xFF)
    Add-IppMore -List $List -Tag $Tag -ValueBytes $vb
}
function Add-IppBool {
    param($List, [string]$Name, [bool]$Value)
    $vb = New-Object byte[] 1
    $vb[0] = [byte]$(if ($Value) { 1 } else { 0 })
    Add-IppNamed -List $List -Tag 0x22 -Name $Name -ValueBytes $vb
}

function New-PrinterAttrs {
    $list = New-Object System.Collections.Generic.List[byte]
    $list.Add(0x04)  # printer-attributes-tag
    $lan = Get-LanIPv4
    $port = $script:Port
    $uuid = $script:PrinterUuid
    if (-not $uuid) { $uuid = Get-PrinterUuid; $script:PrinterUuid = $uuid }

    # --- identity / URI ---
    Add-IppText $list 0x42 'printer-name' $script:ServiceInstance
    Add-IppText $list 0x41 'printer-info' $script:Identity.PrinterInfo
    Add-IppText $list 0x41 'printer-location' 'Studio'
    Add-IppText $list 0x41 'printer-make-and-model' $script:Identity.MakeAndModel
    Add-IppText $list 0x45 'printer-uuid' $uuid
    Add-IppText $list 0x41 'printer-device-id' $script:Identity.DeviceId

    Add-IppText $list 0x45 'printer-uri-supported' ("ipp://{0}:{1}/ipp/print" -f $lan, $port)
    Add-IppTextMore $list 0x45 ("http://{0}:{1}/ipp/print" -f $lan, $port)
    Add-IppTextMore $list 0x45 ("ipp://{0}.local:{1}/ipp/print" -f $script:MdnsHost, $port)
    Add-IppTextMore $list 0x45 ("http://{0}.local:{1}/ipp/print" -f $script:MdnsHost, $port)

    Add-IppText $list 0x44 'uri-security-supported' 'none'
    Add-IppText $list 0x44 'uri-authentication-supported' 'none'

    # --- state ---
    Add-IppInt $list 0x23 'printer-state' 3  # idle
    Add-IppText $list 0x44 'printer-state-reasons' 'none'
    Add-IppBool $list 'printer-is-accepting-jobs' $true
    Add-IppInt $list 0x21 'queued-job-count' ([int]$script:Queue.Count)
    $up = [int](([Environment]::TickCount - $script:StartTick) / 1000)
    if ($up -lt 1) { $up = 1 }
    Add-IppInt $list 0x21 'printer-up-time' $up

    # --- protocol ---
    Add-IppText $list 0x44 'ipp-versions-supported' '1.1'
    Add-IppTextMore $list 0x44 '2.0'
    # operations-supported (enum 0x23): Print-Job=2 Validate-Job=4 Cancel-Job=8 Get-Job-Attributes=9 Get-Jobs=10 Get-Printer-Attributes=11
    Add-IppInt $list 0x23 'operations-supported' 2
    Add-IppIntMore $list 0x23 4
    Add-IppIntMore $list 0x23 8
    Add-IppIntMore $list 0x23 9
    Add-IppIntMore $list 0x23 10
    Add-IppIntMore $list 0x23 11

    Add-IppText $list 0x47 'charset-configured' 'utf-8'
    Add-IppText $list 0x47 'charset-supported' 'utf-8'
    Add-IppText $list 0x48 'natural-language-configured' 'en'
    Add-IppText $list 0x48 'generated-natural-language-supported' 'en'

    Add-IppText $list 0x49 'document-format-default' 'application/pdf'
    Add-IppText $list 0x49 'document-format-supported' 'application/pdf'
    Add-IppTextMore $list 0x49 'application/octet-stream'
    Add-IppTextMore $list 0x49 'text/plain'
    Add-IppTextMore $list 0x49 'application/postscript'
    Add-IppTextMore $list 0x49 'image/pwg-raster'

    Add-IppText $list 0x44 'compression-supported' 'none'
    Add-IppText $list 0x44 'pdl-override-supported' 'not-attempted'
    Add-IppText $list 0x44 'multiple-document-handling-supported' 'separate-documents-uncollated-copies'
    Add-IppBool $list 'multiple-document-jobs-supported' $false
    Add-IppInt $list 0x21 'multiple-operation-time-out' 30

    # --- media / finishings (mono host-based) ---
    Add-IppBool $list 'color-supported' $false
    Add-IppText $list 0x44 'print-color-mode-default' 'monochrome'
    Add-IppText $list 0x44 'print-color-mode-supported' 'monochrome'
    Add-IppText $list 0x44 'sides-default' 'one-sided'
    Add-IppText $list 0x44 'sides-supported' 'one-sided'
    Add-IppText $list 0x44 'media-default' 'iso_a4_210x297mm'
    Add-IppText $list 0x44 'media-supported' 'iso_a4_210x297mm'
    Add-IppTextMore $list 0x44 'na_letter_8.5x11in'
    Add-IppInt $list 0x23 'orientation-requested-default' 3  # portrait
    Add-IppInt $list 0x23 'orientation-requested-supported' 3
    Add-IppIntMore $list 0x23 4  # landscape
    Add-IppInt $list 0x21 'copies-default' 1
    Add-IppNamed -List $list -Tag 0x33 -Name 'copies-supported' -ValueBytes ([byte[]]@(0,0,0,1, 0,0,0,99))  # rangeOfInteger 1..99
    Add-IppInt $list 0x23 'finishings-default' 3  # none
    Add-IppInt $list 0x23 'finishings-supported' 3
    Add-IppText $list 0x44 'which-jobs-supported' 'completed'
    Add-IppTextMore $list 0x44 'not-completed'

    return $list.ToArray()
}

# background print worker
$script:Runspace = [runspacefactory]::CreateRunspace()
$script:Runspace.Open()
$script:Runspace.SessionStateProxy.SetVariable('PrinterName', $script:PrinterName)
$script:Runspace.SessionStateProxy.SetVariable('Acrobat', $script:Acrobat)
$script:Runspace.SessionStateProxy.SetVariable('Sumatra', $script:Sumatra)
$script:Runspace.SessionStateProxy.SetVariable('LogFile', $script:LogFile)
$script:Runspace.SessionStateProxy.SetVariable('Queue', $script:Queue)
$psWorker = [powershell]::Create()
$psWorker.Runspace = $script:Runspace
[void]$psWorker.AddScript({
    $ErrorActionPreference = 'Continue'
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $rawPrintType = @'
using System;
using System.Runtime.InteropServices;
public static class RawPrinterHelper2 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public class DOCINFOA {
    [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
  }
  [DllImport("winspool.drv", EntryPoint="OpenPrinterW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);
  [DllImport("winspool.drv", EntryPoint="ClosePrinter", SetLastError=true)]
  public static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="StartDocPrinterW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] DOCINFOA di);
  [DllImport("winspool.drv", EntryPoint="EndDocPrinter", SetLastError=true)]
  public static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="StartPagePrinter", SetLastError=true)]
  public static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="EndPagePrinter", SetLastError=true)]
  public static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", EntryPoint="WritePrinter", SetLastError=true)]
  public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);
  public static bool SendBytesToPrinter(string printerName, byte[] bytes, string docName) {
    IntPtr hPrinter = IntPtr.Zero; IntPtr p = IntPtr.Zero; int written = 0; bool ok = false;
    try {
      if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) return false;
      DOCINFOA di = new DOCINFOA(); di.pDocName = docName; di.pDataType = "RAW";
      if (!StartDocPrinter(hPrinter, 1, di)) return false;
      if (!StartPagePrinter(hPrinter)) return false;
      p = Marshal.AllocCoTaskMem(bytes.Length);
      Marshal.Copy(bytes, 0, p, bytes.Length);
      ok = WritePrinter(hPrinter, p, bytes.Length, out written);
      EndPagePrinter(hPrinter); EndDocPrinter(hPrinter);
    } finally {
      if (p != IntPtr.Zero) Marshal.FreeCoTaskMem(p);
      if (hPrinter != IntPtr.Zero) ClosePrinter(hPrinter);
    }
    return ok && written == bytes.Length;
  }
}
'@
    if (-not ('RawPrinterHelper2' -as [type])) { Add-Type -TypeDefinition $rawPrintType -Language CSharp }
    function WLog($m,$lvl='INFO') {
        $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $lvl, $m
        try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch {}
    }
    while ($true) {
        $item = $null
        if ($Queue.TryDequeue([ref]$item)) {
            try {
                if ($item.Kind -eq 'pdf') {
                    if ($Sumatra -and (Test-Path -LiteralPath $Sumatra)) {
                        $p = Start-Process -FilePath $Sumatra -ArgumentList @('-print-to', $PrinterName, '-silent', '-exit-when-done', $item.Path) -PassThru -WindowStyle Hidden
                        if (-not $p.WaitForExit(120000)) { WLog "Sumatra linger job $($item.Id)" 'WARN'; try { Stop-Process -Id $p.Id -Force } catch {} }
                        else { WLog "Sumatra exit=$($p.ExitCode) job $($item.Id)" }
                    } else {
                        $p = Start-Process -FilePath $Acrobat -ArgumentList @('/n','/t', $item.Path, $PrinterName) -PassThru -WindowStyle Minimized
                        if (-not $p.WaitForExit(45000)) { WLog "Acrobat linger job $($item.Id)" 'WARN' }
                        else { WLog "Acrobat exit=$($p.ExitCode) job $($item.Id)" }
                    }
                } elseif ($item.Kind -eq 'text') {
                    $doc = New-Object System.Drawing.Printing.PrintDocument
                    $doc.PrinterSettings.PrinterName = $PrinterName
                    $doc.DocumentName = $item.DocName
                    $t = $item.Text
                    $doc.add_PrintPage({ param($s,$e) $f=New-Object System.Drawing.Font 'Consolas',11; $e.Graphics.DrawString($t,$f,[System.Drawing.Brushes]::Black,40,40); $e.HasMorePages=$false }.GetNewClosure())
                    try { $doc.Print() } finally { $doc.Dispose() }
                    WLog "text submitted job $($item.Id)"
                } else {
                    $ok = [RawPrinterHelper2]::SendBytesToPrinter($PrinterName, $item.Bytes, $item.DocName)
                    if (-not $ok) { throw 'RAW failed' }
                    WLog "raw submitted job $($item.Id)"
                }
            } catch {
                WLog "submit failed job $($item.Id): $($_.Exception.Message)" 'ERROR'
            }
        } else {
            Start-Sleep -Milliseconds 250
        }
    }
})
$script:WorkerHandle = $psWorker.BeginInvoke()
Write-Log 'print worker started'

# --- mDNS / DNS-SD publisher (background thread inside C#) ---
$script:LanIp = Get-LanIPv4
$txtPairs = @(
    'txtvers=1',
    'qtotal=1',
    'rp=ipp/print',
    ('ty=' + $script:Identity.TxtTy),
    'note=Studio LAN Print',
    ('product=' + $script:Identity.TxtProduct),
    'pdl=application/pdf,text/plain',
    'priority=0',
    ('usb_MFG=' + $script:Identity.UsbMfg),
    ('usb_MDL=' + $script:Identity.UsbMdl),
    ('adminurl=http://{0}:{1}/' -f $script:LanIp, $script:Port),
    'Transparent=F',
    'Binary=T',
    'Color=F'
)
try {
    $script:Mdns = New-Object StudioMdnsPublisher($script:LogFile, $script:ServiceInstance, $script:MdnsHost, $script:LanIp, $script:Port, $txtPairs, 90)
    $script:Mdns.Start()
    Write-Log ("mdns publisher started for {0}._ipp._tcp.local at {1}:{2}" -f $script:ServiceInstance, $script:LanIp, $script:Port)
} catch {
    Write-Log ("mdns start failed: $($_.Exception.Message)" ) 'WARN'
}

function Handle-Ipp([byte[]]$Body) {
    if ($Body.Length -lt 8) { throw 'short IPP' }
    $op = ($Body[2] -shl 8) -bor $Body[3]
    $reqId = ([int]$Body[4] -shl 24) -bor ([int]$Body[5] -shl 16) -bor ([int]$Body[6] -shl 8) -bor [int]$Body[7]
    Write-Log ("IPP op=0x{0:X4} req={1} bytes={2}" -f $op, $reqId, $Body.Length)

    if ($op -eq 0x000B) {
        $resp = New-IppResponse $reqId 0x0000 (New-PrinterAttrs)
        $n = [Math]::Min(24, $resp.Length)
        $hex = ($resp[0..($n-1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        Write-Log ("Get-Printer-Attributes resp={0}B status=0x{1:X4} head={2}" -f $resp.Length, 0, $hex)
        return $resp
    }
    # Validate-Job(4), Cancel-Job(8), Get-Job-Attributes(9), Get-Jobs(10)
    if ($op -eq 0x0004 -or $op -eq 0x0008 -or $op -eq 0x0009 -or $op -eq 0x000A) {
        return (New-IppResponse $reqId 0x0000 $null)
    }
    if ($op -eq 0x0002) {
        $docStart = Find-AttrEnd $Body
        $doc = if ($docStart -lt $Body.Length) { $Body[$docStart..($Body.Length-1)] } else { @() }
        if ($doc.Length -eq 0) { return (New-IppResponse $reqId 0x0400 $null) }
        $script:JobSeq++
        $jid = $script:JobSeq
        $isPdf = ($doc.Length -ge 4 -and $doc[0] -eq 0x25 -and $doc[1] -eq 0x50 -and $doc[2] -eq 0x44 -and $doc[3] -eq 0x46)
        $isText = $false
        if (-not $isPdf) {
            $sample = [Text.Encoding]::UTF8.GetString($doc[0..([Math]::Min(200,$doc.Length-1))])
            if ($sample -notmatch '[\x00-\x08\x0E-\x1F]') { $isText = $true }
        }
        $ext = if ($isPdf) { '.pdf' } elseif ($isText) { '.txt' } else { '.bin' }
        $path = Join-Path $script:JobsDir ("job_{0:000000}{1}" -f $jid, $ext)
        [IO.File]::WriteAllBytes($path, $doc)
        Write-Log ("queued {0} ({1} bytes)" -f $path, $doc.Length)
        $item = [pscustomobject]@{
            Id = $jid
            Kind = $(if ($isPdf) { 'pdf' } elseif ($isText) { 'text' } else { 'raw' })
            Path = $path
            Bytes = $doc
            Text = $(if ($isText) { [Text.Encoding]::UTF8.GetString($doc) } else { $null })
            DocName = ("job-{0}" -f $jid)
        }
        $script:Queue.Enqueue($item)
        $job = New-Object System.Collections.Generic.List[byte]
        $job.Add(0x02)
        $nb=[Text.Encoding]::UTF8.GetBytes('job-id'); $job.Add(0x21); $job.Add(0); $job.Add([byte]$nb.Length); $job.AddRange($nb); $job.Add(0); $job.Add(4)
        $job.Add([byte](($jid -shr 24)-band 0xFF)); $job.Add([byte](($jid -shr 16)-band 0xFF)); $job.Add([byte](($jid -shr 8)-band 0xFF)); $job.Add([byte]($jid -band 0xFF))
        return (New-IppResponse $reqId 0x0000 $job.ToArray())
    }
    return (New-IppResponse $reqId 0x0400 $null)
}

$listener = New-Object System.Net.HttpListener
try {
    $listener.Prefixes.Add("http://+:$($script:Port)/")
    $listener.Start()
} catch {
    Write-Log "bind + failed, trying IP prefixes: $($_.Exception.Message)" 'WARN'
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$($script:Port)/")
    $ip = Get-LanIPv4
    if ($ip) { $listener.Prefixes.Add("http://${ip}:$($script:Port)/") }
    $listener.Start()
}
Write-Log ("listening on port {0}; printer={1}; lan={2}" -f $script:Port, $script:PrinterName, $script:LanIp)

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request; $res = $ctx.Response
        try {
            $path = $req.Url.AbsolutePath.TrimEnd('/')
            if ($req.HttpMethod -eq 'GET' -and ($path -eq '/health' -or $path -eq '/healthz')) {
                $mdnsState = if ($script:Mdns) { 'on' } else { 'off' }
                $json = '{"status":"ok","printer":"' + (ConvertTo-StudioHealthText $script:PrinterName) + '","port":' + $script:Port + ',"queued":' + [int]$script:Queue.Count + ',"lan":"' + (ConvertTo-StudioHealthText $script:LanIp) + '","mdns":"' + $mdnsState + '","service":"' + (ConvertTo-StudioHealthText $script:ServiceInstance) + '","display":"' + (ConvertTo-StudioHealthText $script:DisplayName) + '"}'
                $bytes = [Text.Encoding]::UTF8.GetBytes($json)
                $res.ContentType = 'application/json'; $res.ContentLength64 = $bytes.Length; $res.OutputStream.Write($bytes,0,$bytes.Length)
            } elseif ($req.HttpMethod -eq 'GET') {
                $bytes = [Text.Encoding]::UTF8.GetBytes("Studio LAN Print IPP + mDNS. POST /ipp/print`n")
                $res.ContentType = 'text/plain'; $res.ContentLength64 = $bytes.Length; $res.OutputStream.Write($bytes,0,$bytes.Length)
            } elseif ($req.HttpMethod -eq 'POST' -and ($path -eq '/ipp/print' -or $path -eq '/ipp/printer')) {
                $ms = New-Object IO.MemoryStream
                $req.InputStream.CopyTo($ms)
                $body = $ms.ToArray()
                $out = Handle-Ipp $body
                $res.ContentType = 'application/ipp'; $res.ContentLength64 = $out.Length; $res.OutputStream.Write($out,0,$out.Length)
            } else {
                $res.StatusCode = 404
            }
        } catch {
            Write-Log ("request error: $($_.Exception.Message)") 'ERROR'
            try { $res.StatusCode = 500 } catch {}
        } finally {
            try { $res.OutputStream.Close() } catch {}
            try { $res.Close() } catch {}
        }
    }
} finally {
    try { if ($script:Mdns) { $script:Mdns.Stop() } } catch {}
    $listener.Stop(); $listener.Close()
    Write-Log 'stopped'
}
