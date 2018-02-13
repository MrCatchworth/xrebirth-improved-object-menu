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
    
    selectTableHeight = 535
}

function menu.getMultiColWidth(startIndex, endIndex)
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
    
    return rowData
end

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
    addRowByClass(setup, self, menu.rowClasses.jumpdrive)
    addRowByClass(setup, self, menu.rowClasses.fuel)
end

menu.categories.cargo = {}
local catCargo = menu.categories.cargo
catCargo.visible = false
catCargo.enabled = false
catCargo.extended = true
catCargo.headerColSpans = {3, 2}
catCargo.headerCells = {"", ""}
catCargo.customHeader = true
function catCargo:init()
    self.rawStorage = GetStorageData(menu.object)
    self.storageSummary = self:aggregateStorage(self.rawStorage)
    self.products = GetComponentData(menu.object, "products")
    
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
    
    local otherCase = menu.type == "station" and self.rawStorage.estimated ~= nil
    self.amountKnown = IsInfoUnlockedForPlayer(menu.object, "storage_amounts") or otherCase
    self.capacityKnown = IsInfoUnlockedForPlayer(menu.object, "storage_capacity") or otherCase
    self.waresKnown = IsInfoUnlockedForPlayer(menu.object, "storage_warelist") or otherCase
    
    self.visible = cap > 0
    self.enabled = (stored > 0 or self.rawStorage.estimated) and self.waresKnown
    
    self.unit = " " .. ReadText(1001, 110)
    
    if self.visible then
        local sep = "\27Z -- \27X"
        -- local mainHeader = ReadText(1001, 1400) .. sep .. amountString .. "/" .. capacityString .. self.unit .. sep .. wareCount .. " " .. (wareCount == 1 and ReadText(1001, 45) or ReadText(1001, 46))
        
        local amountString = Helper.unlockInfo(self.amountKnown, ConvertIntegerString(stored, true, 4, true))
        local capacityString = Helper.unlockInfo(self.capacityKnown, ConvertIntegerString(cap, true, 4, true))
        self.headerCells[1] = ReadText(1001, 1400) .. sep .. amountString .. "/" .. capacityString .. self.unit
        
        local hasLimits = self.products and next(self.products)
        self.headerCells[2] = Helper.createFontString(ReadText(1001, 20) .. (hasLimits and " / " .. ReadText(1001, 1127) or ""), false, "right")
        
        self.rowsByWare = {}
    end
end
function catCargo:display(setup)
    for ware, data in Helper.orderedPairsByWareName(self.storageSummary) do
        self.rowsByWare[ware] = addRowByClass(setup, self, menu.rowClasses.ware, data)
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
catCargo.updateInterval = 1
function catCargo:update()
    self.rawStorage = GetStorageData(menu.object)
    self.storageSummary = self:aggregateStorage(self.rawStorage)
    
    for ware, row in pairs(self.rowsByWare) do
        if self.storageSummary[ware] then
            row:updateAmount(self.storageSummary[ware].amount)
        else
            row:updateAmount(0)
        end
    end
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
    table.insert(self.controlEntities, menu.buildingArchitect)
    
    self.visible = menu.type ~= "block" and not menu.isPlayerShip
    self.enabled = #self.npcs > 0
    self.namesKnown = IsInfoUnlockedForPlayer(menu.object, "operator_name")
    self.commandsKnown = IsInfoUnlockedForPlayer(menu.object, "operator_commands")
end
function catCrew:display(setup)
    addRowByClass(setup, self, menu.rowClasses.personnel)
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

-- return true if isUpdate is set, and the operationals have changed
function catArms:collectData(isUpdate)
    self.upgrades = GetAllUpgrades(menu.object, false)
    self.fixedTurrets = GetNotUpgradesByClass(menu.object, "turret")
    
    self.fixedTurrets.total = 0
    self.fixedTurrets.operational = 0
    
    --we get a list of components from GetNotUpgrades, but we convert them into a format similar to that given by GetAllUpgrades, so the row class can use either interchangeably
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
end

