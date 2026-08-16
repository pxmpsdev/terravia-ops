-- //============================================================\\
-- //  TERRAVIA-OPS RADAR · Critical Ops
-- //  Game Guardian Lua — ESP/Radar Patch für libil2cpp.so
-- //  (nur Radar ESP)
-- //
-- //  FUNKTIONSWEISE:
-- //  Die ESP-Patchstelle hat in 1.80.0.f3358 (arm64) diese 16 Bytes:
-- //    1f 05 00 31 68 5a 40 f9 e9 17 9f 1a 09 01 00 39
-- //    (cmn w8,#1; ldr x8,[x19,#176]; cset w9,eq; strb w9,[x8])
-- //  Das Script scannt die libil2cpp Code-Region (Xa) blockweise mit
-- //  gg.getValues nach diesen Bytes — das findet die Stelle sicher,
-- //  egal wo die Region beginnt. Kein setRanges, keine Offsets nötig.
-- //============================================================\\

local FOUND_FILE = '/sdcard/Download/terravia_ops_radar_found.txt'

-- // Das exakte 16-Byte-Muster (Original) und die ON-Bytes (erste 4 Bytes ersetzen)
local ORIG_HEX = '1f050031685a40f9e9179f1a09010039'
local ON_HEX   = '28008052685a40f9e9179f1a09010039'

-- // Gespeicherte absolute Adresse
local savedAddr = nil

-- // libil2cpp Code-Region (Xa) finden
local function findCode()
    local ok, mods = pcall(gg.getRangesList)
    if not ok or type(mods) ~= 'table' then return nil end
    for _, m in ipairs(mods) do
        if m and m.start and (m.name or ''):find('libil2cpp', 1, true) and m.state == 'Xa' then
            return m
        end
    end
    return nil
end

-- // Mehrere DWords auf einmal lesen (gg.getValues ist dafür da)
-- // returns: Tabelle addr -> Wert oder nil
local function readDwords(addrs)
    local req = {}
    for i, a in ipairs(addrs) do req[i] = { address = a, flags = 4 } end
    local ok, res = pcall(gg.getValues, req)
    if not ok or not res then return nil end
    local out = {}
    for i, r in ipairs(res) do
        if r and r.value ~= nil then out[addrs[i]] = r.value end
    end
    return out
end

-- // DWord-Integer -> Hex-String in Speicherreihenfolge (little-endian)
local function dwordToHexLE(v)
    local h = string.format('%08x', v)
    return h:sub(7, 8) .. h:sub(5, 6) .. h:sub(3, 4) .. h:sub(1, 2)
end

-- // 16 Bytes an addr lesen und als Hex-String zurückgeben (nil wenn unlesbar)
local function read16(addr)
    local vals = readDwords({ addr, addr + 4, addr + 8, addr + 12 })
    if not vals then return nil end
    local a, b, c, d = vals[addr], vals[addr + 4], vals[addr + 8], vals[addr + 12]
    if a == nil or b == nil or c == nil or d == nil then return nil end
    -- unlesbare Stellen liefern 0xffffffff — aussortieren
    if a == 0xffffffff or b == 0xffffffff or c == 0xffffffff or d == 0xffffffff then return nil end
    return dwordToHexLE(a) .. dwordToHexLE(b) .. dwordToHexLE(c) .. dwordToHexLE(d)
end

-- // Gespeicherte Adresse laden
local function loadFound()
    local f = io.open(FOUND_FILE, 'rb')
    if not f then return end
    local line = f:read('*a')
    f:close()
    savedAddr = tonumber(line:match('0x([0-9a-fA-F]+)'), 16)
end

local function saveFound(addr)
    local f = io.open(FOUND_FILE, 'wb')
    if f then f:write('Radar ESP=0x' .. string.format('%X', addr)) f:close() end
end

