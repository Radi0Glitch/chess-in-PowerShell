# ============================================================================
# БЛОК 1: НАСТРОЙКА ОКРУЖЕНИЯ И КОДИРОВКИ
# ============================================================================
# Настройка UTF-8 для корректного отображения символов в консоли
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Установка codepage 65001 (UTF-8) для PowerShell (кроме ISE)
if ($host.Name -notlike '*ISE*') {
    try { chcp 65001 | Out-Null } catch {}
}

# Обработка Ctrl+C как обычного ввода для возможности выхода по Esc
[Console]::TreatControlCAsInput = $true


# ============================================================================
# БЛОК 2: ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ИГРЫ
# ============================================================================

# --- Состояние игрового поля и курсора ---
$script:Grid = @()              # Двумерный массив 8x8 для хранения фигур
$script:SelX = 0                # Координата X курсора на доске
$script:SelY = 0                # Координата Y курсора на доске
$script:HasSelection = $false   # Флаг: выбрана ли фигура для хода
$script:StartX = 0              # Координата X выбранной фигуры
$script:StartY = 0              # Координата Y выбранной фигуры
$script:Turn = 'White'          # Чей сейчас ход: 'White' или 'Black'
$script:ValidMoves = @()        # Список допустимых ходов для выбранной фигуры ("x,y")
$script:Status = ''             # Текстовый статус игры (шах, мат, ничья и т.д.)

# --- Флаги рокировки (отслеживание ходов короля и ладей) ---
$script:WhiteKingMoved = $false
$script:BlackKingMoved = $false
$script:WhiteRookKingsideMoved = $false
$script:WhiteRookQueensideMoved = $false
$script:BlackRookKingsideMoved = $false
$script:BlackRookQueensideMoved = $false

# --- Счётчики для правил ничьей ---
$script:HalfMoveClock = 0       # Ходы без взятий и ходов пешками (правило 50 ходов)
$script:PositionHistory = @()   # История позиций для правила трёхкратного повтора
$script:TotalMoves = 0          # Общее количество сделанных ходов

# --- Сетевые переменные (LAN-режим) ---
$script:NetworkMode = $false    # Активна ли сетевая игра
$script:IsServer = $false       # Текущий игрок — сервер?
$script:IsClient = $false       # Текущий игрок — клиент?
$script:TcpListener = $null     # Listener для сервера
$script:TcpClient = $null       # TCP-клиент для соединения
$script:NetworkStream = $null   # Поток данных для сетевого обмена
$script:LocalColor = $null      # Цвет фигур локального игрока
$script:RemoteColor = $null     # Цвет фигур удалённого игрока
$script:LastPromotion = $null   # Тип фигуры для последнего превращения пешки

# --- Взятие на проходе (en passant) ---
$script:EnPassantTarget = $null # Клетка, на которую можно взять на проходе (@{X=...; Y=...})

# --- Переменные режимов игры ---
$script:GameMode = ''           # Выбранный режим: 'TwoPlayer', 'VsAI', 'LAN'
$script:PlayerColor = ''        # Цвет игрока в режиме VsAI
$script:ComputerColor = ''      # Цвет компьютера в режиме VsAI


# ============================================================================
# БЛОК 3: ИНИЦИАЛИЗАЦИЯ ИГРЫ
# ============================================================================

# Функция: Init-Grid
# Назначение: Создание пустой доски и расстановка фигур в начальную позицию
# Сбрасывает все флаги рокировки и счётчики ничьей
function Init-Grid {
    # Создаём пустую доску 8x8
    $script:Grid = @()
    for ($y = 0; $y -lt 8; $y++) {
        $row = @()
        for ($x = 0; $x -lt 8; $x++) { $row += $null }
        $script:Grid += ,$row
    }
    
    # Расстановка фигур: массив названий для линейных фигур
    $major = 'Rook','Knight','Bishop','Queen','King','Bishop','Knight','Rook'
    for ($i = 0; $i -lt 8; $i++) {
        # Чёрные фигуры (ряды 0 и 1)
        $script:Grid[0][$i] = @{ Type=$major[$i]; Color='Black'; X=$i; Y=0 }
        $script:Grid[1][$i] = @{ Type='Pawn'; Color='Black'; X=$i; Y=1 }
        # Белые фигуры (ряды 6 и 7)
        $script:Grid[6][$i] = @{ Type='Pawn'; Color='White'; X=$i; Y=6 }
        $script:Grid[7][$i] = @{ Type=$major[$i]; Color='White'; X=$i; Y=7 }
    }
    
    # Сброс флагов рокировки
    $script:WhiteKingMoved = $false; $script:BlackKingMoved = $false
    $script:WhiteRookKingsideMoved = $false; $script:WhiteRookQueensideMoved = $false
    $script:BlackRookKingsideMoved = $false; $script:BlackRookQueensideMoved = $false
    
    # Сброс счётчиков для правил ничьей
    $script:HalfMoveClock = 0
    $script:PositionHistory = @()
    $script:TotalMoves = 0

    # Сброс взятия на проходе, хода и состояния выбора
    $script:EnPassantTarget = $null
    $script:Turn = 'White'
    $script:HasSelection = $false
    $script:ValidMoves = @()
}


