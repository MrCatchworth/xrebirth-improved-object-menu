local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
	typedef uint64_t UniverseID;
	typedef struct {
		const char* macro;
		const char* ware;
		uint32_t amount;
		uint32_t capacity;
	} AmmoData;
	typedef struct {
		int64_t trade;
		int64_t defence;
		int64_t missile;
	} SupplyBudget;
	typedef struct {
		uint32_t ID;
		const char* Name;
		const char* RawName;
		const char* WeaponMacro;
		const char* Ware;
		float DamageFactor;
		float CoolingFactor;
		float ReloadFactor;
		float SpeedFactor;
		float LifeTimeFactor;
		float MiningFactor;
		float StickTimeFactor;
		float ChargeTimeFactor;
		float BeamLengthFactor;
		uint32_t AddedAmount;
	} UIWeaponMod;
	uint32_t GetAmmoStorage(AmmoData* result, uint32_t resultlen, UniverseID defensibleid, const char* ammotype);
	bool GetInstalledWeaponMod(UniverseID weaponid, UIWeaponMod* weaponmod);
	uint32_t GetNumAmmoStorage(UniverseID defensibleid, const char* ammotype);
	SupplyBudget GetSupplyBudget(UniverseID containerid);
	bool IsPlayerCameraTargetViewPossible(UniverseID targetid, bool force);
	bool IsVRVersion(void);
	void SetPlayerCameraCockpitView(bool force);
	void SetPlayerCameraTargetView(UniverseID targetid, bool force);
]]

--shallow clone
local function clone(t)
    local new = {}
    for k, v in pairs(t) do
        new[k] = v
    end
    return new
end

local menu = {
	name = "MeJ_ImprovedObjectMenu",
	transparent = { r = 0, g = 0, b = 0, a = 0 },
	white = { r = 255, g = 255, b = 255, a = 100 },
	orange = { r = 255, g = 192, b = 0, a = 100 },
    shieldColor = { r = 0, g = 192, b = 255 , a = 100 },
    
    stretchyColumns = 3,
    selectTableHeight = 535
}

local function getMultiColWidth(startIndex, endIndex)
    local width = 0
    local count = 0
    -- local borderWidth = 3
    local borderWidth = Helper.largePDA and 3 or 4
    
    for index = startIndex, endIndex do
        count = count + 1
        if count > 1 then
            width = width + borderWidth
        end
        
        width = width + menu.selectColWidths[index]
    end
    
    return width
end

local function getStatusBar(frac, height, width, color)
    frac = math.max(frac, 0.01)
    frac = math.min(frac, 1)
    return Helper.createIcon("solid", false, color.r, color.g, color.b, color.a, 0, 0, height, frac * width)
end

local function addRowByClass(setup, cat, rowClass, ...)
    local rowData = {}
    rowData.class = rowClass
    rowData.kind = "regular"
    rowData.category = cat
    setmetatable(rowData, rowClass.metaTable)
    
    if rowData.init then rowData:init() end
    
    local rowProps = {rowData:getContent(...)}
    
    if rowProps and #rowProps > 0 then
        rowProps[3] = rowData
        setup:addRow(unpack(rowProps))
        rowData.row = #setup.rows
        
        table.insert(cat.rows, rowData)
    end
end

menu.extendedCategories = {}

--menu categories start here
--=========================================

menu.categories = {}

menu.categories.general = {}
local catGeneral = menu.categories.general
catGeneral.header = ReadText(1001, 1111)
catGeneral.visible = true
catGeneral.enabled = true
catGeneral.extended = true
function catGeneral:init()
end
function catGeneral:display(setup)
    addRowByClass(setup, self, menu.rowClasses.name)
    addRowByClass(setup, self, menu.rowClasses.faction)
    addRowByClass(setup, self, menu.rowClasses.location)
    addRowByClass(setup, self, menu.rowClasses.hullShield, "hull")
    addRowByClass(setup, self, menu.rowClasses.hullShield, "shield")
    addRowByClass(setup, self, menu.rowClasses.fuel)
end

menu.categories.cargo = {}
local catCargo = menu.categories.cargo
catCargo.visible = false
catCargo.enabled = false
catCargo.extended = true
function catCargo:init()
    self.rawStorage = GetStorageData(menu.object)
    self.storageSummary = self:aggregateStorage(self.rawStorage)
    
    local stored = self.rawStorage.stored
    local cap = self.rawStorage.capacity
    
    local wareCount = 0
    for k, v in pairs(self.storageSummary) do
        wareCount = wareCount + 1
    end
    self.wareCount = wareCount
    
    --TODO: reduce repeated data calls
    local modules = GetProductionModules(menu.object)
    self.productCycleAmounts = {}
    for _, module in ipairs(modules) do
        local data = GetProductionModuleData(module)
        if data.products then
            for _, product in ipairs(data.products) do
                if not self.productCycleAmounts[product.ware] or self.productCycleAmounts[product.ware] < product.cycle then
                    self.productCycleAmounts[product.ware] = product.cycle
                end
            end
        end
    end
    
    local knownOtherCase = menu.type == "station" and self.rawStorage.estimated ~= nil
    self.amountKnown = IsInfoUnlockedForPlayer(menu.object, "storage_amounts") or knownOtherCase
    self.capacityKnown = IsInfoUnlockedForPlayer(menu.object, "storage_capacity") or knownOtherCase
    self.waresKnown = IsInfoUnlockedForPlayer(menu.object, "storage_warelist") or knownOtherCase
    
    self.visible = cap > 0
    self.enabled = (stored > 0 or self.rawStorage.estimated) and self.waresKnown
    
    self.unit = " " .. ReadText(1001, 110)
    
    local amountString = Helper.unlockInfo(self.amountKnown, ConvertIntegerString(stored, true, 4, true))
    local capacityString = Helper.unlockInfo(self.capacityKnown, ConvertIntegerString(cap, true, 4, true))
    
    if self.visible then
        local sep = "\27Z -- \27X"
        self.header = ReadText(1001, 1400) .. sep .. amountString .. "/" .. capacityString .. self.unit .. sep .. wareCount .. " " .. (wareCount == 1 and ReadText(1001, 45) or ReadText(1001, 46))
    end
