[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Попытка переключить кодовую страницу на UTF-8 (если не ISE)
if ($host.Name -notlike '*ISE*') {
    try { chcp 65001 | Out-Null } catch {}
}

[Console]::TreatControlCAsInput = $true

$Grid = @()
$SelX = 0
$SelY = 0
$HasSelection = $false
$StartX = 0
$StartY = 0
$Turn = 'White'
$ValidMoves = @()
$Status = ''

# Сетевые переменные
$NetworkMode = $false
$IsServer = $false
$IsClient = $false
$TcpListener = $null
$TcpClient = $null
$NetworkStream = $null
$LocalColor = $null
$RemoteColor = $null
$LastPromotion = $null

function Init-Grid {
    $script:Grid = @()
    for ($y = 0; $y -lt 8; $y++) {
        $row = @()
        for ($x = 0; $x -lt 8; $x++) {
            $row += $null
        }
        $script:Grid += ,$row
    }
    
    $major = 'Rook','Knight','Bishop','Queen','King','Bishop','Knight','Rook'
    for ($i = 0; $i -lt 8; $i++) {
        $script:Grid[0][$i] = @{ Type=$major[$i]; Color='Black'; X=$i; Y=0 }
        $script:Grid[1][$i] = @{ Type='Pawn'; Color='Black'; X=$i; Y=1 }
        $script:Grid[6][$i] = @{ Type='Pawn'; Color='White'; X=$i; Y=6 }
        $script:Grid[7][$i] = @{ Type=$major[$i]; Color='White'; X=$i; Y=7 }
    }
}

function Get-Symbol($piece) {
    if (!$piece) { return ' ' }
    $s = @{
        'White' = @{ King='K'; Queen='Q'; Rook='R'; Bishop='B'; Knight='N'; Pawn='P' }
        'Black' = @{ King='K'; Queen='Q'; Rook='R'; Bishop='B'; Knight='N'; Pawn='P' }
    }
    return $s[$piece.Color][$piece.Type]
}

function Test-ValidMove($x1, $y1, $x2, $y2, $ignoreCheck) {
    $p = $script:Grid[$y1][$x1]
    $target = $script:Grid[$y2][$x2]
    if (!$p) { return $false }
    # Проверка цвета: при ignoreCheck=$true разрешаем любую фигуру (для определения шаха)
    if (!$ignoreCheck -and $p.Color -ne $script:Turn) { return $false }
    if ($target -and $target.Color -eq $p.Color) { return $false }
    if ($x1 -eq $x2 -and $y1 -eq $y2) { return $false }

    $dx = $x2 - $x1
    $dy = $y2 - $y1
    $absDx = [Math]::Abs($dx)
    $absDy = [Math]::Abs($dy)
    $dir = if ($p.Color -eq 'White') { -1 } else { 1 }

    switch ($p.Type) {
        'Pawn' {
            if ($dx -eq 0) {
                if ($dy -eq $dir -and !$target) { return $true }
                if (($y1 -eq 1 -or $y1 -eq 6) -and $dy -eq 2 * $dir -and !$target) {
                    $midY = $y1 + $dir
                    if (!$script:Grid[$midY][$x1]) { return $true }
                }
            }
            if ($absDx -eq 1 -and $dy -eq $dir -and $target) { return $true }
            return $false
        }
        'Knight' {
            if ($absDx * $absDy -eq 2) {
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'King' {
            if ($absDx -le 1 -and $absDy -le 1) {
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Rook' {
            if ($dx -eq 0 -or $dy -eq 0) {
                if (!(Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Bishop' {
            if ($absDx -eq $absDy) {
                if (!(Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Queen' {
            if ($absDx -eq $absDy -or $dx -eq 0 -or $dy -eq 0) {
                if (!(Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        default { return $false }
    }
}
function Test-PathClear($x1, $y1, $x2, $y2) {
    $stepX = [Math]::Sign($x2 - $x1)
    $stepY = [Math]::Sign($y2 - $y1)
    $x = $x1 + $stepX
    $y = $y1 + $stepY
    while ($x -ne $x2 -or $y -ne $y2) {
        if ($script:Grid[$y][$x]) { return $false }
        $x += $stepX
        $y += $stepY
    }
    return $true
}

function Test-LeavesKingInCheck($x1, $y1, $x2, $y2) {
    $saved = $script:Grid[$y2][$x2]
    $piece = $script:Grid[$y1][$x1]
    $script:Grid[$y2][$x2] = $piece
    $script:Grid[$y1][$x1] = $null
    $check = Test-KingInCheck $piece.Color
    $script:Grid[$y1][$x1] = $piece
    $script:Grid[$y2][$x2] = $saved
    return $check
}

function Test-KingInCheck($color) {
    $kx = -1; $ky = -1
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Type -eq 'King' -and $p.Color -eq $color) {
                $kx = $x; $ky = $y; break
            }
        }
        if ($kx -ge 0) { break }
    }
    if ($kx -lt 0) { return $false }
    
    $enemy = if ($color -eq 'White') { 'Black' } else { 'White' }
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Color -eq $enemy) {
                if (Test-ValidMove $x $y $kx $ky $true) { return $true }
            }
        }
    }
    return $false
}

function Calc-ValidMoves {
    $script:ValidMoves = @()
    if (!$script:HasSelection) { return }
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            if (Test-ValidMove $script:StartX $script:StartY $x $y $false) {
                $script:ValidMoves += "$x,$y"
            }
        }
    }
}

function Test-HasAnyValidMoves($color) {
    $old = $script:Turn
    $script:Turn = $color
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Color -eq $color) {
                for ($ty = 0; $ty -lt 8; $ty++) {
                    for ($tx = 0; $tx -lt 8; $tx++) {
                        if (Test-ValidMove $x $y $tx $ty $false) {
                            $script:Turn = $old
                            return $true
                        }
                    }
                }
            }
        }
    }
    $script:Turn = $old
    return $false
}

function Convert-Pawn($x, $y, $forcedType = $null) {
    $pawn = $script:Grid[$y][$x]
    $color = $pawn.Color
    if ($forcedType) {
        # Принудительное превращение (из сети)
        $script:Grid[$y][$x] = @{ Type=$forcedType; Color=$color; X=$x; Y=$y }
        return
    }
    # Интерактивное превращение (локальный игрок)
    $prompt = "Pawn promotion: (Q)ueen, (R)ook, (B)ishop, (K)night: "
    while ($true) {
        Write-Host $prompt -NoNewline -ForegroundColor Cyan
        $key = $host.UI.RawUI.ReadKey("IncludeKeyDown").Character
        Write-Host $key
        $choice = switch ($key) {
            'Q' { 'Queen' }
            'R' { 'Rook' }
            'B' { 'Bishop' }
            'K' { 'Knight' }
            default { $null }
        }
        if ($choice) {
            $script:Grid[$y][$x] = @{ Type=$choice; Color=$color; X=$x; Y=$y }
            break
        }
    }
}

function Do-Move($x1, $y1, $x2, $y2) {
    if (!(Test-ValidMove $x1 $y1 $x2 $y2 $false)) { return $false }
    
    $script:LastPromotion = $null   # сбрасываем перед ходом
    $piece = $script:Grid[$y1][$x1]
    $wasPawn = ($piece.Type -eq 'Pawn')
    
    $script:Grid[$y2][$x2] = $piece
    $script:Grid[$y1][$x1] = $null
    $script:Grid[$y2][$x2].X = $x2
    $script:Grid[$y2][$x2].Y = $y2
    
    # Превращение пешки
    if ($wasPawn -and ($y2 -eq 0 -or $y2 -eq 7)) {
        Convert-Pawn $x2 $y2
        $script:LastPromotion = $script:Grid[$y2][$x2].Type
    }
    
    $script:Turn = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
    
    $check = Test-KingInCheck $script:Turn
    $can = Test-HasAnyValidMoves $script:Turn
    
    if ($check -and !$can) {
        $winner = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
        $script:Status = "CHECKMATE! $winner wins!"
    } elseif ($check) { $script:Status = "CHECK!" }
    elseif (!$can) { $script:Status = "STALEMATE!" }
    else { $script:Status = "Turn: $script:Turn" }
    return $true
}

function Draw-Board {
    Clear-Host
    $cols = @('A','B','C','D','E','F','G','H')
    Write-Host ("    " + ($cols -join '   '))
    for ($y = 0; $y -lt 8; $y++) {
        # Верхняя граница доски и разделители между рядами
        if ($y -eq 0) {
            Write-Host ("$(8-$y) ╔" + ("═══╦" * 7) + "═══╗")
        } else {
            Write-Host ("$(8-$y) ╠" + ("═══╬" * 7) + "═══╣")
        }

        Write-Host -NoNewline "  ║"
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            $s = Get-Symbol $p
            $bg = if (($x + $y) % 2) { 'DarkGray' } else { 'Gray' }
            $fg = if ($p -and $p.Color -eq 'White') { 'White' } else { 'Red' }
            
            if ($p -and $p.Type -eq 'King' -and (Test-KingInCheck $p.Color)) { $bg = 'Red'; $fg = 'White' }
            if ($script:ValidMoves -contains "$x,$y") { $bg = 'Green' }
            if ($script:HasSelection -and $x -eq $script:StartX -and $y -eq $script:StartY) { $bg = 'Cyan'; $fg = 'Black' }
            if ($x -eq $script:SelX -and $y -eq $script:SelY) { $bg = 'Blue'; $fg = 'Yellow' }
            
            Write-Host " $s " -NoNewline -ForegroundColor $fg -BackgroundColor $bg
            Write-Host -NoNewline "║"
        }
        Write-Host
    }
    Write-Host ("  ╚" + ("═══╩" * 7) + "═══╝")
    Write-Host ("    " + ($cols -join '   '))
    Write-Host $script:Status -ForegroundColor Yellow
    Write-Host "Cursor: $script:SelX,$script:SelY | Moves: $($script:ValidMoves.Count)"
    if ($NetworkMode) {
        Write-Host "LAN mode: You are $LocalColor" -ForegroundColor Cyan
    }
    Write-Host "Arrows: Move | Enter: Select/Move | Esc: Exit"
}

# --- Сетевые функции ---
function Setup-LAN {
    Write-Host "LAN игра:" -ForegroundColor Cyan
    Write-Host "1. Создать игру (сервер)"
    Write-Host "2. Подключиться к игре (клиент)"
    $choice = ''
    while ($choice -notin '1','2') {
        $key = $host.UI.RawUI.ReadKey("IncludeKeyDown").Character
        if ($key -eq '1') { $choice = 'server' }
        elseif ($key -eq '2') { $choice = 'client' }
    }
    $port = 8888
    if ($choice -eq 'server') {
        $script:IsServer = $true
        $script:IsClient = $false
        $script:LocalColor = 'White'
        $script:RemoteColor = 'Black'
        Write-Host "Ожидание подключения на порту $port..." -ForegroundColor Yellow
        $script:TcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
        $script:TcpListener.Start()
        $script:TcpClient = $script:TcpListener.AcceptTcpClient()
        Write-Host "Клиент подключился!" -ForegroundColor Green
        $script:NetworkStream = $script:TcpClient.GetStream()
    }
    else {
        $script:IsServer = $false
        $script:IsClient = $true
        $script:LocalColor = 'Black'
        $script:RemoteColor = 'White'
        $ip = Read-Host "Введите IP-адрес сервера"
        Write-Host "Подключение к {$ip}:{$port}..." -ForegroundColor Yellow
        $script:TcpClient = New-Object System.Net.Sockets.TcpClient
        try {
            $script:TcpClient.Connect($ip, $port)
        } catch {
            Write-Host "Не удалось подключиться: $_" -ForegroundColor Red
            pause
            exit
        }
        Write-Host "Подключено!" -ForegroundColor Green
        $script:NetworkStream = $script:TcpClient.GetStream()
    }
    $script:NetworkMode = $true
    $script:Turn = 'White'  # всегда начинают белые
}

function Send-Move($x1,$y1,$x2,$y2,$promo=$null) {
    $msg = "$x1,$y1,$x2,$y2"
    if ($promo) { $msg += ",$promo" }
    $data = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $script:NetworkStream.Write($data, 0, $data.Length)
    $script:NetworkStream.Flush()
}

function Receive-Move {
    $stream = $script:NetworkStream
    $buffer = New-Object byte[] 1024
    while ($true) {
        if ($stream.DataAvailable) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
                return $message.Trim()
            } else {
                return $null  # соединение закрыто
            }
        }
        # Проверка нажатия Esc для выхода
        if ($host.UI.RawUI.KeyAvailable) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ($key.VirtualKeyCode -eq 27) {
                Close-Network
                exit
            }
        }
        Start-Sleep -Milliseconds 50
    }
}