# ============================================================================
# БЛОК 4: ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ОТОБРАЖЕНИЯ
# ============================================================================

# Функция: Get-Symbol
# Назначение: Возвращает буквенное обозначение фигуры для отображения на доске
function Get-Symbol($piece) {
    if (!$piece) { return ' ' }
    $s = @{
        'White' = @{ King='K'; Queen='Q'; Rook='R'; Bishop='B'; Knight='H'; Pawn='P' }
        'Black' = @{ King='K'; Queen='Q'; Rook='R'; Bishop='B'; Knight='H'; Pawn='P' }
    }
    return $s[$piece.Color][$piece.Type]
}


# ============================================================================
# БЛОК 5: ПРОВЕРКА ДОПУСТИМОСТИ ХОДОВ (ОСНОВНАЯ ЛОГИКА) — ИСПРАВЛЕНО
# ============================================================================

# Функция: Test-ValidMove
# Назначение: Проверяет, является ли ход (x1,y1) -> (x2,y2) легальным по правилам шахмат
# Параметры:
#   $ignoreCheck — если $true, не проверяет, остаётся ли король под шахом после хода
#                  (используется при проверке атак на короля)
# Возвращает: $true если ход допустим, $false иначе
function Test-ValidMove($x1, $y1, $x2, $y2, $ignoreCheck) {
    $p = $script:Grid[$y1][$x1]
    $target = $script:Grid[$y2][$x2]
    
    # Базовые проверки: есть ли фигура, свой ли ход, не бьём ли свою, не на месте ли стоим
    if (!$p) { return $false }
    if (!$ignoreCheck -and $p.Color -ne $script:Turn) { return $false }
    if ($target -and $target.Color -eq $p.Color) { return $false }
    if ($x1 -eq $x2 -and $y1 -eq $y2) { return $false }
    
    # === FIX #1: Нельзя брать короля (ТОЛЬКО в обычном режиме, не при проверке шаха!) ===
    # Без !$ignoreCheck функция Test-KingInCheck не могла определить атаку на короля
    if ($target -and $target.Type -eq 'King' -and !$ignoreCheck) { return $false }

    $dx = $x2 - $x1; $dy = $y2 - $y1
    $absDx = [Math]::Abs($dx); $absDy = [Math]::Abs($dy)
    $dir = if ($p.Color -eq 'White') { -1 } else { 1 }  # Направление движения пешек

    switch ($p.Type) {
        'Pawn' {
            # === FIX #2: Добавлена проверка Test-LeavesKingInCheck для всех ходов пешки ===
            # Раньше пешка могла делать ходы, оставляющие короля под шахом
            if ($dx -eq 0) {
                # Ход вперёд на 1 клетку без взятия
                if ($dy -eq $dir -and !$target) {
                    if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                    return $true
                }
                # Первый ход пешки: прыжок на 2 клетки, если путь свободен
                if (($y1 -eq 1 -or $y1 -eq 6) -and $dy -eq 2 * $dir -and !$target) {
                    $midY = $y1 + $dir
                    if (!$script:Grid[$midY][$x1]) {
                        if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                        return $true
                    }
                }
            }
            # Взятие по диагонали: обычное (есть цель) или взятие на проходе
            if ($absDx -eq 1 -and $dy -eq $dir) {
                if ($target) {
                    if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                    return $true
                }
                # Взятие на проходе (только когда ignoreCheck = $false, т.е. при реальном ходе)
                if (!$ignoreCheck -and $script:EnPassantTarget -and
                    $x2 -eq $script:EnPassantTarget.X -and $y2 -eq $script:EnPassantTarget.Y) {
                    if (Test-LeavesKingInCheck $x1 $y1 $x2 $y2) { return $false }
                    return $true
                }
            }
            return $false
        }
        'Knight' {
            # Ход конём: L-образный (2+1 или 1+2)
            if ($absDx * $absDy -eq 2) {
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'King' {
            # FIX #3: Запрет на приближение королей ближе чем на 1 клетку
            for ($y = 0; $y -lt 8; $y++) {
                for ($x = 0; $x -lt 8; $x++) {
                    $kp = $script:Grid[$y][$x]
                    if ($kp -and $kp.Type -eq 'King' -and $kp.Color -ne $p.Color) {
                        if ([Math]::Abs($x - $x2) -le 1 -and [Math]::Abs($y - $y2) -le 1) { 
                            return $false 
                        }
                    }
                }
            }
            
            # Обычный ход короля на 1 клетку в любом направлении
            if ($absDx -le 1 -and $absDy -le 1) {
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            
            # Рокировка: король двигается на 2 клетки по горизонтали
            if (!$ignoreCheck -and $dy -eq 0 -and $absDx -eq 2) {
                return Test-CanCastle $x1 $y1 $x2 $y2
            }
            return $false
        }
        'Rook' {
            # Ладья: только по прямым линиям
            if ($dx -eq 0 -or $dy -eq 0) {
                if (!(Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Bishop' {
            # Слон: только по диагоналям
            if ($absDx -eq $absDy) {
                if (!(Test-PathClear $x1 $y1 $x2 $y2)) { return $false }
                if (!$ignoreCheck -and (Test-LeavesKingInCheck $x1 $y1 $x2 $y2)) { return $false }
                return $true
            }
            return $false
        }
        'Queen' {
            # Ферзь: комбинация ладьи и слона
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


# ============================================================================
# БЛОК 6: СПЕЦИАЛЬНЫЕ ХОДЫ — РОКИРОВКА
# ============================================================================

# Функция: Test-CanCastle
# Назначение: Проверяет все условия для выполнения рокировки
# Возвращает: $true если рокировка разрешена, $false иначе
function Test-CanCastle($x1, $y1, $x2, $y2) {
    $piece = $script:Grid[$y1][$x1]
    if ($piece.Type -ne 'King') { return $false }
    
    # Проверка: король уже ходил?
    if ($piece.Color -eq 'White' -and $script:WhiteKingMoved) { return $false }
    if ($piece.Color -eq 'Black' -and $script:BlackKingMoved) { return $false }
    
    # Проверка: король сейчас под шахом? (рокировка из-под шаха запрещена)
    if (Test-KingInCheck $piece.Color) { return $false }
    
    $isKingside = $x2 -gt $x1  # Короткая (королевский фланг) или длинная (ферзевый)
    
    if ($piece.Color -eq 'White') {
        if ($isKingside) {
            # Белые, короткая рокировка: e1->g1, ладья h1->f1
            if ($script:WhiteRookKingsideMoved) { return $false }
            if ($script:Grid[7][7] -eq $null -or $script:Grid[7][7].Type -ne 'Rook') { return $false }
            # Клетки f1, g1 должны быть свободны
            if ($script:Grid[7][5] -ne $null -or $script:Grid[7][6] -ne $null) { return $false }
            # Король не должен проходить через битое поле
            if (Test-SquareAttacked 5 7 'White' -or Test-SquareAttacked 6 7 'White') { return $false }
        } else {
            # Белые, длинная рокировка: e1->c1, ладья a1->d1
            if ($script:WhiteRookQueensideMoved) { return $false }
            if ($script:Grid[7][0] -eq $null -or $script:Grid[7][0].Type -ne 'Rook') { return $false }
            # Клетки b1, c1, d1 должны быть свободны
            if ($script:Grid[7][1] -ne $null -or $script:Grid[7][2] -ne $null -or $script:Grid[7][3] -ne $null) { return $false }
            # Проверка полей c1 и d1 на атаку
            if (Test-SquareAttacked 2 7 'White' -or Test-SquareAttacked 3 7 'White') { return $false }
        }
    } else {
        # Аналогичные проверки для чёрных
        if ($isKingside) {
            if ($script:BlackRookKingsideMoved) { return $false }
            if ($script:Grid[0][7] -eq $null -or $script:Grid[0][7].Type -ne 'Rook') { return $false }
            if ($script:Grid[0][5] -ne $null -or $script:Grid[0][6] -ne $null) { return $false }
            if (Test-SquareAttacked 5 0 'Black' -or Test-SquareAttacked 6 0 'Black') { return $false }
        } else {
            if ($script:BlackRookQueensideMoved) { return $false }
            if ($script:Grid[0][0] -eq $null -or $script:Grid[0][0].Type -ne 'Rook') { return $false }
            if ($script:Grid[0][1] -ne $null -or $script:Grid[0][2] -ne $null -or $script:Grid[0][3] -ne $null) { return $false }
            if (Test-SquareAttacked 2 0 'Black' -or Test-SquareAttacked 3 0 'Black') { return $false }
        }
    }
    return $true
}


# ============================================================================
# БЛОК 7: ПРОВЕРКА АТАК И ШАХОВ
# ============================================================================

# Функция: Test-SquareAttacked
# Назначение: Проверяет, атакуется ли клетка (x,y) фигурами противника цвета $color
# Используется для проверки шаха и валидации рокировки
function Test-SquareAttacked($x, $y, $color) {
    $enemy = if ($color -eq 'White') { 'Black' } else { 'White' }
    for ($ty = 0; $ty -lt 8; $ty++) {
        for ($tx = 0; $tx -lt 8; $tx++) {
            $p = $script:Grid[$ty][$tx]
            if ($p -and $p.Color -eq $enemy) {
                # Проверяем, может ли вражеская фигура бить эту клетку (без проверки на шах)
                if (Test-ValidMove $tx $ty $x $y $true) { return $true }
            }
        }
    }
    return $false
}

# Функция: Test-PathClear
# Назначение: Проверяет, свободен ли путь между двумя клетками для линейных фигур
# Возвращает: $true если путь чист, $false если есть препятствия
function Test-PathClear($x1, $y1, $x2, $y2) {
    $stepX = [Math]::Sign($x2 - $x1)
    $stepY = [Math]::Sign($y2 - $y1)
    $x = $x1 + $stepX; $y = $y1 + $stepY
    while ($x -ne $x2 -or $y -ne $y2) {
        if ($script:Grid[$y][$x]) { return $false }  # На пути есть фигура
        $x += $stepX; $y += $stepY
    }
    return $true
}

# Функция: Test-LeavesKingInCheck
# Назначение: Симулирует ход и проверяет, остаётся ли король под шахом после него
# Используется для фильтрации нелегальных ходов, оставляющих короля в опасности
function Test-LeavesKingInCheck($x1, $y1, $x2, $y2) {
    $saved = $script:Grid[$y2][$x2]
    $piece = $script:Grid[$y1][$x1]
    # Временное выполнение хода
    $script:Grid[$y2][$x2] = $piece
    $script:Grid[$y1][$x1] = $null

    # Взятие на проходе: временно убираем захваченную пешку противника
    $epSavedPawn = $null
    if ($piece.Type -eq 'Pawn' -and $x1 -ne $x2 -and !$saved -and
        $script:EnPassantTarget -and $x2 -eq $script:EnPassantTarget.X -and $y2 -eq $script:EnPassantTarget.Y) {
        $epSavedPawn = $script:Grid[$y1][$x2]
        $script:Grid[$y1][$x2] = $null
    }

    $check = Test-KingInCheck $piece.Color

    # Откат хода
    $script:Grid[$y1][$x1] = $piece
    $script:Grid[$y2][$x2] = $saved
    if ($null -ne $epSavedPawn) { $script:Grid[$y1][$x2] = $epSavedPawn }
    return $check
}

# Функция: Test-KingInCheck
# Назначение: Проверяет, находится ли король указанного цвета под шахом
function Test-KingInCheck($color) {
    # Поиск позиции короля
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
    if ($kx -lt 0) { return $false }  # Король не найден (теоретически невозможно)
    
    # Проверка: атакуется ли позиция короля вражескими фигурами
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
# БЛОК 8: ГЕНЕРАЦИЯ ДОПУСТИМЫХ ХОДОВ И ПРОВЕРКА МАТА
# ============================================================================

# Функция: Calc-ValidMoves
# Назначение: Заполняет массив $script:ValidMoves допустимыми ходами для выбранной фигуры
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

# Функция: Test-HasAnyValidMoves
# Назначение: Проверяет, есть ли у стороны $color хотя бы один легальный ход
# Используется для определения мата или пата
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


# ============================================================================
# БЛОК 9: ПРЕВРАЩЕНИЕ ПЕШКИ (ПРОМОУШН)
# ============================================================================

# Функция: Convert-Pawn
# Назначение: Превращает пешку, достигшую последней горизонтали, в выбранную фигуру
# Параметры:
#   $forcedType — если указан, превращение происходит автоматически (для ИИ)
#   $isAI — флаг, что ход делает компьютер (всегда выбирает ферзя)
function Convert-Pawn($x, $y, $forcedType = $null, $isAI = $false) {
    $pawn = $script:Grid[$y][$x]
    $color = $pawn.Color
    if ($forcedType) {
        $script:Grid[$y][$x] = @{ Type=$forcedType; Color=$color; X=$x; Y=$y }
        return
    }
    if ($isAI) {
        # FIX #3: ИИ всегда выбирает ферзя для максимального преимущества
        $script:Grid[$y][$x] = @{ Type='Queen'; Color=$color; X=$x; Y=$y }
        return
    }
    # Интерактивный выбор для игрока
    $prompt = "Pawn promotion: (Q)ueen, (R)ook, (B)ishop, (K)night: "
    while ($true) {
        Write-Host $prompt -NoNewline -ForegroundColor Cyan
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
        Write-Host $key
        $choice = switch ($key) {
            'Q' { 'Queen' } 'q' { 'Queen' }
            'R' { 'Rook'  } 'r' { 'Rook'  }
            'B' { 'Bishop'} 'b' { 'Bishop' }
            'K' { 'Knight'} 'k' { 'Knight' }
            default { $null }
        }
        if ($choice) {
            $script:Grid[$y][$x] = @{ Type=$choice; Color=$color; X=$x; Y=$y }
            break
        }
    }
}


# ============================================================================
# БЛОК 10: ПРАВИЛА НИЧЬЕЙ
# ============================================================================

# Функция: Test-InsufficientMaterial
# Назначение: Проверяет, достаточно ли материала на доске для постановки мата
# Возвращает: $true если ничья по недостатку материала
function Test-InsufficientMaterial {
    $whitePieces = @(); $blackPieces = @()
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p) {
                if ($p.Color -eq 'White') { $whitePieces += $p.Type }
                else { $blackPieces += $p.Type }
            }
        }
    }
    
    # Король против короля
    if ($whitePieces.Count -eq 1 -and $blackPieces.Count -eq 1) { return $true }
    # Король + лёгкая фигура против короля
    if ($whitePieces.Count -eq 1 -and $blackPieces.Count -eq 2) {
        if ($blackPieces -contains 'Bishop' -or $blackPieces -contains 'Knight') { return $true }
    }
    if ($blackPieces.Count -eq 1 -and $whitePieces.Count -eq 2) {
        if ($whitePieces -contains 'Bishop' -or $whitePieces -contains 'Knight') { return $true }
    }
    # Два слона на полях одного цвета (упрощённая проверка)
    if ($whitePieces.Count -eq 2 -and $blackPieces.Count -eq 2) {
        if (($whitePieces -contains 'Bishop') -and ($blackPieces -contains 'Bishop')) {
            return $true
        }
    }
    return $false
}

# Функция: Save-Position
# Назначение: Сохраняет текущую позицию доски в историю для проверки трёхкратного повтора
function Save-Position {
    $pos = ""
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p) { $pos += "$($p.Color[0])$($p.Type[0])$x$y;" }
        }
    }
    # Включаем цель взятия на проходе в позицию (меняет хеш, чтобы позиции с разными правами не считались одинаковыми)
    if ($script:EnPassantTarget) { $pos += "EP$($script:EnPassantTarget.X)$($script:EnPassantTarget.Y);" }
    $script:PositionHistory += $pos
}

# Функция: Test-ThreefoldRepetition
# Назначение: Проверяет, встречалась ли текущая позиция на доске 3 раза
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
# БЛОК 11: ВЫПОЛНЕНИЕ ХОДА И ОБНОВЛЕНИЕ СОСТОЯНИЯ
# ============================================================================

# Функция: Do-Move
# Назначение: Выполняет ход, обновляет состояние игры, проверяет окончание партии
# Возвращает: $true если ход успешен, $false если ход нелегален
function Do-Move($x1, $y1, $x2, $y2, $isAI = $false) {
    if (!(Test-ValidMove $x1 $y1 $x2 $y2 $false)) { return $false }
    
    $script:LastPromotion = $null
    $piece = $script:Grid[$y1][$x1]
    $target = $script:Grid[$y2][$x2]
    $wasPawn = ($piece.Type -eq 'Pawn')
    $wasCapture = ($target -ne $null)
    
    # === Обработка рокировки: перемещение ладьи ===
    if ($piece.Type -eq 'King' -and [Math]::Abs($x2 - $x1) -eq 2) {
        if ($x2 -gt $x1) {
            # Короткая рокировка: ладья h1->f1 или h8->f8
            $script:Grid[$y1][5] = $script:Grid[$y1][7]
            $script:Grid[$y1][7] = $null
            $script:Grid[$y1][5].X = 5
        } else {
            # Длинная рокировка: ладья a1->d1 или a8->d8
            $script:Grid[$y1][3] = $script:Grid[$y1][0]
            $script:Grid[$y1][0] = $null
            $script:Grid[$y1][3].X = 3
        }
    }
    
    # === Обновление флагов рокировки после хода ===
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
    
    # === Обновление счётчика для правила 50 ходов ===
    if ($wasCapture -or $wasPawn) { $script:HalfMoveClock = 0 }
    else { $script:HalfMoveClock++ }
    
    # === Физическое перемещение фигуры ===
    $script:Grid[$y2][$x2] = $piece
    $script:Grid[$y1][$x1] = $null
    $script:Grid[$y2][$x2].X = $x2
    $script:Grid[$y2][$x2].Y = $y2

    # === Взятие на проходе: удалить захваченную пешку ===
    if ($wasPawn -and $x1 -ne $x2 -and !$wasCapture) {
        $script:Grid[$y1][$x2] = $null
    }

    # === Обновление цели для взятия на проходе ===
    if ($wasPawn -and [Math]::Abs($y2 - $y1) -eq 2) {
        $script:EnPassantTarget = @{ X = $x2; Y = ($y1 + [Math]::Sign($y2 - $y1)) }
    } else {
        $script:EnPassantTarget = $null
    }
    
    # === Превращение пешки при достижении последней горизонтали ===
    if ($wasPawn -and ($y2 -eq 0 -or $y2 -eq 7)) {
        Convert-Pawn $x2 $y2 $null $isAI
        $script:LastPromotion = $script:Grid[$y2][$x2].Type
    }
    
    # Смена хода
    $script:Turn = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
    $script:TotalMoves++
    
    # Сохранение позиции для проверки повторения
    Save-Position
    
    # === Проверка окончания игры ===
    $check = Test-KingInCheck $script:Turn
    $can = Test-HasAnyValidMoves $script:Turn
    
    if ($script:HalfMoveClock -ge 100) {
        $script:Status = "DRAW! (50 move rule)"
    } elseif (Test-InsufficientMaterial) {
        $script:Status = "DRAW! (Insufficient material)"
    } elseif (Test-ThreefoldRepetition) {
        $script:Status = "DRAW! (Threefold repetition)"
    } elseif ($check -and !$can) {
        $winner = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
        $script:Status = "CHECKMATE! $winner wins!"
    } elseif ($check) { 
        $script:Status = "CHECK!" 
    } elseif (!$can) { 
        $script:Status = "STALEMATE! DRAW!" 
    } else { 
        $script:Status = "Turn: $script:Turn" 
    }
    return $true
}


# ============================================================================
# БЛОК 12: ОТРИСОВКА ДОСКИ В КОНСОЛИ
# ============================================================================

# Функция: Draw-Board
# Назначение: Очищает экран и отрисовывает шахматную доску с фигурами, подсветкой и статусом
function Draw-Board {
    Clear-Host
    $cols = @('A','B','C','D','E','F','G','H')
    Write-Host ("    " + ($cols -join '   '))
    
    for ($y = 0; $y -lt 8; $y++) {
        # Отрисовка горизонтальных разделителей
        if ($y -eq 0) {
            Write-Host ("$(8-$y) ╔" + ("═══╦" * 7) + "═══╗")
        } else {
            Write-Host ("$(8-$y) ╠" + ("═══╬" * 7) + "═══╣")
        }

        Write-Host -NoNewline "  ║"
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            $s = Get-Symbol $p
            # Базовые цвета: шахматная раскраска
            $bg = if (($x + $y) % 2) { 'DarkGray' } else { 'Gray' }
            $fg = if ($p -and $p.Color -eq 'White') { 'White' } else { 'Black' }
            
            # Подсветка: король под шахом
            if ($p -and $p.Type -eq 'King' -and (Test-KingInCheck $p.Color)) { $bg = 'Red'; $fg = 'White' }
            # Подсветка: допустимые ходы для выбранной фигуры
            if ($script:ValidMoves -contains "$x,$y") { $bg = 'Green' }
            # Подсветка: выбранная фигура
            if ($script:HasSelection -and $x -eq $script:StartX -and $y -eq $script:StartY) { $bg = 'Cyan'; $fg = 'Black' }
            # Подсветка: позиция курсора
            if ($x -eq $script:SelX -and $y -eq $script:SelY) { $bg = 'Blue'; $fg = 'Yellow' }
            
            Write-Host " $s " -NoNewline -ForegroundColor $fg -BackgroundColor $bg
            Write-Host -NoNewline "║"
        }
        Write-Host
    }
    # Нижняя рамка и координаты
    Write-Host ("  ╚" + ("═══╩" * 7) + "═══╝")
    Write-Host ("    " + ($cols -join '   '))
    
    # Статус игры и информация
    Write-Host $script:Status -ForegroundColor Yellow
    Write-Host "Cursor: $($script:SelX),$($script:SelY) | Moves: $($script:ValidMoves.Count) | Half-move clock: $($script:HalfMoveClock)"
    if ($script:NetworkMode) {
        Write-Host "LAN mode: You are $($script:LocalColor)" -ForegroundColor Cyan
    }
    Write-Host "Arrows: Move | Enter: Select/Move | Esc: Exit"
}


# ============================================================================
# БЛОК 13: СЕТЕВЫЕ ФУНКЦИИ (LAN-РЕЖИМ)
# ============================================================================

# Функция: Setup-LAN
# Назначение: Инициализирует сетевое соединение — сервер или клиент
function Setup-LAN {
    Write-Host "LAN игра:" -ForegroundColor Cyan
    Write-Host "1. Создать игру (сервер)"
    Write-Host "2. Подключиться к игре (клиент)"
    $choice = ''
    while ($choice -notin 'server','client') {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            49 { $choice = 'server' }
            50 { $choice = 'client' }
            27 { exit }
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
    }
    else {
        $script:IsServer = $false; $script:IsClient = $true
        $script:LocalColor = 'Black'; $script:RemoteColor = 'White'
        $ip = Read-Host "Введите IP-адрес сервера"
        Write-Host "Подключение к {$ip}:{$port}..." -ForegroundColor Yellow
        $script:TcpClient = New-Object System.Net.Sockets.TcpClient
        try {
            $script:TcpClient.Connect($ip, $port)
        } catch {
            Write-Host "Не удалось подключиться: $_" -ForegroundColor Red
            pause; exit
        }
        Write-Host "Подключено!" -ForegroundColor Green
        $script:NetworkStream = $script:TcpClient.GetStream()
    }
    $script:NetworkMode = $true
    $script:Turn = 'White'
}

# Функция: Send-Move
# Назначение: Отправляет координаты хода и тип превращения по сети
function Send-Move($x1,$y1,$x2,$y2,$promo=$null) {
    $msg = "$x1,$y1,$x2,$y2"
    if ($promo) { $msg += ",$promo" }
    $data = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $script:NetworkStream.Write($data, 0, $data.Length)
    $script:NetworkStream.Flush()
}

# Функция: Receive-Move
# Назначение: Получает ход от удалённого игрока, обрабатывает нажатие Esc для выхода
function Receive-Move {
    $stream = $script:NetworkStream
    $buffer = New-Object byte[] 1024
    while ($true) {
        if ($stream.DataAvailable) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
                return $message.Trim()
            } else { return $null }
        }
        # Позволяет выйти по Esc во время ожидания
        if ($host.UI.RawUI.KeyAvailable) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ($key.VirtualKeyCode -eq 27) { Close-Network; exit }
        }
        Start-Sleep -Milliseconds 50
    }
}

