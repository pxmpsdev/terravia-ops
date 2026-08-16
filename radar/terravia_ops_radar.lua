-- ============================================================
--  TERRAVIA-OPS RADAR - Critical Ops
--  Game Guardian Lua - ESP/Radar Patch fuer libil2cpp.so
--  (nur Radar ESP)
--
--  Die ESP-Patchstelle hat in 1.80.0.f3358 (arm64) exakt diese 16 Bytes:
--    1f 05 00 31 68 5a 40 f9 e9 17 9f 1a 09 01 00 39
--    (cmn w8,#1; ldr x8,[x19,#176]; cset w9,eq; strb w9,[x8])
--  Primaer: GG native Suche nach diesem Muster, Treffer werden auf die
--  libil2cpp Xa-Region gefiltert. Fallback: Block-Scan per gg.getValues.
-- ============================================================

local FOUND_FILE = '/sdcard/Download/terravia_ops_radar_found.txt'

local ORIG_HEX = '1f050031685a40f9e9179f1a09010039'
local ON_HEX   = '28008052685a40f9e9179f1a09010039'
local ORIG_SPACED = '1f 05 00 31 68 5a 40 f9 e9 17 9f 1a 09 01 00 39'

local savedAddr = nil

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

local function allRegionsMask()
    local mask = 0
    for k, v in pairs(gg) do
        if type(v) == 'number' and k:match('^REGION_') then
            mask = mask + v
        end
    end
    return mask
end

local function dwordToHexLE(v)
    local h = string.format('%08x', v)
    return h:sub(7, 8) .. h:sub(5, 6) .. h:sub(3, 4) .. h:sub(1, 2)
end

local function read16(addr)
    local ok, res = pcall(gg.getValues, {
        { address = addr, flags = 4 },
        { address = addr + 4, flags = 4 },
        { address = addr + 8, flags = 4 },
        { address = addr + 12, flags = 4 },
    })
    if not ok or not res or #res < 4 then return nil end
    local a, b, c, d = res[1].value, res[2].value, res[3].value, res[4].value
    if a == nil or b == nil or c == nil or d == nil then return nil end
    if a == 0xffffffff or b == 0xffffffff or c == 0xffffffff or d == 0xffffffff then return nil end
    return dwordToHexLE(a) .. dwordToHexLE(b) .. dwordToHexLE(c) .. dwordToHexLE(d)
end

local function inRegion(addr, code)
    if not code then return false end
    local stop = code['end'] or (code.start + (code.size or 0))
    return addr >= code.start and addr + 16 <= stop
end

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

local function searchNative(code)
    local mask = allRegionsMask()
    if mask > 0 then
        pcall(gg.setRanges, mask)
    end
    gg.searchNumber('h ' .. ORIG_SPACED, 0x1)
    local n = gg.getResultsCount()
    if n and n > 0 then
        local res = gg.getResults(n)
        gg.clearResults()
        for _, r in ipairs(res) do
            if inRegion(r.address, code) then
                local hex = read16(r.address)
                if hex == ORIG_HEX or hex == ON_HEX then
                    return r.address
                end
            end
        end
    end
    return nil
end

local function scanRegion(code)
    local start = code.start
    local stop = code['end'] or (code.start + (code.size or 0))
    if not stop or stop <= start then return nil end

    gg.toast('Block-Scan der Code-Region...')
    local BATCH = 1024
    local STRIDE = 4
    local total = math.floor((stop - start) / (BATCH * STRIDE)) + 1
    local done = 0

    local addr = start
    while addr + 16 <= stop do
        local addrs = {}
        local n = 0
        for a = addr, math.min(addr + (BATCH - 1) * STRIDE, stop - 16), STRIDE do
            n = n + 1
            addrs[n] = { address = a, flags = 4 }
        end
        local ok, vals = pcall(gg.getValues, addrs)
        if ok and vals then
            local blob = {}
            local bad = false
            for _, r in ipairs(vals) do
                local v = r and r.value
                if v == nil or v == 0xffffffff then
                    bad = true
                    break
                end
                blob[#blob + 1] = dwordToHexLE(v)
            end
            if not bad then
                local hexstr = table.concat(blob)
                local pos = hexstr:find(ORIG_HEX, 1, true)
                if pos then
                    local byteOff = (pos - 1) / 2
                    return addr + byteOff
                end
            end
        end
        addr = addr + BATCH * STRIDE
        done = done + 1
        if done % 200 == 0 then
            gg.toast('Scan... ' .. math.floor(done / total * 100) .. '%')
        end
    end
    return nil
end

local function writePatch(addr, enable)
    local cur = read16(addr)
    if cur == nil then return false end
    local wantHex = enable and ON_HEX or ORIG_HEX
    if cur == wantHex then return true end
    local intValue = tonumber(wantHex:sub(7, 8) .. wantHex:sub(5, 6) .. wantHex:sub(3, 4) .. wantHex:sub(1, 2), 16)
    local ok = pcall(gg.setValues, { { address = addr, flags = 4, value = intValue } })
    return ok
end

local function toggleRadar()
    local code = findCode()
    if not code then
        gg.alert('libil2cpp Code-Region nicht gefunden.' ..
            '\nIst Critical Ops gestartet und in GG ausgewaehlt?', 'OK')
        return
    end

    local addr = savedAddr
    if addr then
        local hex = read16(addr)
        if hex == ORIG_HEX or hex == ON_HEX then
            local enable = (hex == ORIG_HEX)
            if writePatch(addr, enable) then
                gg.toast('Radar ESP ' .. (enable and 'AN' or 'AUS'))
            else
                gg.alert('Radar ESP: Schreiben fehlgeschlagen @0x' .. string.format('%X', addr), 'OK')
            end
            return
        else
            savedAddr = nil
        end
    end

    gg.toast('Suche Radar-ESP Stelle...')
    addr = searchNative(code)
    if not addr then
        addr = scanRegion(code)
    end
    if not addr then
        gg.alert('Radar-ESP Stelle nicht gefunden.' ..
            '\n\nDas 16-Byte-Muster existiert in dieser Version/Architektur nicht.', 'OK')
        return
    end

    if writePatch(addr, true) then
        savedAddr = addr
        saveFound(addr)
        gg.toast('Radar ESP AN @0x' .. string.format('%X', addr))
    else
        gg.alert('Radar ESP: Schreiben fehlgeschlagen @0x' .. string.format('%X', addr), 'OK')
    end
end

local function main()
    loadFound()
    gg.setVisible(false)
    gg.toast('Terravia Ops Radar gestartet')

    while true do
        local choice = gg.choice({
            'Radar ESP',
            'Neu scannen',
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
