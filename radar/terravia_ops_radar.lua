-- //============================================================\\
-- //  TERRAVIA-OPS RADAR · Critical Ops
-- //  Game Guardian Lua — Port von Critical-Ops-External (islavikfx)
-- //  Patchen von Code-Bytes in libil2cpp.so:
-- //   - Radar/ESP     (Espradar)
-- //   - Hitboxes      (größere Trefferboxen)
-- //   - Wallshot      (Schüsse durch Wände)
-- //
-- //  VERSIONSTOLERANT:
-- //  Die Patchstellen werden primär per BYTE-MUSTER in der geladenen
-- //  libil2cpp.so gesucht (Pattern-Scan). So funktioniert das Script
-- //  auch nach Spiel-Updates, ohne dass Offsets manuell angepasst
-- //  werden müssen. Gefundene Adressen werden base-relativ gespeichert
-- //  und beim nächsten Start direkt verwendet (nur verifiziert).
-- //============================================================\\

-- // Features: Name, Such-Muster (Original-Bytes am Patchpunkt), ON-Bytes,
-- //           feste Datei-Offsets als Fallback (nur 1.70.1.f3300)
local FEATURES = {
    { name = 'Radar ESP', pattern = '1f 05 00 31', on = '28 00 80 52', fileoff = '0x1b1897c+0xac', libsplit = '0x13a400' },
    { name = 'Hitboxes',  pattern = 'c7 2e 40 bd', on = '07 b0 26 1e', fileoff = '0x1b9b7fc+0x190', libsplit = '0x13a400' },
    { name = 'Wallshot',  pattern = '80 02 00 36', on = '8e 02 00 54', fileoff = '0x1a93b30+0x190', libsplit = '0x13a400' },
}

local PACKAGE = 'com.criticalforceentertainment.criticalops'
local FOUND_FILE = '/sdcard/Download/terravia_ops_radar_found.txt'

-- // Gespeicherte base-relative Offsets: name -> number
local savedOffsets = {}

-- // libil2cpp Regionen + Basis ermitteln
-- // returns: base (niedrigste Adresse), codeRegion (Xa-Region) oder nil
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

-- // Bytes an einer Adresse lesen (flags 4 = dword)
local function readDword(addr)
    local ok, res = pcall(gg.getValues, { { address = addr, flags = 4 } })
    if ok and res and res[1] then
        return res[1].value
    end
    return nil
end

-- // DWord als Little-Endian-Hex-String "1f050031" (wie er im Speicher liegt)
local function dwordToHexLE(v)
    local h = string.format('%08x', v)
    return h:sub(7, 8) .. h:sub(5, 6) .. h:sub(3, 4) .. h:sub(1, 2)
end

local function normHex(s)
    return (tostring(s or ''):gsub('%s+', ''):lower())
end

-- // Hex-String ("0x...", "0x...+0x...") in Zahl
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

-- // Prüft, ob an addr die Original- oder ON-Bytes liegen
local function bytesMatch(addr, origHex, onHex)
    local v = readDword(addr)
    if v == nil then return false end
    local h = dwordToHexLE(v)
    return h == origHex or h == onHex
end

-- // Gespeicherte Offsets laden
local function loadFound()
    local f = io.open(FOUND_FILE, 'rb')
    if not f then return end
    for line in f:lines() do
        local name, off = line:match('^([^=]+)=0x([0-9a-fA-F]+)$')
        if name and off then
            savedOffsets[name] = tonumber(off, 16)
        end
    end
    f:close()
end

-- // Gefundene Offsets speichern (alle Features)
local function saveFound()
    local lines = {}
    for _, ft in ipairs(FEATURES) do
        local off = savedOffsets[ft.name]
        table.insert(lines, ft.name .. '=0x' .. (off and string.format('%X', off) or '???????'))
    end
    local f = io.open(FOUND_FILE, 'wb')
    if f then f:write(table.concat(lines, '\n')) f:close() end
end