end
function catCargo:display(setup)
    for k, ware in Helper.orderedPairsByWareName(self.storageSummary) do
        addRowByClass(setup, self, menu.rowClasses.ware, ware)
    end
end
function catCargo:aggregateStorage(rawStorage)
    local cargo = {}
    for k, bay in ipairs(rawStorage) do
        for l, ware in ipairs(bay) do
            if not cargo[ware.ware] then
                cargo[ware.ware] = ware
            else
                cargo[ware.ware].amount = cargo[ware.ware].amount + ware.amount
            end
        end
    end
    
    return cargo
end
function catCargo:getDetailButtonProps()
    local text = ReadText(1001, 1400)
    local enabled = true
    
    return text, enabled
end
function catCargo:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gMain_objectStorage", { 0, 0, menu.object })
end

menu.categories.crew = {}
local catCrew = menu.categories.crew
catCrew.header = ReadText(1001, 1108)
catCrew.visible = true
catCrew.enabled = false
catCrew.extended = true
function catCrew:init()
    self.npcs = GetNPCs(menu.object)
    
    self.controlEntities = {}
    for k, npc in pairs(self.npcs) do
        if GetComponentData(npc, "iscontrolentity") then
            table.insert(self.controlEntities, npc)
        end
    end
    
    self.visible = menu.type ~= "block" and not menu.isPlayerShip
    self.enabled = #self.controlEntities > 0
    self.namesKnown = IsInfoUnlockedForPlayer(menu.object, "operator_name")
    self.commandsKnown = IsInfoUnlockedForPlayer(menu.object, "operator_commands")
end
function catCrew:display(setup)
    for k, npc in pairs(self.controlEntities) do
        addRowByClass(setup, self, menu.rowClasses.npc, npc)
    end
end

menu.categories.production = {}
local catProd = menu.categories.production
catProd.header = ReadText(1001, 1106)
catProd.visible = false
catProd.enabled = false
catProd.extended = true
function catProd:init()
    self.modules = GetProductionModules(menu.object)
    table.sort(self.modules, Helper.sortComponentName)
    self.visible = #self.modules > 0
    self.enabled = self.visible
end
function catProd:display(setup)
    for k, v in pairs(self.modules) do
        if IsComponentOperational(v) then
            addRowByClass(setup, self, menu.rowClasses.production, v)
        end
    end
end

menu.categories.arms = {}
local catArms = menu.categories.arms
catArms.header = ReadText(1001, 1105)
catArms.visible = false
catArms.enabled = false
catArms.extended = true
function catArms:init()
    self.armament = GetAllWeapons(menu.object)
    
    --don't show empty missile ammo
    for i = #self.armament.missiles, 1, -1 do
        if self.armament.missiles[i].amount == 0 then
            table.remove(self.armament.missiles, i)
        end
    end
    
    self.upgrades = GetAllUpgrades(menu.object, false)
    
    self.fixedTurrets = GetNotUpgradesByClass(menu.object, "turret")
    
    self.fixedTurrets.total = 0
    self.fixedTurrets.operational = 0
    
    for k, turret in ipairs(self.fixedTurrets) do
        local name, macro = GetComponentData(turret, "name", "macro")
        local defStatusKnown = IsInfoUnlockedForPlayer(turret, "defence_status")
        local defTotalKnown = IsInfoUnlockedForPlayer(turret, "defence_level")
        
        if not (defStatusKnown and defTotalKnown) then
            self.fixedTurrets.estimated = true
        end
        
        local macroTab
        if defLevelKnown then
            if not self.fixedTurrets[macro] then
                self.fixedTurrets[macro] = {name = name, macro = macro, total = 0, operational = 0}
            end
            macroTab = self.fixedTurrets[macro]
        end
        
        if defStatusKnown and IsComponentOperational(turret) then
            self.fixedTurrets.operational = self.fixedTurrets.operational + 1
            if defLevelKnown then
                macroTab.operational = macroTab.operational + 1
            end
        end
        
        if defLevelKnown then
            self.fixedTurrets.total = self.fixedTurrets.total + 1
            macroTab.total = macroTab.total + 1
        end
    end
    
    
    self.defLevel = 0
    self.defStatus = 0
    self.estimated = false
    
    if not menu.isPlayerShip and (self.upgrades.totaltotal > 0 or self.upgrades.estimated) then
        self.defLevel = self.defLevel + self.fixedTurrets.total + self.upgrades.totaltotal
        self.defStatus = self.defStatus + self.fixedTurrets.operational + self.upgrades.totaloperational
        self.estimated = self.fixedTurrets.estimated or self.upgrades.estimated
    end
    if #self.armament.missiles > 0 or #self.armament.weapons > 0 then
        self.defLevel = self.defLevel + #self.armament.missiles + #self.armament.weapons
        self.defStatus = self.defStatus + #self.armament.missiles + #self.armament.weapons
    end
    
    self.defStatusKnown = IsInfoUnlockedForPlayer(menu.object, "defence_status") or (menu.type == "station" and self.estimated)
    self.defLevelKnown = IsInfoUnlockedForPlayer(menu.object, "defence_level") or (menu.type == "station" and self.estimated)
    
    local enable = self.defStatus > 0
    self.visible = enable
    self.enabled = enable
