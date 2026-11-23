# ============================================================================
#  拖入自动编号搬运工具   v2.0
#  用法：双击同目录下的 Run.bat（或直接运行本脚本）
#  作者：yunyiawa（AI 辅助生成：DeepSeek Harness）
#  说明：把下载下来的一堆视频拖进命令行窗口，自动按拖入顺序
#        重命名成 1、2、3…… 并移动（或复制）到你选定的文件夹。
#        拖入文件后无需按回车（v2.0 起）。
# ============================================================================
param([switch]$TestMode)

$ErrorActionPreference = 'Stop'

$script:ToolName    = '拖入自动编号搬运工具  v2.0'
$script:ConfigDir   = Join-Path $env:APPDATA 'AutoNumberImport'
$script:ConfigFile  = Join-Path $script:ConfigDir 'config.json'
$script:LogFile     = Join-Path $script:ConfigDir '导入记录.log'

# ============================================================================
#  一、通用小工具
# ============================================================================

function Write-Line {
    param([string]$Text = '', [ConsoleColor]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
}

function Clear-Screen {
    try {
        if (-not [Console]::IsOutputRedirected) { Clear-Host }
    } catch { }
}

function Show-Banner {
    Clear-Screen
    Write-Host ''
    Write-Host '  ================================================================' -ForegroundColor Cyan
    Write-Host '                                                                  ' -ForegroundColor Cyan
    Write-Host '            拖入自动编号搬运工具        v2.0                       ' -ForegroundColor Cyan
    Write-Host '                                                                  ' -ForegroundColor Cyan
    Write-Host '  ================================================================' -ForegroundColor Cyan
    Write-Host ''
}

# 读取一行输入；输入流结束（Ctrl+Z / 管道结束）时返回 $null
#
# 重点：拖文件进窗口时 Windows 只把路径文字塞进输入缓冲、不会带回车。
# 所以真实控制台里用"按键轮询"：字符到达后只要静默一小会儿，就认为这次
# 拖入已经完整，自动当成一行提交 —— 用户拖进来即可，不用按回车。
# 手动输入的命令（go/c/q…）仍然是按回车提交。
# 管道/重定向（自动化测试、被别的程序调用）时自动退回普通逐行读取。
# --------------------------------------------------------------------------
$script:CanRawKeys = $false    # 是否支持按键轮询（真实控制台）
$script:TestKeys   = $null     # 单元测试注入的按键队列

function Initialize-InputMode {
    try {
        if ([Console]::IsInputRedirected) { $script:CanRawKeys = $false; return }
        $null = [Console]::KeyAvailable
        $script:CanRawKeys = $true
    } catch {
        $script:CanRawKeys = $false
    }
}

# 这一行看起来是不是"拖进来的路径"（拖入时 Windows 会自动加双引号）
function Test-DropLikeLine {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $t = $Text.Trim()
    if ($t.IndexOf('"') -ge 0) { return $true }
    if ($t -match '^[A-Za-z]:') { return $true }
    if ($t.StartsWith('\\')) { return $true }
    if ($t.StartsWith('%') -or $t.StartsWith('~')) { return $true }
    return $false
}

function New-KeyInfo {
    param([string]$Ch = '', [bool]$Enter = $false, [bool]$Backspace = $false, [bool]$CtrlC = $false)
    return [pscustomobject]@{ Char = $Ch; IsEnter = $Enter; IsBackspace = $Backspace; IsCtrlC = $CtrlC }
}

# 有按键就返回一个按键对象，没有则返回 $null
function Get-PendingKey {
    if ($null -ne $script:TestKeys) {
        if ($script:TestKeys.Count -eq 0) { return $null }
        $k = $script:TestKeys[0]
        $script:TestKeys.RemoveAt(0)
        return $k
    }
    try {
        if ([Console]::IsInputRedirected) { return $null }
        if (-not [Console]::KeyAvailable) { return $null }
        $rk = [Console]::ReadKey($true)
        return (New-KeyInfo -Ch ([string]$rk.KeyChar) `
            -Enter ($rk.Key -eq [ConsoleKey]::Enter) `
            -Backspace ($rk.Key -eq [ConsoleKey]::Backspace) `
            -CtrlC (($rk.Modifiers -band [ConsoleModifiers]::Control) -and ([int]$rk.KeyChar -eq 3)))
    } catch {
        return $null
    }
}

# 读取"一行"：正常输入按回车提交；拖入的路径静默 IdleMs 毫秒后自动提交
function Read-KeyLine {
    param([string]$Prompt = '', [int]$IdleMs = 450)

    $sb      = New-Object System.Text.StringBuilder
    $echo    = ($null -eq $script:TestKeys)
    $echoBuf = ''
    if ($Prompt -ne '') { Write-Host $Prompt -NoNewline }
    $last = [DateTime]::UtcNow

    while ($true) {
        $k = Get-PendingKey
        if ($null -ne $k) {
            $last = [DateTime]::UtcNow
            if ($k.IsEnter) {
                if ($echo -and $echoBuf -ne '') { Write-Host $echoBuf -NoNewline }
                Write-Host ''
                return $sb.ToString()
            }
            if ($k.IsCtrlC) { throw (New-Object System.OperationCanceledException) }
            if ($k.IsBackspace) {
                if ($sb.Length -gt 0) {
                    [void]$sb.Remove($sb.Length - 1, 1)
                    if ($echo) { Write-Host "`b `b" -NoNewline }
                }
                continue
            }
            $ch = $k.Char
            if ($null -eq $ch -or $ch.Length -eq 0) { continue }
            if ([int][char]$ch[0] -eq 0) { continue }
            [void]$sb.Append($ch)
            $echoBuf += $ch
            if ($echo -and $echoBuf.Length -ge 64) { Write-Host $echoBuf -NoNewline; $echoBuf = '' }
            continue
        }

        if ($echo -and $echoBuf -ne '') { Write-Host $echoBuf -NoNewline; $echoBuf = '' }

        if ($sb.Length -gt 0) {
            $idle = ([DateTime]::UtcNow - $last).TotalMilliseconds
            if ($idle -ge $IdleMs -and (Test-DropLikeLine $sb.ToString())) {
                Write-Host ''
                return $sb.ToString()
            }
        }
        Start-Sleep -Milliseconds 20
    }
}

function Read-Input {
    param([string]$Prompt = '')
    if ($script:CanRawKeys) {
        return (Read-KeyLine -Prompt $Prompt)
    }
    try {
        $v = $null
        if ([string]::IsNullOrEmpty($Prompt)) { $v = Read-Host } else { $v = Read-Host $Prompt }
        if ($null -eq $v) { return $null }
        return [string]$v
    } catch {
        return $null
    }
}

# 一个文本行 -> 若干路径（支持拖入多个文件时 cmd 插入的 "带空格路径" 形式）
function Split-InputPaths {
    param([string]$Line)
    $result = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($Line)) { return @() }
    $s = $Line.Trim()
    $rx = [regex]'"([^"]+)"'
    $ms = $rx.Matches($s)
    if ($ms.Count -gt 0) {
        foreach ($m in $ms) { [void]$result.Add($m.Groups[1].Value) }
        $rest = $rx.Replace($s, ' ').Trim()
        if ($rest -ne '') {
            foreach ($t in ($rest -split '\s+')) { if ($t -ne '') { [void]$result.Add($t) } }
        }
    } else {
        foreach ($t in ($s -split '\s+')) { if ($t -ne '') { [void]$result.Add($t) } }
    }
    return @($result.ToArray())
}

# 去掉引号、展开 %变量%、处理 ~、统一成绝对路径
function ConvertTo-CleanPath {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $p = $Raw.Trim()
    while ($p.Length -ge 2 -and $p.StartsWith('"') -and $p.EndsWith('"')) {
        $p = $p.Substring(1, $p.Length - 2).Trim()
    }
    # 只去掉"成对的"单引号（手打 'C:\x' 的情况）；
    # 不能无脑 Trim("'")，否则名字以撇号结尾的真实路径会被截断。
    if ($p.Length -ge 2 -and $p.StartsWith("'") -and $p.EndsWith("'")) {
        $p = $p.Substring(1, $p.Length - 2).Trim()
    }
    $p = $p.Trim('"').Trim()
    if ($p -eq '') { return $null }
    try { $p = [Environment]::ExpandEnvironmentVariables($p) } catch { }
    if ($p -eq '~') { $p = $env:USERPROFILE }
    elseif ($p.StartsWith('~\') -or $p.StartsWith('~/')) { $p = Join-Path $env:USERPROFILE $p.Substring(2) }
    if ($p.Length -gt 3) { $p = $p.TrimEnd('\', '/') }
    try {
        if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location).ProviderPath $p }
        $p = [IO.Path]::GetFullPath($p)
    } catch {
        return $null
    }
    if ($p -eq '') { return $null }
    return $p
}

function Test-IsDirectory {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    try { return (Test-Path -LiteralPath $Path -PathType Container) } catch { return $false }
}

function Test-IsFile {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $false }
    try { return (Test-Path -LiteralPath $Path -PathType Leaf) } catch { return $false }
}

# 编号格式化：0006 还是 6，由 PadWidth 决定
function Format-Index {
    param([int64]$Number, [int]$PadWidth = 0)
    $s = $Number.ToString([Globalization.CultureInfo]::InvariantCulture)
    if ($PadWidth -gt $s.Length) { $s = $s.PadLeft($PadWidth, '0') }
    return $s
}

# ============================================================================
#  二、配置 / 日志（存在 %APPDATA%\AutoNumberImport\ 下，不污染工具目录）
# ============================================================================

function Get-ToolConfig {
    $cfg = [ordered]@{ Target = ''; Mode = 'Move'; PadWidth = 0 }
    try {
        if (Test-Path -LiteralPath $script:ConfigFile) {
            $raw = Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $j = $raw | ConvertFrom-Json
                if ($j) {
                    if ($j.Target) { $cfg['Target'] = [string]$j.Target }
                    if ($j.Mode -eq 'Copy' -or $j.Mode -eq 'Move') { $cfg['Mode'] = [string]$j.Mode }
                    if ($null -ne $j.PadWidth) {
                        $pw = 0
                        if ([int]::TryParse([string]$j.PadWidth, [ref]$pw) -and $pw -ge 0 -and $pw -le 8) { $cfg['PadWidth'] = $pw }
                    }
                }
            }
        }
    } catch { }
    return $cfg
}

function Save-ToolConfig {
    param($Cfg)
    try {
        if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
            New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        }
        $Cfg | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Add-ToolLog {
    param([string]$Line)
    try {
        if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
            New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        }
        Add-Content -LiteralPath $script:LogFile -Value $Line -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

# ============================================================================
#  三、编号 / 导入核心逻辑
# ============================================================================

# 目标文件夹里已有纯数字文件名（如 7.mp4、12.mov）的最大编号；没有则 0
function Get-MaxUsedNumber {
    param([string]$Directory)
    $max = [int64]0
    if (-not (Test-IsDirectory $Directory)) { return [int64]0 }
    try {
        $files = @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue)
    } catch {
        return [int64]0
    }
    foreach ($f in $files) {
        $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($base -match '^[0-9]{1,9}$') {
            $v = [int64]0
            if ([int64]::TryParse($base, [ref]$v)) {
                if ($v -gt $max) { $max = $v }
            }
        }
    }
    return $max
}

# 真正执行重命名 + 移动/复制。返回每个文件的处理结果。
function Invoke-VideoImport {
    param(
        [string[]]$Sources,
        [string]$Target,
        [int64]$StartNumber = 1,
        [ValidateSet('Move', 'Copy')][string]$Mode = 'Move',
        [int]$PadWidth = 0,
        [switch]$NoLog
    )

    $results = New-Object System.Collections.ArrayList
    $n = $StartNumber

    foreach ($src in @($Sources)) {
        if ([string]::IsNullOrEmpty($src)) { continue }

        if (-not (Test-IsFile $src)) {
            [void]$results.Add([pscustomobject]@{
                Number  = $n
                Name    = ''
                Source  = $src
                Dest    = ''
                Success = $false
                Message = '源文件不存在或已被移动'
            })
            $n++
            continue
        }

        $ext = [IO.Path]::GetExtension($src)

        # 若目标名字已被占用（比如用户手动指定了起始编号），自动往后顺延
        $name = ''
        $dest = ''
        while ($true) {
            $name = (Format-Index -Number $n -PadWidth $PadWidth) + $ext
            $dest = Join-Path $Target $name
            if (-not (Test-Path -LiteralPath $dest)) { break }
            $n++
        }

        $ok  = $false
        $msg = ''
        try {
            if ($Mode -eq 'Copy') {
                Copy-Item -LiteralPath $src -Destination $dest -ErrorAction Stop
            } else {
                Move-Item -LiteralPath $src -Destination $dest -ErrorAction Stop
            }
            $ok = $true
        } catch {
            $msg = $_.Exception.Message
        }

        if (-not $NoLog) {
            $state = 'OK'
            if (-not $ok) { $state = 'FAIL ' + $msg }
            Add-ToolLog ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`t" + $Mode + "`t" + $src + "`t=> `t" + $dest + "`t" + $state)
        }

        [void]$results.Add([pscustomobject]@{
            Number  = $n
            Name    = $name
            Source  = $src
            Dest    = $dest
            Success = $ok
            Message = $msg
        })

        $n++
    }

    return @($results.ToArray())
}

# ============================================================================
#  四、界面各部分
# ============================================================================

# 第 1 步：选目标文件夹（支持拖入文件夹 / 拖入文件取其所在目录 / 自动新建）
function Select-TargetFolder {
    param([string]$DefaultTarget = '')

    while ($true) {
        Write-Line ''
        Write-Line '  [第 1 步] 选择要导入到的文件夹' 'Yellow'
        if (Test-IsDirectory $DefaultTarget) {
            Write-Line ('            上次使用: ' + $DefaultTarget) 'DarkGray'
            Write-Line '            直接回车 = 继续用这个文件夹' 'DarkGray'
        }
        Write-Line '            提示：把文件夹直接拖进本窗口即可（拖进来就会自动读取，不用回车）。' 'DarkGray'
        Write-Line '                  也可以输入路径后回车。' 'DarkGray'

        $raw = Read-Input '            文件夹: '
        if ($null -eq $raw) { return $null }

        $t = $raw.Trim()
        if ($t -eq '') {
            if (Test-IsDirectory $DefaultTarget) { return $DefaultTarget }
            Write-Line '            还没选文件夹，请再试一次（或把文件夹拖进来）。' 'Red'
            continue
        }
        if ($t -ieq 'q' -or $t -ieq 'quit' -or $t -ieq 'exit') { return $null }

        $p = ConvertTo-CleanPath $t
        # 也可能一次拖进来好几个文件：取第一个
        $toks = @(Split-InputPaths $t)
        if ($toks.Count -gt 1) {
            $p2 = ConvertTo-CleanPath $toks[0]
            if ($p2 -and (Test-Path -LiteralPath $p2)) { $p = $p2 }
        }
        if (-not $p) {
            Write-Line '            这个路径无法识别，请再试一次。' 'Red'
            continue
        }

        # 拖进来的是文件 -> 用文件所在的文件夹
        if (Test-IsFile $p) {
            $p = [IO.Path]::GetDirectoryName($p)
            Write-Line ('            你拖入的是文件，已改用它所在的文件夹: ' + $p) 'DarkCyan'
        }

        if (Test-IsDirectory $p) { return $p }

        Write-Line ('            文件夹不存在: ' + $p) 'Yellow'
        $ans = Read-Input '            要新建这个文件夹吗？(y = 新建 / 直接回车 = 重新输入): '
        if ($null -eq $ans) { return $null }
        if ($ans.Trim() -ieq 'y' -or $ans.Trim() -ieq 'yes') {
            try {
                New-Item -ItemType Directory -Path $p -Force -ErrorAction Stop | Out-Null
                Write-Line ('            已新建文件夹: ' + $p) 'Green'
                return (ConvertTo-CleanPath $p)
            } catch {
                Write-Line ('            新建失败: ' + $_.Exception.Message) 'Red'
            }
        }
    }
}

# 第 2 步：起始编号
function Select-StartNumber {
    param([int64]$AutoStart = 1)

    Write-Line ''
    Write-Line '  [第 2 步] 起始编号' 'Yellow'
    Write-Line ('            自动建议: ' + $AutoStart + '（接着目标文件夹里已有的最大编号往后排）') 'DarkGray'

    while ($true) {
        $raw = Read-Input '            直接回车 = 用自动编号；也可以输入其它起始数字: '
        if ($null -eq $raw) { return $null }
        $t = $raw.Trim().Trim('"').Trim()
        if ($t -eq '') { return $AutoStart }
        if ($t -match '^\d{1,9}$') {
            $v = [int64]$t
            if ($v -ge 1) { return $v }
        }
        Write-Line '            请输入一个正整数，例如 1、8、100。' 'Red'
    }
}

# 第 3 步：移动还是复制
function Select-Mode {
    param([string]$Default = 'Move')

    Write-Line ''
    Write-Line '  [第 3 步] 导入方式' 'Yellow'
    Write-Line '            1 = 移动（把文件搬过去，原位置不再保留）' 'DarkGray'
    Write-Line '            2 = 复制（原文件保留，多占一份空间）' 'DarkGray'
    if ($Default -eq 'Copy') {
        Write-Line '            直接回车 = 沿用上次: 复制' 'DarkGray'
    } else {
        Write-Line '            直接回车 = 沿用上次: 移动' 'DarkGray'
    }

    while ($true) {
        $raw = Read-Input '            请选择 [1/2]: '
        if ($null -eq $raw) { return $null }
        $t = $raw.Trim()
        if ($t -eq '') { if ($Default -eq 'Copy') { return 'Copy' } else { return 'Move' } }
        if ($t -eq '1' -or $t -ieq 'move') { return 'Move' }
        if ($t -eq '2' -or $t -ieq 'copy') { return 'Copy' }
        Write-Line '            请输入 1 或 2。' 'Red'
    }
}

function Test-AlreadyInList {
    param($List, [string]$Path)
    foreach ($x in $List) {
        if ([string]::Equals([string]$x, $Path, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# 把一行拖入内容解析后加入列表
function Add-InputToSources {
    param($List, [string]$Raw)

    $text = $Raw.Trim()

    # 手动输入（整行没有双引号）时的处理。拖入的文件 Windows 一定会加双引号，
    # 所以这里只管手打的情况，原则是"宁可提示，也不要导错文件"：
    #   1) 整行本身就是一个存在的路径（带空格路径没加引号）-> 整行当一个路径
    #   2) 按空格拆开后每一段都是真实存在的路径 -> 当成多个路径
    #   3) 都不是 -> 提示加引号，不导入（避免把碰巧存在的片段当成文件）
    if ($text.IndexOf('"') -lt 0 -and $text -match '\s') {
        $whole = ConvertTo-CleanPath $text
        if ($whole -and ((Test-IsFile $whole) -or (Test-IsDirectory $whole))) {
            $tokens = @($text)
        } else {
            $checkTokens = @(Split-InputPaths $Raw)
            $allExist = $checkTokens.Count -gt 0
            foreach ($tk in $checkTokens) {
                $tp = ConvertTo-CleanPath $tk
                if (-not $tp -or -not ((Test-IsFile $tp) -or (Test-IsDirectory $tp))) { $allExist = $false; break }
            }
            if ($allExist) {
                $tokens = $checkTokens
            } else {
                Write-Line ('            找不到这个路径: ' + $text) 'Yellow'
                Write-Line '            如果路径里带空格，请用双引号把整个路径括起来，例如:' 'DarkGray'
                Write-Line '              "D:\我的 视频\第 1 集.mp4"' 'DarkGray'
                return
            }
        }
    } else {
        $tokens = @(Split-InputPaths $Raw)
    }

    if ($tokens.Count -eq 0) {
        Write-Line '            没识别到文件。请从资源管理器把文件拖进本窗口，然后回车。' 'Yellow'
        return
    }

    $added = 0
    $dup   = 0
    foreach ($tok in $tokens) {
        $p = ConvertTo-CleanPath $tok
        if (-not $p) {
            Write-Line ('            [跳过] 无法识别: ' + $tok) 'Yellow'
            continue
        }

        if (Test-IsFile $p) {
            if (Test-AlreadyInList -List $List -Path $p) { $dup++ }
            else { [void]$List.Add($p); $added++ }
            continue
        }

        if (Test-IsDirectory $p) {
            $files = @()
            try { $files = @(Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue | Sort-Object -Property Name) } catch { }
            if ($files.Count -eq 0) {
                Write-Line ('            [跳过] 这个文件夹是空的: ' + $p) 'Yellow'
                continue
            }
            $folderAdded = 0
            foreach ($f in $files) {
                if (Test-AlreadyInList -List $List -Path $f.FullName) { $dup++; continue }
                [void]$List.Add($f.FullName); $added++; $folderAdded++
            }
            $folderDup = $files.Count - $folderAdded
            Write-Line ('            [文件夹] ' + $p + '  ->  新加入 ' + $folderAdded + ' 个，重复 ' + $folderDup + ' 个') 'DarkCyan'
            continue
        }

        Write-Line ('            [跳过] 找不到这个文件: ' + $p) 'Yellow'
    }

    if ($added -gt 0) { Write-Line ('            已加入 ' + $added + ' 个文件，当前共 ' + $List.Count + ' 个。') 'Green' }
    if ($dup -gt 0)   { Write-Line ('            有 ' + $dup + ' 个重复文件已忽略。') 'DarkYellow' }
}

# 显示当前列表 + 重命名预览
function Show-SourceList {
    param($List, [string]$Target, [int64]$StartNumber, [string]$Mode, [int]$PadWidth)

    $modeText = '移动'
    if ($Mode -eq 'Copy') { $modeText = '复制' }

    Write-Line ''
    Write-Line '  --------------------------------------------------------------' 'DarkGray'
    Write-Line ('    导入到   : ' + $Target) 'White'
    Write-Line ('    方式     : ' + $modeText + '        起始编号: ' + (Format-Index -Number $StartNumber -PadWidth $PadWidth)) 'White'
    if ($List.Count -eq 0) {
        Write-Line '    已加入   : 0 个文件' 'DarkGray'
    } else {
        Write-Line ('    已加入   : ' + $List.Count + ' 个文件（重命名预览如下）') 'Green'
        $i = 0
        foreach ($f in $List) {
            $i++
            $newName = (Format-Index -Number ($StartNumber + $i - 1) -PadWidth $PadWidth) + [IO.Path]::GetExtension($f)
            Write-Line ('      {0,3}) {1}    ==>    {2}' -f $i, [IO.Path]::GetFileName($f), $newName) 'Gray'
        }
    }
    Write-Line '  --------------------------------------------------------------' 'DarkGray'
}

# 第 4 步：收集文件
function Read-SourceList {
    param([string]$Target, [int64]$StartNumber, [string]$Mode, [int]$PadWidth)

    $list = New-Object System.Collections.ArrayList

    Write-Line ''
    Write-Line '  [第 4 步] 把视频拖进这个窗口' 'Yellow'
    Write-Line '       · 从资源管理器（或下载目录）选中文件，直接拖到本窗口即可，不用按回车。' 'DarkGray'
    Write-Line '       · 可以分好几批拖；编号顺序 = 你拖入的先后顺序。' 'DarkGray'
    Write-Line '       · 拖入文件夹 = 按文件名顺序加入该文件夹里的所有文件。' 'DarkGray'
    Write-Line '       · 命令（输完按回车）:  go = 开始导入   c = 清空重来   b = 返回上一步   q = 退出' 'DarkGray'

    while ($true) {
        Show-SourceList -List $list -Target $Target -StartNumber $StartNumber -Mode $Mode -PadWidth $PadWidth

        $raw = Read-Input '   拖入文件 / 输入命令: '
        if ($null -eq $raw) { return @{ Action = 'Quit' } }

        $t = $raw.Trim()
        if ($t -eq '') { continue }
        $lower = $t.ToLowerInvariant()

        if ($lower -eq 'go' -or $lower -eq 'g' -or $lower -eq '开始' -or $lower -eq 's') {
            if ($list.Count -eq 0) {
                Write-Line '            列表里还没有文件。' 'Yellow'
                continue
            }
            return @{ Action = 'Go'; Items = @($list.ToArray()) }
        }
        if ($lower -eq 'q' -or $lower -eq 'quit' -or $lower -eq 'exit') { return @{ Action = 'Quit' } }
        if ($lower -eq 'b' -or $lower -eq 'back') { return @{ Action = 'Back' } }
        if ($lower -eq 'c' -or $lower -eq 'clear') {
            $list.Clear()
            Write-Line '            已清空列表。' 'DarkYellow'
            continue
        }
        if ($lower -eq 'l' -or $lower -eq 'list') { continue }

        Add-InputToSources -List $list -Raw $raw
    }
}

# 第 5 步：执行并汇报
function Invoke-ImportUi {
    param([string[]]$Sources, [string]$Target, [int64]$StartNumber, [string]$Mode, [int]$PadWidth)

    Write-Line ''
    Write-Line '  开始导入 ...' 'Cyan'

    $results = @(Invoke-VideoImport -Sources $Sources -Target $Target -StartNumber $StartNumber -Mode $Mode -PadWidth $PadWidth)

    $ok   = 0
    $fail = 0
    foreach ($r in $results) {
        if ($r.Success) {
            $ok++
            Write-Line ('    [完成] ' + [IO.Path]::GetFileName($r.Source) + '   -->   ' + [IO.Path]::GetFileName($r.Dest)) 'Green'
        } else {
            $fail++
            Write-Line ('    [失败] ' + [IO.Path]::GetFileName($r.Source) + '   ' + $r.Message) 'Red'
        }
    }

    Write-Line ''
    $color = 'Green'
    if ($fail -gt 0) { $color = 'Yellow' }
    Write-Line ('  导入结束：成功 ' + $ok + ' 个，失败 ' + $fail + ' 个。') $color
    if ($fail -gt 0) {
        Write-Line ('  失败原因已记录到: ' + $script:LogFile) 'DarkGray'
        Write-Line '  常见原因：文件还在被其他程序占用，或文件已被删除。' 'DarkGray'
    }
    Write-Line ''
}

# ============================================================================
#  五、主流程
# ============================================================================

function Start-VideoImportTool {
    try { $Host.UI.RawUI.WindowTitle = $script:ToolName } catch { }
    Initialize-InputMode

    $cfg    = Get-ToolConfig
    $target = [string]$cfg['Target']
    $mode   = [string]$cfg['Mode']
    $pad    = [int]$cfg['PadWidth']

    while ($true) {
        Show-Banner

        # 1) 目标文件夹
        $target = Select-TargetFolder -DefaultTarget $target
        if ($null -eq $target) { return }

        # 2) 起始编号
        $autoStart = (Get-MaxUsedNumber -Directory $target) + 1
        $start = Select-StartNumber -AutoStart $autoStart
        if ($null -eq $start) { continue }

        # 3) 移动 / 复制
        $mode = Select-Mode -Default $mode
        if ($null -eq $mode) { continue }

        # 4) 收集文件
        $collect = Read-SourceList -Target $target -StartNumber $start -Mode $mode -PadWidth $pad
        if ($collect.Action -eq 'Quit') { return }
        if ($collect.Action -eq 'Back') { continue }

        # 5) 执行
        Invoke-ImportUi -Sources $collect.Items -Target $target -StartNumber $start -Mode $mode -PadWidth $pad

        # 6) 记住这次的选择，下次少填几步
        try {
            $cfg['Target'] = $target
            $cfg['Mode']   = $mode
            Save-ToolConfig -Cfg $cfg
        } catch { }

        # 7) 继续下一批？
        $ans = Read-Input '  按回车继续处理下一批（o = 打开目标文件夹，q = 退出）: '
        if ($null -eq $ans) { return }
        $ans = $ans.Trim()
        if ($ans -ieq 'q') { return }
        if ($ans -ieq 'o') {
            try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $target + '"') } catch { }
        }
    }
}

if (-not $TestMode) {
    try {
        Start-VideoImportTool
    } catch [System.OperationCanceledException] {
        Write-Host ''
        Write-Host '  已取消。' -ForegroundColor DarkGray
        Write-Host ''
    } catch {
        Write-Host ''
        Write-Host ('  程序出错: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host ('  出错位置: ' + $_.InvocationInfo.PositionMessage) -ForegroundColor DarkGray
        Write-Host ''
    }
}
