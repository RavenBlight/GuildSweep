-- GuildSweep: opt-in auto-deposit of loose money into the guild bank.
GuildSweepDB = GuildSweepDB or {}
local DB
local ui
local pending = false

local GOLD_CAP = 100  -- max gold per day in "gold" mode

local MODES = {
    { key = "copper",     label = "All my copper" },
    { key = "halfsilver", label = "Half my silver + all my copper (1x/day)" },
    { key = "silver",     label = "All my silver + copper" },
    { key = "gold",       label = "Fixed gold amount (1x/day):" },
}
local DAILY = { halfsilver = true, gold = true }

local function CanDaily()
    return GetServerTime() >= (DB.nextReset or 0)
end

local function MarkDaily()
    local secs
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        secs = C_DateAndTime.GetSecondsUntilDailyReset()
    end
    DB.nextReset = GetServerTime() + (secs or 86400)  -- fallback: rolling 24h
end

local function FormatMoney(c)
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if fn then
        local ok, s = pcall(fn, c)
        if ok and s then return s end
    end
    return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100)
end

local function Amount()
    local money, mode = GetMoney(), DB.mode
    local copper = money % 100
    local silver = math.floor((money % 10000) / 100)  -- silver coins only
    if mode == "copper" then
        return copper
    elseif mode == "silver" then
        return silver * 100 + copper
    elseif mode == "halfsilver" then
        return math.floor(silver / 2) * 100 + copper
    elseif mode == "gold" then
        return math.min(math.min(DB.gold or 0, GOLD_CAP) * 10000, money)
    end
    return 0
end

local function dbg(...)
    if DB and DB.debug then print("|cffff9900GS debug:|r", ...) end
end

-- fixedAmt is given only when the player just accepted the "not enough gold" popup.
local function Deposit(fixedAmt)
    pending = true
    -- The bank window may not be ready the instant the interaction event fires.
    C_Timer.After(0.5, function()
        local amt = fixedAmt and math.min(fixedAmt, GetMoney()) or Amount()  -- recompute now
        dbg("mode", DB.mode, "amount", amt)
        if amt <= 0 then pending = false; return dbg("nothing to deposit") end

        local before = GetMoney()
        DepositGuildBankMoney(amt)
        C_Timer.After(2, function()
            pending = false
            local spent = before - GetMoney()
            if spent > 0 then  -- only count it if the money actually left
                if DAILY[DB.mode] then MarkDaily() end
                print("|cff00ff00GuildSweep:|r deposited " .. FormatMoney(spent))
            else
                dbg("deposit call made but money did not leave your wallet")
                if fixedAmt then
                    print("|cff00ff00GuildSweep:|r the deposit didn't go through. Is the guild bank still open?")
                end
            end
        end)
    end)
end

