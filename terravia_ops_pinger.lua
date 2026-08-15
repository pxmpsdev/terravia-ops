-- //============================================================\\
-- //  TERRAVIA-OPS · Offset-Ping Helper
-- //  Für Critical Ops 1.80.0 (Scattershot Update)
-- //  Game Guardian Lua — halbautomatisches Pingen der Offsets
-- //  Basis: islavikfx Skinchanger v2 (Offsets) + eigener Parser
-- //  Nutzung: Script im GG laufen lassen, Anweisungen folgen.
-- //============================================================\\


-- // Waffen-Menü: [Slots-Index] = {Name, Default-ID, Test-Skin-ID}
local WEAPONS = {
    { "AK47",         291,   321   },  -- FKYA
    { "AR15",         8985,  9314  },  -- SCION
    { "AUG",          136,   231   },  -- MAPLE
    { "BALISONG",     7684,  7706  },
    { "C4",           8053,  8053  },
    { "DEAGLE",       7501,  7680  },
    { "DRAGONMOURN",  8897,  9789  },
    { "DUALMTX",      143,   144   },
    { "EMPTYHANDS",   9394,  10083 },
    { "FIREBOMB",     8260,  8470  },
    { "FLASHBANG",    8054,  8701  },
    { "FP6",          148,   233   },
    { "FRAG",         8055,  8686  },
    { "GLOVESKIN",    6714,  7093  },
    { "GSR1911",      124,   195   },
    { "HK417",        166,   209   },
    { "INCENDIARY",   10524, 10632 },
    { "JAMBIYA",      10465, 10655 },
    { "KARAMBIT",     4449,  4453  },
    { "KNIFE",        704,   705   },
    { "KSG",          9594,  9674  },
    { "KUKRI",        700,   701   },
    { "M14",          121,   155   },
    { "M1887",        7110,  7111  },
    { "M4",           158,   187   },
    { "MANIAGO",      10672, 10726 },
    { "MEATCLEAVER",  8615,  8639  },
    { "MP5",          115,   238   },
    { "MP7",          163,   222   },
    { "MPX",          1,     7029  },
    { "MR96",         114,   223   },
    { "P250",         197,   226   },
    { "P90",          225,   242   },
    { "PIPEWRENCH",   7498,  7552  },
    { "PRACTICE",     8056,  8056  },
    { "PUSHDAGGERS",  10466, 10541 },
    { "REMIX",        717,   718   },
    { "SA58",         202,   215   },
    { "SCARH",        9453,  9482  },
    { "SG551",        244,   409   },
    { "SHORTSWORD",   8259,  8341  },
    { "SMOKE",        8057,  8703  },
    { "SUPER90",      171,   185   },
    { "SVD",          7174,  7179  },
    { "TACTICAL_AXE", 4672,  4693  },
    { "TACTOOL",      731,   741   },
    { "TANTO",        10622, 10646 },
    { "TOMAHAWK",     8862,  8869  },
    { "TRENCH_KNIFE", 8743,  9443  },
    { "TRG22",        3079,  3957  },
    { "URATIO",       156,   165   },
    { "VECTOR",       4677,  4678  },
    { "XD45",         128,   230   },
    { "ZOMBIEHANDS",  10526, 10526 },
}

local ini = nil        -- Basis-Adresse (globale ID-Tabelle)
local found = {}       -- gemerkte Adressen pro Waffe

gg.setRanges(gg.REGION_ANONYMOUS)
gg.clearResults()


