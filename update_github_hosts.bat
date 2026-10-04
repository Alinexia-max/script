@echo off
chcp 65001 >nul 2>&1
REM === 自动解析 GitHub 最优 IP 并写入 hosts ===
REM 以管理员身份运行（无权限则自动 UAC 提权）
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
REM 读取本文件尾部 ===PS1=== 之后的 PowerShell 代码（按 UTF-8 读取，保证中文不乱码）并执行
powershell -ExecutionPolicy Bypass -Command "$c=(Get-Content '%~f0' -Raw -Encoding UTF8) -split '===PS1==='; Invoke-Expression $c[-1]"
goto :eof

===PS1===
# 设置控制台输出编码为 UTF-8，避免中文乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$domains = @('github.com','github.global.ssl.fastly.net','assets-cdn.github.com','avatars.githubusercontent.com','gist.github.com','codeload.github.com')
$dnss = @('223.5.5.5','119.29.29.29','8.8.8.8','1.1.1.1')

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   GitHub hosts 自动更新工具' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

function Measure-Latency($ip){
  $c = New-Object System.Net.Sockets.TcpClient
  $c.SendTimeout = 2000; $c.ReceiveTimeout = 2000
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try { $c.Connect($ip, 443); $sw.Stop(); return $sw.Elapsed.TotalSeconds } catch { return $null } finally { $c.Close() }
}

$mapping = @{}
foreach($d in $domains){
  Write-Host ''
  Write-Host ">> 正在检测：$d" -ForegroundColor Yellow
  $ips = @()
  foreach($ns in $dnss){
    try { $r = Resolve-DnsName -Name $d -Type A -Server $ns -ErrorAction SilentlyContinue; if($r){ $ips += $r.IPAddress } } catch {}
  }
  $ips = $ips | Sort-Object -Unique | Where-Object { $_ }
  if($ips.Count -eq 0){ Write-Host '   解析失败，跳过该域名' -ForegroundColor Red; continue }
  Write-Host "   已解析到候选 IP：$($ips -join ', ')"
  $best = $null; $bestLat = $null
  foreach($ip in $ips){
    Write-Host -NoNewline "   正在测速 $ip ... "
    $l = Measure-Latency $ip
    if($l -eq $null){ Write-Host '超时 / 不可达' -ForegroundColor Red; continue }
    Write-Host "延迟 $([math]::Round($l,3)) 秒" -ForegroundColor Gray
    if($bestLat -eq $null -or $l -lt $bestLat){ $best=$ip; $bestLat=$l }
  }
  if($best){ $mapping[$d]=$best; Write-Host "   => 已选择最优 IP：$best（延迟 $([math]::Round($bestLat,3)) 秒）" -ForegroundColor Green } else { Write-Host '   => 未找到可用 IP，跳过' -ForegroundColor Red }
}

if($mapping.Count -gt 0){
  Write-Host ''
  Write-Host '正在更新 hosts 文件...' -ForegroundColor Yellow

  # 读取原内容：读不到就中止，避免把原有记录冲掉
  $lines = $null
  if(Test-Path -LiteralPath $hosts){
    foreach($i in 1..3){
      try { $lines = @([System.IO.File]::ReadAllLines($hosts)); break } catch { Start-Sleep -Milliseconds 300 }
    }
    if($null -eq $lines){ Write-Host 'hosts 正被其他程序占用，无法读取，已放弃本次修改。' -ForegroundColor Red; Read-Host '按回车键退出'; exit 1 }
  } else { $lines = @() }

  # 备份（仅当现有内容非空，避免用空文件覆盖旧备份）
  if((Test-Path -LiteralPath $hosts) -and (Get-Item -LiteralPath $hosts).Length -gt 0){
    Copy-Item -LiteralPath $hosts -Destination ($hosts + '.bak') -Force
    Write-Host '已备份原 hosts 文件到 hosts.bak' -ForegroundColor Gray
  }

  # 剔除本脚本管理的记录（按第 2 列主机名判断）
  $managed = @($mapping.Keys)
  $kept = New-Object System.Collections.Generic.List[string]
  foreach($line in $lines){
    $cols = @($line.Trim() -split '\s+')
    if($line.Trim() -and -not $line.Trim().StartsWith('#') -and $cols.Count -ge 2 -and $managed -contains $cols[1]){ continue }
    $kept.Add($line)
  }

  # 先在内存拼出完整内容，再整体替换，避免“先清空后追加”中途失败把 hosts 写坏
  $out = New-Object System.Collections.Generic.List[string]
  $out.AddRange($kept)
  if($out.Count -gt 0 -and $out[$out.Count - 1].Trim()){ $out.Add('') }
  $out.Add('# === GitHub hosts 自动更新 ===')
  foreach($k in $mapping.Keys){ $out.Add("$($mapping[$k])`t$k") }
  $text = ($out -join "`r`n") + "`r`n"

  # 写到同目录的临时文件后原子替换（Replace 要求同盘，且备份参数不能为 $null，否则报“路径形式不合法”）
  $newFile = $hosts + '.new'
  $swapFile = $hosts + '.swap'
  $lastErr = ''
  $ok = $false
  try {
    [System.IO.File]::WriteAllText($newFile, $text, [System.Text.Encoding]::ASCII)
    foreach($i in 1..5){
      try {
        if(Test-Path -LiteralPath $hosts){ [System.IO.File]::Replace($newFile, $hosts, $swapFile, $true) } else { [System.IO.File]::Move($newFile, $hosts) }
        $ok = $true; break
      } catch { $lastErr = $_.Exception.Message; Start-Sleep -Milliseconds 400 }
    }
  } catch { $lastErr = $_.Exception.Message }
  Remove-Item -LiteralPath $newFile -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $swapFile -Force -ErrorAction SilentlyContinue

  if(-not $ok){
    Write-Host "写入 hosts 失败：$lastErr" -ForegroundColor Red
    Write-Host 'hosts 常被杀毒软件 / 安全软件 / hosts 保护工具占用，请关闭它们后重新运行本脚本。' -ForegroundColor Yellow
    Write-Host 'hosts 原有内容未被破坏。' -ForegroundColor Yellow
    Read-Host '按回车键退出'; exit 1
  }

  Write-Host '已将以下记录写入 hosts：' -ForegroundColor Green
  foreach($k in $mapping.Keys){ Write-Host "   $($mapping[$k])  ->  $k" -ForegroundColor Green }
  ipconfig /flushdns | Out-Null
  Write-Host '已刷新 DNS 缓存' -ForegroundColor Green
  Write-Host ''
  Write-Host '完成！现在可以尝试访问 github.com 验证效果。' -ForegroundColor Cyan
  Write-Host ''
  Write-Host "hosts 文件路径：$hosts" -ForegroundColor Cyan
  Write-Host '---- 当前 hosts 文件内容如下 ----' -ForegroundColor Cyan
  Get-Content -LiteralPath $hosts | ForEach-Object { Write-Host $_ }
} else {
  Write-Host '未获取到任何可用 IP，未修改 hosts 文件。' -ForegroundColor Red
}
Read-Host '按回车键退出'