-- Shown in gold mode when the player has less than their chosen amount.
StaticPopupDialogs["GUILDSWEEP_SHORT"] = {
    text = "You are set to deposit %sg a day, but you currently have only %s.\n\nDo you want to deposit this right now?\n\nNo take backs: guild bank withdrawals are limited by rank.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) Deposit(data) end,
    OnCancel = function() MarkDaily() end,  -- declined: don't ask again until the daily reset
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function Sweep()
    if not DB or not DB.configured then return dbg("not configured") end
    if pending then return dbg("pending") end
    if DAILY[DB.mode] and not CanDaily() then return dbg("daily limit hit") end
    if Amount() <= 0 then return dbg("nothing to deposit") end

    if DB.mode == "gold" then
        local goldAmt = math.min(DB.gold or 0, GOLD_CAP)
        local money = GetMoney()
        if goldAmt > 0 and money < goldAmt * 10000 then
            dbg("gold shortfall, asking player", money)
            StaticPopup_Show("GUILDSWEEP_SHORT", tostring(goldAmt), FormatMoney(money), money)
            return
        end
    end

    Deposit()
end

-- Staged choices from the window. Nothing reaches saved settings until
-- FinishSave runs (Save, plus Yes on the gold confirmation popup).
local sel = {}

local function FinishSave()
    DB.mode = sel.mode
    DB.gold = sel.gold
    DB.configured = true
    print("|cff00ff00GuildSweep:|r saved. Type /guildsweep to change it.")
    ui:Hide()
end

StaticPopupDialogs["GUILDSWEEP_CONFIRM"] = {
    text = "Do you REALLY want to donate %sg to the guild bank once a day?\n\nYou can change this any time with /guildsweep.",
    button1 = YES,
    button2 = NO,
    OnAccept = FinishSave,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function BuildUI()
    ui = CreateFrame("Frame", "GuildSweepFrame", UIParent, "BasicFrameTemplateWithInset")
    ui:SetSize(320, 250)
    ui:SetPoint("CENTER")
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    ui.TitleText:SetText("GuildSweep - Guild Contribution")
    ui:Hide()  -- new frames start visible; hide so Show() later really fires OnShow

    local intro = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, -32)
    intro:SetWidth(288)
    intro:SetJustifyH("LEFT")
    intro:SetText("When you open the guild bank, deposit:")

    local buttons, y = {}, -52
    local function Refresh()
        for key, b in pairs(buttons) do b:SetChecked(sel.mode == key) end
    end
    for _, m in ipairs(MODES) do
        local b = CreateFrame("CheckButton", nil, ui, "UICheckButtonTemplate")
        b:SetPoint("TOPLEFT", 12, y)
        local fs = b.Text or b.text
        if fs then fs:SetText(m.label) end
        b:SetScript("OnClick", function() sel.mode = m.key; Refresh() end)
        buttons[m.key] = b
        y = y - 28
    end

    local goldBox = CreateFrame("EditBox", nil, ui, "InputBoxTemplate")
    goldBox:SetSize(60, 20)
    goldBox:SetPoint("TOPLEFT", 48, y - 4)
    goldBox:SetAutoFocus(false)
    goldBox:SetNumeric(true)
    goldBox:SetMaxLetters(3)
    local gl = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gl:SetPoint("LEFT", goldBox, "RIGHT", 6, 0)
    gl:SetText("gold (max " .. GOLD_CAP .. "/day)")

    local save = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    save:SetSize(100, 24)
    save:SetPoint("BOTTOM", 0, 14)
    save:SetText("Save")
    save:SetScript("OnClick", function()
        local g = tonumber(goldBox:GetText()) or 0
        if g > GOLD_CAP then
            g = GOLD_CAP
            print("|cff00ff00GuildSweep:|r gold amount capped at " .. GOLD_CAP .. "g per day.")
        end
        sel.gold = g
        goldBox:SetText(tostring(g))
        if sel.mode == "gold" and g > 0 then
            StaticPopup_Show("GUILDSWEEP_CONFIRM", tostring(g))
        else
            FinishSave()
        end
    end)

    ui:SetScript("OnShow", function()
        sel.mode = DB.mode            -- reload from saved settings; discards unsaved changes
        sel.gold = DB.gold or 1
        goldBox:SetText(tostring(sel.gold))
        Refresh()
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
pcall(f.RegisterEvent, f, "GUILDBANKFRAME_OPENED")
pcall(f.RegisterEvent, f, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        DB = GuildSweepDB
        DB.mode = DB.mode or "copper"
        BuildUI()
        if not DB.configured then ui:Show() end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        dbg("interaction event", tostring(arg1))
        if Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.GuildBanker then
            Sweep()
        end
    else
        dbg("event", event)
        Sweep()
    end
end)

SLASH_GUILDSWEEP1 = "/guildsweep"
SlashCmdList.GUILDSWEEP = function(msg)
    if (msg or ""):lower():match("debug") then
        DB.debug = not DB.debug
        print("|cff00ff00GuildSweep:|r debug " .. (DB.debug and "ON" or "OFF"))
    elseif ui then
        ui:SetShown(not ui:IsShown())
    end
end