# Функция: Apply-RemoteMove
# Назначение: Применяет полученный от сети ход к локальной доске (аналог Do-Move без ввода)
function Apply-RemoteMove($x1,$y1,$x2,$y2,$promo) {
    if (!(Test-ValidMove $x1 $y1 $x2 $y2 $false)) {
        Write-Host "Получен нелегальный ход от противника!" -ForegroundColor Red
        return
    }
    $piece = $script:Grid[$y1][$x1]
    $target = $script:Grid[$y2][$x2]
    $wasPawn = ($piece.Type -eq 'Pawn')
    $wasCapture = ($target -ne $null)
    
    # Обработка рокировки
    if ($piece.Type -eq 'King' -and [Math]::Abs($x2 - $x1) -eq 2) {
        if ($x2 -gt $x1) {
            $script:Grid[$y1][5] = $script:Grid[$y1][7]; $script:Grid[$y1][7] = $null; $script:Grid[$y1][5].X = 5
        } else {
            $script:Grid[$y1][3] = $script:Grid[$y1][0]; $script:Grid[$y1][0] = $null; $script:Grid[$y1][3].X = 3
        }
    }
    
    # Обновление флагов
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
    
    # Счётчики и перемещение
    if ($wasCapture -or $wasPawn) { $script:HalfMoveClock = 0 }
    else { $script:HalfMoveClock++ }
    $script:Grid[$y2][$x2] = $piece; $script:Grid[$y1][$x1] = $null
    $script:Grid[$y2][$x2].X = $x2; $script:Grid[$y2][$x2].Y = $y2

    # Взятие на проходе: удалить захваченную пешку
    if ($wasPawn -and $x1 -ne $x2 -and !$wasCapture) {
        $script:Grid[$y1][$x2] = $null
    }

    # Обновление цели для взятия на проходе
    if ($wasPawn -and [Math]::Abs($y2 - $y1) -eq 2) {
        $script:EnPassantTarget = @{ X = $x2; Y = ($y1 + [Math]::Sign($y2 - $y1)) }
    } else {
        $script:EnPassantTarget = $null
    }
    
    # Превращение пешки
    if ($wasPawn -and ($y2 -eq 0 -or $y2 -eq 7)) {
        if ($promo) {
            $color = $script:Grid[$y2][$x2].Color
            $script:Grid[$y2][$x2] = @{ Type=$promo; Color=$color; X=$x2; Y=$y2 }
        } else {
            $color = $script:Grid[$y2][$x2].Color
            $script:Grid[$y2][$x2] = @{ Type='Queen'; Color=$color; X=$x2; Y=$y2 }
        }
    }
    
    # Завершение хода
    $script:Turn = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
    $script:TotalMoves++; Save-Position
    $check = Test-KingInCheck $script:Turn; $can = Test-HasAnyValidMoves $script:Turn
    if ($script:HalfMoveClock -ge 100) { $script:Status = "DRAW! (50 move rule)" }
    elseif (Test-InsufficientMaterial) { $script:Status = "DRAW! (Insufficient material)" }
    elseif (Test-ThreefoldRepetition) { $script:Status = "DRAW! (Threefold repetition)" }
    elseif ($check -and !$can) {
        $winner = if ($script:Turn -eq 'White') { 'Black' } else { 'White' }
        $script:Status = "CHECKMATE! $winner wins!"
    } elseif ($check) { $script:Status = "CHECK!" }
    elseif (!$can) { $script:Status = "STALEMATE! DRAW!" }
    else { $script:Status = "Turn: $script:Turn" }
}

