-- Game.lua: State machine, player registration, roll resolution

-- ── Start a new game (host) ───────────────────────────────────────────────────

function GoldRoll:StartGame()
    if self.game.state ~= GoldRoll.STATES.IDLE then
        self:Announce("A game is already in progress!")
        return
    end

    self.game.state   = GoldRoll.STATES.REGISTERING
    self.game.isHost  = true
    self.game.wager   = self.db.global.wager
    self.game.channel = self.db.global.channel
    self.game.players = {}
    self.game.result  = nil

    -- Auto-register the host
    self:AddPlayer(self.game.playerName)

    -- Sync wager and channel to all other clients before broadcasting NEW_GAME
    self:Broadcast("SET_CHANNEL", self.game.channel)
    self:Broadcast("SET_WAGER",   tostring(self.game.wager))
    self:Broadcast("NEW_GAME")

    -- Start listening for join/leave ("1" / "-1") in group chat
    self:RegisterJoinEvents()

    self:GroupSay(string.format(
        "[GoldRoll] New game! Wager: %sg -- Type 1 to join, -1 to leave.",
        self:FormatGold(self.game.wager)
    ))

    self:RefreshUI()
end

-- ── Re-announce join instructions (host) ─────────────────────────────────────

function GoldRoll:AnnounceJoin()
    if self.game.state ~= GoldRoll.STATES.REGISTERING then return end
    self:GroupSay(string.format(
        "[GoldRoll] Gambling game open! Wager: %sg -- Type 1 to join, -1 to leave.",
        self:FormatGold(self.game.wager)
    ))
end

-- ── Begin rolling phase (host) ────────────────────────────────────────────────

function GoldRoll:BeginRolling()
    if self.game.state ~= GoldRoll.STATES.REGISTERING then
        self:Announce("Not in registration phase.")
        return
    end
    if not self.game.isHost then
        self:Announce("Only the host can start rolling.")
        return
    end
    if #self.game.players < 2 then
        self:GroupSay("[GoldRoll] Need at least 2 players to start rolling!")
        return
    end

    self.game.state = GoldRoll.STATES.ROLLING

    self:UnregisterJoinEvents()
    -- Only the host watches CHAT_MSG_SYSTEM for roll results
    self:RegisterEvent("CHAT_MSG_SYSTEM", "OnSystemMessage")

    self:Broadcast("START_ROLLS")

    local names = {}
    for _, p in ipairs(self.game.players) do
        table.insert(names, p.name)
    end

    self:GroupSay(string.format(
        "[GoldRoll] Entries closed! All %d players type: /roll %d",
        #self.game.players, self.game.wager
    ))
    self:GroupSay("Players: " .. table.concat(names, ", "))

    self:RefreshUI()
end

-- ── Cancel game (host or cleanup) ────────────────────────────────────────────

function GoldRoll:CancelGame()
    if self.game.state == GoldRoll.STATES.IDLE then return end

    self:UnregisterJoinEvents()
    self:UnregisterEvent("CHAT_MSG_SYSTEM")

    if self.game.isHost then
        self:GroupSay("[GoldRoll] Game cancelled.")
        self:Broadcast("CANCEL")
    end

    self:ResetGame()
    self:RefreshUI()
end

-- ── Player management ─────────────────────────────────────────────────────────