end
function catArms:display(setup)
    for ut, upgrade in Helper.orderedPairs(self.upgrades) do
        if not (ut == "totaltotal" or ut == "totalfree" or ut == "totaloperational" or ut == "totalconstruction" or ut == "estimated") and upgrade.total > 0 then
            addRowByClass(setup, self, menu.rowClasses.upgrade, upgrade, self.estimated, self.defStatusKnown, self.defLevelKnown)
        end
    end
    for macro, turret in pairs(self.fixedTurrets) do
        if type(turret) == "table" and turret.operational > 0 then
            addRowByClass(setup, self, menu.rowClasses.upgrade, turret, self.fixedTurrets.estimated, self.defStatusKnown, self.defLevelKnown)
        end
    end
    for k, weapon in ipairs(self.armament.weapons) do
        addRowByClass(setup, self, menu.rowClasses.weapon, weapon)
    end
end

menu.categories.shoppingList = {}
local catShoppingList = menu.categories.shoppingList
catShoppingList.header = ReadText(1001, 1105)
catShoppingList.visible = false
catShoppingList.enabled = false
catShoppingList.extended = true
function catShoppingList:init()
    self.visible = menu.isPlayerOwned and menu.type == "ship" and not GetBuildAnchor(menu.object)
    
    if not self.visible then return end
    
    self.shoppingList = GetShoppingList(menu.object)
    
    if #self.shoppingList <= 0 then
        self.visible = false
        return
    end
    
    if PlayerPrimaryShipHasContents("trademk3") then
        self.maxTrips = 7
    elseif PlayerPrimaryShipHasContents("trademk2") then
        self.maxTrips = 5
    else
        self.maxTrips = 3
    end
    
    self.header = ReadText(1001, 2937) .. "\27Z -- \27X" .. #self.shoppingList .. "\27Z / \27X" .. self.maxTrips
    
    self.visible = true
    self.enabled = #self.shoppingList > 0
end
function catShoppingList:display(setup)
    for k, item in pairs(self.shoppingList) do
        addRowByClass(setup, self, menu.rowClasses.shoppingList, item, k)
    end
end

menu.categories.units = {}
local catUnits = menu.categories.units
catUnits.visible = false
catUnits.enabled = true
catUnits.extended = true
function catUnits:init()
    if not IsComponentClass(menu.object, "defensible") then
        self.visible = false
        return
    end
    
    self.amountKnown = IsInfoUnlockedForPlayer(menu.object, "units_amount")
    self.capacityKnown = IsInfoUnlockedForPlayer(menu.object, "units_capacity")
    self.detailsKnown = IsInfoUnlockedForPlayer(menu.object, "units_details")
    
    self.units = GetUnitStorageData(menu.object)
    if #self.units <= 0 then
        self.visible = false
        return
    end
    
    local hasUnits = false
    for k, unit in ipairs(self.units) do
        if unit.amount > 0 then
            hasUnits = true
            break
        end
    end
    
    --[[
    if menu.isPlayerShip then
        hasUnits = true
    end
    ]]
    
    if not hasUnits then
        self.visible = false
        return
    end
    
    self.visible = true
    
    self.header = ReadText(1001, 22) .. "\27Z -- \27X" .. Helper.unlockInfo(self.amountKnown, self.units.stored) .. "\27Z / \27X" .. Helper.unlockInfo(self.capacityKnown, self.units.capacity)
end

function catUnits:display(setup)
    for k, unit in ipairs(self.units) do
        if unit.amount > 0 then
            addRowByClass(setup, self, menu.rowClasses.unit, unit)
        end
    end
end
    
--row classes start here
--===================================================================

menu.rowClasses = {}

local function registerRowClass(name)
    local rc = {}
    menu.rowClasses[name] = rc
    rc.metaTable = {__index = rc}
    
    return rc
end