# Функция: Close-Network
# Назначение: Корректно закрывает все сетевые соединения
function Close-Network {
    if ($script:NetworkStream) { $script:NetworkStream.Close() }
    if ($script:TcpClient) { $script:TcpClient.Close() }
    if ($script:TcpListener) { $script:TcpListener.Stop() }
}


# ============================================================================
# БЛОК 14: ИИ (ПРОСТОЙ АЛГОРИТМ ХОДА КОМПЬЮТЕРА)
# ============================================================================

# Функция: Get-AIMove
# Назначение: Выбирает ход для компьютера на основе простой эвристики
# Возвращает: хэш с координатами хода или $null если ходов нет
function Get-AIMove {
    $color = $script:Turn
    $moves = @()
    $bestMove = $null
    $bestScore = -9999
    
    # Перебор всех легальных ходов
    for ($y = 0; $y -lt 8; $y++) {
        for ($x = 0; $x -lt 8; $x++) {
            $p = $script:Grid[$y][$x]
            if ($p -and $p.Color -eq $color) {
                for ($ty = 0; $ty -lt 8; $ty++) {
                    for ($tx = 0; $tx -lt 8; $tx++) {
                        if (Test-ValidMove $x $y $tx $ty $false) {
                            $moves += @{ fromX = $x; fromY = $y; toX = $tx; toY = $ty }
                            
                            # === Простая оценка хода ===
                            $score = 0
                            $target = $script:Grid[$ty][$tx]
                            # Бонус за взятие фигуры по её относительной силе
                            if ($target) {
                                $score += switch ($target.Type) {
                                    'Queen' { 900 }; 'Rook' { 500 }; 'Bishop' { 300 }; 'Knight' { 300 }; 'Pawn' { 100 }; default { 0 }
                                }
                            }
                            # Предпочтение продвижению пешек
                            if ($p.Type -eq 'Pawn') { $score += 10 }
                            # Предпочтение контролю центра доски
                            if ($tx -in 3,4 -and $ty -in 3,4) { $score += 5 }
                            
                            if ($score -gt $bestScore) {
                                $bestScore = $score
                                $bestMove = @{ fromX = $x; fromY = $y; toX = $tx; toY = $ty }
                            }
                        }
                    }
                }
            }
        }
    }
    
    if ($moves.Count -eq 0) { return $null }
    # Если есть выгодный ход — выбираем его, иначе случайный из легальных
    if ($bestMove -and $bestScore -gt 0) { return $bestMove }
    $random = Get-Random -Maximum $moves.Count
    return $moves[$random]
}