function catArms:init()
    self.armament = GetAllWeapons(menu.object)
    
    --don't show empty missile ammo
    for i = #self.armament.missiles, 1, -1 do
        if self.armament.missiles[i].amount == 0 then
            table.remove(self.armament.missiles, i)
        end
    end
    
    self:collectData()
    
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
    self.upgradeRows = {}
    self.fixedTurretRows = {}
    if not menu.isPlayerShip then
        for ut, upgrade in Helper.orderedPairs(self.upgrades) do
            if type(upgrade) == "table" and upgrade.total > 0 then
                self.upgradeRows[ut] = addRowByClass(setup, self, menu.rowClasses.upgrade, upgrade, self.estimated)
            end
        end
        for macro, turret in pairs(self.fixedTurrets) do
            if type(turret) == "table" and turret.operational > 0 then
                self.fixedTurretRows[macro] = addRowByClass(setup, self, menu.rowClasses.upgrade, turret, self.fixedTurrets.estimated)
            end
        end
    end
    for k, weapon in ipairs(self.armament.weapons) do
        local ffiMod = ffi.new("UIWeaponMod")
        local retVal = C.GetInstalledWeaponMod(ConvertIDTo64Bit(weapon.component), ffiMod)
        if not retVal then
            ffiMod = nil
        end
        addRowByClass(setup, self, menu.rowClasses.weapon, weapon, ffiMod)
    end
end
catArms.updateInterval = 2
function catArms:update()
    self:collectData()
    for ut, row in pairs(self.upgradeRows) do
        local upgrade = self.upgrades[ut]
        if upgrade then
            row:updateVal(upgrade)
        end
    end
    for macro, row in pairs(self.fixedTurretRows) do
        local turret = self.fixedTurrets[macro]
        if turret then
            row:updateVal(turret)
        end
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
catUnits.headerColSpans = {2, 2, 1}
catUnits.headerCells = {"", "", ""}
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
    self:aggregateByMacro()
    
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
    
    local mainHeader = ReadText(1001, 22) .. "\27Z -- \27X" .. Helper.unlockInfo(self.amountKnown, self.units.stored) .. "\27Z / \27X" .. Helper.unlockInfo(self.capacityKnown, self.units.capacity)
    if self.extended then
        self.customHeader = true
        self.headerCells[1] = mainHeader
        self.headerCells[2] = Helper.createFontString(ReadText(1001, 20), false, "right")
        self.headerCells[3] = Helper.createFontString(ReadText(1001, 1403), false, "right")
    else
        self.customHeader = false
        self.header = mainHeader
    end
end

function catUnits:aggregateByMacro()
    self.unitsByMacro = {}
    for k, unit in ipairs(self.units) do
        self.unitsByMacro[unit.macro] = unit
    end
end

function catUnits:display(setup)
    for k, unit in ipairs(self.units) do
        if unit.amount > 0 then
            addRowByClass(setup, self, menu.rowClasses.unit, unit)
        end
    end
end

catUnits.updateInterval = 3
function catUnits:update()
    if #self.rows == 0 then return end
    
    self.units = GetUnitStorageData(menu.object)
    self:aggregateByMacro()
    for k, row in ipairs(self.rows) do
        local newUnit = self.unitsByMacro[row.unit.macro]
        if newUnit then
            row:updateUnit(newUnit)
        else
            DebugError("No unit with that macro")
        end
    end
end

menu.categories.playerUpgrades = {}
local catPlayerUpgrades = menu.categories.playerUpgrades
catPlayerUpgrades.visible = false
catPlayerUpgrades.enabled = true
catPlayerUpgrades.extended = true
catPlayerUpgrades.upgradeCats = {"engine", "shieldgenerator", "scanner", "software"}
catPlayerUpgrades.catHeaders = {
    engine = ReadText(1001, 1103),
    shieldgenerator = ReadText(1001, 1317),
    scanner = ReadText(1001, 74),
    software = ReadText(1001, 87)
}
catPlayerUpgrades.catNones = {
    engine = ReadText(1001, 88),
    shieldgenerator = ReadText(1001, 89),
    scanner = ReadText(1001, 90),
    software = ReadText(1001, 91)
}
catPlayerUpgrades.header = "Upgrades"
function catPlayerUpgrades:init()
    self.visible = menu.isPlayerShip
    
    if not self.visible then return end
    
    self.upgradesByCat = {}
    for k, cat in pairs(self.upgradeCats) do
        if not (ut == "totaltotal" or ut == "totalfree" or ut == "totaloperational" or ut == "totalconstruction" or ut == "estimated") then
            self.upgradesByCat[cat] = GetAllUpgrades(menu.object, true, cat)
        end
    end
