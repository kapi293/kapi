<#
  上传并发布（kapi 的博客）

  用法：把文件拖到 发布.bat 上（或者双击 发布.bat 后粘贴路径）

  支持的输入：
    .md / .markdown / .txt   -> 当作文章发布（自动补标题、日期，同目录图片一起带走）
    图片 png/jpg/gif/webp/svg -> 当作素材放到 /img/uploads/
    其它任意文件              -> 当作附件放到 /files/
    文件夹                    -> 找里面唯一的 .md 发布

  不想传新文件、只是想重新发布（比如删了文章、改了旧文章）：
    双击 发布.bat，什么都不输直接回车

  发布过程：构建 -> 部署到 GitHub Pages -> 提交源码到 main
#>
param(
  [string]$File,
  [switch]$All,
  [switch]$DryRun,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Step($m) { Write-Host ""; Write-Host ("[>] " + $m) -ForegroundColor Cyan }
function Info($m) { Write-Host ("    " + $m) -ForegroundColor Gray }
function Ok($m)   { Write-Host ("[OK] " + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ("[!] " + $m) -ForegroundColor Yellow }
function Die($m)  {
  Write-Host ("[X] " + $m) -ForegroundColor Red
  if (-not $NoPause) { Write-Host ""; [void](Read-Host "按回车退出") }
  exit 1
}

Write-Host "========================================" -ForegroundColor DarkCyan
Write-Host "  kapi 的博客  ·  上传发布" -ForegroundColor DarkCyan
Write-Host "========================================" -ForegroundColor DarkCyan

# ---------- 1. 收文件 ----------
if (-not $All -and -not $File) {
  Write-Host ""
  Write-Host "  什么都不输直接回车 = 重新发布当前站点（改完/删完文章时用）" -ForegroundColor DarkGray
  $File = Read-Host "把文件拖进来，然后回车"
  if (-not $File) { $All = $true }
}

$item = $null
if (-not $All) {
  $File = $File.Trim().Trim('"').Trim("'")
  if (-not (Test-Path -LiteralPath $File)) { Die "找不到：$File" }

  $item = Get-Item -LiteralPath $File
  if ($item.PSIsContainer) {
    $mds = @(Get-ChildItem -LiteralPath $item.FullName -File |
             Where-Object { $_.Extension -match '^\.(md|markdown|txt)$' })
    if ($mds.Count -eq 0) { Die "这个文件夹里没有 .md 文件" }
    if ($mds.Count -gt 1) {
      Die ("文件夹里有多个文件，请直接拖某一个：" + (($mds | ForEach-Object { $_.Name }) -join ' / '))
    }
    $item = $mds[0]
  }

  $ext = $item.Extension.ToLower()
  $assetDir = $item.DirectoryName
  $kind = 'file'
  if ($ext -match '^\.(md|markdown|txt)$') { $kind = 'article' }
  elseif ($ext -match '^\.(png|jpg|jpeg|gif|webp|svg|ico|bmp)$') { $kind = 'image' }
} else {
  Step "没有指定文件，重新发布当前站点"
  $kind = 'site'
}

$title = ''
$dateVal = Get-Date
$slug = ''
$resultUrl = ''

# ---------- 2a. 文章 ----------
if ($kind -eq 'article') {
  Step "读取文章：$($item.Name)"
  $text = [System.IO.File]::ReadAllText($item.FullName, [System.Text.Encoding]::UTF8)

  $fm = ''
  $body = $text
  if ($text -match '(?s)^\s*---\r?\n(.*?)\r?\n---\r?\n') {
    $fm = $matches[1]
    $body = $text.Substring($matches[0].Length)
  }

  if ($fm -match '(?m)^title:\s*(.+)$') { $title = $matches[1].Trim().Trim('"').Trim("'") }
  if (-not $title) { $title = [IO.Path]::GetFileNameWithoutExtension($item.Name) }

  if ($fm -match '(?m)^date:\s*(.+)$') {
    $tmp = [datetime]::MinValue
    if ([datetime]::TryParse($matches[1].Trim(), [ref]$tmp)) { $dateVal = $tmp }
  }

  $slug = $title
  foreach ($c in [IO.Path]::GetInvalidFileNameChars()) { $slug = $slug.Replace([string]$c, '') }
  $slug = ($slug -replace '\s+', '-').Trim('-')
  if (-not $slug) { $slug = 'post-' + (Get-Date -Format 'yyyyMMddHHmmss') }

  Info "标题：$title"
  Info "日期：$($dateVal.ToString('yyyy-MM-dd HH:mm'))"
  Info "链接名：$slug"

  # 同目录图片一起搬过去
  $imgRel = "img/posts/$slug"
  $imgDir = Join-Path $Root ("source\" + ($imgRel -replace '/', '\'))
  $replacements = @{}
  $pattern = '!\[[^\]]*\]\((?<u>[^)\s]+)|<img[^>]+?src="(?<u>[^"]+)"'
  $refs = @()
  foreach ($m in [regex]::Matches($body, $pattern)) { $refs += $m.Groups['u'].Value }
  foreach ($u in $refs) {
    if ($u -match '^(https?:|//|/|data:|#)') { continue }
    if ($replacements.ContainsKey($u)) { continue }
    $decoded = $u
    try { $decoded = [Uri]::UnescapeDataString($u) } catch { }
    $srcPath = Join-Path $assetDir ($decoded -replace '/', '\')
    if (-not (Test-Path -LiteralPath $srcPath)) {
      $srcPath = Join-Path $assetDir ([IO.Path]::GetFileName($decoded))
    }
    if (Test-Path -LiteralPath $srcPath) {
      if (-not (Test-Path -LiteralPath $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }
      $safeName = ([IO.Path]::GetFileName($srcPath) -replace '\s+', '-')
      Copy-Item -LiteralPath $srcPath -Destination (Join-Path $imgDir $safeName) -Force
      $replacements[$u] = "/$imgRel/$safeName"
      Info "图片：$safeName -> /$imgRel/$safeName"
    } else {
      Warn "引用里的图片没找到：$u"
    }
  }
  foreach ($k in $replacements.Keys) { $body = $body.Replace($k, $replacements[$k]) }

  # 组装 front-matter（保留原有的 category/tags 等，重写 title/date）
  $keep = @()
  if ($fm) {
    $keep = @($fm -split "\r?\n" | Where-Object { $_ -notmatch '^\s*(title|date)\s*:' -and $_.Trim() -ne '' })
  }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('---')
  [void]$sb.AppendLine("title: $title")
  [void]$sb.AppendLine("date: " + $dateVal.ToString('yyyy-MM-dd HH:mm:ss'))
  foreach ($line in $keep) { [void]$sb.AppendLine($line) }
  [void]$sb.AppendLine('---')
  [void]$sb.AppendLine('')
  [void]$sb.Append($body.TrimStart([char[]]@("`r", "`n")))

  $dest = Join-Path $Root "source\_posts\$slug.md"
  if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).FullName -eq $item.FullName)) {
    Info "这个文件已经在 _posts 里了，直接发布当前改动"
  } else {
    [System.IO.File]::WriteAllText($dest, $sb.ToString(), $Utf8NoBom)
    Ok "已放入：source\_posts\$slug.md"
  }

  $resultUrl = "https://kapi403.top/" + $dateVal.ToString('yyyy/MM/dd') + "/$slug/"
}

# ---------- 2b. 图片素材 ----------
elseif ($kind -eq 'image') {
  Step "上传图片：$($item.Name)"
  $dstDir = Join-Path $Root 'source\img\uploads'
  if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
  $safeName = ($item.Name -replace '\s+', '-')
  Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $dstDir $safeName) -Force
  Ok "已放入：source\img\uploads\$safeName"
  Info "文章里这样引用：![](/img/uploads/$safeName)"
  $resultUrl = "https://kapi403.top/img/uploads/$safeName"
}

# ---------- 2c. 其它文件 ----------
elseif ($kind -eq 'file') {
  Step "上传附件：$($item.Name)"
  $dstDir = Join-Path $Root 'source\files'
  if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
  $safeName = ($item.Name -replace '\s+', '-')
  Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $dstDir $safeName) -Force
  Ok "已放入：source\files\$safeName"
  Info "文章里这样链接：[下载](/files/$safeName)"
  $resultUrl = "https://kapi403.top/files/$safeName"
}