# ============================================================================
# БЛОК 15: ИНИЦИАЛИЗАЦИЯ И ВЫБОР РЕЖИМА ИГРЫ
# ============================================================================

# Инициализация доски и статуса
Init-Grid
$script:Status = "Turn: $script:Turn"
Save-Position

# Меню выбора режима
$GameMode = ''
while ($GameMode -notin 'TwoPlayer','VsAI','LAN') {
    Clear-Host
    Write-Host "Выберите режим:" -ForegroundColor Cyan
    Write-Host "1. Два игрока (локально)"
    Write-Host "2. Против компьютера"
    Write-Host "3. LAN игра"
    Write-Host "> " -NoNewline
    
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    switch ($key.VirtualKeyCode) {
        49 { $GameMode = 'TwoPlayer' }
        50 { $GameMode = 'VsAI' }
        51 { $GameMode = 'LAN' }
        27 { exit }
    }
}
$script:GameMode = $GameMode

# Настройка режима "Против компьютера"
if ($GameMode -eq 'VsAI') {
    Write-Host "Выберите цвет (W - белые, B - чёрные):" -ForegroundColor Cyan
    do {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            87 { $script:PlayerColor = 'White' }  # W
            66 { $script:PlayerColor = 'Black' }  # B
        }
    } until ($script:PlayerColor -in 'White','Black')
    $script:ComputerColor = if ($script:PlayerColor -eq 'White') { 'Black' } else { 'White' }
}
# Настройка LAN-режима
elseif ($GameMode -eq 'LAN') {
    Clear-Host
    Setup-LAN
}
Clear-Host