-- // Blockweise die Code-Region nach dem 16-Byte-Muster durchsuchen
-- // returns: Adresse oder nil
local function scanRegion(code)
    local start = code.start
    local stop = code['end'] or (code.start + (code.size or 0))
    if not stop or stop <= start then
        gg.alert('Code-Region ungültig: 0x' .. string.format('%X', start), 'OK')
        return nil
    end

    gg.toast('Scanne Code-Region (0x' .. string.format('%X', (stop - start)) .. ' Bytes)...')
    local BATCH = 128   -- 128 DWords pro gg.getValues-Aufruf (512 Bytes)
    local STRIDE = 4    -- 4-Byte-Schritte

    local addr = start
    while addr + 16 <= stop do
        -- Batch an Adressen bauen
        local addrs = {}
        local n = 0
        for a = addr, math.min(addr + (BATCH - 1) * STRIDE, stop - 16), STRIDE do
            n = n + 1
            addrs[n] = a
        end
        local vals = readDwords(addrs)
        if vals then
            for _, a in ipairs(addrs) do
                local hex = read16(a)
                if hex == ORIG_HEX or hex == ON_HEX then
                    return a
                end
            end
        end
        addr = addr + BATCH * STRIDE
    end
    return nil
end

-- // An addr patchen: enable=true → ON-Bytes, false → Original
local function writePatch(addr, enable)
    local cur = read16(addr)
    if cur == nil then return false end
    local wantHex = enable and ON_HEX or ORIG_HEX
    if cur == wantHex then return true end
    -- nur die ersten 4 Bytes ändern (Rest ist identisch)
    local intValue = tonumber(wantHex:sub(7, 8) .. wantHex:sub(5, 6) .. wantHex:sub(3, 4) .. wantHex:sub(1, 2), 16)
    local ok = pcall(gg.setValues, { { address = addr, flags = 4, value = intValue } })
    return ok
end

-- // Radar ESP togglen
local function toggleRadar()
    local code = findCode()
    if not code then
        gg.alert('libil2cpp Code-Region nicht gefunden.\nIst Critical Ops gestartet und in GG ausgewählt?', 'OK')
        return
    end

    local addr = savedAddr
    -- Gespeicherte Adresse verifizieren
    if addr then
        local hex = read16(addr)
        if hex == ORIG_HEX or hex == ON_HEX then
            -- direkt togglen
            local enable = (hex == ORIG_HEX)
            if writePatch(addr, enable) then
                gg.toast('✅ Radar ESP ' .. (enable and 'AN' or 'AUS'))
            else
                gg.alert('Radar ESP: Schreiben fehlgeschlagen @0x' .. string.format('%X', addr), 'OK')
            end
            return
        else
            gg.alert('Gespeicherte Adresse 0x' .. string.format('%X', addr) ..
                ' matcht nicht mehr (Bytes: ' .. tostring(hex) .. ').\nScanne neu...', 'OK')
            savedAddr = nil
        end
    end

    -- Scannen
    gg.toast('Suche Radar-ESP Stelle (16-Byte-Muster)...')
    addr = scanRegion(code)
    if not addr then
        gg.alert('Radar-ESP Stelle nicht gefunden.\n\n' ..
            'Das 16-Byte-Muster\n' .. ORIG_HEX .. '\n' ..
            'wurde in der Code-Region 0x' .. string.format('%X', code.start) ..
            ' - 0x' .. string.format('%X', code['end'] or (code.start + code.size)) ..
            ' nicht gefunden.\n\n' ..
            '→ Andere Spielversion oder andere Architektur (armeabi-v7a?).', 'OK')
        return
    end

    -- Gefunden → patchen und speichern
    if writePatch(addr, true) then
        savedAddr = addr
        saveFound(addr)
        gg.toast('✅ Radar ESP AN @0x' .. string.format('%X', addr))
    else
        gg.alert('Radar ESP: Schreiben fehlgeschlagen @0x' .. string.format('%X', addr), 'OK')
    end
end

-- // Hauptmenü
local function main()
    loadFound()
    gg.setVisible(false)
    gg.toast('Terravia Ops Radar gestartet')

    while true do
        local choice = gg.choice({
            '📡 Radar ESP',
            '🔄 Neu scannen',
            'EXIT',
        }, nil, 'TERRAVIA OPS RADAR')

        if choice == nil or choice == 3 then
            gg.setVisible(true)
            return
        end

        if choice == 2 then
            savedAddr = nil
            gg.toast('Neuer Scan...')
        end

        toggleRadar()
    end
end

main()