-- // Schritt 1: Basis finden (ini) — gleiche Strategie wie das Haupt-Script
local function findBase()
    gg.toast('Phase 1: Suche globale ID-Tabelle (ini)...')
    gg.searchNumber('h 00 00 00 a6 11 00 00 a7 11 00 00 a8 11 00 00 a9 11 00 00 66 1f 00 00 67 1f 00 00 68 1f 00 00 ad 11 00 00 69 1f 00 00 6a 1f 00 00 6b 1f 00 00 6c 1f 00 00 6d 1f 00 00 6e 1f 00 00 6f 1f 00 00 70 1f 00 00 71 1f 00 00 72 1f 00 00 73 1f 00 00 9c 18 00 00 74 1f 00 00 75 1f 00 00 76 1f 00 00 77 1f 00 00 78 1f 00 00 79 1f 00 00 75 1b 00 00 c6 1b 00 00 06 1c 00 00 9b 1d 00 00 4d 1d 00 00 43 20 00 00 44 20 00 00 ba 20 00 00 16 21 00 00 bf 21 00 00 9e 22 00 00 19 23 00 00 ed 24 00 00 7a', 0x1)
    gg.getResults(160)
    gg.refineNumber('h 67 1f 00 00', 0x1)
    if gg.getResultsCount() < 4 then
        gg.alert('Basis nicht gefunden!\nMöglicherweise andere Version oder Pattern geändert.\nDann: Restart Game & nochmal versuchen.', 'OK')
        return false
    end
    local r = gg.getResults(1)
    ini = r[1].address
    gg.clearResults()
    gg.toast('Basis gefunden: 0x' .. string.format('%X', ini))
    return true
end


-- // Schritt 2: Offset für eine Waffe pingen
-- // Flow: Default-Skin ausrüsten -> Wert suchen -> Test-Skin anlegen -> Wert suchen -> verfeinern
local function pingWeapon(w)
    local name, defID, testID = w[1], w[2], w[3]
    gg.clearResults()

    if defID == testID then
        gg.alert('Für "' .. name .. '" gibt es nur den Default-Skin — überspringe.', 'OK')
        return
    end

    -- 1) erster Search: aktuell ausgerüstete Skin-ID (sollte Default sein)
    gg.searchNumber(defID, 0x2)   -- 2 Byte (flags 2)
    local n = gg.getResultsCount()
    gg.toast(name .. ': Suche ' .. defID .. ' -> ' .. n .. ' Treffer')
    gg.alert(
        'Schritt 1/3 für ' .. name .. '\n\n' ..
        'Rüste den DEFAULT-Skin in-game aus (Lobby -> Ausrüstung).\n' ..
        'Ergebnis: ' .. n .. ' Adressen gefunden.\n' ..
        'Weiter im Script?', 'OK')

    -- 2) Test-Skin in-game anlegen, dann verfeinern
    gg.alert(
        'Schritt 2/3 für ' .. name .. '\n\n' ..
        'Wechsle in-game auf einen ANDEREN Skin (Test-Skin ID ' .. testID .. ').\n' ..
        'Danach OK drücken — Script sucht den neuen Wert.', 'OK')
    gg.searchNumber(testID, 0x2)
    n = gg.getResultsCount()
    gg.toast(name .. ': Refine auf ' .. testID .. ' -> ' .. n .. ' Treffer')
    gg.alert(
        'Schritt 3/3 für ' .. name .. '\n\n' ..
        n .. ' Adressen übrig.\n' ..
        'Wechsle weiter zwischen Default und Test-Skin und verfeinere,\n' ..
        'bis 1-3 Adressen übrig bleiben.\n' ..
        '(Manuell: GG-Suche -> Verfeinern)', 'OK')

    -- 3) Ergebnis speichern: Offset = Adresse - ini
    local res = gg.getResults(50)
    local lines = {}
    for i, r in ipairs(res) do
        local off = r.address - ini
        table.insert(lines, string.format('%d) 0x%X  (ini %+d  ->  ini + 0x%X)', i, r.address, off, off))
    end
    gg.alert(name .. ' — Adressen:\n' .. table.concat(lines, '\n') ..
        '\n\nTrage den Offset als "ini + 0xXX" in config1.ini ein.', 'OK')
    found[name] = res
end


-- // Hauptmenü
local function main()
    if not findBase() then return end

    local list = {}
    for _, w in ipairs(WEAPONS) do
        table.insert(list, w[1])
    end
    table.insert(list, 'EXIT')

    while true do
        local sel = gg.choice(list, nil, 'TERRAVIA-OPS · Offset-Ping')
        if not sel then break end
        if sel == #list then break end
        pingWeapon(WEAPONS[sel])
    end

    gg.alert('Fertig! Alle Offsets in config1.ini eintragen:\n' ..
        'gg.setValues({[1] = {address = ini + 0xXX, flags = 2, value = <SkinID>}})', 'OK')
end


main()
