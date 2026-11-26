local ADDON_NAME = ...

local DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -140,
    scale = 1.0,
    locked = false,
    combatOnly = false,
    showRating = false,
    showCooldown = true,
    cachedIcon = 134830,
    potionName = "Potion of Recklessness",
    minimapAngle = 225,   -- degrees around the minimap (225 = bottom-left)
    minimapHide = false,
}

-- "Reset" restores the tracker icon only; the minimap button keeps its own place/visibility
local RESET_SKIP = { cachedIcon = true, minimapAngle = true, minimapHide = true }

local SCALE_PRESETS = { 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0 }
local SCALE_MIN, SCALE_MAX = 0.5, 3.0

local POPUP_ITEM = "RECKLESSSTATTRACKER_SET_ITEM"
local POPUP_RESET = "RECKLESSSTATTRACKER_RESET"

local STAT_DEFS = {
    { key = "Crit",    name = "Crit",    r = 1.00, g = 0.30, b = 0.30 },
    { key = "Haste",   name = "Haste",   r = 0.30, g = 1.00, b = 0.35 },
    { key = "Mastery", name = "Mastery", r = 0.65, g = 0.38, b = 1.00 },
    { key = "Vers",    name = "Vers",    r = 0.30, g = 0.70, b = 1.00 },
}

local db
local trackedItemID = nil
local OpenMenu -- defined in the "Settings Menu" section below

local GetItemCD = (C_Container and C_Container.GetItemCooldown)
    or (C_Item and C_Item.GetItemCooldown)
    or GetItemCooldown

local function PrintMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9d4eff[RecklessStatTracker]|r " .. msg)
end

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function SafeRating(ratingID)
    if not ratingID or not GetCombatRating then return 0 end
    local ok, val = pcall(GetCombatRating, ratingID)
    if ok and type(val) == "number" then
        return val
    end
    return 0
end

local function FormatNumber(n)
    local rounded = math.floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then
        local ok, formatted = pcall(BreakUpLargeNumbers, rounded)
        if ok and formatted then
            return formatted
        end
    end
    return tostring(rounded)
end

-- Main Icon Frame
local frame = CreateFrame("Frame", "RecklessStatTrackerFrame", UIParent)
frame:SetSize(48, 48)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("MEDIUM")

-- Thin 1px dark border (WeakAuras / ElvUI style)
local border = frame:CreateTexture(nil, "BACKGROUND")
border:SetColorTexture(0, 0, 0, 0.9)
border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)

-- Potion Icon Texture
local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints(frame)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetTexture(DEFAULTS.cachedIcon)

-- Cooldown Spiral
local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints(frame)
cooldown:SetDrawEdge(false)

-- Text Overlay (renders above cooldown sweep)
local textOverlay = CreateFrame("Frame", nil, frame)
textOverlay:SetAllPoints(frame)
textOverlay:SetFrameLevel(cooldown:GetFrameLevel() + 2)

-- Highest Secondary Stat Text (above icon)
local statText = textOverlay:CreateFontString(nil, "OVERLAY")
statText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
statText:SetPoint("BOTTOM", frame, "TOP", 0, 4)
statText:SetShadowOffset(1, -1)
statText:SetShadowColor(0, 0, 0, 1)
statText:SetJustifyH("CENTER")
statText:SetText("Mastery")

-- Potion Stack Count Text (bottom-right corner)
local countText = textOverlay:CreateFontString(nil, "OVERLAY")
countText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
countText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
countText:SetShadowOffset(1, -1)
countText:SetShadowColor(0, 0, 0, 1)
countText:SetJustifyH("RIGHT")
countText:SetText("0")

-- Minimap Button (native, same layout as LibDBIcon so it matches other addon buttons)
local minimapButton = CreateFrame("Button", "RecklessStatTrackerMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")
minimapButton:Hide() -- shown once SavedVariables are loaded

local mmBorder = minimapButton:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(50, 50)
mmBorder:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
mmBorder:SetPoint("TOPLEFT", minimapButton, "TOPLEFT")

local mmBackground = minimapButton:CreateTexture(nil, "BACKGROUND")
mmBackground:SetSize(24, 24)
mmBackground:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
mmBackground:SetPoint("CENTER", minimapButton, "CENTER")

local mmIcon = minimapButton:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(18, 18)
mmIcon:SetPoint("CENTER", minimapButton, "CENTER")
mmIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
mmIcon:SetTexture(DEFAULTS.cachedIcon)

-- Both icons always show the tracked potion
local function SetIconTexture(tex)
    icon:SetTexture(tex)
    mmIcon:SetTexture(tex)
