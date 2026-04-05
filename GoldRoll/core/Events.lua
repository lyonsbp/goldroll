-- Events.lua: Chat and addon-message event handling for GoldRoll

-- ── Group chat join/leave events (REGISTERING phase) ─────────────────────────
-- Players type "1" to join or "-1" to leave while host is accepting entries.

function GoldRoll:RegisterJoinEvents()
    local ch = self.game.channel
    if ch == "PARTY" then
        self:RegisterEvent("CHAT_MSG_PARTY",       "OnJoinMessage")
        self:RegisterEvent("CHAT_MSG_PARTY_LEADER", "OnJoinMessage")
    elseif ch == "RAID" then
        self:RegisterEvent("CHAT_MSG_RAID",        "OnJoinMessage")
        self:RegisterEvent("CHAT_MSG_RAID_LEADER",  "OnJoinMessage")
    elseif ch == "GUILD" then
        self:RegisterEvent("CHAT_MSG_GUILD",        "OnJoinMessage")
    end
end

function GoldRoll:UnregisterJoinEvents()
    self:UnregisterEvent("CHAT_MSG_PARTY")
    self:UnregisterEvent("CHAT_MSG_PARTY_LEADER")
    self:UnregisterEvent("CHAT_MSG_RAID")
    self:UnregisterEvent("CHAT_MSG_RAID_LEADER")
    self:UnregisterEvent("CHAT_MSG_GUILD")
end

-- Fired when anyone types in the active group channel
function GoldRoll:OnJoinMessage(_, text, senderFull)
    if self.game.state ~= GoldRoll.STATES.REGISTERING then return end
    if not self.game.isHost then return end  -- only host manages the player list

    -- Strip realm suffix ("Name-Realm" → "Name")
    local name = strsplit("-", senderFull, 2)

    if text == "1" then
        self:AddPlayer(name)          -- update host's own state immediately
        self:Broadcast("ADD_PLAYER", name)
    elseif text == "-1" then
        self:RemovePlayer(name)
        self:Announce(name .. " left the game.")
        self:Broadcast("REMOVE_PLAYER", name)
    end
end

-- ── System message: captures /roll results (host only) ───────────────────────
-- WoW roll message format: "Playername rolls 73 (1-100)."
-- The verb ("rolls") may be localized, so we match with .+ between name and result.

function GoldRoll:OnSystemMessage(_, text)
    if self.game.state ~= GoldRoll.STATES.ROLLING then return end

    -- Pattern handles optional trailing period and any localized roll verb
    local name, roll, minRoll, maxRoll =
        text:match("^([^ ]+) .+ (%d+) %((%d+)%-(%d+)%)%.?$")

    if not name then return end

    minRoll = tonumber(minRoll)
    maxRoll = tonumber(maxRoll)
    roll    = tonumber(roll)

    -- Only count rolls that match exactly our wager range (1 to wager)
    if minRoll ~= 1 or maxRoll ~= self.game.wager then return end

    self:RecordRoll(name, roll)
end

-- ── Addon messages: cross-client game state sync ──────────────────────────────
-- Host → all clients.  Format: "COMMAND" or "COMMAND:argument"

function GoldRoll:Broadcast(cmd, arg)
    local msg = arg and (cmd .. ":" .. arg) or cmd
    C_ChatInfo.SendAddonMessage(GoldRoll.PREFIX, msg, self.game.channel)
end

function GoldRoll:OnAddonMessage(_, prefix, message, _, senderFull)
    if prefix ~= GoldRoll.PREFIX then return end

    -- Ignore messages we sent ourselves (host receives its own broadcasts)
    local sender = strsplit("-", senderFull, 2)
    if sender == self.game.playerName and self.game.isHost then return end

    local cmd, arg = strsplit(":", message, 2)

    if cmd == "SET_CHANNEL" then
        self.game.channel = arg

    elseif cmd == "SET_WAGER" then
        self.game.wager = tonumber(arg) or self.game.wager

    elseif cmd == "NEW_GAME" then
        -- Non-host clients initialize their game state
        self.game.state   = GoldRoll.STATES.REGISTERING
        self.game.isHost  = false
        self.game.players = {}
        self.game.result  = nil
        self:RegisterJoinEvents()
        self:Announce(string.format(
            "A %sg gambling game has started! Type 1 in chat to join.",
            self:FormatGold(self.game.wager)
        ))
        self:RefreshUI()

    elseif cmd == "ADD_PLAYER" then
        self:AddPlayer(arg)

    elseif cmd == "REMOVE_PLAYER" then
        self:RemovePlayer(arg)
        self:Announce(arg .. " left the game.")
        self:RefreshUI()

    elseif cmd == "START_ROLLS" then
        self.game.state = GoldRoll.STATES.ROLLING
        self:UnregisterJoinEvents()
        -- Non-hosts do NOT register CHAT_MSG_SYSTEM — host handles that
        self:RefreshUI()

    elseif cmd == "PLAYER_ROLL" then
        -- Non-hosts update the player's roll for display purposes
        if arg then
            local name, rollStr = strsplit(":", arg, 2)
            local player = self:GetPlayer(name)
            if player then
                player.roll = tonumber(rollStr)
                self:RefreshUI()
            end
        end

    elseif cmd == "TIEBREAKER" then
        -- arg = comma-joined names of tied players ("Name1 & Name2")
        -- Rebuild the player list to only the tied players, clear their rolls
        if arg then
            local tiedNames = {}
            for name in arg:gmatch("[^&]+") do
                table.insert(tiedNames, strtrim(name))
            end
            local newPlayers = {}
            for _, name in ipairs(tiedNames) do
                table.insert(newPlayers, { name = name, roll = nil })
            end
            self.game.players = newPlayers
            self.game.result  = nil
        end
        self:RefreshUI()

    elseif cmd == "CANCEL" then
        self:UnregisterJoinEvents()
        self:UnregisterEvent("CHAT_MSG_SYSTEM")
        self:ResetGame()
        self:Announce("The game was cancelled by the host.")
        self:RefreshUI()

    elseif cmd == "GAME_OVER" then
        self:UnregisterJoinEvents()
        self:UnregisterEvent("CHAT_MSG_SYSTEM")
        self:ResetGame()
        self:RefreshUI()
    end
end
