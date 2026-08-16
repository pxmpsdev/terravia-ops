-- //============================================================\\
-- //  TERRAVIA-OPS RADAR · Critical Ops
-- //  Game Guardian Lua — ESP/Radar Patch für libil2cpp.so
-- //  (nur Radar ESP; Hitboxes/Wallshot entfernt)
-- //
-- //  WICHTIG ZUM VERSTEHEN:
-- //  Das Byte-Muster "1f 05 00 31" (cmn w8, #1) kommt oft mehrfach in der
-- //  Binary vor. Deshalb sucht das Script KANDIDATEN und filtert sie:
-- //  die Stelle muss von einer Sprung-Instruktion gefolgt sein.
-- //  Bleiben mehrere Kandidaten, testet das Script sie nacheinander —
-- //  du musst dabei IM MATCH sein und auf die Minimap schauen.
-- //============================================================\\

local PACKAGE = 'com.criticalforceentertainment.criticalops'
local FOUND_FILE = '/sdcard/Download/terravia_ops_radar_found.txt'

-- // Nur Radar ESP: Name, Original-Muster, ON-Muster
-- // Bekannter Offset für 1.80.0.f3358 (arm64): 0x1513a70
-- // (base-relativ, im RAM: libil2cpp-Basis + 0x1513a70)
local FEATURES = {
    { name = 'Radar ESP', pattern = '1f 05 00 31', on = '28 00 80 52', fileoff = '0x1513a70', libsplit = '0x0' },
}

-- // Gespeicherte base-relative Offsets: name -> number
local savedOffsets = {}

-- // libil2cpp Basis + Code-Region
local function findLib()
    local ok, mods = pcall(gg.getRangesList)
    if not ok or type(mods) ~= 'table' then return nil end
    local base, code = nil, nil
    for _, m in ipairs(mods) do
        if m and m.start and (m.name or ''):find('libil2cpp', 1, true) then
            if not base or m.start < base then base = m.start end
            if m.state == 'Xa' then code = m end
        end
    end
    if not base then return nil end
    return base, code
end

local function readDword(addr)
    local ok, res = pcall(gg.getValues, { { address = addr, flags = 4 } })
    if ok and res and res[1] then return res[1].value end
    return nil
end

-- // DWord-Integer (wie GG ihn liefert) -> Hex-String in Speicherreihenfolge
local function dwordToHexLE(v)
    local h = string.format('%08x', v)
    return h:sub(7, 8) .. h:sub(5, 6) .. h:sub(3, 4) .. h:sub(1, 2)
end

local function normHex(s)
    return (tostring(s or ''):gsub('%s+', ''):lower())
end

local function parseHex(s)
    s = tostring(s or ''):gsub('%s+', '')
    if s:find('+') then
        local a, b = s:match('^([^+]+)%+(.+)$')
        if a and b then
            return tonumber(a:gsub('^0[xX]', ''), 16) + tonumber(b:gsub('^0[xX]', ''), 16)
        end
    end
    return tonumber(s:gsub('^0[xX]', ''), 16)
end

local function bytesMatch(addr, origHex, onHex)
    local v = readDword(addr)
    if v == nil then return false end
    local h = dwordToHexLE(v)
    return h == origHex or h == onHex
end

-- // An addr auf enable setzen (true=ON, false=Original)
local function writePatch(addr, enable, origHex, onHex)
    local cur = readDword(addr)
    if cur == nil then return false end
    local curHex = dwordToHexLE(cur)
    local want = enable and onHex or origHex
    if curHex == want then return true end
    -- GG schreibt little-endian: Hex-String umdrehen
    local intValue = tonumber(want:sub(7, 8) .. want:sub(5, 6) .. want:sub(3, 4) .. want:sub(1, 2), 16)
    local ok = pcall(gg.setValues, { { address = addr, flags = 4, value = intValue } })
    return ok
end

-- // Gespeicherte Offsets laden
local function loadFound()
    local f = io.open(FOUND_FILE, 'rb')
    if not f then return end
    for line in f:lines() do
        local name, off = line:match('^([^=]+)=0x([0-9a-fA-F]+)$')
        if name and off then savedOffsets[name] = tonumber(off, 16) end
    end
    f:close()
end

