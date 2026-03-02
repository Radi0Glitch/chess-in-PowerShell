# ============================================================================
# ШАХМАТЫ В POWERSHELL — ФИНАЛЬНАЯ ВЕРСИЯ С ИИ
# ============================================================================
# Исправления:
#   #1 - Виртуальная доска для ИИ (не повреждает реальную игру)
#   #2 - Test-ValidMove: проверка King только когда !$ignoreCheck
#   #3 - Test-ValidMove: Test-LeavesKingInCheck для ВСЕХ фигур
#   #4 - AlphaBeta: явные   везде
#   #5 - Get-Symbol/Draw-Board: защита от NULL фигур
# ============================================================================

# ============================================================================
# БЛОК 1: НАСТРОЙКА ОКРУЖЕНИЯ
# ============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if ($host.Name -notlike '*ISE*') {
    try { chcp 65001 | Out-Null } catch {}
}

[Console]::TreatControlCAsInput = $true

# ============================================================================
# БЛОК 2: ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ============================================================================

$script:Grid = @()
$script:SelX = 0
$script:SelY = 0
$script:HasSelection = $false
$script:StartX = 4
$script:StartY = 4
$script:Turn = 'White'
$script:ValidMoves = @()
$script:Status = ''

# Рокировка
$script:WhiteKingMoved = $false
$script:BlackKingMoved = $false
$script:WhiteRookKingsideMoved = $false
$script:WhiteRookQueensideMoved = $false
$script:BlackRookKingsideMoved = $false
$script:BlackRookQueensideMoved = $false

# Ничья
$script:HalfMoveClock = 0
$script:PositionHistory = @()
$script:TotalMoves = 0

# Сеть
$script:NetworkMode = $false
$script:IsServer = $false
$script:IsClient = $false
$script:TcpListener = $null
$script:TcpClient = $null
$script:NetworkStream = $null
$script:LocalColor = $null
$script:RemoteColor = $null
$script:LastPromotion = $null

# Режимы
$script:GameMode = ''
$script:PlayerColor = ''
$script:ComputerColor = ''

# Для ИИ (виртуальная доска)
$script:AIGrid = @()
$script:AITurn = ''
$script:AILastMove = $null

# Таблицы позиций
$script:PawnTable = @(
    0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
    5,  5, 10, 25, 25, 10,  5,  5,
    0,  0,  0, 20, 20,  0,  0,  0,
    5, -5,-10,  0,  0,-10, -5,  5,
    5, 10, 10,-20,-20, 10, 10,  5,
    0,  0,  0,  0,  0,  0,  0,  0
)

$script:KnightTable = @(
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50
)

# ============================================================================
# БЛОК 3: ИНИЦИАЛИЗАЦИЯ
# ============================================================================

function Init-Grid {
    $script:Grid = @()
    for ($y = 0; $y -lt 8; $y++) {
        $row = @()
        for ($x = 0; $x -lt 8; $x++) { $row += $null }
        $script:Grid += ,$row
    }
    
    $major = 'Rook','Knight','Bishop','Queen','King','Bishop','Knight','Rook'
    for ($i = 0; $i -lt 8; $i++) {
        $script:Grid[0][$i] = @{ Type=$major[$i]; Color='Black'; X=$i; Y=0 }
        $script:Grid[1][$i] = @{ Type='Pawn'; Color='Black'; X=$i; Y=1 }
        $script:Grid[6][$i] = @{ Type='Pawn'; Color='White'; X=$i; Y=6 }
        $script:Grid[7][$i] = @{ Type=$major[$i]; Color='White'; X=$i; Y=7 }
    }
    
    $script:WhiteKingMoved = $false; $script:BlackKingMoved = $false
    $script:WhiteRookKingsideMoved = $false; $script:WhiteRookQueensideMoved = $false
    $script:BlackRookKingsideMoved = $false; $script:BlackRookQueensideMoved = $false
    $script:HalfMoveClock = 0
    $script:PositionHistory = @()
    $script:TotalMoves = 0
    $script:HasSelection = $false
    $script:ValidMoves = @()
}

function Get-Symbol($piece) {
    if (!$piece) { return ' ' }
    if (!$piece.Color -or !$piece.Type) { return '?' }
    
    $symbols = @{
        'White' = @{ King='K'; Queen='Q'; Rook='R'; Bishop='B'; Knight='H'; Pawn='P' }
        'Black' = @{ King='K'; Queen='Q'; Rook='R'; Bishop='B'; Knight='H'; Pawn='P' }
    }
    
    if ($symbols.ContainsKey($piece.Color) -and $symbols[$piece.Color].ContainsKey($piece.Type)) {
        return $symbols[$piece.Color][$piece.Type]
    }
    return '?'
}

# ============================================================================
# БЛОК 4: ПРОВЕРКА ХОДОВ (РЕАЛЬНАЯ ДОСКА)
# ============================================================================

