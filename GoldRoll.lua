-- GoldRoll: Friendly group gambling for WoW Midnight (12.0)
-- Highest /roll wins (highRoll - lowRoll) gold from the lowest roller.

GoldRoll = LibStub("AceAddon-3.0"):NewAddon("GoldRoll", "AceConsole-3.0", "AceEvent-3.0")

GoldRoll.STATES   = { IDLE = "IDLE", REGISTERING = "REGISTERING", ROLLING = "ROLLING" }
GoldRoll.CHANNELS = { "PARTY", "RAID", "GUILD" }
GoldRoll.PREFIX   = "GoldRoll"

-- ── Initialization ────────────────────────────────────────────────────────────

function GoldRoll:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("GoldRollDB", {
        global = {
            wager    = 1000,
            channel  = "PARTY",
            stats    = {},   -- [playerName] = net gold (positive = winnings)
            altLinks = {},   -- [altName]    = mainName
            scale    = 1.0,
        }
    }, true)

    self:InitGame()

    C_ChatInfo.RegisterAddonMessagePrefix(GoldRoll.PREFIX)

    self:RegisterChatCommand("goldroll", "SlashHandler")
    self:RegisterChatCommand("gr",       "SlashHandler")

    StaticPopupDialogs["GOLDROLL_RESET_CONFIRM"] = {
        text      = "Reset all GoldRoll stats? This cannot be undone.",
        button1   = "Reset",
        button2   = "Cancel",
        OnAccept  = function()
            GoldRoll:ResetStats()
            GoldRoll:RefreshLeaderboard()
        end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }

    self:BuildUI()

    self:Announce("Loaded! Type /gr to open.")
end

function GoldRoll:OnEnable()
    self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
end

function GoldRoll:InitGame()
    self.game = {
        state      = GoldRoll.STATES.IDLE,
        isHost     = false,
        wager      = self.db.global.wager,
        channel    = self.db.global.channel,
        players    = {},    -- array of { name=string, roll=number|nil }
        result     = nil,
        playerName = UnitName("player"),
    }
end

-- ── Slash command handler ─────────────────────────────────────────────────────

function GoldRoll:SlashHandler(input)
    local cmd, rest = strsplit(" ", strtrim(input or ""), 2)
    cmd  = (cmd  or ""):lower()
    rest = strtrim(rest or "")

    if cmd == "" or cmd == "show" then
        self:ToggleUI()
    elseif cmd == "stats" then
        self:PrintStats(false)
    elseif cmd == "allstats" then
        self:PrintStats(true)
    elseif cmd == "reset" then
        self:ResetStats()
    elseif cmd == "link" then
        -- /gr link <alt> [main]  — if main omitted, defaults to current character
        local alt, main = strsplit(" ", rest, 2)
        alt  = strtrim(alt  or "")
        main = strtrim(main or "")
        if alt == "" then
            self:Announce("Usage: /gr link <alt> [main]")
            self:Announce("  Omitting [main] links the alt to your current character.")
        else
            if main == "" then main = self.game.playerName end
            self:LinkAlt(main, alt)
        end
    elseif cmd == "unlink" then
        -- /gr unlink <alt>
        if rest == "" then
            self:Announce("Usage: /gr unlink <alt>")
        else
            self:UnlinkAlt(rest)
        end
    elseif cmd == "links" then
        self:ListLinks()
    else
        self:Announce("Commands:")
        self:Announce("  /gr show            - Toggle window")
        self:Announce("  /gr stats           - Top 5 leaderboard")
        self:Announce("  /gr allstats        - Full leaderboard")
        self:Announce("  /gr link <alt> [main] - Link alt to main (default: current char)")
        self:Announce("  /gr unlink <alt>    - Remove alt link")
        self:Announce("  /gr links           - List all alt links")
        self:Announce("  /gr reset           - Reset all stats")
    end
end

-- ── Utility ───────────────────────────────────────────────────────────────────

-- Print a message only in the local chat frame (no group broadcast).
function GoldRoll:Announce(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffFFD700[GoldRoll]|r " .. tostring(msg))
end

-- Send a message to the active group channel.
function GoldRoll:GroupSay(msg)
    SendChatMessage(msg, self.game.channel)
end

-- Format a number with commas: 1234567 → "1,234,567"
function GoldRoll:FormatGold(n)
    local s = tostring(math.floor(n))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- ── Alt linking ───────────────────────────────────────────────────────────────

-- Returns the canonical (main) name for a given character name.
function GoldRoll:GetMain(name)
    return self.db.global.altLinks[name] or name
end

-- Returns stats with all alt amounts folded into their mains.
function GoldRoll:GetMergedStats()
    local merged = {}
    for name, amount in pairs(self.db.global.stats) do
        local main = self:GetMain(name)
        merged[main] = (merged[main] or 0) + amount
    end
    return merged
end

function GoldRoll:LinkAlt(mainName, altName)
    if mainName == altName then
        self:Announce("Cannot link a character to itself.")
        return
    end
    -- Prevent the main itself from being someone else's alt (circular link)
    if self.db.global.altLinks[mainName] then
        self:Announce(mainName .. " is already linked as an alt of " ..
                      self.db.global.altLinks[mainName] .. ". Unlink it first.")
        return
    end
    self.db.global.altLinks[altName] = mainName
    self:Announce(string.format("Linked %s as an alt of %s.", altName, mainName))
    self:RefreshLeaderboard()
end

function GoldRoll:UnlinkAlt(altName)
    if self.db.global.altLinks[altName] then
        local main = self.db.global.altLinks[altName]
        self.db.global.altLinks[altName] = nil
        self:Announce(string.format("Unlinked %s from %s.", altName, main))
        self:RefreshLeaderboard()
    else
        self:Announce(altName .. " has no link to remove.")
    end
end

function GoldRoll:ListLinks()
    -- Group alts under their mains for readable output
    local byMain = {}
    for alt, main in pairs(self.db.global.altLinks) do
        byMain[main] = byMain[main] or {}
        table.insert(byMain[main], alt)
    end

    local count = 0
    for main, alts in pairs(byMain) do
        table.sort(alts)
        self:Announce(string.format("%s  <--  %s", main, table.concat(alts, ", ")))
        count = count + 1
    end
    if count == 0 then
        self:Announce("No alt links configured. Use /gr link <alt> [main] to add one.")
    end
end

-- ── Stats ─────────────────────────────────────────────────────────────────────

function GoldRoll:UpdateStat(name, delta)
    local stats = self.db.global.stats
    stats[name] = (stats[name] or 0) + delta
end

function GoldRoll:PrintStats(showAll)
    local merged = self:GetMergedStats()
    local list   = {}
    for name, amount in pairs(merged) do
        table.insert(list, { name = name, amount = amount })
    end
    table.sort(list, function(a, b) return a.amount > b.amount end)

    if #list == 0 then
        self:Announce("No stats recorded yet.")
        return
    end

    local limit = showAll and #list or math.min(5, #list)
    self:Announce("=== GoldRoll Stats ===")
    for i = 1, limit do
        local e    = list[i]
        local sign = e.amount >= 0 and "+" or ""
        self:Announce(string.format("%d. %s: %s%sg", i, e.name, sign, self:FormatGold(e.amount)))
    end
end

function GoldRoll:ResetStats()
    self.db.global.stats = {}
    self:Announce("Stats reset.")
end
