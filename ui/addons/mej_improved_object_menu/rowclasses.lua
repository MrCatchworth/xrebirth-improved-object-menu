local menu = ...

local ffi = require("ffi")

local rcName = menu.registerRowClass("name")
function rcName:display(setup)
    self.row = setup:addRow(true, {
        "",
        Helper.createFontString(Helper.unlockInfo(menu.unlocked.name, GetComponentData(menu.object, "name")), false, "center", menu.objNameColor.r, menu.objNameColor.g, menu.objNameColor.b, menu.objNameColor.a)
    }, self, {1, #menu.selectColWidths-1})
end
function rcName:getDetailButtonProps()
    local enabled = menu.isPlayerOwned
    local text = ReadText(1001, 1114)
    
    return text, enabled
end
function rcName:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gMain_rename", { 0, 0, menu.object })
end

local rcFaction = menu.registerRowClass("faction")
function rcFaction:display(setup)
    self.faction = GetComponentData(menu.object, "owner")
    
    if self.faction == "ownerless" then return end
    
    local relation = GetUIRelation(self.faction)
    local relationColor = "\27C"
    local sign = ""
    if relation > 0 then
        relationColor = "\27G"
        sign = "+"
    elseif relation < 0 then
        relationColor = "\27R"
    end
    
    local facText = GetComponentData(menu.object, "ownername") .. relationColor .. " (" .. sign .. relation .. ")"
    
    self.row = setup:addRow(true, {
        "",
        Helper.createFontString(facText, false, "center")
    }, self, {1, #menu.selectColWidths-1})
end
function rcFaction:getDetailButtonProps()
    local text = ReadText(1001, 2400)
    local enabled = true
    return text, enabled
end
function rcFaction:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_faction", {0, 0, self.faction})
end

local function getStatusBar(frac, height, width, color)
    frac = math.max(frac, 0.01)
    frac = math.min(frac, 1)
    return Helper.createIcon("solid", false, color.r, color.g, color.b, color.a, 0, 0, height, frac * width)
end

local rcPartOf = menu.registerRowClass("partOf")
function rcPartOf:display(setup)
    if menu.type ~= "block" then return end
    local color
    
    local isPlayer, isEnemy, name = GetComponentData(menu.container, "isplayerowned", "isenemy", "name")
    if isPlayer then
        color = menu.holomapColor.playerColor
    elseif isEnemy then
        color = menu.holomapColor.enemyColor
    else
        color = menu.holomapColor.friendColor
    end
    
    self.row = setup:addRow(true, {
        Helper.createFontString(ReadText(1001, 1134), false, "right"),
        Helper.unlockInfo(IsInfoUnlockedForPlayer(menu.container, "name"), Helper.createFontString(name, false, "left", color.r, color.g, color.b, color.a))
    }, self, {3, 3})
end
function rcPartOf:getDetailButtonProps()
    local text = ReadText(1001, 2961)
    local enabled = true
    
    return text, enabled
end
function rcPartOf:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gMain_object", { 0, 0, menu.container })
end

local rcHullShield = menu.registerRowClass("hullShield")
rcHullShield.updateInterval = 1
function rcHullShield:getVals()
    if self.property == "shield" then
        return GetComponentData(menu.object, "shield", "shieldmax", "shieldpercent")
    else
        return GetComponentData(menu.object, "hull", "hullmax", "hullpercent")
    end
end
function rcHullShield:getText()
    return ConvertIntegerString(self.value, true, 4, true) .. "\27Z/\27X" .. ConvertIntegerString(self.maximum, true, 4, true)
end
function rcHullShield:getBar()
    return getStatusBar(self.value/self.maximum, Helper.standardTextHeight, menu.getMultiColWidth(4, 6), self.barColor)
end
function rcHullShield:display(setup, property)
    self.property = property
    
    local value, maximum, pct = self:getVals()
    self.barColor = self.property == "shield" and menu.shieldColor or menu.white
    
    if maximum <= 0 then return end
    
    self.value, self.maximum, self.pct = value, maximum, pct
    
    self.row = setup:addRow(true, {Helper.createFontString(self:getText(), false, "right"), self:getBar()}, self, {3, 3})
end
function rcHullShield:update(tab, row)
    local val, maximum, pct = self:getVals()
    
    if val ~= self.value or maximum ~= self.maximum then
        self.value = val
        self.maximum = maximum
        Helper.updateCellText(tab, row, 1, self:getText())
        SetCellContent(tab, self:getBar(), row, 4)
    end
end

local rcFuel = menu.registerRowClass("fuel")
function rcFuel:display(setup)
    if menu.type ~= "ship" then return end
    
    local fuelAmount = GetComponentData(menu.object, "cargo").fuelcells or 0
    local fuelCapacity = GetWareCapacity(menu.object, "fuelcells")
    
    if fuelCapacity == 0 then return end
    
    self.amount = fuelAmount
    self.capacity = fuelCapacity
    
    local fuelText = ConvertIntegerString(fuelAmount, true, 4, true) .. "\27Z/\27X" .. ConvertIntegerString(fuelCapacity, true, 4, true)
    
    if menu.isPlayerOwned and fuelAmount / fuelCapacity <= 0.3 then
        fuelText = "\27R" .. fuelText
    end
    
    self.row = setup:addRow(true, {
        Helper.createFontString(ReadText(20205, 800), false, "right"),
        fuelText
    }, self, {3, 3})
end

local rcWare = menu.registerRowClass("ware")
function rcWare:getWareAmountCell()
    local mot
    local amountString = ConvertIntegerString(self.ware.amount, true, 4, true)
    
    --decide the color of the amount, and whether there should be any "x / y" bit
    if self.ware.amount == 0 then
            amountString = "\27Z" .. amountString .. "\27X"
    elseif menu.isPlayerOwned then
        self.isFull = next(self.category.productCycleAmounts) and (GetWareCapacity(menu.object, self.ware.ware, false) <= self.cycleAmount or (self.limit - self.cycleAmount) < self.ware.amount)
        if self.isFull then
            if self.cycleAmount > 0 then
                --it's a product with full storage (which actually stalls production so it gets a harsher colour)
                amountString = "\27R" .. amountString .. "\27X"
                mot = ReadText(1001, 1125)
            else
                --it's a resource with full storage
                amountString = "\27Y" .. amountString .. "\27X"
                mot = ReadText(1001, 1126)
            end
        end
    end
    
    if menu.isPlayerOwned and self.limit > 0 then
        amountString = amountString .. " / " .. ConvertIntegerString(self.limit, true, 4, true)
    end
    
    return Helper.createFontString(amountString, false, "right", 255, 255, 255, 100, nil, nil, nil, nil, nil, nil, nil, mot)
end
function rcWare:getNameColor()
    if self.category.zoneOwner and IsWareIllegalTo(self.ware.ware, self.category.owner, self.category.zoneOwner) then
        return menu.orange
    elseif self.ware.amount == 0 then
        return menu.lightGrey
    else
        return menu.white
    end
end
function rcWare:display(setup, ware)
    self.ware = ware
    
    local limit = 0
    if menu.isPlayerOwned and menu.type ~= "block" then
        limit = GetWareProductionLimit(menu.object, ware.ware)
    end
    self.limit = limit
    
    self.cycleAmount = self.category.productCycleAmounts[ware.ware] and self.category.productCycleAmounts[ware.ware] + 1 or 0
    
    local color = self:getNameColor()
    
    local totalVolume = ware.amount * ware.volume
    local icon = GetWareData(ware.ware, "icon")
    self.row = setup:addRow(true, {
        Helper.createButton(nil, Helper.createButtonIcon(icon, nil, 255, 255, 255, 100), false, true),
        Helper.createFontString(ware.name, false, "left", color.r, color.g, color.b, color.a),
        self:getWareAmountCell()
        -- Helper.createFontString(ConvertIntegerString(totalVolume, true, 4, true) .. "\27Z" .. self.category.unit, false, "right")
    }, self, {1, 2, 3})
end
function rcWare:applyScripts(tab, row)
    Helper.setButtonScript(menu, nil, tab, row, 1, function()
        Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_ware", { 0, 0, "wares", self.ware.ware })
        menu.cleanup()
    end)
end
function rcWare:updateAmount(newAmount)
    -- DebugError("Update amount of " .. self.ware.name)
    if self.ware.amount ~= newAmount then
        DebugError(self.ware.name .. " has changed from " .. self.ware.amount .. " to " .. newAmount)
        
        local nameNeedsUpdate = self.ware.amount == 0 or newAmount == 0
        
        self.ware.amount = newAmount
        
        SetCellContent(self.tab, self:getWareAmountCell(), self.row, 4)
        
        if nameNeedsUpdate then
            Helper.updateCellText(self.tab, self.row, 2, self.ware.name, self:getNameColor())
        end
    end
end

local rcNpc = menu.registerRowClass("npc")
function rcNpc:getCommandString()
    local accountString
    if menu.isPlayerOwned and (self.typeString == "manager" or self.typeString == "architect") then
        accountString = "\27W" .. ConvertMoneyString(GetAccountData(self.npc, "money"), false, true, 5, true) .. " " .. ReadText(1001, 101) .. "\27X "
    end
    
    if self.typeString == "engineer" then
        local action, param = GetComponentData(self.npc, "aicommandaction", "aicommandactionparam")
        return string.format(action, IsComponentClass(param, "component") and GetComponentData(param, "name") or "")
        
    elseif self.typeString == "architect" then
        local buildAnchor = GetBuildAnchor(GetContextByClass(self.npc, "container"))
		if buildAnchor and GetCurrentBuildSlot(buildAnchor) then
			local _, _, progress = GetCurrentBuildSlot(buildAnchor)
			return accountString .. string.format(ReadText(1001, 4218), GetComponentData(buildAnchor, "name")) .. " (" .. math.floor(progress) .. "%)"
		else
			return accountString .. ReadText(1001, 4223)
		end
        
    elseif self.typeString == "defencecontrol" then
        local blackboard_attackenemies = GetNPCBlackboard(self.npc, "$config_attackenemies")
		blackboard_attackenemies = blackboard_attackenemies and blackboard_attackenemies ~= 0
		if blackboard_attackenemies then
			return ReadText(1001, 4214)
		else
			return ReadText(1001, 4213)
		end
        
    elseif self.typeString == "manager" then
        return accountString .. string.format(ReadText(1001, 4204), GetComponentData(GetContextByClass(self.npc, "container"), "name"))
        
    else
        local command, param, action, actionParam = GetComponentData(self.npc, "aicommand", "aicommandparam", "aicommandaction", "aicommandactionparam")
        param = IsComponentClass(param, "component") and GetComponentData(param, "name") or ""
        actionParam = IsComponentClass(actionParam, "component") and GetComponentData(actionParam, "name") or ""
        
        return string.format(command, param) .. " -- " .. string.format(action, actionParam)
    end
end

function rcNpc:getCommandCell()
    return Helper.createFontString(self.commandString, false, "left", menu.statusMsgColor.r, menu.statusMsgColor.g, menu.statusMsgColor.b, menu.statusMsgColor.a)
end
function rcNpc:display(setup, npc)
    self.npc = npc
    
    local name, typeString, typeIcon, typeName, isControlEntity, combinedSkill, skillsKnown = GetComponentData(npc, "name", "typestring", "typeicon", "typename", "iscontrolentity", "combinedskill", "skillsvisible")
    
    self.name, self.typeString = name, typeString
    
    local nameCell = Helper.unlockInfo(self.category.namesKnown, name)
    
    local combinedSkillRank = skillsKnown and math.floor(combinedSkill/20) or 0
    local skillColor = skillsKnown and Helper.statusYellow or menu.grey
    local skillStars = string.rep("*", combinedSkillRank) .. string.rep("#", 5 - combinedSkillRank)
    local skillCell = Helper.createFontString(skillStars, false, "left", skillColor.r, skillColor.g, skillColor.b, skillColor.a, Helper.starFont, 24)
    
    self.row = setup:addRow(true, {
        Helper.createIcon(typeIcon, false, 255, 255, 255, 100, 0, 0, Helper.standardTextHeight, Helper.standardButtonWidth),
        -- typeName .. " " .. name,
        nameCell,
        skillCell
    }, self, {1, 4, 1})
    
    if self.category.commandsKnown then
        self.commandString = self:getCommandString()
        setup:addRow(true, {
            "",
            self:getCommandCell()
        }, nil, {1, 5})
    end
end
rcNpc.updateInterval = 3
function rcNpc:update()
    if self.category.commandsKnown then
        local newCommandString = self:getCommandString()
        if newCommandString ~= self.commandString then
            self.commandString = newCommandString
            SetCellContent(self.tab, self:getCommandCell(), self.row+1, 2)
        end
    end
end
function rcNpc:getDetailButtonProps()
    local text = ReadText(1001, 2961) .. " (" .. Helper.unlockInfo(self.category.namesKnown, self.name) .. ")"
    local enabled = self.category.namesKnown
    
    return text, enabled
end
function rcNpc:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gMain_charOrders", { 0, 0, self.npc })
end

local rcLocation = menu.registerRowClass("location")
rcLocation.updateInterval = 1
function rcLocation:display(setup)
    local cluster, sector, zone
    
    self.zone = GetContextByClass(menu.object, "zone", false)
    
    self.row = setup:addRow(true, {
        Helper.createIcon("menu_sector", false, 255, 255, 255, 100, 0, 0, Helper.standardTextHeight, Helper.standardButtonWidth),
        Helper.createFontString(self:getLocationText(), false, "center")
    }, self, {1, #menu.selectColWidths-1})
end
function rcLocation:getLocationText()
    if not menu.unlocked.name then return ReadText(1001, 3210) end
    
    local sep = " \27Z/\27X "
    
    local zone = self.zone
    local sector = GetContextByClass(menu.object, "sector", false)
    local cluster = GetContextByClass(menu.object, "cluster", false)
    
    
    local locText = GetComponentData(zone, "name")
    if sector then
        locText = GetComponentData(sector, "name") .. sep .. locText
    end
    locText = GetComponentData(cluster, "name") .. sep .. locText
    
    return locText
end
function rcLocation:update(tab, row)
    if menu.type == "station" or not menu.unlocked.name then return end
    
    local newZone = GetContextByClass(menu.object, "zone", false)
    
    self.isRenameButton = menu.isPlayerOwned and menu.type == "station" and GetComponentData(GetComponentData(menu.object, "zoneid"), "istemporaryzone")
    
    if not IsSameComponent(self.zone, newZone) then
        self.zone = newZone
        Helper.updateCellText(tab, row, 2, self:getLocationText())
    end
end
function rcLocation:getDetailButtonProps()
    local text = self.isRenameButton and ReadText(1001, 1114) or ReadText(1001, 3408)
    local enabled = true
    
    return text, enabled
end
function rcLocation:onDetailButtonPress()
    if self.isRenameButton then
        Helper.closeMenuForSubSection(menu, false, "gMain_rename", { 0, 0, GetComponentData(menu.object, "zoneid") })
    else
        Helper.closeMenuForSubSection(menu, false, "gMainNav_menumap", { 0, 0, "zone", GetContextByClass(menu.object, "zone", true), nil, menu.object })
    end
end

local rcUpgrade = menu.registerRowClass("upgrade")
function rcUpgrade:getOperationalText()
    local color
    if self.upgrade.operational/self.upgrade.total <= 0.5 then
        color = Helper.statusRed
    elseif self.upgrade.operational/self.upgrade.total <= 0.8 then
        color = Helper.statusOrange
    elseif self.upgrade.operational/self.upgrade.total < 1 then
        color = Helper.statusYellow
    else
        color = menu.white
    end
    
    return Helper.createFontString(Helper.estimateString(self.estimated) .. Helper.unlockInfo(self.category.defStatusKnown, self.upgrade.operational), false, "right", color.r, color.g, color.b, color.a)
end
function rcUpgrade:display(setup, weapon, estimated)
    local operational = weapon.operational
    local total = weapon.total
    
    self.estimated = estimated
    self.upgrade = weapon
    
    self.row = setup:addRow(true, {
        Helper.createFontString(weapon.name, false, "right"),
        self:getOperationalText(),
        Helper.createFontString(Helper.estimateString(estimated) .. Helper.unlockInfo(self.category.defLevelKnown, total), false, "right")
    }, self, {3, 2, 1})
end
function rcUpgrade:updateVal(newVal)
    if newVal.operational ~= self.upgrade.operational then
        self.upgrade.operational = newVal.operational
        SetCellContent(self.tab, self:getOperationalText(), self.row, 4)
    end
end

local rcWeapon = menu.registerRowClass("weapon")
rcWeapon.colors = {}
rcWeapon.colors["inv_weaponmod_t1"] = {r = 30, g = 255, b = 0, a = 100}
rcWeapon.colors["inv_weaponmod_t2"] = {r = 64, g = 154, b = 255, a = 100}
rcWeapon.colors["inv_weaponmod_t3"] = {r = 181, g = 72, b = 208, a = 100}
function rcWeapon:display(setup, weapon, weaponMod)
    self.weapon = weapon
    
    local color
    if weaponMod then
        local ware = ffi.string(weaponMod.Ware)
        color = self.colors[ware]
    else
        color = menu.white
    end
    self.row = setup:addRow(true, {
        Helper.createButton(nil, Helper.createButtonIcon("menu_info", nil, 255, 255, 255, 100), false, true),
        Helper.createFontString(weapon.name, false, "right", color.r, color.g, color.b, color.a),
        Helper.createFontString(ConvertIntegerString(weapon.dps, true, nil, true), false, "right"),
        Helper.createFontString(ConvertIntegerString(weapon.range, true, nil, true) .. " " .. ReadText(1001, 107), false, "right")
    }, self, {1, 2, 2, 1})
end
function rcWeapon:applyScripts(tab, row)
    Helper.setButtonScript(menu, nil, tab, row, 1, function()
        Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_weapon", {0, 0, "weapontypes_primary", self.weapon.macro})
    end)
end

local rcAmmo = menu.registerRowClass("ammo")
function rcAmmo:getAmountText()
    return Helper.unlockInfo(self.category.defStatusKnown, tostring(self.ammo.amount))
end
function rcAmmo:display(setup, ammo)
    self.ammo = ammo
    self.name = GetWareData(ammo.ware, "name")
    
    self.row = setup:addRow(true, {
        self.name,
        self:getAmountText()
    }, self, {4, 2})
end
function rcAmmo:updateVal(newVal)
    if self.category.defStatusKnown then
        if newVal.amount ~= self.ammo.amount then
            self.ammo.amount = newVal.amount
            SetCellContent(self.tab, self:getAmountText(), self.row, 5)
        end
    end
end

local rcProduction = menu.registerRowClass("production")
rcProduction.updateInterval = 3
function rcProduction:getTimeText()
    local t = self.data.remainingtime
    if t == 0 or not t then
        return "\27Z--"
    else
        return ConvertTimeString(t, "%h\27Z:\27X%M\27Z:\27X%S", true)
    end
end

rcProduction.colorNoStorage = {r = 255, g = 255, b = 0, a = 100}
rcProduction.colorNoResources = {r = 255, g = 140, b = 0, a = 100}
rcProduction.colorDamaged = {r = 255, g = 0, b = 0, a = 100}
function rcProduction:getNameText()
    local player = menu.isPlayerOwned
    local state = self.data.state
    local color = menu.white
    local mot
    
    if self.nameKnown then
        if not GetComponentData(self.module, "isfunctional") then
            if player then color = self.colorDamaged end
            mot = ReadText(1001, 1501)
        elseif state == "waitingforresources" then
            if player then color = self.colorNoResources end
            mot = ReadText(1001, 1604)
        elseif state == "waitingforstorage" then
            if player then color = self.colorNoStorage end
            mot = ReadText(1001, 1605)
        elseif state ~= "producing" then
            if player then color = self.colorNoStorage end
            mot = ReadText(1001, 1606)
        else
            mot = ReadText(1001, 1607)
        end
    end
    
    return Helper.createFontString(self.name, false, "left", color.r, color.g, color.b, 100, nil, nil, nil, nil, nil, nil, nil, mot)
end

function rcProduction:display(setup, module)
    self.module = module
    self.nameKnown = IsInfoUnlockedForPlayer(module, "name")
    self.timeKnown = IsInfoUnlockedForPlayer(module, "production_time")
    self.effKnown = IsInfoUnlockedForPlayer(module, "efficiency_amount")
    
    self.name = Helper.unlockInfo(self.nameKnown, GetComponentData(module, "name"))
    
    local data = GetProductionModuleData(module)
    self.data = data
    
    local productText
    local iconCell = ""
    if data.products then
        local product = data.products[1]
        productText = "\27Z" .. ConvertIntegerString(product.cycle * 3600 / data.cycletime, true, 4, true) .. "x\27X" .. product.name
        if self.effKnown then
            iconCell = Helper.createIcon(GetWareData(product.ware, "icon"), false, 255, 255, 255, 100, 0, 0, Helper.standardTextHeight, Helper.standardButtonWidth)
        end
    else
        productText = "\27Z--"
    end
    
    self.lastState = data.state
    self.lastWare = data.products and data.products[1].ware
    
    self.row = setup:addRow(true, {
        iconCell,
        self:getNameText(),
        Helper.unlockInfo(self.effKnown, productText),
        Helper.unlockInfo(self.timeKnown, self:getTimeText())
    }, self, {1, 1, 3, 1})
end

function rcProduction:update(tab, row)
    if not self.timeKnown or not IsComponentOperational(self.module) then return end
    
    local data = GetProductionModuleData(self.module)
    self.data = data
    
    if self.nameKnown and data.state ~= self.lastState then
        --name cell needs updating
        SetCellContent(tab, self:getNameText(), row, 2)
    end
    Helper.updateCellText(tab, row, 6, self:getTimeText())
    
    self.lastState = data.state
end

function rcProduction:getDetailButtonProps()
    local text = ReadText(1001, 2961)
    local enabled = IsComponentOperational(self.module)
    return text, enabled
end
function rcProduction:onDetailButtonPress()
    if not IsComponentOperational(self.module) then return end
    Helper.closeMenuForSubSection(menu, false, "gMain_objectProduction", { 0, 0, menu.object, self.module })
end

local rcShopList = menu.registerRowClass("shoppingList")
rcShopList.colorBuy = {r = 66, g = 92, b = 111, a = 60}
rcShopList.colorSell = {r = 82, g = 122, b = 108, a = 60}
rcShopList.colorExchange = {r = 68, g = 111, b = 65, a = 60}
local function frameWhite(text)
    return "\27W" .. text .. "\27X"
end
local function relationColorCode(isPlayer, isEnemy)
    if isPlayer then
        return "\27G"
    elseif isEnemy then
        return "\27R"
    else
        return "\27U"
    end
end
function rcShopList:display(setup, item, index)
    self.item = item
    self.index = index
    
    local cluster, sector, zone, isPlayerOwned, isEnemy = GetComponentData(item.station, "cluster", "sector", "zone", "isplayerowned", "isenemy")
    local template
    local location
    local colorCode = relationColorCode(isPlayerOwned, isEnemy)
    local baseColor
    if item.iswareexchange or isPlayerOwned then
        if item.ispassive then
            if item.isbuyoffer then
                template = ReadText(1001, 2993) -- object transfers to
            else
                template = ReadText(1001, 2995) -- object receives
            end
        else
            if item.isbuyoffer then
                template = ReadText(1001, 2993) -- object transfers to
            else
                template = ReadText(1001, 2992) -- object transfers from
            end
        end
        
        baseColor = self.colorExchange
        template = string.format(template, frameWhite(ConvertIntegerString(item.amount, true, nil, true)), frameWhite(item.name), colorCode .. item.stationname .. "\27X")
        
        -- local locTemplate = ReadText(1001, 2994)
        local locTemplate = "%s / %s / %s"
        location = string.format(locTemplate, frameWhite(cluster), frameWhite(sector), frameWhite(zone))
    else
        if item.isbuyoffer then
            template = ReadText(1001, 2976)
            baseColor = self.colorSell
        else
            template = ReadText(1001, 2975)
            baseColor = self.colorBuy
        end
        
        template = string.format(template, frameWhite(ConvertIntegerString(item.amount, true, nil, true)), frameWhite(item.name), frameWhite(ConvertMoneyString(RoundTotalTradePrice(item.price * item.amount), false, true, nil, true)))
        
        if item.isbuyoffer and item.station then
            local trade = GetTradeData(item.id)
            local profit = GetReferenceProfit(menu.object, trade.ware, item.price, item.amount, index - 1)
            template = template .. "\n" .. string.format(ReadText(1001, 6203), "\27G" .. (profit and ConvertMoneyString(profit, false, true, 6, true) or ReadText(1001, 2672)) .. "\27X " .. ReadText(1001, 101))
        end
        
        local locTemplate = "%s -- %s / %s / %s"
        -- local locTemplate = ReadText(1001, 2977)
        if item.station then
            location = string.format(locTemplate, colorCode .. item.stationname .. "\27X", frameWhite(cluster), frameWhite(sector), frameWhite(zone))
        end
    end
    
    local text = template
    
    if item.station then
        text = text .. "\n" .. location
    end
    
    self.row = setup:addRow(true, {
        Helper.createFontString(text, false, "left", 170, 170, 170, 100, Helper.standardFont, Helper.standardFontSize, true, nil, nil, 0, Helper.standardSizeX/2 - 20)
        --, Helper.standardSizeX/2 - menu.selectColWidths[1] - 7)
    }, self, {#menu.selectColWidths}, false, baseColor)
end

local rcUnit = menu.registerRowClass("unit")
function rcUnit:display(setup, unit)
    self.unit = unit
    
    self.isMarine = IsMacroClass(unit.macro, "npc")
    
    self.row = setup:addRow(true, {
        Helper.createButton(nil, Helper.createButtonIcon("menu_info", nil, 255, 255, 255, 100), false, self.category.detailsKnown),
        Helper.unlockInfo(self.category.detailsKnown, unit.name),
        self:getAmountText(),
        self:getInUseText()
    }, self, {1, 2, 2, 1})
end
function rcUnit:getAmountText()
    return Helper.createFontString(Helper.unlockInfo(self.category.amountKnown, self.unit.amount), false, "right")
end
function rcUnit:getInUseText()
    return Helper.createFontString(Helper.unlockInfo(self.category.detailsKnown, self.unit.unavailable), false, "right")
end
function rcUnit:applyScripts(tab, row)
    Helper.setButtonScript(menu, nil, tab, row, 1, function()
        if self.isMarine then
            Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_character", {0, 0, "marines", self.unit.macro})
        else
            Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_object", {0, 0, "shiptypes_xs", self.unit.macro, false})
        end
    end)
end
function rcUnit:updateUnit(newUnit)
    if self.category.amountKnown and newUnit.amount ~= self.unit.amount then
        self.unit.amount = newUnit.amount
        SetCellContent(self.tab, self:getAmountText(), self.row, 4)
    end
    if self.category.detailsKnown and newUnit.unavailable ~= self.unit.unavailable then
        self.unit.unavailable = newUnit.unavailable
        SetCellContent(self.tab, self:getInUseText(), self.row, 6)
    end
end

local rcPersonnel = menu.registerRowClass("personnel")
function rcPersonnel:display(setup)
    if menu.type ~= "station" then return end
    
    self.inRange = IsSameComponent(GetComponentData(menu.object, "zoneid"), GetComponentData(menu.playerShip, "zoneid"))
    
    local textCell = Helper.createFontString(ReadText(1001, 1116) .. ": " .. (self.inRange and #self.category.npcs or ReadText(1001, 1117)), false, "right")
    local buttonCell = Helper.createButton(Helper.createButtonText(ReadText(1001, 2961), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, self.inRange)
    
    self.row = setup:addRow(true, {
        textCell,
        buttonCell
    }, self, {4, 2}, false, Helper.defaultHeaderBackgroundColor)
end
function rcPersonnel:applyScripts(tab, row)
    Helper.setButtonScript(menu, nil, tab, row, 5, function()
        Helper.closeMenuForSubSection(menu, false, "gMain_objectPlatforms", { 0, 0, menu.object })
    end)
end
function rcPersonnel:getDetailButtonProps()
    local text = ReadText(1001, 2961)
    local enabled = self.inRange
    
    return text, enabled
end
function rcPersonnel:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gMain_objectPlatforms", { 0, 0, menu.object })
end

local rcJumpdrive = menu.registerRowClass("jumpdrive")
function rcJumpdrive:assessState()
    local exists, charging, busy, nextJump = GetComponentData(menu.object, "hasjumpdrive", "isjumpdrivecharging", "isjumpdrivebusy", "nextjumptime")
    
    if not exists then
        self.state = "none"
    elseif charging then
        self.state = "charging"
    elseif busy then
        self.state = "busy"
    else
        self.state = "ready"
    end
end
function rcJumpdrive:getStateText()
    local text
    local color
    if self.state == "none" then
        text = ReadText(1001, 30)
        color = Helper.statusRed
    elseif self.state == "charging" then
        text = ReadText(1015, 155)
        color = Helper.statusGreen
    elseif self.state == "busy" then
        text = ReadText(1001, 3221)
        color = Helper.statusYellow
    else
        text = ReadText(1001, 14)
        color = menu.white
    end
    
    return Helper.createFontString(text, false, "left", color.r, color.g, color.b, color.a)
end
function rcJumpdrive:display(setup)
    if menu.type ~= "ship" then return end
    
    self:assessState()
    self.lastState = self.state
    
    if self.state == "none" and not menu.isBigShip then
        return
    end
    
    self.row = setup:addRow(true, {
        Helper.createFontString(ReadText(1001, 1104), false, "right"),
        self:getStateText()
    }, self, {3, 3})
end
rcJumpdrive.updateInterval = 2
function rcJumpdrive:update(tab, row)
    self:assessState()
    if self.state ~= self.lastState then
        SetCellContent(tab, self:getStateText(), row, 4)
        self.lastState = self.state
    end
end

local rcPlayerUpgrade = menu.registerRowClass("playerUpgrade")
function rcPlayerUpgrade:display(setup, upgrade, factor)
    self.row = setup:addRow( true, {
        Helper.createButton(nil, Helper.createButtonIcon(GetWareData(upgrade.ware, "icon"), nil, 255, 255, 255, 100), false),
        upgrade.name,
        Helper.createFontString(factor * upgrade.operational, false, "right")
    }, self, {1, 4, 1})
end

local rcSubordinate = menu.registerRowClass("subordinate")
function rcSubordinate:getCommandString()
    if not self.pilot then return end
    
    local command, param = GetComponentData(self.pilot, "aicommand", "aicommandparam")
    
    param = IsComponentClass(param, "component") and GetComponentData(param, "name") or ""
    
    return string.format(command, param)
end
function rcSubordinate:getMainString()
    if self.commandString then
        return self.name .. " \27Z" .. self.commandString
    else
        return self.name
    end
end
function rcSubordinate:display(setup, ship)
    self.ship = ship
    
    local isPlayer, isEnemy, name, pilot = GetComponentData(ship, "isplayerowned", "isenemy", "name", "pilot")
    
    self.name, self.pilot = name, pilot
    
    if isPlayer then
        self.color = menu.holomapColor.playerColor
    elseif isEnemy then
        self.color = menu.holomapColor.enemyColor
    else
        self.color = menu.holomapColor.friendColor
    end
    
    self.commandString = self:getCommandString()
    
    self.row = setup:addRow(true, {
        "",
        Helper.createFontString(self:getMainString(), false, "left", self.color.r, self.color.g, self.color.b, self.color.a)
    }, self, {1, 5})
end
rcSubordinate.updateInterval = 5
function rcSubordinate:update()
    if self.destroyed then return end
    
    if not IsComponentOperational(self.ship) then
        self.destroyed = true
        Helper.updateCellText(self.tab, self.row, 2, self:getMainString(), menu.lightGrey)
        return
    end
    
    self.name, self.pilot = GetComponentData(self.ship, "name", "pilot")
    local nextCommand = self:getCommandString()
    if nextCommand ~= self.commandString then
        self.commandString = nextCommand
        Helper.updateCellText(self.tab, self.row, 2, self:getMainString())
    end
end
function rcSubordinate:getDetailButtonProps()
    local text = self.name
    local enabled = (not self.destroyed) and IsComponentOperational(self.ship)
    
    return text, enabled
end
function rcSubordinate:onDetailButtonPress()
    if self.destroyed or not IsComponentOperational(self.ship) then return end
    
    Helper.closeMenuForSubSection(menu, false, "gMain_object", { 0, 0, self.ship })
end

local rcEconomy = menu.registerRowClass("economy")
function rcEconomy:display(setup)
    if not ((menu.type == "station" or (menu.type == "ship" and GetBuildAnchor(menu.object))) and (GetComponentData(menu.object, "tradesubscription") or menu.isPlayerOwned)) then
        return
    end
    
    local textCell = Helper.createFontString(ReadText(1001, 1131), false, "right")
    local buttonCell = Helper.createButton(Helper.createButtonText(ReadText(1001, 2961), "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, true)
    
    self.row = setup:addRow(true, {
        textCell,
        buttonCell
    }, self, {4, 2}, false, Helper.defaultHeaderBackgroundColor)
end
function rcEconomy:viewStats()
    Helper.closeMenuForSubSection(menu, false, "gMain_economystats", { 0, 0, menu.object })
end
function rcEconomy:applyScripts(tab, row)
    Helper.setButtonScript(menu, nil, tab, row, 5, function()
        self:viewStats()
    end)
end
function rcEconomy:getDetailButtonProps()
    local text = ReadText(1001, 2961)
    local enabled = true
    
    return text, enabled
end
function rcEconomy:onDetailButtonPress()
    self:viewStats()
end