local rcName = registerRowClass("name")
function rcName:getContent()
    return true, {
        "",
        Helper.createFontString(Helper.unlockInfo(menu.unlocked.name, GetComponentData(menu.object, "name")), false, "center", menu.objNameColor.r, menu.objNameColor.g, menu.objNameColor.b, menu.objNameColor.a)
    }, nil, {1, #menu.selectColWidths-1}
end
function rcName:getDetailButtonProps()
    local enabled = menu.isPlayerOwned
    local text = ReadText(1001, 1114)
    
    return text, enabled
end
function rcName:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gMain_rename", { 0, 0, menu.object })
end

local rcFaction = registerRowClass("faction")
function rcFaction:getContent()
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
    
    return true, {
        "",
        Helper.createFontString(facText, false, "center")
    }, nil, {1, #menu.selectColWidths-1}
end
function rcFaction:getDetailButtonProps()
    local text = ReadText(1001, 2400)
    local enabled = true
    return text, enabled
end
function rcFaction:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_faction", {0, 0, self.faction})
end

local rcHullShield = registerRowClass("hullShield")
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
    return getStatusBar(self.value/self.maximum, Helper.standardTextHeight, menu.selectColWidths[4], self.barColor)
end
function rcHullShield:getContent(property)
    self.property = property
    
    local value, maximum, pct = self:getVals()
    self.barColor = self.property == "shield" and menu.shieldColor or menu.white
    
    if maximum <= 0 then return end
    
    self.value, self.maximum, self.pct = value, maximum, pct
    
    return true, {Helper.createFontString(self:getText(), false, "right"), self:getBar()}, nil, {3, 1}
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

local rcFuel = registerRowClass("fuel")
function rcFuel:getContent()
    local fuelAmount = GetComponentData(menu.object, "cargo").fuelcells or 0
    local fuelCapacity = GetWareCapacity(menu.object, "fuelcells")
    
    if menu.type ~= "ship" or fuelCapacity == 0 then return end
    
    self.amount = fuelAmount
    self.capacity = fuelCapacity
    
    local fuelText = ConvertIntegerString(fuelAmount, true, 4, true) .. "\27Z/\27X" .. ConvertIntegerString(fuelCapacity, true, 4, true)
    
    if menu.isPlayerOwned and fuelAmount / fuelCapacity <= 0.3 then
        fuelText = "\27R" .. fuelText
    end
    
    return true, {
        Helper.createFontString(ReadText(20205, 800), false, "right"),
        fuelText
    }, nil, {2, 2}
end

local rcWare = registerRowClass("ware")
function rcWare:getWareAmountCell()
    local mot
    local amountString = ConvertIntegerString(self.ware.amount, true, 4, true)
    
    --don't display any limit or warning info for non-player stations
    if menu.isPlayerOwned then
    
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
        
        if self.limit > 0 then
            amountString = amountString .. " / " .. ConvertIntegerString(self.limit, true, 4, true)
        end
    end
    
    return Helper.createFontString(amountString, false, "right", 255, 255, 255, 100, nil, nil, nil, nil, nil, nil, nil, mot)
end
function rcWare:getContent(ware)
    self.ware = ware
    
    local limit = 0
    if menu.isPlayerOwned and menu.type ~= "block" then
        limit = GetWareProductionLimit(menu.object, ware.ware)
    end
    self.limit = limit
    
    self.cycleAmount = self.category.productCycleAmounts[ware.ware] and self.category.productCycleAmounts[ware.ware] + 1 or 0
    
    local totalVolume = ware.amount * ware.volume
    local icon = GetWareData(ware.ware, "icon")
    return true, {
        Helper.createButton(nil, Helper.createButtonIcon(icon, nil, 255, 255, 255, 100), false, true),
        ware.name,
        self:getWareAmountCell(),
        ConvertIntegerString(totalVolume, true, 4, true) .. "\27Z" .. self.category.unit
    }, nil, {1, 1, 1, 1}
end
function rcWare:applyScripts(tab, row)
    Helper.setButtonScript(menu, nil, tab, row, 1, function()
        Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_ware", { 0, 0, "wares", self.ware.ware })
        menu.cleanup()
    end)
end

local rcNpc = registerRowClass("npc")
function rcNpc:getContent(npc)
    self.npc = npc
    
    local name, typeString, typeIcon, typeName, isControlEntity, combinedSkill, skillsKnown = GetComponentData(npc, "name", "typestring", "typeicon", "typename", "iscontrolentity", "combinedskill", "skillsvisible")
    local aiCommand = Helper.parseAICommand(npc)
    
    self.name, self.typeString = name, typeString
    
    local nameCell = Helper.unlockInfo(self.category.namesKnown, name)
    if skillsKnown then
        nameCell = "\27Y"..combinedSkill.."\27X "..nameCell
    end
    
    return true, {
        Helper.createIcon(typeIcon, false, 255, 255, 255, 100, 0, 0, Helper.standardTextHeight, Helper.standardButtonWidth),
        -- typeName .. " " .. name,
        nameCell,
        Helper.unlockInfo(self.category.commandsKnown, aiCommand)
    }, nil, {1, 1, 2}
end
function rcNpc:getDetailButtonProps()
    local text = ReadText(1001, 2961) .. " (" .. Helper.unlockInfo(self.category.namesKnown, self.name) .. ")"
    local enabled = self.category.namesKnown
    
    return text, enabled
end
function rcNpc:onDetailButtonPress()
    Helper.closeMenuForSubSection(menu, false, "gMain_charOrders", { 0, 0, self.npc })
end

local rcLocation = registerRowClass("location")
rcLocation.updateInterval = 1
function rcLocation:getContent()
    local cluster, sector, zone
    
    self.zone = GetContextByClass(menu.object, "zone", false)
    
    return true, {
        Helper.createIcon("menu_sector", false, 255, 255, 255, 100, 0, 0, Helper.standardTextHeight, Helper.standardButtonWidth),
        Helper.createFontString(self:getLocationText(), false, "center")
    }, nil, {1, 3}
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
    if not menu.unlocked.name then return end
    
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

local rcUpgrade = registerRowClass("upgrade")
function rcUpgrade:getContent(weapon, estimated, defStatusKnown, defLevelKnown)
    local operational = weapon.operational
    local total = weapon.total
    
    local color
    if operational/total < 0.5 then
        color = Helper.statusRed
    else
        color = menu.white
    end
    
    return true, {
        Helper.createFontString(weapon.name, false, "right"),
        Helper.createFontString(Helper.estimateString(estimated) .. Helper.unlockInfo(defStatusKnown, operational), false, "right", color.r, color.g, color.b, color.a),
        Helper.createFontString(Helper.estimateString(estimated) .. Helper.unlockInfo(defLevelKnown, total), false, "right")
    }, nil, {2, 1, 1}
end

local rcWeapon = registerRowClass("weapon")
function rcWeapon:getContent(weapon)
    self.weapon = weapon
    return true, {
        Helper.createButton(nil, Helper.createButtonIcon("menu_info", nil, 255, 255, 255, 100), false, true),
        Helper.createFontString(weapon.name, false, "right"),
        Helper.createFontString(ConvertIntegerString(weapon.dps, true, nil, true), false, "right"),
        Helper.createFontString(ConvertIntegerString(weapon.range, true, nil, true) .. " " .. ReadText(1001, 107), false, "right")
    }, nil, {1, 1, 1, 1}
end
function rcWeapon:applyScripts(tab, row)
    Helper.setButtonScript(menu, nil, tab, row, 1, function()
        Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_weapon", {0, 0, "weapontypes_primary", self.weapon.macro})
    end)
end

local rcProduction = registerRowClass("production")
rcProduction.updateInterval = 3
function rcProduction:getTimeText()
    local t = self.data.remainingtime
    if t == 0 or not t then
        return "\27Z--"
    else
        return ConvertTimeString(t, "%h\27Z : \27X%M\27Z : \27X%S", true)
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

function rcProduction:getContent(module)
    self.module = module
    self.nameKnown = IsInfoUnlockedForPlayer(module, "name")
    self.timeKnown = IsInfoUnlockedForPlayer(module, "production_time")
    self.effKnown = IsInfoUnlockedForPlayer(module, "efficiency_amount")
    
    self.name = Helper.unlockInfo(self.nameKnown, GetComponentData(module, "name"))
    
    local data = GetProductionModuleData(module)
    self.data = data
    self.lastState = data.state
    
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
    
    return true, {
        iconCell,
        self:getNameText(),
        Helper.unlockInfo(self.effKnown, productText),
        Helper.unlockInfo(self.timeKnown, self:getTimeText())
    }, nil, {1, 1, 1, 1}
end

function rcProduction:update(tab, row)
    if not self.timeKnown or not IsComponentOperational(self.module) then return end
    local data = GetProductionModuleData(self.module)
    
    if self.nameKnown and data.state ~= self.lastState then
        --name cell needs updating
        SetCellContent(tab, self:getNameText(), row, 2)
    end
    
    self.data = data
    Helper.updateCellText(tab, row, 4, self:getTimeText())
    
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

local rcShopList = registerRowClass("shoppingList")
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
function rcShopList:getContent(item, index)
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
    
    return true, {
        Helper.createFontString(text, false, "left", 170, 170, 170, 100, Helper.standardFont, Helper.standardFontSize, true, nil, nil, 0, Helper.standardSizeX/2 - 20)
        --, Helper.standardSizeX/2 - menu.selectColWidths[1] - 7)
    }, nil, {#menu.selectColWidths}, false, baseColor
end

local rcUnit = registerRowClass("unit")
function rcUnit:getContent(unit)
    self.unit = unit
    
    self.isMarine = IsMacroClass(unit.macro, "npc")
    
    return true, {
        Helper.createButton(nil, Helper.createButtonIcon("menu_info", nil, 255, 255, 255, 100), false, self.category.detailsKnown),
        Helper.unlockInfo(self.category.detailsKnown, unit.name),
        Helper.createFontString(Helper.unlockInfo(self.category.amountKnown, unit.amount), false, "right"),
        Helper.createFontString(Helper.unlockInfo(self.category.detailsKnown, unit.unavailable), false, "right")
    }, nil, {1, 1, 1, 1}
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

menu.categoryScheme = {
    left = {
        menu.categories.general,
        menu.categories.crew,
        menu.categories.arms
    },
    right = {
        menu.categories.production,
        menu.categories.shoppingList,
        menu.categories.cargo,
        menu.categories.units,
    }
}

local function iterateSelectRows(f)
    for i = 1, GetTableNumRows(menu.selectTableLeft) do
        f(i, menu.selectTableLeft, menu.rowDataColumns[menu.selectTableLeft][i])
    end
    for i = 1, GetTableNumRows(menu.selectTableRight) do
        f(i, menu.selectTableRight, menu.rowDataColumns[menu.selectTableRight][i])
    end
end

function menu.processCategory(setup, cat)
    if not cat.visible then return end
    local isExtended = cat.enabled and cat.extended
    
    local rowData = {kind = "catheader", category = cat}
    
    local extendButton = Helper.createButton(Helper.createButtonText(isExtended and "-" or "+", "center", Helper.standardFont, Helper.standardFontSize, 255, 255, 255, 100), nil, false, cat.enabled, 0, 0, 0, Helper.standardTextHeight)
    setup:addSimpleRow({extendButton, cat.header}, rowData, {1, 3}, nil, Helper.defaultHeaderBackgroundColor)
    
    if isExtended then
        cat:display(setup)
    end
end

local function setupColWidths()
    local colWidthTemplate = {Helper.standardButtonWidth, "stretch"}
    local fixedColWidth = 0
    local fixedColumns = 0
    for k, v in ipairs(colWidthTemplate) do
        if v ~= "stretch" then
            fixedColWidth = fixedColWidth + v
            fixedColumns = fixedColumns + 1
        end
    end
    
    local numStretch = menu.stretchyColumns
    local numColumns = fixedColumns + numStretch
    local totalWidth = GetUsableTableWidth(Helper.standardSizeX/2, 0, numColumns, true)
    totalWidth = totalWidth - fixedColWidth
    local stretchWidth = totalWidth / numStretch
    
    local baseColWidth = {}
    
    for i, col in ipairs(colWidthTemplate) do
        if col == "stretch" then
            for j = 1, numStretch do
                table.insert(baseColWidth, stretchWidth)
            end
        else
            table.insert(baseColWidth, col)
        end
    end
    
    menu.selectColWidths = baseColWidth
end
    

local function init()
	Menus = Menus or { }
	table.insert(Menus, menu)
	if Helper then
		Helper.registerMenu(menu)
	end
end

function menu.onShowMenu()
	menu.object = menu.param[3] or GetPlayerTarget()
	--menu.extendedcategories = menu.param[5] or menu.extendedcategories
	menu.category = ""
	menu.unlocked = {}
	menu.playerShip = GetPlayerPrimaryShipID()
	menu.isPlayerShip = IsSameComponent(menu.object, menu.playerShip)
	menu.isPlayerOwned = GetComponentData(menu.object, "isplayerowned")
	menu.data = {}
	menu.unlocked.name = IsInfoUnlockedForPlayer(menu.object, "name")
	local object = menu.object
	if IsComponentClass(object, "ship") then
		menu.type, menu.title = "ship", Helper.unlockInfo(menu.unlocked.name, GetComponentData(menu.object, "name")) .. " - " .. ReadText(1001, 1101)
	elseif IsComponentClass(object, "station") then 
		menu.type, menu.title = "station", Helper.unlockInfo(menu.unlocked.name, GetComponentData(menu.object, "name")) .. " - " .. ReadText(1001, 1100)
	else
		menu.container = GetContextByClass(menu.object, "container")
		if menu.container then
			local name = Helper.unlockInfo(menu.unlocked.name, GetComponentData(menu.object, "name"))
			menu.unlocked[tostring(menu.container)] = { name = IsInfoUnlockedForPlayer(menu.container, "name") }
			menu.type, menu.title = "block", Helper.unlockInfo(menu.unlocked[tostring(menu.container)].name, GetComponentData(menu.container, "name")) .. " - " .. (name ~= "" and name or ReadText(1001, 56))
		else
			menu.type, menu.title = "block", ReadText(1001, 1102)
		end
	end

	if menu.type ~= "block" then
		if IsComponentClass(object, "station") then
			menu.category = "stationtypes"
		elseif IsComponentClass(object, "ship_xl") then
			menu.category = "shiptypes_xl"
		elseif IsComponentClass(object, "ship_l") then
			menu.category = "shiptypes_l"
		elseif IsComponentClass(object, "ship_m") then
			menu.category = "shiptypes_m"
		elseif IsComponentClass(object, "ship_s") then
			menu.category = "shiptypes_s"
		elseif IsComponentClass(object, "ship_xs") then
			menu.category = "shiptypes_xs"
		end
	else
		menu.category = GetModuleType(object)
	end
    
    local productionColor, buildColor, storageColor, radarColor, dronedockColor, efficiencyColor, defenceColor, playerColor, friendColor, enemyColor, missionColor = GetHoloMapColors()
    menu.holomapColor = { productionColor = productionColor, buildColor = buildColor, storageColor = storageColor, radarColor = radarColor, dronedockColor = dronedockColor, efficiencyColor = efficiencyColor, defenceColor = defenceColor, playerColor = playerColor, friendColor = friendColor, enemyColor = enemyColor, missionColor = missionColor }
    
    setupColWidths()
    
    --calculate col widths:
    --there are 9 elements: 4 buttons and 5 spaces
    --a button is about 3 times the width of a space
    --total 'weight' is 12 for buttons and 5 for spaces
    local buttonUsableWidth = GetUsableTableWidth(Helper.standardSizeX-20, 0, 9, false)
    local buttonTableButtonShare = 14
    local buttonTableSpacerShare = 4
    local buttonTableTotalShare = buttonTableButtonShare + buttonTableSpacerShare
    menu.buttonTableButtonWidth = (buttonTableButtonShare/buttonTableTotalShare) * buttonUsableWidth / 4
    menu.buttonTableSpacerWidth = (buttonTableSpacerShare/buttonTableTotalShare) * buttonUsableWidth / 5
    
    menu.statusMessage = menu.statusMessage or "Ready"

	menu.displayMenu(true)
end

function menu.displayMenu(isFirstTime)
    menu.nowDisplaying = true
    
    local topRowLeft = 0
    local topRowRight = 0
    local curRowLeft = 0
    local curRowRight = 0
    
    menu.ignoreRowChange = 3
    
    local nextActive = "left"
    
    local lastCurTable
    
	if not isFirstTime then
        if menu.nextRows and menu.nextRows.left then
            curRowLeft = menu.nextRows.left
        else
            curRowLeft = Helper.currentTableRow[menu.selectTableLeft]
        end
        if menu.nextRows and menu.nextRows.right then
            curRowRight = menu.nextRows.right
        else
            curRowRight = Helper.currentTableRow[menu.selectTableRight]
        end
        
        topRowLeft = GetTopRow(menu.selectTableLeft)
        topRowRight = GetTopRow(menu.selectTableRight)
        Helper.removeAllButtonScripts(menu)
        Helper.currentTableRow = {}
        Helper.currentTableRowData = nil
        menu.rowDataMap = {}
        
        if menu.nextTable then
            nextActive = menu.tableNames[menu.nextTable]
        else
            nextActive = menu.tableNames[GetInteractiveObject(menu.frame)]
        end
        
        lastCurTable = menu.currentColumn
    end
    
    menu.nextTable = nil
    menu.nextRows = {}
    menu.tableNames = {}
    menu.rowDataColumns = {}
    menu.namedTables = {}
    
    local tabLeft, tabRight, tabButton
    if nextActive == "left" then
        tabLeft = 1
        tabRight = 2
        tabButton = 3
    elseif nextActive == "right" then
        tabRight = 1
        tabButton = 2
        tabLeft = 3
    else
        tabButton = 1
        tabLeft = 2
        tabRight = 3
    end
    
    --get all categories to set up their data again
    for k, cat in pairs(menu.categories) do
        cat:init()
        cat.rows = {}
    end

    --table for title and left column
    --=========================================
    local titleColor
    if menu.isPlayerOwned then
        titleColor = menu.holomapColor.playerColor
    elseif GetComponentData(menu.object, "isenemy") then
        titleColor = menu.holomapColor.enemyColor
    else
        titleColor = menu.holomapColor.friendColor
    end
    menu.objNameColor = titleColor
    
    local setup = Helper.createTableSetup(menu)
    setup:addSimpleRow({
        Helper.createButton(nil, Helper.createButtonIcon("menu_info", nil, 255, 255, 255, 100), false),
        Helper.createFontString(menu.title, false, "left", titleColor.r, titleColor.g, titleColor.b, titleColor.a, Helper.headerRow1Font, Helper.headerRow1FontSize, false, Helper.headerRow1Offsetx, Helper.headerRow1Offsety, Helper.headerRow1Height, Helper.headerRow1Width)
    }, nil, {1, #menu.selectColWidths-1}, false, Helper.defaultTitleBackgroundColor)
    
    setup:addTitleRow({ 
        Helper.createFontString(menu.statusMessage, false, "left", 129, 160, 182, 100, Helper.headerRow2Font, Helper.headerRow2FontSize)
    }, nil, {#menu.selectColWidths})
    
    local numHeaderRows = #setup.rows
    
    for k, cat in pairs(menu.categoryScheme.left) do
        menu.processCategory(setup, cat)
    end
    
    local selectLeftDesc = setup:createCustomWidthTable(clone(menu.selectColWidths), false, false, true, tabLeft, numHeaderRows, 0, 0, menu.selectTableHeight, nil, topRowLeft, curRowLeft)
    
    local rowDataLeft = clone(menu.rowDataMap)
    menu.rowDataMap = {}
    
    --table for right column
    --=========================================
    
    setup = Helper.createTableSetup(menu)
    
    for k, cat in pairs(menu.categoryScheme.right) do
        menu.processCategory(setup, cat)
    end
    
    local selectRightDesc = setup:createCustomWidthTable(clone(menu.selectColWidths), false, false, true, tabRight, 0, (Helper.standardSizeX/2) - 7, 0, menu.selectTableHeight, nil, topRowRight, curRowRight)
    
    local rowDataRight = clone(menu.rowDataMap)
    menu.rowDataMap = {}

    --table for ABXY buttons
    --=========================================
    
    setup = Helper.createTableSetup(menu)
    
    setup:addSimpleRow({ 
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 2669), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_B", true)),
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 2669), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_BACK", true)),
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 2669), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_Y", true)),
        Helper.getEmptyCellDescriptor(),
        -- Helper.createButton(Helper.createButtonText(ReadText(1001, 2669), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_X", true)),
        --we'll be naughty here and just replace it instantly rather than make it now
        Helper.getEmptyCellDescriptor(),
        Helper.getEmptyCellDescriptor()
    }, nil, nil, false, menu.transparent)
    
    local buttonTableDesc = setup:createCustomWidthTable(
    {
        menu.buttonTableSpacerWidth,
        menu.buttonTableButtonWidth,
        menu.buttonTableSpacerWidth,
        menu.buttonTableButtonWidth,
        menu.buttonTableSpacerWidth,
        menu.buttonTableButtonWidth,
        menu.buttonTableSpacerWidth,
        menu.buttonTableButtonWidth,
        menu.buttonTableSpacerWidth
    }, false, false, false, tabButton, 0, 0, Helper.standardSizeY-50, 0, false)

    --create and display the table view
    --=========================================
    menu.selectTableLeft, menu.selectTableRight, menu.buttonTable = Helper.displayThreeTableView(menu, selectLeftDesc, selectRightDesc, buttonTableDesc, false)
    
    menu.tableNames[menu.selectTableLeft] = "left"
    menu.tableNames[menu.selectTableRight] = "right"
    menu.tableNames[menu.buttonTable] = "button"
    
    menu.namedTables.left = menu.selectTableLeft
    menu.namedTables.right = menu.selectTableRight
    menu.namedTables.button = menu.buttonTable
    
    local curInteractive = GetInteractiveObject(menu.frame)
    if curInteractive == menu.buttonTable then
        if not menu.currentColumn then
            menu.currentColumn = menu.selectTableLeft
        end
    else
        menu.currentColumn = GetInteractiveObject(menu.frame)
    end
    
    menu.rowDataColumns[menu.selectTableLeft] = rowDataLeft
    menu.rowDataColumns[menu.selectTableRight] = rowDataRight

    --set script for encyclopedia button (top left)
    --Helper.setButtonScript(menu, nil, menu.selectTableLeft, 1, 1, menu.buttonEncyclopedia)
    
    iterateSelectRows(function(row, tab, rowData)
        if not rowData then return end
        if rowData.kind == "catheader" then
            local category = rowData.category
            Helper.setButtonScript(menu, nil, tab, row, 1, function()
                category.extended = not category.extended
                menu.nextRows[menu.tableNames[tab]] = row
                menu.nextTable = tab
                menu.displayMenu()
            end)
        end
        
        if rowData.kind == "regular" then
            if rowData.applyScripts then
                rowData:applyScripts(tab, row)
            end
        end
    end)
    
    menu.refreshDetailButton()
    
    menu.nowDisplaying = nil
end

function menu.refreshDetailButton(rowData)
    if not rowData then
        rowData = menu.rowDataColumns[menu.currentColumn][Helper.currentTableRow[menu.currentColumn]]
        if not rowData then return end
    end
    
    local obj
    if rowData.kind == "regular" then
        obj = rowData
    elseif rowData.kind == "catheader" then
        obj = rowData.category
    else
        return
    end
    
    local text, enabled
    
    if obj.getDetailButtonProps then
        text, enabled = obj:getDetailButtonProps()
        
        text = TruncateText(text, Helper.standardFont, Helper.standardFontSize, menu.buttonTableButtonWidth)
    else
        text = "--"
        enabled = false
    end
    
    if not menu.nowDisplaying then
        Helper.removeButtonScripts(menu, menu.buttonTable, 1, 8)
    end
    
    local button = Helper.createButton(Helper.createButtonText(text, "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, enabled, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_X", true))
    SetCellContent(menu.buttonTable, button, 1, 8)
    
    Helper.setButtonScript(menu, nil, menu.buttonTable, 1, 8, function() obj:onDetailButtonPress() end)
end

menu.updateInterval = 0.1
function menu.onUpdate()
    for k, v in pairs(menu.categories) do
        if v.updateInterval and v.update and v.visible then
            local nextUpd = v.nextUpdate or 0
            local now = GetCurTime()
            if now > nextUpd then
                v.nextUpdate = now + v.updateInterval
                v:update()
            end
        end
    end
    
    iterateSelectRows(function(row, tab, rowData)
        if not rowData or rowData.kind ~= "regular" then return end
        
        if rowData.updateInterval and rowData.update then
            local nextUpd = rowData.nextUpdate or 0
            local now = GetCurTime()
            if now > nextUpd then
                rowData.nextUpdate = now + rowData.updateInterval
                rowData:update(tab, row)
            end
        end
    end)
end

function menu.updateStatusMessage()
    local tab = menu.currentColumn
    
    local msg = "Table = " .. menu.tableNames[tab] .. ", Row = " .. Helper.currentTableRow[tab]
    
    menu.statusMessage = msg
    Helper.updateCellText(menu.selectTableLeft, 2, 1, menu.statusMessage)
end

local function kludgeSetInteractive(tab)
    while GetInteractiveObject(menu.frame) ~= tab do
        SwitchInteractiveObject(menu.frame)
    end
end

menu.ignoreRowChange = 0
function menu.onRowChanged(row, rowData, tab)
    if menu.ignoreRowChange > 0 then
        --DebugError("False row change")
        menu.ignoreRowChange = menu.ignoreRowChange - 1
        return
    end
    
    if tab == menu.selectTableLeft or tab == menu.selectTableRight then
        menu.currentColumn = tab
        kludgeSetInteractive(tab)
        menu.onSelectionChanged()
    end
end

function menu.onSelectElement(tab)
    if tab == menu.selectTableLeft or tab == menu.selectTableRight then
        kludgeSetInteractive(tab)
        if tab ~= menu.currentColumn then
            menu.currentColumn = tab
            menu.onSelectionChanged()
        end
    end
end

function menu.onCloseElement(dueToClose)
	if dueToClose == "close" then
		Helper.closeMenuAndCancel(menu)
		menu.cleanup()
	else
		Helper.closeMenuAndReturn(menu)
		menu.cleanup()
	end
end

function menu.onInteractiveElementChanged(element)
    menu.activeElement = element
    if element == menu.selectTableLeft or element == menu.selectTableRight then
        menu.currentColumn = element
        menu.onSelectionChanged()
    end
end

function menu.onSelectionChanged()
    local tab = menu.currentColumn
    local row = Helper.currentTableRow[tab]
    --DebugError(string.format("Tab = %s, Row = %s", tab, row))
    local rowData = menu.rowDataColumns[tab][row]
    
    menu.updateStatusMessage()
    menu.refreshDetailButton(rowData)
end

function menu.cleanup()
end

init()