function Apply-RemoteMove($x1,$y1,$x2,$y2,$promo) {
    # Проверим легальность (для безопасности)
    if (!(Test-ValidMove $x1 $y1 $x2 $y2 $false)) {
        Write-Host "Получен нелегальный ход от противника!" -ForegroundColor Red
        return
    }
    # Выполняем перемещение
    $piece = $script:Grid[$y1][$x1]
    $wasPawn = ($piece.Type -eq 'Pawn')
    $script:Grid[$y2][$x2] = $piece
    $script:Grid[$y1][$x1] = $null
    $script:Grid[$y2][$x2].X = $x2
    $script:Grid[$y2][$x2].Y = $y2
    
    # Превращение пешки, если нужно
    if ($wasPawn -and ($y2 -eq 0 -or $y2 -eq 7)) {
        if ($promo) {
            $color = $script:Grid[$y2][$x2].Color
            $script:Grid[$y2][$x2] = @{ Type=$promo; Color=$color; X=$x2; Y=$y2 }
        } else {
            # Если промо не пришло (ошибка), ставим ферзя
            $color = $script:Grid[$y2][$x2].Color
            $script:Grid[$y2][$x2] = @{ Type='Queen'; Color=$color; X=$x2; Y=$y2 }
        }
    }
    
    $script:Turn = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
    
    $check = Test-KingInCheck $script:Turn
    $can = Test-HasAnyValidMoves $script:Turn
    if ($check -and !$can) {
        $winner = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
        $script:Status = "CHECKMATE! $winner wins!"
    } elseif ($check) { $script:Status = "CHECK!" }
    elseif (!$can) { $script:Status = "STALEMATE!" }
    else { $script:Status = "Turn: $script:Turn" }
}