local function saveFound()
    local lines = {}
    for _, ft in ipairs(FEATURES) do
        local off = savedOffsets[ft.name]
        table.insert(lines, ft.name .. '=0x' .. (off and string.format('%X', off) or '???????'))
    end
    local f = io.open(FOUND_FILE, 'wb')
    if f then f:write(table.concat(lines, '\n')) f:close() end
end

-- // Kandidaten-Adressen für ein Feature finden (gefiltert)
-- // returns: Tabelle mit Adressen (leer wenn nichts)
local function findCandidates(ft, base, code)
    local origHex = normHex(ft.pattern)
    local onHex = normHex(ft.on)
    local cands = {}

    -- 1) Gespeicherter Offset (falls noch gültig)
    local saved = savedOffsets[ft.name]
    if saved and base and bytesMatch(base + saved, origHex, onHex) then
        return { base + saved }
    end

    -- 2) Pattern-Scan (Hex-String MIT Leerzeichen — GG braucht "1f 05 00 31",
    --    sonst findet die Suche 0 Treffer und meldet fälschlich "Muster existiert nicht")
    if code then
        pcall(gg.setRanges, gg.REGION_CODE + gg.REGION_ANONYMOUS)
        local spaced = origHex:gsub('(%x%x)', '%1 ')
        gg.searchNumber('h ' .. spaced, 0x1)
        local n = gg.getResultsCount()
        if n and n > 0 then
            local res = gg.getResults(n)
            gg.clearResults()
            -- Filter: Stelle muss Original/ON sein UND gefolgt von Sprung-Instruktion
            -- (b.cond=0x54, cbz/cbnz=0x35/0x37, tbz/tbnz=0x34/0x36)
            for _, r in ipairs(res) do
                if bytesMatch(r.address, origHex, onHex) then
                    local nextDword = readDword(r.address + 4)
                    if nextDword then
                        -- ARM64-Instruktionen little-endian: Opcode-Feld (0x54 etc.)
                        -- liegt im höchsten Byte des DWord.
                        local opByte = math.floor(nextDword / 0x1000000) % 0x100
                        if opByte == 0x54 or opByte == 0x34 or opByte == 0x35 or opByte == 0x36 or opByte == 0x37 then
                            table.insert(cands, r.address)
                        end
                    end
                end
            end
            -- Fallback: falls Filter nichts findet, alle verifizierten Treffer
            if #cands == 0 then
                for _, r in ipairs(res) do
                    if bytesMatch(r.address, origHex, onHex) then
                        table.insert(cands, r.address)
                    end
                end
            end
        end
    end

    -- 3) Fester Offset (nur 1.70.1)
    if #cands == 0 and base and ft.fileoff and ft.libsplit then
        local off = parseHex(ft.fileoff)
        local split = parseHex(ft.libsplit)
        if off and split then
            local addr = base + off - split
            if bytesMatch(addr, origHex, onHex) then
                table.insert(cands, addr)
            end
        end
    end

    return cands
end

