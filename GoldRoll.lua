-- GoldRoll: Friendly group gambling for WoW Midnight (12.0)
-- Highest /roll wins (highRoll - lowRoll) gold from the lowest roller.

GoldRoll = LibStub("AceAddon-3.0"):NewAddon("GoldRoll", "AceConsole-3.0", "AceEvent-3.0")

GoldRoll.STATES   = { IDLE = "IDLE", REGISTERING = "REGISTERING", ROLLING = "ROLLING" }
GoldRoll.CHANNELS = { "PARTY", "RAID", "GUILD" }
GoldRoll.PREFIX   = "GoldRoll"

-- Channels available for the Leaderboard Announce feature (/gr announce).
-- These are distinct from GoldRoll.CHANNELS (which governs game coordination)
-- because users may want to brag in SAY/YELL/GUILD while running games in PARTY.
GoldRoll.ANNOUNCE_CHANNELS = {
    { key = "SAY",           label = "Say"      },
    { key = "YELL",          label = "Yell"     },
    { key = "PARTY",         label = "Party"    },
    { key = "RAID",          label = "Raid"     },
    { key = "INSTANCE_CHAT", label = "Instance" },
    { key = "GUILD",         label = "Guild"    },
}

GoldRoll.ANNOUNCE_SCOPES = {
    { key = "FULL",     label = "Full leaderboard"   },
    { key = "TOP10",    label = "Top 10"             },
    { key = "TOP5",     label = "Top 5"              },
    { key = "TOPBOT10", label = "Top 10 & Bottom 10" },
    { key = "TOPBOT5",  label = "Top 5 & Bottom 5"   },
}

-- ── Initialization ────────────────────────────────────────────────────────────