end

function catPlayerUpgrades:getSoftwareSlots(upgrades)
    local organiseUpgrades = {}
    local totalSlots = 0
    for ut, upgrade in Helper.orderedPairs(upgrades) do
        if not (ut == "totaltotal" or ut == "totalfree" or ut == "totaloperational" or ut == "totalconstruction" or ut == "estimated") then
            local index
            for i, cat in ipairs(organiseUpgrades) do
                if cat == upgrade.tags then
                    index = i
                    break
                end
            end
            if not index then
                totalSlots = totalSlots + 1
                table.insert(organiseUpgrades, upgrade.tags)
            end
        end
    end
    return totalSlots
end

function catPlayerUpgrades:displayCat(setup, cat)
    local upgrades = self.upgradesByCat[cat]
    local factor = cat == "engine" and 0.5 or 1
    
    local totalSlots = cat == "software" and self:getSoftwareSlots(upgrades) or upgrades.totaltotal
    
    setup:addHeaderRow({
        "",
        self.catHeaders[cat],
        Helper.createFontString(factor * upgrades.totaloperational .. " / " .. factor * totalSlots, false, "right")
    }, nil, {1, 4, 1})
    
    local displayed = false
    for ut, upgrade in Helper.orderedPairs(upgrades) do
        if not (ut == "totaltotal" or ut == "totalfree" or ut == "totaloperational" or ut == "totalconstruction" or ut == "estimated") then
            if upgrade.operational ~= 0 then
                addRowByClass(setup, self, menu.rowClasses.playerUpgrade, upgrade, factor)
                displayed = true
            end
        end
    end
    
    if not displayed then
        setup:addSimpleRow({
			"",
			"--- " .. self.catNones[cat] .. " ---"
		}, nil, {1, #menu.selectColWidths-1})
    end
end

function catPlayerUpgrades:display(setup)
    for k, cat in pairs(self.upgradesByCat) do
        self:displayCat(setup, k)
    end
end
    
--row classes start here
--===================================================================

menu.rowClasses = {}

function menu.registerRowClass(name)
    local rc = {}
    menu.rowClasses[name] = rc
    rc.metaTable = {__index = rc}
    rc.className = name
    
    return rc
end

local rowClassLib = loadfile("extensions/mej_improved_object_menu/ui/addons/mej_improved_object_menu/rowclasses.lua")
rowClassLib(menu)

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
        menu.categories.playerUpgrades
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
    
    local cells
    local colSpans
    if cat.customHeader then
        colSpans = {1}
        for k, colSpan in ipairs(cat.headerColSpans) do
            table.insert(colSpans, colSpan)
        end
        
        cells = {extendButton}
        for k, catCell in ipairs(cat.headerCells) do
            table.insert(cells, catCell)
        end
    else
        colSpans = {1, #menu.selectColWidths-1}
        cells = {extendButton, cat.header}
    end
    
    setup:addSimpleRow(cells, rowData, colSpans, nil, Helper.defaultHeaderBackgroundColor)
    
    if isExtended then
        cat:display(setup)
    end
end

local function setupColWidths()
    local colFracs = {1/3, 1/6, 1/6, 1/12, 1/4}
    local colWidths = {Helper.standardButtonWidth}
    
    local totalWidth = GetUsableTableWidth(Helper.standardSizeX/2 - 7 - Helper.standardButtonWidth, 0, #colFracs, true)
    
    for k, frac in pairs(colFracs) do
        table.insert(colWidths, totalWidth * frac)
    end
    
    menu.selectColWidths = colWidths
end
    

local function init()
	Menus = Menus or { }
	table.insert(Menus, menu)
	if Helper then
		Helper.registerMenu(menu)
	end
end

function menu.onShowMenu()
	menu.object = menu.param[3]
	menu.category = ""
	menu.unlocked = {}
	menu.playerShip = GetPlayerPrimaryShipID()
	menu.isPlayerShip = IsSameComponent(menu.object, menu.playerShip)
	menu.isPlayerOwned = GetComponentData(menu.object, "isplayerowned")
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
    
    menu.isBigShip = menu.type == "ship" and (IsComponentClass(menu.object, "ship_l") or IsComponentClass(menu.object, "ship_xl"))
    
    menu.buildingModule = GetComponentData(menu.object, "buildingmodule")
    if menu.buildingModule then
        menu.buildingContainer = GetContextByClass(menu.buildingModule, "container")
        if menu.buildingContainer then
            menu.buildingArchitect = GetComponentData(menu.buildingContainer, "architect")
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
    
    RegisterAddonBindings("ego_detailmonitor")

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
        Helper.removeAllKeyBindings(menu)
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
    
    Helper.setKeyBinding(menu, menu.onHotkey)
    
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
    
    local selectLeftDesc = setup:createCustomWidthTable(clone(menu.selectColWidths), false, false, true, tabLeft, numHeaderRows, 0, 0, menu.selectTableHeight, true, topRowLeft, curRowLeft)
    
    local rowDataLeft = clone(menu.rowDataMap)
    menu.rowDataMap = {}
    
    --table for right column
    --=========================================
    
    setup = Helper.createTableSetup(menu)
    
    for k, cat in pairs(menu.categoryScheme.right) do
        menu.processCategory(setup, cat)
    end
    
    local selectRightDesc = setup:createCustomWidthTable(clone(menu.selectColWidths), false, false, true, tabRight, 0, (Helper.standardSizeX/2) - 7, 0, menu.selectTableHeight, true, topRowRight, curRowRight)
    
    local rowDataRight = clone(menu.rowDataMap)
    menu.rowDataMap = {}

    --table for ABXY buttons
    --=========================================
    
    setup = Helper.createTableSetup(menu)
    
    setup:addSimpleRow({ 
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 2669), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_B", true)),
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 1113), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_BACK", true)),
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 1109), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, not menu.isPlayerShip, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_Y", true)),
        Helper.getEmptyCellDescriptor(),
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
    }, false, false, false, tabButton, 0, 0, Helper.standardSizeY-30, 0, false)

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
            rowData.tab = tab
            if rowData.applyScripts then
                rowData:applyScripts(tab, row)
            end
        end
    end)
    
    --set the action for three ABXY buttons in a separate function
    Helper.setButtonScript(menu, nil, menu.buttonTable, 1, 2, function()
        menu.onCloseElement()
    end)
    
    Helper.setButtonScript(menu, nil, menu.buttonTable, 1, 4, menu.tradeOffers)
    
    Helper.setButtonScript(menu, nil, menu.buttonTable, 1, 6, menu.plotCourse)
    
    menu.refreshDetailButton()
    
    menu.nowDisplaying = nil