-- // Kandidaten nacheinander testen (User muss im Match sein)
-- // returns: true wenn einer funktioniert hat (und gespeichert wurde)
local function tryCandidates(ft, base, cands)
    local origHex = normHex(ft.pattern)
    local onHex = normHex(ft.on)

    if #cands == 1 then
        -- Nur ein Kandidat: direkt patchen, kein Test nötig
        if writePatch(cands[1], true, origHex, onHex) then
            savedOffsets[ft.name] = cands[1] - base
            saveFound()
            gg.toast('✅ Radar ESP gepatcht @0x' .. string.format('%X', cands[1]))
            return true
        end
        return false
    end

    gg.alert('Es wurden ' .. #cands .. ' Kandidaten gefunden.\n\n' ..
        'Das Script testet sie jetzt nacheinander.\n' ..
        'WICHTIG: Sei IM MATCH und schau nach jedem Test auf die Minimap!\n\n' ..
        'Los?', 'OK')

    for i, addr in ipairs(cands) do
        if not writePatch(addr, true, origHex, onHex) then
            gg.toast('Kandidat ' .. i .. ' nicht beschreibbar, überspringe')
        else
            gg.toast('Kandidat ' .. i .. '/' .. #cands .. ' AN @0x' .. string.format('%X', addr))
            gg.sleep(7000)  -- Zeit zum Schauen auf die Minimap
        end

        local choice = gg.choice({
            '✅ Radar AN',
            '❌ Nicht AN',
            'Abbrechen',
        }, nil, 'Kandidat ' .. i .. '/' .. #cands)

        if choice == 1 then
            savedOffsets[ft.name] = addr - base
            saveFound()
            gg.toast('✅ Gespeichert! Radar ESP ist jetzt an.')
            return true
        elseif choice == 3 then
            writePatch(addr, false, origHex, onHex)
            return false
        else
            writePatch(addr, false, origHex, onHex)  -- zurück auf Original
        end
    end

    gg.alert('Kein Kandidat hat funktioniert.\n' ..
        'Das Byte-Muster existiert in dieser Spielversion nicht (Funktion umgebaut).\n' ..
        '→ Spiel-Update abwarten oder neues Muster eintragen.', 'OK')
    return false
end

-- // Radar ESP togglen (an/aus), bei unbekannter Stelle: Kandidaten testen
local function toggleRadar()
    local base, code = findLib()
    if not base then
        gg.alert('libil2cpp.so nicht gefunden.\nIst Critical Ops gestartet und in GG ausgewählt?', 'OK')
        return
    end

    local ft = FEATURES[1]
    local origHex = normHex(ft.pattern)
    local onHex = normHex(ft.on)

    -- Gespeicherter Offset vorhanden und gültig -> direkt togglen
    local saved = savedOffsets[ft.name]
    if saved and base and bytesMatch(base + saved, origHex, onHex) then
        local addr = base + saved
        local curHex = dwordToHexLE(readDword(addr))
        local enable = curHex == origHex
        if writePatch(addr, enable, origHex, onHex) then
            gg.toast('✅ Radar ESP ' .. (enable and 'AN' or 'AUS'))
        else
            gg.alert('Radar ESP: Schreiben fehlgeschlagen.', 'OK')
        end
        return
    end

    -- Keine gespeicherte Stelle -> Kandidaten suchen und testen
    gg.toast('Suche Radar-ESP Stelle...')

    -- DIAGNOSE: rohes Pattern zählen (ohne Filter), damit man sieht ob's überhaupt da ist
    local rawCount = 0
    if code then
        pcall(gg.setRanges, gg.REGION_CODE + gg.REGION_ANONYMOUS)
        local spaced = origHex:gsub('(%x%x)', '%1 ')
        gg.searchNumber('h ' .. spaced, 0x1)
        rawCount = gg.getResultsCount() or 0
        gg.clearResults()
    end

    local cands = findCandidates(ft, base, code)
    if #cands == 0 then
        gg.alert('Radar-ESP Stelle nicht gefunden.\n\n' ..
            'Diagnose:\n' ..
            '- Muster "' .. ft.pattern .. '" gefunden: ' .. rawCount .. 'x\n' ..
            '- Davon mit Sprung danach: 0\n\n' ..
            'Möglich:\n' ..
            '1) Spielversion hat anderes Muster (Funktion umgebaut)\n' ..
            '2) GG-Suche braucht anderen Typ — probier im GG-Suchfeld manuell:\n' ..
            '   h ' .. origHex:gsub('(%x%x)', '%1 ') .. '\n\n' ..
            'Wenn GG manuell Treffer zeigt, sag mir die Anzahl — dann passe ich das Script an.', 'OK')
        return
    end

    tryCandidates(ft, base, cands)
end

-- // Hauptmenü
local function main()
    loadFound()
    -- Bekannten Offset als Default setzen (falls nichts gespeichert ist):
    -- erspart den Pattern-Scan, solange die Version passt (Bytes werden verifiziert).
    if savedOffsets['Radar ESP'] == nil then
        savedOffsets['Radar ESP'] = parseHex(FEATURES[1].fileoff) or 0
    end
    gg.setVisible(false)
    gg.toast('Terravia Ops Radar gestartet')

    while true do
        local choice = gg.choice({
            '📡 Radar ESP',
            '🔄 Scan erzwingen',
            'EXIT',
        }, nil, 'TERRAVIA OPS RADAR\n(nur ESP)')

        if choice == nil or choice == 3 then
            gg.setVisible(true)
            return
        end

        if choice == 2 then
            savedOffsets['Radar ESP'] = nil  -- gespeicherten Offset verwerfen
            gg.toast('Neuer Scan...')
        end

        toggleRadar()
    end
end

main()