function Test-ValidMove($x1, $y1, $x2, $y2, $ignoreCheck) {
    if ($x1 -lt 0 -or $x1 -gt 7 -or $y1 -lt 0 -or $y1 -gt 7) { return $false }
    if ($x2 -lt 0 -or $x2 -gt 7 -or $y2 -lt 0 -or $y2 -gt 7) { return $false }
    
    $p = $script:Grid[$y1][$x1]
    $target = $script:Grid[$y2][$x2]
    
    if (!$p -or !$p.Type -or !$p.Color) { return $false }
    if (!$ignoreCheck -and $p.Color -ne $script:Turn) { return $false }
    if ($target -and $target.Color -eq $p.Color) { return $false }
    if ($x1 -eq $x2 -and $y1 -eq $y2) { return $false }
    if ($target -and $target.Type -eq 'King' -and !$ignoreCheck) { return $false }

    $dx = $x2 - $x1; $dy = $y2 - $y1
    $absDx = [Math]::Abs($dx); $absDy = [Math]::Abs($dy)
    $dir = if ($p.Color -eq 'White') { -1 } else { 1 }

    switch ($p.Type) {
        'Pawn' {
            if ($dx -eq 0) {
                if ($dy -eq $dir -and !$target) {
                    if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                    return $true
                }
                if (($y1 -eq 1 -or $y1 -eq 6) -and $dy -eq 2 * $dir -and !$target) {
                    $midY = $y1 + $dir
                    if (!$script:Grid[$midY][$x1]) {
                        if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                        return $true
                    }
                }
            }
            if ($absDx -eq 1 -and $dy -eq $dir -and $target) {
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
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
            for ($ky = 0; $ky -lt 8; $ky++) {
                for ($kx = 0; $kx -lt 8; $kx++) {
                    $kp = $script:Grid[$ky][$kx]
                    if ($kp -and $kp.Type -eq 'King' -and $kp.Color -ne $p.Color) {
                        if ([Math]::Abs($kx - $x2) -le 1 -and [Math]::Abs($ky - $y2) -le 1) { 
                            return $false 
                        }
                    }
                }
            }
            
            if ($absDx -le 1 -and $absDy -le 1) {
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            
            if (!$ignoreCheck -and $dy -eq 0 -and $absDx -eq 2) {
                return Test-CanCastle $x1 $y1 $x2 $y2
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

function Test-CanCastle($x1, $y1, $x2, $y2) {
    $piece = $script:Grid[$y1][$x1]
    if (!$piece -or $piece.Type -ne 'King') { return $false }
    
    if ($piece.Color -eq 'White' -and $script:WhiteKingMoved) { return $false }
    if ($piece.Color -eq 'Black' -and $script:BlackKingMoved) { return $false }
    if (Test-KingInCheck $piece.Color) { return $false }
    
    $isKingside = $x2 -gt $x1
    
    if ($piece.Color -eq 'White') {
        if ($isKingside) {
            if ($script:WhiteRookKingsideMoved) { return $false }
            $rook = $script:Grid[7][7]
            if (!$rook -or $rook.Type -ne 'Rook') { return $false }
            if ($script:Grid[7][5] -or $script:Grid[7][6]) { return $false }
            if (Test-SquareAttacked 7 5 'White' -or Test-SquareAttacked 7 6 'White') { return $false }
        } else {
            if ($script:WhiteRookQueensideMoved) { return $false }
            $rook = $script:Grid[7][0]
            if (!$rook -or $rook.Type -ne 'Rook') { return $false }
            if ($script:Grid[7][1] -or $script:Grid[7][2] -or $script:Grid[7][3]) { return $false }
            if (Test-SquareAttacked 7 2 'White' -or Test-SquareAttacked 7 3 'White') { return $false }
        }
    } else {
        if ($isKingside) {
            if ($script:BlackRookKingsideMoved) { return $false }
            $rook = $script:Grid[0][7]
            if (!$rook -or $rook.Type -ne 'Rook') { return $false }
            if ($script:Grid[0][5] -or $script:Grid[0][6]) { return $false }
            if (Test-SquareAttacked 0 5 'Black' -or Test-SquareAttacked 0 6 'Black') { return $false }
        } else {
            if ($script:BlackRookQueensideMoved) { return $false }
            $rook = $script:Grid[0][0]
            if (!$rook -or $rook.Type -ne 'Rook') { return $false }
            if ($script:Grid[0][1] -or $script:Grid[0][2] -or $script:Grid[0][3]) { return $false }
            if (Test-SquareAttacked 0 2 'Black' -or Test-SquareAttacked 0 3 'Black') { return $false }
        }
    }
    return $true
}

function Test-SquareAttacked($x, $y, $color) {
    $enemy = if ($color -eq 'White') { 'Black' } else { 'White' }
    for ($ty = 0; $ty -lt 8; $ty++) {
        for ($tx = 0; $tx -lt 8; $tx++) {
            $p = $script:Grid[$ty][$tx]
            if ($p -and $p.Color -eq $enemy) {
                if (Test-ValidMove $tx $ty $x $y $true) { return $true }
            }
        }
    }
    return $false
}

function Test-PathClear($x1, $y1, $x2, $y2) {
    $stepX = [Math]::Sign($x2 - $x1)
    $stepY = [Math]::Sign($y2 - $y1)
    $x = $x1 + $stepX; $y = $y1 + $stepY
    while ($x -ne $x2 -or $y -ne $y2) {
        if ($script:Grid[$y][$x]) { return $false }
        $x += $stepX; $y += $stepY
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

# ============================================================================
# БЛОК 5: ГЕНЕРАЦИЯ ХОДОВ (РЕАЛЬНАЯ ДОСКА)
# ============================================================================

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
    $hasMoves = $false
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Color -eq $color) {
                for ($ty = 0; $ty -lt 8; $ty++) {
                    for ($tx = 0; $tx -lt 8; $tx++) {
                        if (Test-ValidMove $x $y $tx $ty $false) {
                            $hasMoves = $true; break
                        }
                    }
                    if ($hasMoves) { break }
                }
            }
            if ($hasMoves) { break }
        }
        if ($hasMoves) { break }
    }
    $script:Turn = $old
    return $hasMoves
}

function Convert-Pawn($x, $y, $forcedType = $null, $isAI = $false) {
    $pawn = $script:Grid[$y][$x]
    if (!$pawn) { return }
    $color = $pawn.Color
    if ($forcedType) {
        $script:Grid[$y][$x] = @{ Type=$forcedType; Color=$color; X=$x; Y=$y }
        return
    }
    if ($isAI) {
        $script:Grid[$y][$x] = @{ Type='Queen'; Color=$color; X=$x; Y=$y }
        return
    }
    $prompt = "Pawn promotion: (Q)ueen, (R)ook, (B)ishop, (K)night: "
    while ($true) {
        Write-Host $prompt -NoNewline -ForegroundColor Cyan
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
        Write-Host $key
        $choice = switch ($key) {
            'Q' { 'Queen' }; 'R' { 'Rook' }; 'B' { 'Bishop' }; 'K' { 'Knight' }
            default { $null }
        }
        if ($choice) {
            $script:Grid[$y][$x] = @{ Type=$choice; Color=$color; X=$x; Y=$y }
            break
        }
    }
}

function Test-InsufficientMaterial {
    $whitePieces = @(); $blackPieces = @()
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Type) {
                if ($p.Color -eq 'White') { $whitePieces += $p.Type }
                else { $blackPieces += $p.Type }
            }
        }
    }
    if ($whitePieces.Count -eq 1 -and $blackPieces.Count -eq 1) { return $true }
    if ($whitePieces.Count -eq 1 -and $blackPieces.Count -eq 2) {
        if ($blackPieces -contains 'Bishop' -or $blackPieces -contains 'Knight') { return $true }
    }
    if ($blackPieces.Count -eq 1 -and $whitePieces.Count -eq 2) {
        if ($whitePieces -contains 'Bishop' -or $whitePieces -contains 'Knight') { return $true }
    }
    return $false
}

function Save-Position {
    $pos = ""
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Type) { $pos += "$($p.Color[0])$($p.Type[0])$x$y;" }
        }
    }
    $script:PositionHistory += $pos
}