# ============================================================================
# БЛОК 16: ГЛАВНЫЙ ИГРОВОЙ ЦИКЛ
# ============================================================================

while ($true) {
    Draw-Board

    # === Проверка окончания игры ===
    if ($script:Status -like "*MATE*" -or $script:Status -like "*STALEMATE*" -or $script:Status -like "*DRAW*") {
        Write-Host "Press Esc to exit or any key to restart" -ForegroundColor Green
        $k = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        if ($k.VirtualKeyCode -eq 27) { Close-Network; break }
        # Перезапуск партии
        Init-Grid; $script:Status = "Turn: $script:Turn"
        Save-Position
        continue
    }

    # === Ход компьютера (режим VsAI) ===
    if ($GameMode -eq 'VsAI' -and $script:Turn -eq $script:ComputerColor) {
        Start-Sleep -Milliseconds 500  # Небольшая задержка для естественности
        $aiMove = Get-AIMove
        if ($aiMove) {
            Do-Move $aiMove.fromX $aiMove.fromY $aiMove.toX $aiMove.toY $true
            $script:HasSelection = $false; $script:ValidMoves = @()
            continue
        }
    }

    # === Обработка сетевого хода (LAN-режим) ===
    if ($script:NetworkMode -and $script:Turn -eq $script:RemoteColor) {
        $moveData = Receive-Move
        if ($moveData) {
            $parts = $moveData -split ','
            $x1 = [int]$parts[0]; $y1 = [int]$parts[1]
            $x2 = [int]$parts[2]; $y2 = [int]$parts[3]
            $promo = if ($parts.Count -gt 4) { $parts[4] } else { $null }
            Apply-RemoteMove $x1 $y1 $x2 $y2 $promo
            $script:HasSelection = $false; $script:ValidMoves = @()
            continue
        } else {
            Write-Host "Сетевое соединение разорвано." -ForegroundColor Red
            pause; Close-Network; break
        }
    }

    # === Обработка ввода игрока ===
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($key.VirtualKeyCode -eq 27) { Close-Network; break }  # Выход по Esc
    
    # Перемещение курсора стрелками
    if ($key.VirtualKeyCode -eq 38 -and $script:SelY -gt 0) { $script:SelY-- }  # Up
    if ($key.VirtualKeyCode -eq 40 -and $script:SelY -lt 7) { $script:SelY++ }  # Down
    if ($key.VirtualKeyCode -eq 37 -and $script:SelX -gt 0) { $script:SelX-- }  # Left
    if ($key.VirtualKeyCode -eq 39 -and $script:SelX -lt 7) { $script:SelX++ }  # Right
    
    # Обработка нажатия Enter: выбор фигуры / выполнение хода
    if ($key.VirtualKeyCode -eq 13) {
        if (!$script:HasSelection) {
            # Выбор фигуры, если она своя и сейчас её ход
            $p = $script:Grid[$script:SelY][$script:SelX]
            if ($p -and $p.Color -eq $script:Turn) {
                $script:HasSelection = $true
                $script:StartX = $script:SelX; $script:StartY = $script:SelY
                Calc-ValidMoves
            }
        } else {
            # Попытка выполнить ход на выбранную клетку
            if (Do-Move $script:StartX $script:StartY $script:SelX $script:SelY $false) {
                if ($script:NetworkMode) {
                    Send-Move $script:StartX $script:StartY $script:SelX $script:SelY $script:LastPromotion
                }
                $script:HasSelection = $false; $script:ValidMoves = @()
            } else {
                # Если ход нелегален, но выбрана своя фигура — перевыбираем её
                $p = $script:Grid[$script:SelY][$script:SelX]
                if ($p -and $p.Color -eq $script:Turn) {
                    $script:StartX = $script:SelX; $script:StartY = $script:SelY
                    Calc-ValidMoves
                } else {
                    # Иначе снимаем выделение
                    $script:HasSelection = $false; $script:ValidMoves = @()
                }
            }
        }
    }
}