function GoldRoll:AddPlayer(name)
    -- Prevent duplicate registration
    for _, p in ipairs(self.game.players) do
        if p.name == name then return end
    end
    table.insert(self.game.players, { name = name, roll = nil })

    if self.game.isHost then
        self:Announce(name .. " joined! (" .. #self.game.players .. " players)")
    end

    self:RefreshUI()
end

function GoldRoll:RemovePlayer(name)
    for i, p in ipairs(self.game.players) do
        if p.name == name then
            table.remove(self.game.players, i)
            self:RefreshUI()
            return
        end
    end
end

function GoldRoll:GetPlayer(name)
    for _, p in ipairs(self.game.players) do
        if p.name == name then return p end
    end
    return nil
end

-- ── Roll recording (host-side, via CHAT_MSG_SYSTEM) ──────────────────────────

function GoldRoll:RecordRoll(name, roll)
    local player = self:GetPlayer(name)
    if not player then return end   -- player not registered
    if player.roll  then return end -- already rolled

    player.roll = roll

    self:Announce(name .. " rolled " .. roll)
    self:Broadcast("PLAYER_ROLL", name .. ":" .. tostring(roll))
    self:RefreshUI()

    if self:AllRolled() then
        self:ResolveGame()
    end
end

function GoldRoll:AllRolled()
    for _, p in ipairs(self.game.players) do
        if not p.roll then return false end
    end
    return true
end

function GoldRoll:PendingRollers()
    local pending = {}
    for _, p in ipairs(self.game.players) do
        if not p.roll then table.insert(pending, p.name) end
    end
    return pending
end

-- ── Result resolution ─────────────────────────────────────────────────────────

function GoldRoll:ResolveGame()
    local result = self:CalculateResult(self.game.players)
    self.game.result = result

    if self.game.savedResult then
        -- This is a tiebreaker round: keep the original prize and loser,
        -- but use whichever player won the tiebreaker as the winner.
        if #result.winners == 1 then
            local finalResult = {
                winners = result.winners,
                losers  = self.game.savedResult.losers,
                prize   = self.game.savedResult.prize,
            }
            self.game.savedResult = nil
            self:CloseGame(finalResult)
        else
            -- Still tied — run another tiebreaker
            self:TieBreaker("High", result.winners)
        end
        return
    end

    self:HandleTieOrClose(result)
end

-- Returns { winners={}, losers={}, prize=number }
-- prize = highestRoll - lowestRoll
function GoldRoll:CalculateResult(players)
    local winners = { players[1] }
    local losers  = { players[1] }

    for i = 2, #players do
        local p = players[i]
        if p.roll > winners[1].roll then
            winners = { p }
        elseif p.roll == winners[1].roll then
            table.insert(winners, p)
        end
        if p.roll < losers[1].roll then
            losers = { p }
        elseif p.roll == losers[1].roll and p.name ~= winners[1].name then
            table.insert(losers, p)
        end
    end

    -- Complete tie: every player rolled the same number
    if winners[1].name == losers[1].name then
        return { winners = {}, losers = {}, prize = 0 }
    end

    return {
        winners = winners,
        losers  = losers,
        prize   = winners[1].roll - losers[1].roll,
    }
end

function GoldRoll:HandleTieOrClose(result)
    -- Tie for the highest roll → tiebreaker among tied winners
    if #result.winners > 1 then
        -- Preserve the original prize and loser before narrowing the player list
        self.game.savedResult = result
        self:TieBreaker("High", result.winners)
        return
    end
    self:CloseGame(result)
end

function GoldRoll:TieBreaker(tieType, tiedPlayers)
    -- Replace player list with only the tied players, clear their rolls
    self.game.players = tiedPlayers
    for _, p in ipairs(self.game.players) do
        p.roll = nil
    end
    self.game.result = nil

    local names = {}
    for _, p in ipairs(tiedPlayers) do table.insert(names, p.name) end
    local nameStr = table.concat(names, " & ")

    -- Broadcast updated player list so non-host clients stay in sync
    self:Broadcast("TIEBREAKER", nameStr)

    self:GroupSay(string.format(
        "[GoldRoll] TIE between %s — re-roll to break it: /roll %d",
        nameStr, self.game.wager
    ))

    self:RefreshUI()
end

function GoldRoll:CloseGame(result)
    self:UnregisterEvent("CHAT_MSG_SYSTEM")

    if #result.winners == 0 then
        -- Everyone rolled the same value
        self:GroupSay("[GoldRoll] Complete tie — no winner this round!")
    else
        local winner = result.winners[1]

        -- Announce one line per loser (handles multi-loser cases)
        for _, loser in ipairs(result.losers) do
            self:GroupSay(string.format(
                "[GoldRoll] %s wins! %s owes %s %sg  (rolled %d vs %d)",
                winner.name,
                loser.name,
                winner.name,
                self:FormatGold(result.prize),
                winner.roll,
                loser.roll
            ))
        end

        -- Update persistent stats: winner earns, each loser pays
        self:UpdateStat(winner.name, result.prize * #result.losers)
        for _, loser in ipairs(result.losers) do
            self:UpdateStat(loser.name, -result.prize)
        end
    end

    -- Broadcast game-over so non-host clients reset
    self:Broadcast("GAME_OVER")

    self:ResetGame()
    self:RefreshUI()
end

function GoldRoll:ResetGame()
    self.game.state       = GoldRoll.STATES.IDLE
    self.game.isHost      = false
    self.game.players     = {}
    self.game.result      = nil
    self.game.savedResult = nil
end