-- // Adresse eines Features ermitteln: gespeichert -> Pattern-Scan -> Fallback
-- // returns: addr oder nil
local function findAddr(ft, base, code)
    local origHex = normHex(ft.pattern)
    local onHex = normHex(ft.on)

    -- 1) Gespeicherter base-relativer Offset (falls noch gültig)
    local saved = savedOffsets[ft.name]
    if saved and base and bytesMatch(base + saved, origHex, onHex) then
        return base + saved
    end

    -- 2) Pattern-Scan in der Code-Region der libil2cpp.so
    --    Zuerst nach dem Original-Muster suchen; wenn das Feature schon
    --    eingeschaltet ist, liegt das ON-Muster an der Stelle — dann danach suchen.
    if code then
        local ok = pcall(gg.setRanges, code.start)
        if ok then
            local patterns = { origHex, onHex }
            for _, pat in ipairs(patterns) do
                gg.searchNumber('h ' .. pat, 0x1)
                local n = gg.getResultsCount()
                if n and n > 0 then
                    local res = gg.getResults(n)
                    gg.clearResults()
                    for _, r in ipairs(res) do
                        if bytesMatch(r.address, origHex, onHex) then
                            savedOffsets[ft.name] = r.address - base
                            saveFound()
                            return r.address
                        end
                    end
                end
            end
        end
    end

    -- 3) Feste Datei-Offsets (nur für die Version aus dem Repo)
    if base and ft.fileoff and ft.libsplit then
        local off = parseHex(ft.fileoff)
        local split = parseHex(ft.libsplit)
        if off and split then
            local addr = base + off - split
            if bytesMatch(addr, origHex, onHex) then
                savedOffsets[ft.name] = addr - base
                saveFound()
                return addr
            end
        end
    end

    return nil
end

-- // Feature togglen
-- // returns: status, msg
local function toggleFeature(ft)
    local base, code = findLib()
    if not base then
        return 'error', 'libil2cpp.so nicht gefunden.\nIst Critical Ops gestartet und in GG ausgewählt?'
    end

    local addr = findAddr(ft, base, code)
    if not addr then
        return 'error', ft.name .. ': Patchstelle nicht gefunden.\n\nDas Byte-Muster "' .. ft.pattern ..
            '" existiert in dieser Spielversion nicht (Funktion umgebaut).\n' ..
            '→ Spiel-Update abwarten oder neue Offsets von der Community holen.'
    end

    local origHex = normHex(ft.pattern)
    local onHex = normHex(ft.on)
    local cur = readDword(addr)
    if cur == nil then
        return 'error', ft.name .. ': Adresse nicht lesbar 0x' .. string.format('%X', addr)
    end

    local curHex = dwordToHexLE(cur)
    local enable = curHex == origHex  -- Original -> einschalten, sonst ausschalten
    local want = enable and onHex or origHex
    -- GG schreibt Integer little-endian ins RAM. Damit die gewünschten Bytes
    -- (z. B. "28 00 80 52") im Speicher liegen, den Hex-String umdrehen:
    -- 28008052 -> 52800028.
    local intValue = tonumber(want:sub(7, 8) .. want:sub(5, 6) .. want:sub(3, 4) .. want:sub(1, 2), 16)
    local ok = pcall(gg.setValues, { { address = addr, flags = 4, value = intValue } })
    if not ok then
        return 'error', ft.name .. ': Schreiben fehlgeschlagen.'
    end
    return 'ok', ft.name .. (enable and ' AN' or ' AUS') .. '  (' .. string.format('%X', addr) .. ')'
end

-- // Hauptmenü
local function main()
    loadFound()
    gg.setVisible(false)
    gg.toast('Terravia Ops Radar gestartet')

    while true do
        local choice = gg.choice({
            '📡 Radar ESP',
            '🎯 Hitboxes',
            '🧱 Wallshot',
            'EXIT',
        }, nil, 'TERRAVIA OPS RADAR\nPattern-Scan aktiv (versionsunabhängig)')

        if choice == nil or choice == 4 then
            gg.setVisible(true)
            return
        end

        local ft = FEATURES[choice]
        local status, msg = toggleFeature(ft)
        if status == 'ok' then
            gg.toast('✅ ' .. msg)
        else
            gg.alert('❌ ' .. msg, 'OK')
        end
    end
end

main()