# ---------- 3. 构建 ----------
Step "构建站点"
Push-Location $Root
try {
  & npx hexo clean 2>&1 | Out-Null
  $log = & npx hexo generate 2>&1
  if ($LASTEXITCODE -ne 0) {
    $log | Select-Object -Last 25 | ForEach-Object { Write-Host $_ }
    Pop-Location
    Die "构建失败，把上面的报错发我"
  }
  Ok "构建完成"

  if ($DryRun) {
    Step "DryRun：跳过部署和提交"
    Pop-Location
    if (-not $NoPause) { [void](Read-Host "按回车退出") }
    exit 0
  }

  # ---------- 4. 部署 ----------
  Step "部署到 GitHub Pages"
  $dlog = & npx hexo generate --deploy 2>&1
  if ($LASTEXITCODE -ne 0) {
    $dlog | Select-Object -Last 25 | ForEach-Object { Write-Host $_ }
    Pop-Location
    Die "部署失败（检查网络或 GitHub 凭据）"
  }
  Ok "部署完成"

  # ---------- 5. 提交源码 ----------
  Step "提交源码到 main"
  & git add -A
  $msg = 'chore: 更新站点'
  if ($kind -eq 'article') { $msg = "post: $title" }
  elseif ($kind -eq 'image') { $msg = "asset: $($item.Name)" }
  elseif ($kind -eq 'site') { $msg = 'chore: 重新发布站点' }
  else { $msg = "file: $($item.Name)" }

  $cout = & git commit -m $msg 2>&1
  if ($LASTEXITCODE -ne 0) {
    Info "没有新改动，跳过提交"
  } else {
    Ok "已提交：$msg"
  }

  $pout = & git push origin main 2>&1
  if ($LASTEXITCODE -ne 0) {
    Warn "源码推送失败（网络或凭据），网站已更新但源码没同步"
    $pout | Select-Object -Last 5 | ForEach-Object { Write-Host $_ }
  } else {
    Ok "源码已推送"
  }
}
finally {
  try { Pop-Location } catch { }
}

# ---------- 6. 结果 ----------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
if ($kind -eq 'article') { Write-Host "  文章已发布" -ForegroundColor Green }
elseif ($kind -eq 'image') { Write-Host "  图片已上传" -ForegroundColor Green }
elseif ($kind -eq 'site') { Write-Host "  站点已重新发布" -ForegroundColor Green }
else { Write-Host "  文件已上传" -ForegroundColor Green }
if ($resultUrl) {
  Write-Host ""
  Write-Host "  $resultUrl" -ForegroundColor White
  Write-Host "  （GitHub Pages 构建约 1 分钟后生效）" -ForegroundColor DarkGray
}
Write-Host "========================================" -ForegroundColor Green

if (-not $NoPause) { Write-Host ""; [void](Read-Host "按回车关闭") }