function Test-ThreefoldRepetition {
    if ($script:PositionHistory.Count -lt 3) { return $false }
    $current = $script:PositionHistory[-1]
    $count = 0
    foreach ($pos in $script:PositionHistory) {
        if ($pos -eq $current) { $count++ }
    }
    return $count -ge 3
}

# ============================================================================
# БЛОК 6: ВЫПОЛНЕНИЕ ХОДА (РЕАЛЬНАЯ ДОСКА)
# ============================================================================

function Do-Move($x1, $y1, $x2, $y2, $isAI = $false) {
    if (!(Test-ValidMove $x1 $y1 $x2 $y2 $false)) { return $false }
    
    $script:LastPromotion = $null
    $piece = $script:Grid[$y1][$x1]
    $target = $script:Grid[$y2][$x2]
    $wasPawn = ($piece.Type -eq 'Pawn')
    $wasCapture = ($target -ne $null)
    
    if ($piece.Type -eq 'King' -and [Math]::Abs($x2 - $x1) -eq 2) {
        if ($x2 -gt $x1) {
            $script:Grid[$y1][5] = @{ Type='Rook'; Color=$piece.Color; X=5; Y=$y1 }
            $script:Grid[$y1][7] = $null
        } else {
            $script:Grid[$y1][3] = @{ Type='Rook'; Color=$piece.Color; X=3; Y=$y1 }
            $script:Grid[$y1][0] = $null
        }
    }
    
    if ($piece.Type -eq 'King') {
        if ($piece.Color -eq 'White') { $script:WhiteKingMoved = $true }
        else { $script:BlackKingMoved = $true }
    }
    if ($piece.Type -eq 'Rook') {
        if ($piece.Color -eq 'White') {
            if ($x1 -eq 7 -and $y1 -eq 7) { $script:WhiteRookKingsideMoved = $true }
            if ($x1 -eq 0 -and $y1 -eq 7) { $script:WhiteRookQueensideMoved = $true }
        } else {
            if ($x1 -eq 7 -and $y1 -eq 0) { $script:BlackRookKingsideMoved = $true }
            if ($x1 -eq 0 -and $y1 -eq 0) { $script:BlackRookQueensideMoved = $true }
        }
    }
    
    if ($wasCapture -or $wasPawn) { $script:HalfMoveClock = 0 }
    else { $script:HalfMoveClock++ }
    
    $newType = $piece.Type
    $script:Grid[$y2][$x2] = @{ Type=$newType; Color=$piece.Color; X=$x2; Y=$y2 }
    $script:Grid[$y1][$x1] = $null
    
    if ($wasPawn -and ($y2 -eq 0 -or $y2 -eq 7)) {
        Convert-Pawn $x2 $y2 $null $isAI
        $script:LastPromotion = $script:Grid[$y2][$x2].Type
    }
    
    $script:Turn = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
    $script:TotalMoves++
    Save-Position
    
    $check = Test-KingInCheck $script:Turn
    $can = Test-HasAnyValidMoves $script:Turn
    
    if ($script:HalfMoveClock -ge 100) { $script:Status = "DRAW! (50 move rule)" }
    elseif (Test-InsufficientMaterial) { $script:Status = "DRAW! (Insufficient material)" }
    elseif (Test-ThreefoldRepetition) { $script:Status = "DRAW! (Threefold repetition)" }
    elseif ($check -and !$can) {
        $winner = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
        $script:Status = "CHECKMATE! $winner wins!"
    } elseif ($check) { $script:Status = "CHECK!" }
    elseif (!$can) { $script:Status = "STALEMATE! DRAW!" }
    else { $script:Status = "Turn: $script:Turn" }
    return $true
}