end

function menu.closeIfDead()
    if not IsComponentOperational(menu.object) then
        Helper.closeMenuAndReturn(menu)
        return false
    end
    return true
end

function menu.tradeOffers()
    if not menu.closeIfDead() then return end
    Helper.closeMenuForSubSection(menu, false, "gTrade_offerselect", { 0, 0, nil, nil, nil, menu.object })
end

function menu.plotCourse()
    if IsComponentOperational(menu.object) then
        Helper.closeMenuForSection(menu, false, "gMainNav_select_plotcourse", {menu.object, menu.type, IsSameComponent(GetActiveGuidanceMissionComponent(), menu.object)})
    else
        Helper.closeMenuAndReturn(menu)
    end
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
    
    Helper.setButtonScript(menu, nil, menu.buttonTable, 1, 8, function()
        if IsComponentOperational(menu.object) then
            obj:onDetailButtonPress()
        end
    end)
end

menu.updateInterval = 0.1
function menu.onUpdate()
    if menu.nowDisplaying then
        DebugError("Error detected while displaying menu!")
        menu.updateInterval = 3600
        return
    end
    
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
    
    if not (IsComponentOperational(menu.object) or IsComponentConstruction(menu.object)) then
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
    UnregisterAddonBindings("ego_detailmonitor")
end

init()