end

-- Drag Handling
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if db and not db.locked then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if db then
        local point, _, relativePoint, x, y = self:GetPoint()
        db.point = point
        db.relativePoint = relativePoint
        db.x = math.floor(x + 0.5)
        db.y = math.floor(y + 0.5)
    end
end)

frame:SetScript("OnEnter", function(self)
    if db and not db.locked then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reckless Stat Tracker", 0.65, 0.38, 1.0)
        GameTooltip:AddLine("Drag to move position", 1, 1, 1)
        GameTooltip:AddLine("Right-click: settings menu", 1, 1, 1)
        GameTooltip:AddLine("Lock it from the minimap button menu (click-through)", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
-- Right-click opens the menu (only reachable while unlocked; locked = click-through)
frame:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and OpenMenu then
        GameTooltip:Hide()
        OpenMenu(self)
    end
end)

-- Update Functions
local function UpdateVisibility(forceCombatState)
    if not db then return end
    if db.combatOnly and db.locked then
        local inCombat
        if forceCombatState ~= nil then
            inCombat = forceCombatState
        else
            inCombat = InCombatLockdown() or UnitAffectingCombat("player")
        end
        if inCombat then
            frame:Show()
        else
            frame:Hide()
        end
    else
        frame:Show()
    end
end

local function UpdateLockState()
    if not db then return end
    frame:EnableMouse(not db.locked)
    UpdateVisibility()
end

local function UpdateCooldown()
    if not db or not db.showCooldown or not trackedItemID or not GetItemCD then
        cooldown:Clear()
        return
    end
    local ok, startTime, duration, enable = pcall(GetItemCD, trackedItemID)
    if ok and type(startTime) == "number" and type(duration) == "number" and duration > 0 and enable == 1 then
        cooldown:SetCooldown(startTime, duration)
    else
        cooldown:Clear()
    end
end

local function MaxBagIndex()
    local maxBag = NUM_BAG_SLOTS or 4
    if NUM_TOTAL_EQUIPPED_BAG_SLOTS and NUM_TOTAL_EQUIPPED_BAG_SLOTS > maxBag then
        maxBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS
    end
    return maxBag
end

local function UpdatePotionCount()
    if not db then return end
    local targetName = db.potionName or DEFAULTS.potionName
    local totalCount = 0
    local foundIcon = nil
    local foundItemID = nil

    local maxBag = MaxBagIndex()

    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bag = 0, maxBag do
            local numSlots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    local matched = false
                    if info.hyperlink and string.find(info.hyperlink, targetName, 1, true) then
                        matched = true
                    elseif C_Item and C_Item.GetItemNameByID then
                        local itemName = C_Item.GetItemNameByID(info.itemID)
                        if itemName and string.find(itemName, targetName, 1, true) then
                            matched = true
                        end
                    end

                    if matched then
                        totalCount = totalCount + (info.stackCount or 1)
                        if not foundIcon and info.iconFileID then
                            foundIcon = info.iconFileID
                        end
                        if not foundItemID then
                            foundItemID = info.itemID
                        end
                    end
                end
            end
        end
    end

    if foundIcon then
        db.cachedIcon = foundIcon
        SetIconTexture(foundIcon)
    elseif db.cachedIcon then
        SetIconTexture(db.cachedIcon)
    end

    if foundItemID then
        trackedItemID = foundItemID
    end

    countText:SetText(tostring(totalCount))
    if totalCount > 0 then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1, 1)
        countText:SetTextColor(1, 1, 1, 1)
    else
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.55, 0.55, 0.55, 1)
        countText:SetTextColor(1, 0.3, 0.3, 1)
    end

    UpdateCooldown()
end

local function UpdateStats()
    if not db then return end

    local critVal = math.max(
        SafeRating(CR_CRIT_MELEE or 9),
        SafeRating(CR_CRIT_RANGED or 10),
        SafeRating(CR_CRIT_SPELL or 11)
    )
    local hasteVal = math.max(
        SafeRating(CR_HASTE_MELEE or 18),
        SafeRating(CR_HASTE_RANGED or 19),
        SafeRating(CR_HASTE_SPELL or 20)
    )
    local masteryVal = SafeRating(CR_MASTERY or 26)
    local versVal = SafeRating(CR_VERSATILITY_DAMAGE_DONE or 29)

    local values = { critVal, hasteVal, masteryVal, versVal }

    local bestIndex = 1
    local bestVal = values[1]
    for i = 2, #values do
        if values[i] > bestVal then
            bestVal = values[i]
            bestIndex = i
        end
    end

    local bestStat = STAT_DEFS[bestIndex]
    statText:SetTextColor(bestStat.r, bestStat.g, bestStat.b, 1)

    if db.showRating then
        statText:SetText(bestStat.name .. "\n" .. FormatNumber(bestVal))
    else
        statText:SetText(bestStat.name)
    end
