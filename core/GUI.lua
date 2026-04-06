-- GUI.lua: GoldRoll window — movable, draggable, live-updating

local FRAME_W      = 360
local FRAME_H      = 330
local ROW_H        = 18
local MAX_ROWS     = 16   -- pre-created rows (handles up to 40-man raids with scroll)
local CONTENT_H    = ROW_H * MAX_ROWS

local mainFrame    = nil
local playerRows   = {}

-- ── Build the main window ─────────────────────────────────────────────────────

function GoldRoll:BuildUI()
    -- Main frame
    mainFrame = CreateFrame("Frame", "GoldRollFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(FRAME_W, FRAME_H)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetScale(self.db.global.scale)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:Hide()

    -- Title
    mainFrame.TitleText:SetText("|cffFFD700Gold|rRoll")

    -- ── Wager row ─────────────────────────────────────────────────────────────
    local wagerLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wagerLabel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, -30)
    wagerLabel:SetText("Wager (g):")

    local wagerInput = CreateFrame("EditBox", "GoldRollWagerInput", mainFrame, "InputBoxTemplate")
    wagerInput:SetSize(80, 20)
    wagerInput:SetPoint("LEFT", wagerLabel, "RIGHT", 6, 0)
    wagerInput:SetAutoFocus(false)
    wagerInput:SetNumeric(true)
    wagerInput:SetMaxLetters(9)
    wagerInput:SetText(tostring(self.db.global.wager))
    wagerInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val > 0 then
            GoldRoll.db.global.wager = val
            GoldRoll.game.wager      = val
        else
            self:SetText(tostring(GoldRoll.db.global.wager))
        end
        self:ClearFocus()
    end)
    wagerInput:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(GoldRoll.db.global.wager))
        self:ClearFocus()
    end)
    mainFrame.wagerInput = wagerInput

    -- Channel cycle button
    local channelBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    channelBtn:SetSize(65, 22)
    channelBtn:SetPoint("LEFT", wagerInput, "RIGHT", 10, 0)
    channelBtn:SetText(self.game.channel)
    channelBtn:SetScript("OnClick", function(btn)
        if GoldRoll.game.state ~= GoldRoll.STATES.IDLE then return end
        local channels = GoldRoll.CHANNELS
        local idx = 1
        for i, ch in ipairs(channels) do
            if ch == GoldRoll.game.channel then idx = i; break end
        end
        idx = (idx % #channels) + 1
        GoldRoll.game.channel        = channels[idx]
        GoldRoll.db.global.channel   = channels[idx]
        btn:SetText(channels[idx])
    end)
    channelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Chat Channel", 1, 1, 1)
        GameTooltip:AddLine("Click to cycle: PARTY → RAID → GUILD", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    channelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.channelBtn = channelBtn

    -- ── Separator ─────────────────────────────────────────────────────────────
    local sep1 = mainFrame:CreateTexture(nil, "ARTWORK")
    sep1:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    sep1:SetSize(FRAME_W - 26, 1)
    sep1:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 13, -56)

    -- ── View tabs ─────────────────────────────────────────────────────────────
    local tabW = math.floor((FRAME_W - 30) / 2)

    local gameTabBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    gameTabBtn:SetSize(tabW, 22)
    gameTabBtn:SetPoint("TOPLEFT", sep1, "BOTTOMLEFT", 0, -4)
    gameTabBtn:SetText("Game")
    gameTabBtn:SetScript("OnClick", function() GoldRoll:SetTab("game") end)
    mainFrame.gameTabBtn = gameTabBtn

    local lbTabBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    lbTabBtn:SetSize(tabW, 22)
    lbTabBtn:SetPoint("LEFT", gameTabBtn, "RIGHT", 4, 0)
    lbTabBtn:SetText("Leaderboard")
    lbTabBtn:SetScript("OnClick", function() GoldRoll:SetTab("leaderboard") end)
    mainFrame.lbTabBtn = lbTabBtn

    -- ── Column headers (game view) ────────────────────────────────────────────
    local hdrName = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrName:SetPoint("TOPLEFT", gameTabBtn, "BOTTOMLEFT", 4, -4)
    hdrName:SetWidth(190)
    hdrName:SetJustifyH("LEFT")
    hdrName:SetText("Player")
    mainFrame.hdrName = hdrName

    local hdrRoll = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrRoll:SetPoint("LEFT", hdrName, "RIGHT", 0, 0)
    hdrRoll:SetWidth(60)
    hdrRoll:SetJustifyH("CENTER")
    hdrRoll:SetText("Roll")
    mainFrame.hdrRoll = hdrRoll

    local hdrResult = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrResult:SetPoint("LEFT", hdrRoll, "RIGHT", 0, 0)
    hdrResult:SetWidth(80)
    hdrResult:SetJustifyH("CENTER")
    hdrResult:SetText("Result")
    mainFrame.hdrResult = hdrResult

    -- ── Scroll frame for player list ──────────────────────────────────────────
    local listH = ROW_H * 9   -- visible area: 9 rows

    local scrollFrame = CreateFrame("ScrollFrame", "GoldRollScrollFrame", mainFrame,
                                    "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(FRAME_W - 44, listH)
    scrollFrame:SetPoint("TOPLEFT", hdrName, "BOTTOMLEFT", 0, -3)
    mainFrame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(FRAME_W - 44, CONTENT_H)
    scrollFrame:SetScrollChild(content)
    mainFrame.scrollContent = content

    -- Pre-create player rows
    for i = 1, MAX_ROWS do
        local row = {}

        local bg = content:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(FRAME_W - 44, ROW_H)
        bg:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        if i % 2 == 0 then
            bg:SetColorTexture(0.14, 0.14, 0.14, 0.6)
        else
            bg:SetColorTexture(0.08, 0.08, 0.08, 0.4)
        end
        bg:Hide()
        row.bg = bg

        local nameFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("LEFT", bg, "LEFT", 4, 0)
        nameFS:SetWidth(190)
        nameFS:SetJustifyH("LEFT")
        row.nameFS = nameFS

        local rollFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        rollFS:SetPoint("LEFT", nameFS, "RIGHT", 0, 0)
        rollFS:SetWidth(60)
        rollFS:SetJustifyH("CENTER")
        row.rollFS = rollFS

        local resultFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        resultFS:SetPoint("LEFT", rollFS, "RIGHT", 0, 0)
        resultFS:SetWidth(80)
        resultFS:SetJustifyH("CENTER")
        row.resultFS = resultFS

        playerRows[i] = row
    end

    -- ── Leaderboard panel (hidden until tab is clicked) ───────────────────────
    local LB_ROW_H   = 17
    local MAX_LB     = 10   -- top 10 winners, top 10 losers
    local LB_TOTAL   = MAX_LB * 2 + 2   -- +2 for section header rows

    local lbPanel = CreateFrame("Frame", nil, mainFrame)
    lbPanel:SetSize(FRAME_W - 26, listH + 20)
    lbPanel:SetPoint("TOPLEFT", gameTabBtn, "BOTTOMLEFT", 0, -4)
    lbPanel:Hide()
    mainFrame.lbPanel  = lbPanel
    mainFrame.MAX_LB   = MAX_LB

    local lbScroll = CreateFrame("ScrollFrame", "GoldRollLBScroll", lbPanel,
                                 "UIPanelScrollFrameTemplate")
    lbScroll:SetSize(FRAME_W - 44, listH + 20 - 30)
    lbScroll:SetPoint("TOPLEFT", lbPanel, "TOPLEFT", 0, 0)

    local lbContent = CreateFrame("Frame", nil, lbScroll)
    lbContent:SetSize(FRAME_W - 44, LB_ROW_H * LB_TOTAL)
    lbScroll:SetScrollChild(lbContent)

    local lbRows = {}
    for i = 1, LB_TOTAL do
        local rowBg = lbContent:CreateTexture(nil, "BACKGROUND")
        rowBg:SetSize(FRAME_W - 44, LB_ROW_H)
        rowBg:SetPoint("TOPLEFT", lbContent, "TOPLEFT", 0, -(i - 1) * LB_ROW_H)
        rowBg:Hide()

        local rankFS = lbContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rankFS:SetPoint("LEFT", rowBg, "LEFT", 4, 0)
        rankFS:SetWidth(24)
        rankFS:SetJustifyH("LEFT")

        local nameFS = lbContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFS:SetPoint("LEFT", rankFS, "RIGHT", 2, 0)
        nameFS:SetWidth(180)
        nameFS:SetJustifyH("LEFT")

        local amtFS = lbContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        amtFS:SetPoint("LEFT", nameFS, "RIGHT", 0, 0)
        amtFS:SetWidth(100)
        amtFS:SetJustifyH("RIGHT")

        lbRows[i] = { bg = rowBg, rankFS = rankFS, nameFS = nameFS, amtFS = amtFS }
    end
    mainFrame.lbRows = lbRows

    -- Reset Stats button at the bottom of the leaderboard panel
    local resetBtn = CreateFrame("Button", nil, lbPanel, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 22)
    resetBtn:SetPoint("BOTTOMRIGHT", lbPanel, "BOTTOMRIGHT", -2, 2)
    resetBtn:SetText("Reset Stats")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("GOLDROLL_RESET_CONFIRM")
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset Stats", 1, 0.2, 0.2)
        GameTooltip:AddLine("Permanently wipe all win/loss records.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Separator ─────────────────────────────────────────────────────────────
    local sep2 = mainFrame:CreateTexture(nil, "ARTWORK")
    sep2:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    sep2:SetSize(FRAME_W - 26, 1)
    sep2:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 0, -6)

    -- ── Status bar ────────────────────────────────────────────────────────────
    local statusFS = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFS:SetPoint("TOPLEFT", sep2, "BOTTOMLEFT", 0, -4)
    statusFS:SetWidth(FRAME_W - 26)
    statusFS:SetJustifyH("CENTER")
    statusFS:SetText("Idle — start a new game to begin.")
    mainFrame.statusFS = statusFS

    -- ── Separator ─────────────────────────────────────────────────────────────
    local sep3 = mainFrame:CreateTexture(nil, "ARTWORK")
    sep3:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    sep3:SetSize(FRAME_W - 26, 1)
    sep3:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 44)

    -- ── Action buttons ────────────────────────────────────────────────────────
    local newBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    newBtn:SetSize(64, 24)
    newBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 10, 10)
    newBtn:SetText("New Game")
    newBtn:SetScript("OnClick", function()
        GoldRoll:StartGame()
    end)
    newBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("New Game", 1, 1, 1)
        GameTooltip:AddLine("Open registration. Others type 1 to join.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    newBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.newBtn = newBtn

    local announceBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    announceBtn:SetSize(64, 24)
    announceBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
    announceBtn:SetText("Announce")
    announceBtn:SetScript("OnClick", function()
        GoldRoll:AnnounceJoin()
    end)
    announceBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Announce", 1, 1, 1)
        GameTooltip:AddLine("Re-send the join instructions to group chat.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    announceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.announceBtn = announceBtn

    local rollBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    rollBtn:SetSize(64, 24)
    rollBtn:SetPoint("LEFT", announceBtn, "RIGHT", 6, 0)
    rollBtn:SetText("Start Rolls")
    rollBtn:SetScript("OnClick", function()
        local state = GoldRoll.game.state
        if state == GoldRoll.STATES.REGISTERING then
            GoldRoll:BeginRolling()
        elseif state == GoldRoll.STATES.ROLLING then
            -- Nudge anyone who hasn't rolled yet
            local pending = GoldRoll:PendingRollers()
            if #pending > 0 then
                GoldRoll:GroupSay("[GoldRoll] Still waiting on: " .. table.concat(pending, ", "))
            else
                GoldRoll:Announce("Everyone has rolled!")
            end
        end
    end)
    rollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local state = GoldRoll.game.state
        if state == GoldRoll.STATES.REGISTERING then
            GameTooltip:SetText("Start Rolls", 1, 1, 1)
            GameTooltip:AddLine("Close entries and prompt everyone to /roll.", 0.8, 0.8, 0.8, true)
        elseif state == GoldRoll.STATES.ROLLING then
            GameTooltip:SetText("Remind Roll", 1, 1, 1)
            GameTooltip:AddLine("Announce who still needs to roll.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    rollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.rollBtn = rollBtn

    local myRollBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    myRollBtn:SetSize(64, 24)
    myRollBtn:SetPoint("LEFT", rollBtn, "RIGHT", 6, 0)
    myRollBtn:SetText("Roll!")
    myRollBtn:SetScript("OnClick", function()
        RandomRoll(1, GoldRoll.game.wager)
    end)
    myRollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Roll!", 1, 1, 1)
        GameTooltip:AddLine(string.format("Roll /roll %d for you.", GoldRoll.game.wager), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    myRollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.myRollBtn = myRollBtn

    local cancelBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(64, 24)
    cancelBtn:SetPoint("LEFT", myRollBtn, "RIGHT", 6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        GoldRoll:CancelGame()
    end)
    mainFrame.cancelBtn = cancelBtn

    self:RefreshUI()
end

-- ── Show / hide ───────────────────────────────────────────────────────────────

function GoldRoll:ShowUI()  mainFrame:Show() end
function GoldRoll:HideUI()  mainFrame:Hide() end

function GoldRoll:ToggleUI()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        if not mainFrame.activeTab then
            self:SetTab("game")
        end
        self:RefreshUI()
    end
end

-- ── Tab switching ─────────────────────────────────────────────────────────────

function GoldRoll:SetTab(tab)
    mainFrame.activeTab = tab
    local onGame = (tab == "game")

    -- Show/hide game view elements
    mainFrame.hdrName:SetShown(onGame)
    mainFrame.hdrRoll:SetShown(onGame)
    mainFrame.hdrResult:SetShown(onGame)
    mainFrame.scrollFrame:SetShown(onGame)

    -- Show/hide leaderboard panel
    mainFrame.lbPanel:SetShown(not onGame)

    -- Style tabs: disable the active one so it looks "pressed in"
    mainFrame.gameTabBtn:SetEnabled(not onGame)
    mainFrame.lbTabBtn:SetEnabled(onGame)

    if not onGame then
        self:RefreshLeaderboard()
    end
end

-- ── Leaderboard refresh ───────────────────────────────────────────────────────

function GoldRoll:RefreshLeaderboard()
    if not mainFrame or not mainFrame.lbPanel:IsShown() then return end

    -- Use merged stats so alts are folded into their mains
    local merged  = self:GetMergedStats()
    local altLinks = self.db.global.altLinks

    -- Build a reverse map: mainName -> list of alt names
    local altsByMain = {}
    for alt, main in pairs(altLinks) do
        altsByMain[main] = altsByMain[main] or {}
        table.insert(altsByMain[main], alt)
    end

    local winners, losers = {}, {}
    for name, amount in pairs(merged) do
        local alts = altsByMain[name]
        local label = name
        if alts and #alts > 0 then
            table.sort(alts)
            label = name .. " |cff888888(+" .. #alts .. " alt" .. (#alts > 1 and "s" or "") .. ")|r"
        end
        if amount > 0 then
            table.insert(winners, { label = label, amount = amount })
        elseif amount < 0 then
            table.insert(losers,  { label = label, amount = amount })
        end
    end

    table.sort(winners, function(a, b) return a.amount > b.amount end)
    table.sort(losers,  function(a, b) return a.amount < b.amount end)

    local MAX_LB = mainFrame.MAX_LB
    local lbRows = mainFrame.lbRows
    local rowIdx = 1

    local function writeSection(label, entries, isWinner)
        local hdrRow = lbRows[rowIdx]
        if not hdrRow then return end
        hdrRow.bg:Hide()
        hdrRow.rankFS:SetText("")
        hdrRow.nameFS:SetText(label)
        hdrRow.nameFS:SetTextColor(1, 0.84, 0)
        hdrRow.amtFS:SetText("")
        rowIdx = rowIdx + 1

        if #entries == 0 then
            local row = lbRows[rowIdx]
            if row then
                row.bg:Show()
                row.rankFS:SetText("")
                row.nameFS:SetText("  None yet")
                row.nameFS:SetTextColor(0.5, 0.5, 0.5)
                row.amtFS:SetText("")
                rowIdx = rowIdx + 1
            end
            return
        end

        for i = 1, math.min(#entries, MAX_LB) do
            local row = lbRows[rowIdx]
            if not row then return end
            local e = entries[i]

            row.bg:Show()
            if i % 2 == 0 then
                row.bg:SetColorTexture(0.14, 0.14, 0.14, 0.6)
            else
                row.bg:SetColorTexture(0.08, 0.08, 0.08, 0.4)
            end

            row.rankFS:SetText(i .. ".")
            row.rankFS:SetTextColor(0.6, 0.6, 0.6)

            row.nameFS:SetText(e.label)
            row.nameFS:SetTextColor(1, 1, 1)

            if isWinner then
                row.amtFS:SetText("+" .. GoldRoll:FormatGold(e.amount) .. "g")
                row.amtFS:SetTextColor(0.4, 1, 0.4)
            else
                row.amtFS:SetText("-" .. GoldRoll:FormatGold(math.abs(e.amount)) .. "g")
                row.amtFS:SetTextColor(1, 0.35, 0.35)
            end

            rowIdx = rowIdx + 1
        end
    end

    writeSection("Top Winners", winners, true)
    writeSection("Top Losers",  losers,  false)

    -- Clear any unused rows
    for i = rowIdx, #lbRows do
        local row = lbRows[i]
        row.bg:Hide()
        row.rankFS:SetText("")
        row.nameFS:SetText("")
        row.amtFS:SetText("")
    end
end

-- ── Refresh: sync UI state with game state ────────────────────────────────────

function GoldRoll:RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    local state   = self.game.state
    local isHost  = self.game.isHost
    local players = self.game.players
    local wager   = self.game.wager

    -- Status text
    if state == GoldRoll.STATES.IDLE then
        mainFrame.statusFS:SetText("Idle — start a new game to begin.")
        mainFrame.statusFS:SetTextColor(0.7, 0.7, 0.7)

    elseif state == GoldRoll.STATES.REGISTERING then
        mainFrame.statusFS:SetText(string.format(
            "Registering: %d player(s) | Wager: %sg | Type 1 to join!",
            #players, self:FormatGold(wager)
        ))
        mainFrame.statusFS:SetTextColor(0.4, 1, 0.4)

    elseif state == GoldRoll.STATES.ROLLING then
        local rolled = 0
        for _, p in ipairs(players) do if p.roll then rolled = rolled + 1 end end
        mainFrame.statusFS:SetText(string.format(
            "Rolling: %d / %d rolled | Type /roll %d",
            rolled, #players, wager
        ))
        mainFrame.statusFS:SetTextColor(1, 0.84, 0)
    end

    -- Wager input: editable only when idle
    mainFrame.wagerInput:SetEnabled(state == GoldRoll.STATES.IDLE)
    mainFrame.channelBtn:SetEnabled(state == GoldRoll.STATES.IDLE)

    -- New Game button
    mainFrame.newBtn:SetEnabled(state == GoldRoll.STATES.IDLE)

    -- Announce button: host only, during registration
    mainFrame.announceBtn:SetEnabled(
        isHost and state == GoldRoll.STATES.REGISTERING
    )

    -- Start Rolls / Remind Roll button
    if state == GoldRoll.STATES.REGISTERING and isHost then
        mainFrame.rollBtn:SetText("Start Rolls")
        mainFrame.rollBtn:SetEnabled(true)
    elseif state == GoldRoll.STATES.ROLLING then
        mainFrame.rollBtn:SetText("Remind Roll")
        mainFrame.rollBtn:SetEnabled(isHost)
    else
        mainFrame.rollBtn:SetText("Start Rolls")
        mainFrame.rollBtn:SetEnabled(false)
    end

    -- Roll! button: only while rolling and the host hasn't rolled yet
    local hostPlayer  = self:GetPlayer(self.game.playerName)
    local hostRolled  = hostPlayer and hostPlayer.roll ~= nil
    mainFrame.myRollBtn:SetEnabled(
        state == GoldRoll.STATES.ROLLING and not hostRolled
    )

    -- Cancel button: only host, only during an active game
    mainFrame.cancelBtn:SetEnabled(
        isHost and state ~= GoldRoll.STATES.IDLE
    )

    -- ── Determine high/low rolls for colour coding ────────────────────────────
    local highRoll, lowRoll = -1, math.huge
    for _, p in ipairs(players) do
        if p.roll then
            if p.roll > highRoll then highRoll = p.roll end
            if p.roll < lowRoll  then lowRoll  = p.roll end
        end
    end
    local prize = (highRoll > lowRoll) and (highRoll - lowRoll) or 0

    -- Refresh leaderboard if it's the active tab
    if mainFrame.activeTab == "leaderboard" then
        self:RefreshLeaderboard()
    end

    -- ── Player rows ───────────────────────────────────────────────────────────
    for i, row in ipairs(playerRows) do
        local p = players[i]
        if p then
            row.bg:Show()

            -- Name: highlight your own character in a lighter tint
            row.nameFS:SetText(p.name)
            if p.name == self.game.playerName then
                row.nameFS:SetTextColor(0.4, 0.8, 1)
            else
                row.nameFS:SetTextColor(1, 1, 1)
            end

            -- Roll column
            if p.roll then
                row.rollFS:SetText(tostring(p.roll))
                if p.roll == highRoll and p.roll ~= lowRoll then
                    -- Winner: gold
                    row.rollFS:SetTextColor(1, 0.84, 0)
                elseif p.roll == lowRoll and p.roll ~= highRoll then
                    -- Loser: red
                    row.rollFS:SetTextColor(1, 0.3, 0.3)
                else
                    row.rollFS:SetTextColor(0.9, 0.9, 0.9)
                end
            else
                row.rollFS:SetText("---")
                row.rollFS:SetTextColor(0.45, 0.45, 0.45)
            end

            -- Result column: show "+" or "−" gold only after all players have rolled
            if p.roll and prize > 0 then
                if p.roll == highRoll and p.roll ~= lowRoll then
                    row.resultFS:SetText("+  " .. GoldRoll:FormatGold(prize) .. "g")
                    row.resultFS:SetTextColor(0.4, 1, 0.4)
                elseif p.roll == lowRoll and p.roll ~= highRoll then
                    row.resultFS:SetText("−  " .. GoldRoll:FormatGold(prize) .. "g")
                    row.resultFS:SetTextColor(1, 0.4, 0.4)
                else
                    row.resultFS:SetText("")
                end
            else
                row.resultFS:SetText("")
            end
        else
            -- Empty row
            row.bg:Hide()
            row.nameFS:SetText("")
            row.rollFS:SetText("")
            row.resultFS:SetText("")
        end
    end
end