function Close-Network {
    if ($script:NetworkStream) { $script:NetworkStream.Close() }
    if ($script:TcpClient) { $script:TcpClient.Close() }
    if ($script:TcpListener) { $script:TcpListener.Stop() }
}

# --- Начало игры ---
Init-Grid
$script:Status = "Turn: $script:Turn"

# Выбор режима
$GameMode = ''
while ($GameMode -notin '1','2','3') {
    Write-Host "Выберите режим:" -ForegroundColor Cyan
    Write-Host "1. Два игрока (локально)"
    Write-Host "2. Против компьютера"
    Write-Host "3. LAN игра"
    $key = $host.UI.RawUI.ReadKey("IncludeKeyDown").Character
    if ($key -eq '1') { $GameMode = 'TwoPlayer' }
    elseif ($key -eq '2') { $GameMode = 'VsAI' }
    elseif ($key -eq '3') { $GameMode = 'LAN' }
}

if ($GameMode -eq 'VsAI') {
    Write-Host "Выберите цвет (W - белые, B - чёрные):" -ForegroundColor Cyan
    do {
        $key = $host.UI.RawUI.ReadKey("IncludeKeyDown").Character
        if ($key -in 'W','w') { $script:PlayerColor = 'White' }
        elseif ($key -in 'B','b') { $script:PlayerColor = 'Black' }
    } until ($script:PlayerColor -in 'White','Black')
    $script:ComputerColor = if ($PlayerColor -eq 'White') { 'Black' } else { 'White' }
}
elseif ($GameMode -eq 'LAN') {
    Setup-LAN
}

