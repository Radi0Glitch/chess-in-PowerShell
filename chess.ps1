[Console]::OutputEncoding = [System.Text.Encoding]::Unicode
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
        'Black' = @{ King="K"; Queen='Q'; Rook='R'; Bishop='B'; Knight='N'; Pawn='P' }
    }
    return $s[$piece.Color][$piece.Type]
}

function Test-ValidMove($x1, $y1, $x2, $y2, $ignoreCheck) {
    $p = $script:Grid[$y1][$x1]
    $target = $script:Grid[$y2][$x2]
    if (!$p) { return $false }
    if ($p.Color -ne $script:Turn) { return $false }
    if ($target -and $target.Color -eq $p.Color) { return $false }
    
    $dx = [Math]::Abs($x2 - $x1)
    $dy = [Math]::Abs($y2 - $y1)
    $dir = if ($p.Color -eq 'White') { -1 } else { 1 }
    
    if ($p.Type -eq 'Pawn') {
        if ($x1 -eq $x2 -and !$target) {
            if ($y2 -eq $y1 + $dir) { return $true }
            if (($y1 -eq 1 -or $y1 -eq 6) -and $y2 -eq $y1 + 2 * $dir) {
                if (!$script:Grid[$y1 + $dir][$x1]) { return $true }
            }
        }
        if ($dx -eq 1 -and $y2 -eq $y1 + $dir -and $target) { return $true }
        return $false
    }
    if ($p.Type -eq 'Knight' -and $dx * $dy -ne 2) { return $false }
    if ($p.Type -eq 'King' -and ($dx -gt 1 -or $dy -gt 1)) { return $false }
    if ($p.Type -eq 'Rook' -and $dx -ne 0 -and $dy -ne 0) { return $false }
    if ($p.Type -eq 'Bishop' -and $dx -ne $dy) { return $false }
    if ($p.Type -eq 'Queen' -and $dx -ne $dy -and $dx -ne 0 -and $dy -ne 0) { return $false }
    
    if (!(Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
    if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
    return $true
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

function Do-Move($x1, $y1, $x2, $y2) {
    if (!(Test-ValidMove $x1 $y1 $x2 $y2 $false)) { return $false }
    $script:Grid[$y2][$x2] = $script:Grid[$y1][$x1]
    $script:Grid[$y1][$x1] = $null
    $script:Grid[$y2][$x2].X = $x2
    $script:Grid[$y2][$x2].Y = $y2
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
            # Рамки (без лишних пробелов)
            if ($y -eq 0) {
                Write-Host ("$(8-$y) ╔" + ("═══╦" * 7) + "═══╗")
            }
            
            else {
                Write-Host ("$(8-$y) ╠" + ("═══╬" * 7) + "═══╣")
            }

            Write-Host -NoNewline "  ║"
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            $s = Get-Symbol $p
            $bg = if (($x + $y) % 2) { 'DarkGray' } else { 'Gray' }
            $fg = if ($p -and $p.Color -eq 'White') { 'White' } else { 'Red' }
            
            if ($p -and $p.Type -eq 'King' -and (Test-KingInCheck $p.Color)) { $bg = 'Red'; $fg = 'White' }
            
            # Проверка через -contains (работает с массивом)
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
    Write-Host "Arrows: Move | Enter: Select/Move | Esc: Exit"
}

Init-Grid
$script:Status = "Turn: $script:Turn"

while ($true) {
    Draw-Board
    if ($script:Status -like "*MATE*" -or $script:Status -like "*STALEMATE*") {
        $k = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($k.VirtualKeyCode -eq 27) { break }
        continue
    }
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($key.VirtualKeyCode -eq 27) { break }
    
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