# ============================================================================
# БЛОК 7: ВИРТУАЛЬНАЯ ДОСКА ДЛЯ ИИ
# ============================================================================

function Init-AIBoard {
    $script:AIGrid = @()
    for ($y = 0; $y -lt 8; $y++) {
        $row = @()
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Type) {
                $row += @{ Type=$p.Type; Color=$p.Color; X=$x; Y=$y }
            } else {
                $row += $null
            }
        }
        $script:AIGrid += ,$row
    }
    $script:AITurn = $script:Turn
}

function AI-Make-Move($x1, $y1, $x2, $y2) {
    $piece = $script:AIGrid[$y1][$x1]
    $captured = $script:AIGrid[$y2][$x2]
    
    if (!$piece -or !$piece.Type -or !$piece.Color) { return }
    
    $script:AILastMove = @{
        FromX = $x1; FromY = $y1; ToX = $x2; ToY = $y2
        PieceType = $piece.Type; PieceColor = $piece.Color
        CapturedType = if ($captured -and $captured.Type) { $captured.Type } else { $null }
        CapturedColor = if ($captured -and $captured.Color) { $captured.Color } else { $null }
        Turn = $script:AITurn
        Promotion = $null
    }
    
    $script:AIGrid[$y1][$x1] = $null
    
    $newType = $piece.Type
    if ($piece.Type -eq 'Pawn' -and ($y2 -eq 0 -or $y2 -eq 7)) {
        $newType = 'Queen'
        $script:AILastMove.Promotion = 'Queen'
    }
    $script:AIGrid[$y2][$x2] = @{ Type = $newType; Color = $piece.Color; X = $x2; Y = $y2 }
    
    $script:AITurn = if ($script:AITurn -eq 'White') { 'Black' } else { 'White' }
}

function AI-Undo-Move() {
    if (!$script:AILastMove) { return }
    $move = $script:AILastMove
    
    $script:AIGrid[$move.ToY][$move.ToX] = $null
    
    if ($move.PieceType) {
        $script:AIGrid[$move.FromY][$move.FromX] = @{ 
            Type = $move.PieceType; Color = $move.PieceColor
            X = $move.FromX; Y = $move.FromY
        }
    }
    
    if ($move.CapturedType) {
        $script:AIGrid[$move.ToY][$move.ToX] = @{ 
            Type = $move.CapturedType; Color = $move.CapturedColor
            X = $move.ToX; Y = $move.ToY
        }
    }
    
    $script:AITurn = $move.Turn
    $script:AILastMove = $null
}

# ============================================================================
# БЛОК 8: ПРОВЕРКА ХОДОВ (ВИРТУАЛЬНАЯ ДОСКА ИИ)
# ============================================================================