# Функция для ИИ (режим против компьютера)
function Get-AIMove {
    $color = $script:Turn
    $moves = @()
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Color -eq $color) {
                for ($ty = 0; $ty -lt 8; $ty++) {
                    for ($tx = 0; $tx -lt 8; $tx++) {
                        if (Test-ValidMove $x $y $tx $ty $false) {
                            $moves += @{ fromX = $x; fromY = $y; toX = $tx; toY = $ty }
                        }
                    }
                }
            }
        }
    }
    if ($moves.Count -eq 0) { return $null }
    $random = Get-Random -Maximum $moves.Count
    return $moves[$random]
}

# --- Главный игровой цикл ---
while ($true) {
    Draw-Board

    # Проверка окончания игры
    if ($script:Status -like "*MATE*" -or $script:Status -like "*STALEMATE*") {
        $k = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($k.VirtualKeyCode -eq 27) { 
            Close-Network
            break 
        }
        continue
    }

    # Режим против компьютера: ход компьютера
    if ($GameMode -eq 'VsAI' -and $Turn -eq $ComputerColor) {
        $aiMove = Get-AIMove
        if ($aiMove) {
            Do-Move $aiMove.fromX $aiMove.fromY $aiMove.toX $aiMove.toY
            $script:HasSelection = $false
            $script:ValidMoves = @()
            continue
        }
    }

    # LAN режим: ход удалённого игрока
    if ($NetworkMode -and $Turn -eq $RemoteColor) {
        $moveData = Receive-Move
        if ($moveData) {
            $parts = $moveData -split ','
            $x1 = [int]$parts[0]
            $y1 = [int]$parts[1]
            $x2 = [int]$parts[2]
            $y2 = [int]$parts[3]
            $promo = if ($parts.Count -gt 4) { $parts[4] } else { $null }
            Apply-RemoteMove $x1 $y1 $x2 $y2 $promo
            $script:HasSelection = $false
            $script:ValidMoves = @()
            continue
        } else {
            Write-Host "Сетевое соединение разорвано." -ForegroundColor Red
            pause
            Close-Network
            break
        }
    }

    # Обработка клавиш (локальный ввод)
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($key.VirtualKeyCode -eq 27) { 
        Close-Network
        break 
    }
    
    if ($key.VirtualKeyCode -eq 38 -and $script:SelY -gt 0) { $script:SelY-- }
    if ($key.VirtualKeyCode -eq 40 -and $script:SelY -lt 7) { $script:SelY++ }
    if ($key.VirtualKeyCode -eq 37 -and $script:SelX -gt 0) { $script:SelX-- }
    if ($key.VirtualKeyCode -eq 39 -and $script:SelX -lt 7) { $script:SelX++ }
    
    if ($key.VirtualKeyCode -eq 13) {
        if (!$script:HasSelection) {
            $p = $script:Grid[$script:SelY][$script:SelX]
            if ($p -and $p.Color -eq $script:Turn) {
                $script:HasSelection = $true
                $script:StartX = $script:SelX
                $script:StartY = $script:SelY
                Calc-ValidMoves
            }
        } else {
            if (Do-Move $script:StartX $script:StartY $script:SelX $script:SelY) {
                # Отправка хода в LAN режиме
                if ($NetworkMode) {
                    Send-Move $StartX $StartY $SelX $SelY $LastPromotion
                }
                $script:HasSelection = $false
                $script:ValidMoves = @()
            } else {
                $p = $script:Grid[$script:SelY][$script:SelX]
                if ($p -and $p.Color -eq $script:Turn) {
                    $script:StartX = $script:SelX
                    $script:StartY = $script:SelY
                    Calc-ValidMoves
                } else {
                    $script:HasSelection = $false
                    $script:ValidMoves = @()
                }
            }
        }
    }
}