end

local function ApplySettings()
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
    frame:SetScale(db.scale)
    UpdateLockState()
    UpdatePotionCount()
    UpdateStats()
end

-- Setting Actions (shared by the menu and the slash commands)
local function SetLocked(locked)
    db.locked = locked and true or false
    UpdateLockState()
end

local function SetScaleValue(num)
    db.scale = num
    frame:SetScale(num)
end

local function IsScale(value)
    return math.abs((db.scale or 1) - value) < 0.001
end

local function SetTrackedName(name)
    if not db then return false end
    name = strtrim(name or "")
    if name == "" then return false end
    db.potionName = name
    trackedItemID = nil
    UpdatePotionCount()
    return true
end

local function ResetSettings()
    for k, v in pairs(DEFAULTS) do
        if not RESET_SKIP[k] then
            db[k] = v
        end
    end
    trackedItemID = nil
    ApplySettings()
end

-- Minimap Button Behaviour
local function UpdateMinimapPosition()
    local angle = math.rad((db and db.minimapAngle) or DEFAULTS.minimapAngle)
    local x, y = math.cos(angle), math.sin(angle)
    local r = (Minimap:GetWidth() / 2) + 5
    local shape = (type(GetMinimapShape) == "function") and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        -- slide along the edge of a square minimap instead of floating off the corners
        local diag = math.sqrt(2 * r * r) - 10
        x = math.max(-r, math.min(x * diag, r))
        y = math.max(-r, math.min(y * diag, r))
    else
        x, y = x * r, y * r
    end
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function UpdateMinimapButton()
    if not db then return end
    UpdateMinimapPosition()
    minimapButton:SetShown(not db.minimapHide)
end

local function SetMinimapHidden(hidden)
    db.minimapHide = hidden and true or false
    UpdateMinimapButton()
    if db.minimapHide then
        PrintMsg("Minimap button hidden. Type /reckless to open the menu, /reckless minimap to show the button again.")
    end
end