function GoldRoll:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("GoldRollDB", {
        global = {
            wager    = 1000,
            channel  = "PARTY",
            stats    = {},   -- [playerName] = net gold (positive = winnings)
            altLinks = {},   -- [altName]    = mainName
            scale       = 1.0,
            frameWidth  = 480,
            frameHeight = 350,
            minimap     = { hide = false },
            announce = {
                channel = "PARTY",   -- SAY | YELL | PARTY | RAID | INSTANCE_CHAT | GUILD
                scope   = "TOP10",   -- FULL | TOP10 | TOP5 | TOPBOT10 | TOPBOT5
            },
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

    -- Minimap button via LibDataBroker + LibDBIcon
    local ldb = LibStub("LibDataBroker-1.1")
    local icon = LibStub("LibDBIcon-1.0")

    local launcher = ldb:NewDataObject("GoldRoll", {
        type  = "launcher",
        icon  = "Interface\\AddOns\\GoldRoll\\goldroll-logo",
        label = "GoldRoll",
        OnClick = function(_, button)
            if button == "LeftButton" then
                GoldRoll:ToggleUI()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cffFFD700GoldRoll|r")
            tt:AddLine("Click to toggle the GoldRoll window.", 0.8, 0.8, 0.8)
        end,
    })
    icon:Register("GoldRoll", launcher, self.db.global.minimap)

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
    elseif cmd == "announce" then
        -- /gr announce                   → use saved scope + channel
        -- /gr announce <scope>           → override scope, use saved channel
        -- /gr announce <scope> <channel> → override both (one-shot; not persisted)
        local scopeArg, chanArg = strsplit(" ", rest, 2)
        scopeArg = strtrim(scopeArg or "")
        chanArg  = strtrim(chanArg  or "")
        self:AnnounceLeaderboard(
            scopeArg ~= "" and scopeArg:upper() or nil,
            chanArg  ~= "" and chanArg:upper()  or nil
        )
    else
        self:Announce("Commands:")
        self:Announce("  /gr show            - Toggle window")
        self:Announce("  /gr stats           - Top 5 leaderboard")
        self:Announce("  /gr allstats        - Full leaderboard")
        self:Announce("  /gr announce [scope] [channel] - Post leaderboard to chat")
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

-- ── Leaderboard announce ─────────────────────────────────────────────────────

-- Look up a scope/channel entry by key in one of the ANNOUNCE_* tables.
local function findByKey(list, key)
    for _, entry in ipairs(list) do
        if entry.key == key then return entry end
    end
    return nil
end

-- Friendly label for a channel key (for tooltips / local echoes).
function GoldRoll:AnnounceChannelLabel(key)
    local entry = findByKey(GoldRoll.ANNOUNCE_CHANNELS, key)
    return entry and entry.label or key
end

function GoldRoll:AnnounceScopeLabel(key)
    local entry = findByKey(GoldRoll.ANNOUNCE_SCOPES, key)
    return entry and entry.label or key
end

-- Build the sorted winners/losers lists used by the announce/leaderboard views.
-- Returns { winners = { {name, label, amount}, ... }, losers = { ... } }.
-- Labels include a plain-text "(+N alts)" suffix when applicable — no color codes,
-- since this output may be sent to chat (WoW renders escape codes literally there).
function GoldRoll:BuildAnnounceLists()
    local merged   = self:GetMergedStats()
    local altLinks = self.db.global.altLinks

    local altsByMain = {}
    for alt, main in pairs(altLinks) do
        altsByMain[main] = altsByMain[main] or {}
        table.insert(altsByMain[main], alt)
    end

    local winners, losers = {}, {}
    for name, amount in pairs(merged) do
        local alts  = altsByMain[name]
        local label = name
        if alts and #alts > 0 then
            label = string.format("%s (+%d alt%s)", name, #alts, #alts > 1 and "s" or "")
        end
        if amount > 0 then
            table.insert(winners, { name = name, label = label, amount = amount })
        elseif amount < 0 then
            table.insert(losers,  { name = name, label = label, amount = amount })
        end
    end

    table.sort(winners, function(a, b) return a.amount > b.amount end)
    table.sort(losers,  function(a, b) return a.amount < b.amount end)
    return winners, losers
end

-- Format one leaderboard row for chat output: "1. Bob (+1 alt): +12,345g".
local function formatAnnounceRow(rank, entry)
    local sign = entry.amount >= 0 and "+" or "-"
    return string.format("%d. %s: %s%sg",
        rank, entry.label, sign, GoldRoll:FormatGold(math.abs(entry.amount)))
end

-- Returns true if the player is in a valid state to post to the given channel.
-- Second return is a human message describing why not, when false.
local function canSendToChannel(channel)
    if channel == "PARTY" then
        if not IsInGroup() then
            return false, "Can't announce to Party — not in a group."
        end
    elseif channel == "RAID" then
        if not IsInRaid() then
            return false, "Can't announce to Raid — not in a raid."
        end
    elseif channel == "GUILD" then
        if not IsInGuild() then
            return false, "Can't announce to Guild — not in a guild."
        end
    elseif channel == "INSTANCE_CHAT" then
        if not IsInInstance() then
            return false, "Can't announce to Instance — not in an instance."
        end
    end
    return true
end

-- Announce the leaderboard to chat. `scope` and `channel` default to the saved
-- settings when omitted. Both arguments are uppercase keys from ANNOUNCE_*.
function GoldRoll:AnnounceLeaderboard(scope, channel)
    local saved = self.db.global.announce
    scope   = scope   or saved.scope
    channel = channel or saved.channel

    if not findByKey(GoldRoll.ANNOUNCE_SCOPES, scope) then
        self:Announce("Unknown scope: " .. tostring(scope))
        self:Announce("Valid scopes: FULL, TOP10, TOP5, TOPBOT10, TOPBOT5")
        return
    end
    if not findByKey(GoldRoll.ANNOUNCE_CHANNELS, channel) then
        self:Announce("Unknown channel: " .. tostring(channel))
        self:Announce("Valid channels: SAY, YELL, PARTY, RAID, INSTANCE_CHAT, GUILD")
        return
    end

    local winners, losers = self:BuildAnnounceLists()
    if #winners == 0 and #losers == 0 then
        self:Announce("No stats to announce yet.")
        return
    end

    local ok, reason = canSendToChannel(channel)
    if not ok then
        self:Announce(reason)
        return
    end

    -- Decide header + how many of each side to post.
    local header, winnerLimit, loserLimit
    if scope == "FULL" then
        header, winnerLimit, loserLimit = "GoldRoll Leaderboard", #winners, #losers
    elseif scope == "TOP10" then
        header, winnerLimit, loserLimit = "GoldRoll Top 10", math.min(10, #winners), 0
    elseif scope == "TOP5" then
        header, winnerLimit, loserLimit = "GoldRoll Top 5",  math.min(5,  #winners), 0
    elseif scope == "TOPBOT10" then
        header, winnerLimit, loserLimit = "GoldRoll Top/Bottom 10",
            math.min(10, #winners), math.min(10, #losers)
    elseif scope == "TOPBOT5" then
        header, winnerLimit, loserLimit = "GoldRoll Top/Bottom 5",
            math.min(5,  #winners), math.min(5,  #losers)
    end

    local lines = { header }
    if winnerLimit > 0 then
        table.insert(lines, "-- Winners --")
        for i = 1, winnerLimit do
            table.insert(lines, formatAnnounceRow(i, winners[i]))
        end
    end
    if loserLimit > 0 then
        table.insert(lines, "-- Losers --")
        for i = 1, loserLimit do
            table.insert(lines, formatAnnounceRow(i, losers[i]))
        end
    end

    for _, line in ipairs(lines) do
        SendChatMessage(line, channel)
    end
end

function GoldRoll:ResetStats()
    self.db.global.stats = {}
    self:Announce("Stats reset.")
end