function AI-Test-ValidMove($x1, $y1, $x2, $y2, $ignoreCheck) {
    if ($x1 -lt 0 -or $x1 -gt 7 -or $y1 -lt 0 -or $y1 -gt 7) { return $false }
    if ($x2 -lt 0 -or $x2 -gt 7 -or $y2 -lt 0 -or $y2 -gt 7) { return $false }
    
    $p = $script:AIGrid[$y1][$x1]
    $target = $script:AIGrid[$y2][$x2]
    
    if (!$p -or !$p.Type -or !$p.Color) { return $false }
    if (!$ignoreCheck -and $p.Color -ne $script:AITurn) { return $false }
    if ($target -and $target.Color -eq $p.Color) { return $false }
    if ($x1 -eq $x2 -and $y1 -eq $y2) { return $false }
    if ($target -and $target.Type -eq 'King' -and !$ignoreCheck) { return $false }

    $dx = $x2 - $x1; $dy = $y2 - $y1
    $absDx = [Math]::Abs($dx); $absDy = [Math]::Abs($dy)
    $dir = if ($p.Color -eq 'White') { -1 } else { 1 }

    switch ($p.Type) {
        'Pawn' {
            if ($dx -eq 0) {
                if ($dy -eq $dir -and !$target) {
                    if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                    return $true
                }
                if (($y1 -eq 1 -or $y1 -eq 6) -and $dy -eq 2 * $dir -and !$target) {
                    $midY = $y1 + $dir
                    if (!$script:AIGrid[$midY][$x1]) {
                        if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                        return $true
                    }
                }
            }
            if ($absDx -eq 1 -and $dy -eq $dir -and $target) {
                if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Knight' {
            if ($absDx * $absDy -eq 2) {
                if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'King' {
            if ($absDx -le 1 -and $absDy -le 1) {
                if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Rook' {
            if ($dx -eq 0 -or $dy -eq 0) {
                if (!(AI-Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Bishop' {
            if ($absDx -eq $absDy) {
                if (!(AI-Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Queen' {
            if ($absDx -eq $absDy -or $dx -eq 0 -or $dy -eq 0) {
                if (!(AI-Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (AI-Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        default { return $false }
    }
}

function AI-Test-PathClear($x1, $y1, $x2, $y2) {
    $stepX = [Math]::Sign($x2 - $x1)
    $stepY = [Math]::Sign($y2 - $y1)
    $x = $x1 + $stepX; $y = $y1 + $stepY
    while ($x -ne $x2 -or $y -ne $y2) {
        if ($script:AIGrid[$y][$x]) { return $false }
        $x += $stepX; $y += $stepY
    }
    return $true
}

function AI-Test-LeavesKingInCheck($x1, $y1, $x2, $y2) {
    $saved = $script:AIGrid[$y2][$x2]
    $piece = $script:AIGrid[$y1][$x1]
    $script:AIGrid[$y2][$x2] = $piece
    $script:AIGrid[$y1][$x1] = $null
    $check = AI-Test-KingInCheck $piece.Color
    $script:AIGrid[$y1][$x1] = $piece
    $script:AIGrid[$y2][$x2] = $saved
    return $check
}

function AI-Test-KingInCheck($color) {
    $kx = -1; $ky = -1
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:AIGrid[$y][$x]
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
            $p = $script:AIGrid[$y][$x]
            if ($p -and $p.Color -eq $enemy) {
                if (AI-Test-ValidMove $x $y $kx $ky $false) { return $true }
            }
        }
    }
    return $false
}

# ============================================================================
# БЛОК 9: ОЦЕНКА И ПОИСК (ИИ)
# ============================================================================

function AI-Evaluate-Position {
    $score = 0
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:AIGrid[$y][$x]
            if ($p -and $p.Type -and $p.Color) {
                $material = 0
                if ($p.Type -eq 'Pawn')   { $material = 100 }
                elseif ($p.Type -eq 'Knight') { $material = 320 }
                elseif ($p.Type -eq 'Bishop') { $material = 330 }
                elseif ($p.Type -eq 'Rook')   { $material = 500 }
                elseif ($p.Type -eq 'Queen')  { $material = 900 }
                elseif ($p.Type -eq 'King')   { $material = 20000 }
                
                $position = 0
                $mirrorIndex = if ($p.Color -eq 'White') { (7-$y) * 8 + $x } else { $y * 8 + $x }
                if ($p.Type -eq 'Pawn')   { $position = ($script:PawnTable[$mirrorIndex]) }
                elseif ($p.Type -eq 'Knight') { $position = ($script:KnightTable[$mirrorIndex]) }
                
                $value = $material + $position
                if ($p.Color -eq $script:ComputerColor) { $score += $value }
                else { $score -= $value }
            }
        }
    }
    return $score
}

function AI-Get-AllValidMoves($color) {
    $moves = @()
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:AIGrid[$y][$x]
            if ($p -and $p.Type -and $p.Color -eq $color) {
                for ($ty = 0; $ty -lt 8; $ty++) {
                    for ($tx = 0; $tx -lt 8; $tx++) {
                        $target = $script:AIGrid[$ty][$tx]
                        if ($target -and $target.Color -eq $color) { continue }
                        if (AI-Test-ValidMove $x $y $tx $ty $true) {
                            $moves += @{ fromX=$x; fromY=$y; toX=$tx; toY=$ty }
                        }
                    }
                }
            }
        }
    }
    return $moves
}

function AI-Get-CaptureMoves($color) {
    $moves = @()
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:AIGrid[$y][$x]
            if ($p -and $p.Type -and $p.Color -eq $color) {
                for ($ty = 0; $ty -lt 8; $ty++) {
                    for ($tx = 0; $tx -lt 8; $tx++) {
                        $target = $script:AIGrid[$ty][$tx]
                        if ($target -and $target.Type -and $target.Color -ne $color) {
                            if (AI-Test-ValidMove $x $y $tx $ty $true) {
                                $moves += @{ fromX=$x; fromY=$y; toX=$tx; toY=$ty }
                            }
                        }
                    }
                }
            }
        }
    }
    return $moves
}

function AI-Quiescence-Search($alpha, $beta) {
    $standPat = (AI-Evaluate-Position)
    if ($standPat -ge $beta) { return  $beta }
    if ($alpha -lt $standPat) { $alpha =  $standPat }
    
    $captures = AI-Get-CaptureMoves $script:AITurn
    foreach ($move in $captures) {
        AI-Make-Move $move.fromX $move.fromY $move.toX $move.toY
         $subScore =  (AI-Quiescence-Search $( -$beta) $( -$alpha))
         $score =  (-$subScore)
        AI-Undo-Move
        if ($score -ge $beta) { return  $beta }
        if ($score -gt $alpha) { $alpha =  $score }
    }
    return  $alpha
}

function AI-AlphaBeta-Search($depth, $alpha, $beta, $isMaximizing) {
     $depth =  $depth
     $alpha =  $alpha
     $beta =  $beta
    
    if ($depth -eq 0) { return AI-Quiescence-Search $alpha $beta }
    
    $moves = AI-Get-AllValidMoves $script:AITurn
    if ($moves.Count -eq 0) { return  (AI-Evaluate-Position) }
    
    if ($isMaximizing) {
         $maxEval = -999999
        foreach ($move in $moves) {
            AI-Make-Move $move.fromX $move.fromY $move.toX $move.toY
             $eval =  (AI-AlphaBeta-Search ($depth-1) $alpha $beta $false)
            AI-Undo-Move
            if ($eval -gt $maxEval) { $maxEval = $eval }
            $alpha = [Math]::Max($alpha, $eval)
            if ($beta -le $alpha) { break }
        }
        return $maxEval
    } else {
         $minEval = 999999
        foreach ($move in $moves) {
            AI-Make-Move $move.fromX $move.fromY $move.toX $move.toY
             $eval =  (AI-AlphaBeta-Search ($depth-1) $alpha $beta $true)
            AI-Undo-Move
            if ($eval -lt $minEval) { $minEval = $eval }
            $beta = [Math]::Min($beta, $eval)
            if ($beta -le $alpha) { break }
        }
        return $minEval
    }
}

function Get-AIMove-Improved {
    Write-Host "ИИ думает..." -ForegroundColor Cyan
    $startTime = Get-Date
    
    # КЛЮЧЕВОЕ: Копируем доску для ИИ
    Init-AIBoard
    
     $bestScore = -999999
     $alpha = -999999
     $beta = 999999
     $depth = 4
    $bestMove = $null
    
    $moves = AI-Get-AllValidMoves $script:ComputerColor
    if ($moves.Count -eq 0) { return $null }
    
    # Упорядочивание ходов
    $moves = $moves | ForEach-Object {
        $m = $_
         $score = 0
        $target = $script:AIGrid[$m.toY][$m.toX]
        if ($target -and $target.Type) {
            if ($target.Type -eq 'Queen')  { $score = 900 }
            elseif ($target.Type -eq 'Rook')    { $score = 500 }
            elseif ($target.Type -eq 'Bishop')  { $score = 330 }
            elseif ($target.Type -eq 'Knight')  { $score = 320 }
            elseif ($target.Type -eq 'Pawn')    { $score = 100 }
        }
        [PSCustomObject]@{
            fromX = $m.fromX; fromY = $m.fromY
            toX = $m.toX; toY = $m.toY
            captureScore = $score
        }
    } | Sort-Object -Property captureScore -Descending | ForEach-Object {
        @{ fromX = $_.fromX; fromY = $_.fromY; toX = $_.toX; toY = $_.toY }
    }
    
    foreach ($move in $moves) {
        AI-Make-Move $move.fromX $move.fromY $move.toX $move.toY
         $score =  (AI-AlphaBeta-Search ($depth-1) $alpha $beta $false)
        AI-Undo-Move
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestMove = $move
        }
        $alpha = [Math]::Max($alpha, $bestScore)
    }
    
    $elapsed = (Get-Date) - $startTime
    Write-Host "ИИ: глубина=$depth, оценка=$bestScore, время=$($elapsed.TotalSeconds)с" -ForegroundColor Gray
    return $bestMove
}

# ============================================================================
# БЛОК 10: ОТРИСОВКА
# ============================================================================

function Draw-Board {
    Clear-Host
    $cols = @('A','B','C','D','E','F','G','H')
    Write-Host ("    " + ($cols -join '   '))
    for ($y = 0; $y -lt 8; $y++) {
        if ($y -eq 0) { Write-Host ("$(8-$y) ╔" + ("═══╦" * 7) + "═══╗") }
        else { Write-Host ("$(8-$y) ╠" + ("═══╬" * 7) + "═══╣") }

        Write-Host -NoNewline "  ║"
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            
            $s = ' '
            if ($p -and $p.Type -and $p.Color) {
                try { $s = Get-Symbol $p } catch { $s = '?' }
            }
            
            $bg = if (($x + $y) % 2) { 'DarkGray' } else { 'Gray' }
            $fg = if ($p -and $p.Color -eq 'White') { 'White' } else { 'Black' }
            
            if ($p -and $p.Type -eq 'King' -and $p.Color) {
                try {
                    if (Test-KingInCheck $p.Color) { $bg = 'Red'; $fg = 'White' }
                } catch {}
            }
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
    Write-Host "Cursor: $($script:SelX),$($script:SelY) | Moves: $($script:ValidMoves.Count) | Half-move clock: $($script:HalfMoveClock)"
    if ($script:NetworkMode) { Write-Host "LAN mode: You are $($script:LocalColor)" -ForegroundColor Cyan }
    Write-Host "Arrows: Move | Enter: Select/Move | Esc: Exit"
}

# ============================================================================
# БЛОК 11: СЕТЕВЫЕ ФУНКЦИИ
# ============================================================================

function Setup-LAN {
    Write-Host "LAN игра:" -ForegroundColor Cyan
    Write-Host "1. Создать игру (сервер)"
    Write-Host "2. Подключиться к игре (клиент)"
    $choice = ''
    while ($choice -notin '1','2') {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            49 { $choice = 'server' }; 50 { $choice = 'client' }; 27 { exit }
        }
    }
    $port = 8888
    if ($choice -eq 'server') {
        $script:IsServer = $true; $script:IsClient = $false
        $script:LocalColor = 'White'; $script:RemoteColor = 'Black'
        Write-Host "Ожидание подключения на порту $port..." -ForegroundColor Yellow
        $script:TcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
        $script:TcpListener.Start()
        $script:TcpClient = $script:TcpListener.AcceptTcpClient()
        Write-Host "Клиент подключился!" -ForegroundColor Green
        $script:NetworkStream = $script:TcpClient.GetStream()
    } else {
        $script:IsServer = $false; $script:IsClient = $true
        $script:LocalColor = 'Black'; $script:RemoteColor = 'White'
        $ip = Read-Host "Введите IP-адрес сервера"
        Write-Host "Подключение к {$ip}:{$port}..." -ForegroundColor Yellow
        $script:TcpClient = New-Object System.Net.Sockets.TcpClient
        try { $script:TcpClient.Connect($ip, $port) }
        catch { Write-Host "Не удалось подключиться: $_" -ForegroundColor Red; pause; exit }
        Write-Host "Подключено!" -ForegroundColor Green
        $script:NetworkStream = $script:TcpClient.GetStream()
    }
    $script:NetworkMode = $true
    $script:Turn = 'White'
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
            if ($read -gt 0) { return [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read).Trim() }
            else { return $null }
        }
        if ($host.UI.RawUI.KeyAvailable) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ($key.VirtualKeyCode -eq 27) { Close-Network; exit }
        }
        Start-Sleep -Milliseconds 50
    }
}

function Apply-RemoteMove($x1,$y1,$x2,$y2,$promo) {
    if (!(Test-ValidMove $x1 $y1 $x2 $y2 $false)) { Write-Host "Нелегальный ход!" -ForegroundColor Red; return }
    $piece = $script:Grid[$y1][$x1]; $target = $script:Grid[$y2][$x2]
    $wasPawn = ($piece.Type -eq 'Pawn'); $wasCapture = ($target -ne $null)
    
    if ($piece.Type -eq 'King' -and [Math]::Abs($x2 - $x1) -eq 2) {
        if ($x2 -gt $x1) {
            $script:Grid[$y1][5] = @{ Type='Rook'; Color=$piece.Color; X=5; Y=$y1 }
            $script:Grid[$y1][7] = $null
        } else {
            $script:Grid[$y1][3] = @{ Type='Rook'; Color=$piece.Color; X=3; Y=$y1 }
            $script:Grid[$y1][0] = $null
        }
    }
    if ($piece.Type -eq 'King') { if ($piece.Color -eq 'White') { $script:WhiteKingMoved = $true } else { $script:BlackKingMoved = $true } }
    if ($piece.Type -eq 'Rook') {
        if ($piece.Color -eq 'White') {
            if ($x1 -eq 7 -and $y1 -eq 7) { $script:WhiteRookKingsideMoved = $true }
            if ($x1 -eq 0 -and $y1 -eq 7) { $script:WhiteRookQueensideMoved = $true }
        } else {
            if ($x1 -eq 7 -and $y1 -eq 0) { $script:BlackRookKingsideMoved = $true }
            if ($x1 -eq 0 -and $y1 -eq 0) { $script:BlackRookQueensideMoved = $true }
        }
    }
    if ($wasCapture -or $wasPawn) { $script:HalfMoveClock = 0 } else { $script:HalfMoveClock++ }
    $script:Grid[$y2][$x2] = @{ Type=$piece.Type; Color=$piece.Color; X=$x2; Y=$y2 }
    $script:Grid[$y1][$x1] = $null
    if ($wasPawn -and ($y2 -eq 0 -or $y2 -eq 7)) {
        if ($promo) { $script:Grid[$y2][$x2] = @{ Type=$promo; Color=$piece.Color; X=$x2; Y=$y2 } }
        else { $script:Grid[$y2][$x2] = @{ Type='Queen'; Color=$piece.Color; X=$x2; Y=$y2 } }
    }
    $script:Turn = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
    $script:TotalMoves++; Save-Position
    $check = Test-KingInCheck $script:Turn; $can = Test-HasAnyValidMoves $script:Turn
    if ($script:HalfMoveClock -ge 100) { $script:Status = "DRAW! (50 move rule)" }
    elseif (Test-InsufficientMaterial) { $script:Status = "DRAW! (Insufficient material)" }
    elseif (Test-ThreefoldRepetition) { $script:Status = "DRAW! (Threefold repetition)" }
    elseif ($check -and !$can) { $winner = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }; $script:Status = "CHECKMATE! $winner wins!" }
    elseif ($check) { $script:Status = "CHECK!" }
    elseif (!$can) { $script:Status = "STALEMATE! DRAW!" }
    else { $script:Status = "Turn: $script:Turn" }
}

function Close-Network {
    if ($script:NetworkStream) { $script:NetworkStream.Close() }
    if ($script:TcpClient) { $script:TcpClient.Close() }
    if ($script:TcpListener) { $script:TcpListener.Stop() }
}

# ============================================================================
# БЛОК 12: ГЛАВНЫЙ ЦИКЛ
# ============================================================================

Init-Grid
$script:Status = "Turn: $script:Turn"
Save-Position

$GameMode = ''
while ($GameMode -notin 'TwoPlayer','VsAI','LAN') {
    Clear-Host
    Write-Host "Выберите режим:" -ForegroundColor Cyan
    Write-Host "1. Два игрока (локально)"
    Write-Host "2. Против компьютера (ИИ с Alpha-Beta + Quiescence)"
    Write-Host "3. LAN игра"
    Write-Host "> " -NoNewline
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    switch ($key.VirtualKeyCode) {
        49 { $GameMode = 'TwoPlayer' }; 50 { $GameMode = 'VsAI' }; 51 { $GameMode = 'LAN' }; 27 { exit }
    }
}
$script:GameMode = $GameMode

if ($GameMode -eq 'VsAI') {
    Write-Host "Выберите цвет (W - белые, B - чёрные):" -ForegroundColor Cyan
    do {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) { 87 { $script:PlayerColor = 'White' }; 66 { $script:PlayerColor = 'Black' } }
    } until ($script:PlayerColor -in 'White','Black')
    $script:ComputerColor = if ($script:PlayerColor -eq 'White') { 'Black' } else { 'White' }
} elseif ($GameMode -eq 'LAN') { Clear-Host; Setup-LAN }

Clear-Host

while ($true) {
    Draw-Board

    if ($script:Status -like "*MATE*" -or $script:Status -like "*STALEMATE*" -or $script:Status -like "*DRAW*") {
        Write-Host "Press Esc to exit or any key to restart" -ForegroundColor Green
        $k = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($k.VirtualKeyCode -eq 27) { Close-Network; break }
        Init-Grid; $script:Status = "Turn: $script:Turn"; $script:PositionHistory = @(); Save-Position
        continue
    }

    # Ход ИИ
    if ($GameMode -eq 'VsAI' -and $script:Turn -eq $script:ComputerColor) {
        Start-Sleep -Milliseconds 300
        $aiMove = Get-AIMove-Improved
        if ($aiMove) {
            Do-Move $aiMove.fromX $aiMove.fromY $aiMove.toX $aiMove.toY $true
            $script:HasSelection = $false; $script:ValidMoves = @()
            continue
        }
    }

    # LAN режим
    if ($script:NetworkMode -and $script:Turn -eq $script:RemoteColor) {
        $moveData = Receive-Move
        if ($moveData) {
            $parts = $moveData -split ','
            $x1 =  $parts[0]; $y1 =  $parts[1]; $x2 =  $parts[2]; $y2 =  $parts[3]
            $promo = if ($parts.Count -gt 4) { $parts[4] } else { $null }
            Apply-RemoteMove $x1 $y1 $x2 $y2 $promo
            $script:HasSelection = $false; $script:ValidMoves = @()
            continue
        } else { Write-Host "Сетевое соединение разорвано." -ForegroundColor Red; pause; Close-Network; break }
    }

    # Ввод игрока
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($key.VirtualKeyCode -eq 27) { Close-Network; break }
    
    if ($key.VirtualKeyCode -eq 38 -and $script:SelY -gt 0) { $script:SelY-- }
    if ($key.VirtualKeyCode -eq 40 -and $script:SelY -lt 7) { $script:SelY++ }
    if ($key.VirtualKeyCode -eq 37 -and $script:SelX -gt 0) { $script:SelX-- }
    if ($key.VirtualKeyCode -eq 39 -and $script:SelX -lt 7) { $script:SelX++ }
    
    if ($key.VirtualKeyCode -eq 13) {
        if (!$script:HasSelection) {
            $p = $script:Grid[$script:SelY][$script:SelX]
            if ($p -and $p.Color -eq $script:Turn) {
                $script:HasSelection = $true
                $script:StartX = $script:SelX; $script:StartY = $script:SelY
                Calc-ValidMoves
            }
        } else {
            if (Do-Move $script:StartX $script:StartY $script:SelX $script:SelY $false) {
                if ($script:NetworkMode) { Send-Move $script:StartX $script:StartY $script:SelX $script:SelY $script:LastPromotion }
                $script:HasSelection = $false; $script:ValidMoves = @()
            } else {
                $p = $script:Grid[$script:SelY][$script:SelX]
                if ($p -and $p.Color -eq $script:Turn) {
                    $script:StartX = $script:SelX; $script:StartY = $script:SelY
                    Calc-ValidMoves
                } else { $script:HasSelection = $false; $script:ValidMoves = @() }
            }
        }
    }
}