local function ShowMinimapTooltip(owner)
    if not db then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Reckless Stat Tracker", 0.65, 0.38, 1.0)
    GameTooltip:AddDoubleLine("Position:", db.locked and "Locked" or "Unlocked (drag the icon)",
        0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Tracking:", db.potionName or DEFAULTS.potionName,
        0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: settings menu", 1, 1, 1)
    GameTooltip:AddLine("Right-click: lock / unlock position", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function MinimapDragUpdate()
    local mx, my = Minimap:GetCenter()
    if not mx or not db then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdateMinimapPosition()
end

minimapButton:SetScript("OnDragStart", function(self)
    if not db then return end
    self.isDragging = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", MinimapDragUpdate)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self.isDragging = false
    if db then
        db.minimapAngle = math.floor(db.minimapAngle + 0.5) % 360
        UpdateMinimapPosition()
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    if not self.isDragging then
        ShowMinimapTooltip(self)
    end
end)
minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

minimapButton:SetScript("OnClick", function(self, button)
    if not db then return end
    if button == "RightButton" then
        SetLocked(not db.locked)
        PrintMsg(db.locked and "Locked position (click-through enabled)."
            or "Unlocked position. Drag the icon to move it.")
        if GameTooltip:IsOwned(self) then
            ShowMinimapTooltip(self)
        end
    else
        GameTooltip:Hide()
        OpenMenu(self)
    end
end)

-- Settings Menu
local CONSUMABLE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local POTION_SUBCLASS = (Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Potion) or 1
local GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Potions currently in the bags, one entry per name (all ranks of a potion share a name)
local function ScanBagPotions()
    local list, byName = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return list, byName
    end
    for bag = 0, MaxBagIndex() do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and GetItemInfoInstantFn then
                local _, _, _, _, _, classID, subclassID = GetItemInfoInstantFn(info.itemID)
                if classID == CONSUMABLE_CLASS and subclassID == POTION_SUBCLASS then
                    local name = info.itemName
                    if (type(name) ~= "string" or name == "") and C_Item and C_Item.GetItemNameByID then
                        name = C_Item.GetItemNameByID(info.itemID)
                    end
                    if type(name) == "string" and name ~= "" then
                        local entry = byName[name]
                        if not entry then
                            entry = { name = name, count = 0 }
                            byName[name] = entry
                            list[#list + 1] = entry
                        end
                        entry.count = entry.count + (info.stackCount or 1)
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list, byName
end

-- Return value of a menu callback: keep the menu open and refresh check marks
local function KeepOpen()
    return MenuResponse and MenuResponse.Refresh
end

local function BuildScaleMenu(parent)
    local scaleMenu = parent:CreateButton("Icon scale")
    local isPreset = false
    for _, s in ipairs(SCALE_PRESETS) do
        if IsScale(s) then isPreset = true end
        scaleMenu:CreateRadio(string.format("%.2f", s),
            function() return IsScale(s) end,
            function() SetScaleValue(s); return KeepOpen() end)
    end
    if not isPreset then
        -- value typed with /reckless scale that is not one of the presets
        local custom = db.scale
        scaleMenu:CreateRadio(string.format("%.2f (custom)", custom),
            function() return IsScale(custom) end,
            function() SetScaleValue(custom); return KeepOpen() end)
    end
end

local function BuildItemMenu(parent)
    local itemMenu = parent:CreateButton("Tracked item")
    local potions, byName = ScanBagPotions()
    local listed = {}

    local function AddChoice(name, label)
        listed[name] = true
        local entry = byName[name]
        if entry then
            label = string.format("%s  |cffaaaaaax%d|r", label, entry.count)
        end
        itemMenu:CreateRadio(label,
            function() return db.potionName == name end,
            function() SetTrackedName(name); return KeepOpen() end)
    end

    AddChoice(DEFAULTS.potionName, DEFAULTS.potionName .. " (default)")
    local current = db.potionName or DEFAULTS.potionName
    if not listed[current] and not byName[current] then
        AddChoice(current, current .. " (custom)")
    end

    local first = true
    for _, p in ipairs(potions) do
        if not listed[p.name] then
            if first then
                itemMenu:CreateDivider()
                itemMenu:CreateTitle("Potions in your bags")
                first = false
            end
            AddChoice(p.name, p.name)
        end
    end

    itemMenu:CreateDivider()
    itemMenu:CreateButton("Enter item name...", function()
        StaticPopup_Show(POPUP_ITEM)
    end)
end

local function BuildMenu(_, root)
    if not db then return end
    root:CreateTitle("Reckless Stat Tracker")

    root:CreateCheckbox("Lock position (click-through)",
        function() return db.locked end,
        function() SetLocked(not db.locked); return KeepOpen() end)

    root:CreateCheckbox("Show stat rating number",
        function() return db.showRating end,
        function() db.showRating = not db.showRating; UpdateStats(); return KeepOpen() end)

    local combatItem = root:CreateCheckbox("Show only in combat",
        function() return db.combatOnly end,
        function() db.combatOnly = not db.combatOnly; UpdateVisibility(); return KeepOpen() end)
    combatItem:SetTitleAndTextTooltip("Show only in combat",
        "Hides the icon out of combat. Only applies while the position is locked.")

    root:CreateCheckbox("Show cooldown spiral",
        function() return db.showCooldown end,
        function() db.showCooldown = not db.showCooldown; UpdateCooldown(); return KeepOpen() end)

    BuildScaleMenu(root)
    BuildItemMenu(root)

    root:CreateDivider()
    root:CreateButton("Reset position & settings...", function()
        StaticPopup_Show(POPUP_RESET)
    end)
    root:CreateCheckbox("Show minimap button",
        function() return not db.minimapHide end,
        function()
            local hide = not db.minimapHide
            -- hide after the menu has closed: the menu may be anchored to this button
            C_Timer.After(0, function() SetMinimapHidden(hide) end)
            return MenuResponse and MenuResponse.CloseAll
        end)
end

OpenMenu = function(owner)
    if not db then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        PrintMsg("Menu is not available on this client. Type /reckless help for commands.")
        return
    end
    MenuUtil.CreateContextMenu(owner or UIParent, BuildMenu)
end

-- Addon Compartment (the "AddOns" button on the minimap) — still works with the minimap button hidden
function RecklessStatTracker_OnAddonCompartmentClick()
    -- open on the next frame so the compartment's own menu has finished closing
    C_Timer.After(0, function() OpenMenu(UIParent) end)
end

-- Popups
local function PopupEditBox(dialog)
    if not dialog then return nil end
    if dialog.GetEditBox then
        return dialog:GetEditBox()
    end
    return dialog.EditBox or dialog.editBox
end

local function AcceptItemName(text)
    if SetTrackedName(text) then
        PrintMsg("Tracking item name containing: " .. db.potionName)
    end
end

StaticPopupDialogs[POPUP_ITEM] = {
    text = "Reckless Stat Tracker\nTrack items whose name contains:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 80,
    editBoxWidth = 260,
    OnShow = function(self)
        local eb = PopupEditBox(self)
        if eb then
            eb:SetText((db and db.potionName) or DEFAULTS.potionName)
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self)
        local eb = PopupEditBox(self)
        if eb then
            AcceptItemName(eb:GetText())
        end
    end,
    EditBoxOnEnterPressed = function(editBox)
        local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(POPUP_ITEM)
        local eb = PopupEditBox(dialog) or editBox
        if eb and eb.GetText then
            AcceptItemName(eb:GetText())
        end
        StaticPopup_Hide(POPUP_ITEM)
    end,
    EditBoxOnEscapePressed = function()
        StaticPopup_Hide(POPUP_ITEM)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs[POPUP_RESET] = {
    text = "Reset Reckless Stat Tracker position and settings?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        if db then
            ResetSettings()
            PrintMsg("Reset to default position and settings.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Event Registration
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("COMBAT_RATING_UPDATE")
frame:RegisterEvent("UNIT_STATS")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        RecklessStatTrackerDB = CopyDefaults(DEFAULTS, RecklessStatTrackerDB)
        db = RecklessStatTrackerDB
        ApplySettings()
        UpdateMinimapButton()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdatePotionCount()
        UpdateStats()
        UpdateVisibility()
    elseif event == "COMBAT_RATING_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        UpdateStats()
    elseif (event == "UNIT_STATS" or event == "UNIT_AURA") and arg1 == "player" then
        UpdateStats()
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdatePotionCount()
    elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        UpdateCooldown()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateVisibility(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateVisibility(false)
    end
end)

-- Slash Commands
SLASH_RECKLESSSTATTRACKER1 = "/reckless"
SLASH_RECKLESSSTATTRACKER2 = "/rst"

SlashCmdList["RECKLESSSTATTRACKER"] = function(msg)
    if not db then return end
    local cmd, arg = string.match(strtrim(msg or ""), "^(%S+)%s*(.-)$")
    cmd = cmd and string.lower(cmd) or ""

    if cmd == "" or cmd == "menu" or cmd == "config" then
        OpenMenu(UIParent)
    elseif cmd == "minimap" then
        SetMinimapHidden(not db.minimapHide)
        if not db.minimapHide then
            PrintMsg("Minimap button shown.")
        end
    elseif cmd == "lock" then
        SetLocked(true)
        PrintMsg("Locked position (click-through enabled).")
    elseif cmd == "unlock" then
        SetLocked(false)
        PrintMsg("Unlocked position. Drag the icon to move it.")
    elseif cmd == "scale" then
        local num = tonumber(arg)
        if num and num >= SCALE_MIN and num <= SCALE_MAX then
            SetScaleValue(num)
            PrintMsg("Scale set to " .. num)
        else
            PrintMsg("Usage: /reckless scale <0.5 - 3.0> (e.g. /reckless scale 1.2)")
        end
    elseif cmd == "num" or cmd == "rating" then
        db.showRating = not db.showRating
        UpdateStats()
        PrintMsg("Show stat rating number: " .. (db.showRating and "ON" or "OFF"))
    elseif cmd == "combat" then
        db.combatOnly = not db.combatOnly
        UpdateVisibility()
        PrintMsg("Combat-only mode: " .. (db.combatOnly and "ON (hides out of combat when locked)" or "OFF"))
    elseif cmd == "cd" or cmd == "cooldown" then
        db.showCooldown = not db.showCooldown
        UpdateCooldown()
        PrintMsg("Cooldown spiral: " .. (db.showCooldown and "ON" or "OFF"))
    elseif cmd == "item" and arg and arg ~= "" then
        AcceptItemName(arg)
    elseif cmd == "reset" then
        ResetSettings()
        PrintMsg("Reset to default position and settings.")
    else
        PrintMsg("Commands (or just click the minimap button):")
        PrintMsg("  /reckless         - Open settings menu")
        PrintMsg("  /reckless minimap - Show/hide minimap button")
        PrintMsg("  /reckless unlock  - Unlock & drag icon")
        PrintMsg("  /reckless lock    - Lock position (click-through)")
        PrintMsg("  /reckless scale <0.5-3.0> - Resize icon")
        PrintMsg("  /reckless num     - Toggle stat rating number")
        PrintMsg("  /reckless combat  - Toggle show only in combat")
        PrintMsg("  /reckless cd      - Toggle cooldown swipe")
        PrintMsg("  /reckless reset   - Reset position & settings")
    end
end
