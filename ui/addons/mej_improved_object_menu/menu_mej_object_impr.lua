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
    double GetCurrentGameTime(void);
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
    grey = { r = 128, g = 128, b = 128, a = 100 },
    lightGrey = { r = 170, g = 170, b = 170, a = 100 },
    statusMsgColor = { r = 129, g = 160, b = 182, a = 100 },
}

function menu.getMultiColWidth(startIndex, endIndex)
    local width = 0
    local count = 0
    -- local borderWidth = 3
    local borderWidth = menu.lowResMode and 4 or 3
    
    for index = startIndex, endIndex do
        count = count + 1
        if count > 1 then
            width = width + borderWidth
        end
        
        width = width + menu.selectColWidths[index]
    end
    
    return width
end

--menu categories start here
--=========================================

menu.categories = {}

function menu.registerCategory(name)
    local cat = {}
    setmetatable(cat, {__index = menu.baseCategoryLib})
    menu.categories[name] = cat
    return cat
end

menu.baseCategoryLib = {}
function menu.baseCategoryLib:addItem(setup, class, ...)
    local rowsBefore = #setup.rows
    
    local rowData = {}
    rowData.class = class
    rowData.kind = "regular"
    rowData.category = self
    setmetatable(rowData, class.metaTable)
    
    -- DebugError("Adding category item of class " .. class.className)
    
    if rowData.init then rowData:init() end
    
    rowData:display(setup, ...)
    
    local rowAdded = false
    for i = rowsBefore, #setup.rows do
        if menu.rowDataMap[i] == rowData then
            rowAdded = true
            break
        end
    end
    
    if rowAdded then
        table.insert(self.rows, rowData)
        return rowData
    else
        return nil
    end
end

local catGeneral = menu.registerCategory("general")
catGeneral.header = ReadText(1001, 1111)
catGeneral.visible = true
catGeneral.enabled = true
catGeneral.extended = true
function catGeneral:init()
end
function catGeneral:display(setup)
    self:addItem(setup, menu.rowClasses.name)
    self:addItem(setup, menu.rowClasses.faction)
    self:addItem(setup, menu.rowClasses.commander)
    self:addItem(setup, menu.rowClasses.partOf)
    self:addItem(setup, menu.rowClasses.location)
    self:addItem(setup, menu.rowClasses.hullShield, "hull")
    self:addItem(setup, menu.rowClasses.hullShield, "shield")
    self:addItem(setup, menu.rowClasses.engine)
    self:addItem(setup, menu.rowClasses.efficiency)
    self:addItem(setup, menu.rowClasses.jumpdrive)
    self:addItem(setup, menu.rowClasses.fuel)
    self:addItem(setup, menu.rowClasses.boardingResistance)
    self:addItem(setup, menu.rowClasses.boardingStrength)
    self:addItem(setup, menu.rowClasses.economy)
end

local catCargo = menu.registerCategory("cargo")
catCargo.visible = false
catCargo.enabled = false
catCargo.extended = true
catCargo.headerColSpans = {2, 3}
catCargo.headerCells = {"", ""}
catCargo.customHeader = true
function catCargo:getHeaderString()
    local amountString = Helper.unlockInfo(self.amountKnown, ConvertIntegerString(self.rawStorage.stored, true, 4, true))
    local capacityString = Helper.unlockInfo(self.capacityKnown, ConvertIntegerString(self.rawStorage.capacity, true, 4, true))
    return --[[ReadText(1001, 1400) .. sep .. ]] amountString .. "/" .. capacityString .. self.unit
end
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
    
    self.owner = GetComponentData(menu.object, "owner")
    self.zoneOwner = GetComponentData(GetComponentData(menu.object, "zoneid"), "owner")
    
    if self.visible then
        local sep = "\27Z -- \27X"
        -- local mainHeader = ReadText(1001, 1400) .. sep .. amountString .. "/" .. capacityString .. self.unit .. sep .. wareCount .. " " .. (wareCount == 1 and ReadText(1001, 45) or ReadText(1001, 46))
        
        self.headerCells[1] = self:getHeaderString()
        
        local hasLimits = self.products and next(self.products)
        self.headerCells[2] = Helper.createFontString(ReadText(1001, 20) .. (hasLimits and " / " .. ReadText(1001, 1127) or ""), false, "right")
        
        self.rowsByWare = {}
    end
end
function catCargo:display(setup)
    for ware, data in Helper.orderedPairsByWareName(self.storageSummary) do
        AddKnownItem("wares", ware)
        self.rowsByWare[ware] = self:addItem(setup, menu.rowClasses.ware, data)
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
    
    if menu.isPlayerOwned then
        --add rows for empty resources
        for k, ware in pairs(GetComponentData(menu.object, "pureresources")) do
            if not cargo[ware] then
                cargo[ware] = {ware = ware, amount = 0, name = GetWareData(ware, "name"), volume = 1}
            end
        end
    end
    
    return cargo
end
catCargo.updateInterval = 1
function catCargo:update()
    local prevStoredAmount = self.rawStorage.stored
    self.rawStorage = GetStorageData(menu.object)
    self.storageSummary = self:aggregateStorage(self.rawStorage)
    
    if prevStoredAmount ~= self.rawStorage.stored then
        -- DebugError("Updating total stored from " .. prevStoredAmount .. " to " .. self.rawStorage.stored)
        Helper.updateCellText(self.tab, self.headerRow, 2, self:getHeaderString())
    end
    
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
function catCargo:cleanup()
    self.rawStorage = nil
    self.storageSummary = nil
    self.rowsByWare = nil
end

local catCrew = menu.registerCategory("crew")
catCrew.header = ReadText(1001, 1108)
catCrew.visible = true
catCrew.enabled = false
catCrew.extended = true
catCrew.typeOrdering = {
    manager = 1,
    commander = 2,
    pilot = 3,
    defencecontrol = 4,
    engineer = 5,
    architect = 6
}
function catCrew:init()
    self.visible = menu.type ~= "block" and not menu.isPlayerShip
    if not self.visible then return end
    
    self.npcs = GetNPCs(menu.object)
    
    self.displayedNpcs = {}
    for k, npc in pairs(self.npcs) do
        local isControlEntity, isPlayer = GetComponentData(npc, "iscontrolentity", "isplayerowned")
        if isControlEntity or (menu.isPlayerOwned and isPlayer) then
            table.insert(self.displayedNpcs, npc)
        end
    end
    table.insert(self.displayedNpcs, menu.buildingArchitect)
    
    table.sort(self.displayedNpcs, function(a, b)
        local aType, bType = GetComponentData(a, "typestring"), GetComponentData(b, "typestring")
        local aIndex, bIndex = self.typeOrdering[aType], self.typeOrdering[bType]
        
        --if both types are sorted, put them in that order
        if aIndex and bIndex then
            return aIndex < bIndex
        end
        
        --if only one type is sorted, the npc with the unsorted type goes at the end
        if not aIndex then return false end
        if not bIndex then return true end
        
        --if neither types are sorted, sort the types in alphabetical order
        return aType < bType
    end)
    
    --[[
    for k, npc in ipairs(self.displayedNpcs) do
        DebugError(GetComponentData(npc, "typestring"))
    end
    ]]
    
    self.enabled = #self.npcs > 0
    self.namesKnown = IsInfoUnlockedForPlayer(menu.object, "operator_name")
    self.commandsKnown = IsInfoUnlockedForPlayer(menu.object, "operator_commands")
end
function catCrew:display(setup)
    self:addItem(setup, menu.rowClasses.personnel)
    for k, npc in pairs(self.displayedNpcs) do
        self:addItem(setup, menu.rowClasses.npc, npc)
    end
end
function catCrew:cleanup()
    self.npcs = nil
    self.displayedNpcs = nil
end

local catUpkeep = menu.registerCategory("upkeep")
catUpkeep.visible = true
catUpkeep.enabled = true
catUpkeep.extended = false
function catUpkeep:init()
    if menu.isPlayerShip or not menu.isPlayerOwned then
        self.visible = false
        return
    end
    
    self.missions = {}
    
    local textWidth = menu.getMultiColWidth(2, 6)
    
    local numMissions = GetNumMissions()
    for i = 1, numMissions do
        local id, name, description, difficulty, mainType, subType, faction, reward, rewardText, _, _, _, _, missionTime, _, abortable, disableGuidance, component = GetMissionDetails(i, Helper.standardFont, Helper.standardFontSize, textWidth)
        local objectiveText, objectiveIcon, timeout, progressName, curProgress, maxProgress = GetMissionObjective(i, Helper.standardFont, Helper.standardFontSize, textWidth)
        
        if mainType == "upkeep" then
            local container = GetContextByClass(component, "container", true)
            local buildAnchor = GetBuildAnchor(container)
            container = buildAnchor or container
            
            if IsSameComponent(container, menu.object) then
                table.insert(self.missions, {
                    active = i == activeMission,
                    name = name,
                    description = description,
                    difficulty = difficulty,
                    subType = subType,
                    faction = faction,
                    reward = reward,
                    rewardText = rewardText,
                    objectiveText = objectiveText,
                    objectiveIcon = objectiveIcon,
                    timeout = (timeout and timeout ~= -1) and timeout or (missionTime or -1),
                    progressName = progressName,
                    curProgress = curProgress,
                    maxProgress = maxProgress,
                    component = component,
                    disableGuidance = disableGuidance,
                    id = id,
                })
            end
        end
    end
    
    if #self.missions == 0 then
        self.visible = false
        return
    end
    
    self.visible = true
    self.header = ReadText(1001, 3305) .. ": " .. #self.missions
end
function catUpkeep:display(setup)
    for k, mission in ipairs(self.missions) do
        self:addItem(setup, menu.rowClasses.upkeepMission, mission)
    end
end
function catUpkeep:cleanup()
    self.missions = nil
end

local catProd = menu.registerCategory("production")
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
            self:addItem(setup, menu.rowClasses.production, v)
        end
    end
end
function catProd:cleanup()
    self.modules = nil
end

local catArms = menu.registerCategory("arms")
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
    
    if not menu.isPlayerShip then
        local numMissiles = C.GetNumAmmoStorage(ConvertIDTo64Bit(menu.object), "missile")
        local missiles = ffi.new("AmmoData[?]", numMissiles)
        numMissiles = C.GetAmmoStorage(missiles, numMissiles, ConvertIDTo64Bit(menu.object), "missile")
        
        self.ammo = {}
        for i = 0, numMissiles-1 do
            local ware = ffi.string(missiles[i].ware)
            local amount = missiles[i].amount
            self.ammo[ware] = {ware = ware, amount = amount}
        end
    end
end

function catArms:init()
    if not IsComponentClass(menu.object, "defensible") then
        self.visible = false
        return
    end
    
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
    self.ammoRows = {}
    if not menu.isPlayerShip then
        for ut, upgrade in Helper.orderedPairs(self.upgrades) do
            if type(upgrade) == "table" and upgrade.total > 0 then
                self.upgradeRows[ut] = self:addItem(setup, menu.rowClasses.upgrade, upgrade, self.estimated)
            end
        end
        for macro, turret in pairs(self.fixedTurrets) do
            if type(turret) == "table" and turret.operational > 0 then
                self.fixedTurretRows[macro] = self:addItem(setup, menu.rowClasses.upgrade, turret, self.fixedTurrets.estimated)
            end
        end
    end
    for k, weapon in ipairs(self.armament.weapons) do
        local ffiMod = ffi.new("UIWeaponMod")
        local retVal = C.GetInstalledWeaponMod(ConvertIDTo64Bit(weapon.component), ffiMod)
        if not retVal then
            ffiMod = nil
        end
        self:addItem(setup, menu.rowClasses.weapon, weapon, ffiMod)
        AddKnownItem("weapontypes_primary", weapon.macro)
    end
    for k, missile in ipairs(self.armament.missiles) do
        self:addItem(setup, menu.rowClasses.missile, missile)
        AddKnownItem("weapontypes_secondary", missile.macro)
    end
    if not menu.isPlayerShip then
        for ware, ammo in pairs(self.ammo) do
            self.ammoRows[ware] = self:addItem(setup, menu.rowClasses.ammo, ammo)
        end
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
    for ware, row in pairs(self.ammoRows) do
        if self.ammo[ware] then
            row:updateVal(self.ammo[ware])
        end
    end
end
function catArms:cleanup()
    self.upgrades = nil
    self.fixedTurrets = nil
    self.armament = nil
    self.ammo = nil
    
    self.upgradeRows = nil
    self.fixedTurretRows = nil
    self.ammoRows = nil
end

local catShoppingList = menu.registerCategory("shoppingList")
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
        self:addItem(setup, menu.rowClasses.shoppingList, item, k)
    end
end
function catShoppingList:getDetailButtonProps()
    local text = ReadText(1001, 73)
    local enabled = self.enabled
    return text, enabled
end
function catShoppingList:onDetailButtonPress()
    ClearTradeQueue(menu.object)
    menu.setDelayedRefresh(0.2)
end
function catShoppingList:cleanup()
    self.shoppingList = nil
end

local catUnits = menu.registerCategory("units")
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
    local unitTotal = self.units.stored
    local unitCapacity = self.units.capacity
    
    local playerDroneTotal = 0
    if menu.isPlayerShip then
        local rawDrones = GetPlayerDroneStorageData()
        unitCapacity = unitCapacity + GetPlayerDroneSlots()
        
        self.playerDrones = {}
        for k, rawDrone in pairs(rawDrones) do
            if type(k) ~= "string" then
            
                local found = false
                for l, drone in ipairs(self.playerDrones) do
                    if drone.macro == rawDrone.macro then
                        found = true
                        drone.amount = drone.amount + rawDrone.amount + 1
                        break
                    end
                end
                if not found then
                    rawDrone.amount = rawDrone.amount + 1
                    table.insert(self.playerDrones, rawDrone)
                end
                
            end
        end
        
        for k, drone in ipairs(self.playerDrones) do
            playerDroneTotal = playerDroneTotal + drone.amount
        end
        
    end
    unitTotal = unitTotal + playerDroneTotal
    
    if unitTotal <= 0 then
        self.visible = false
        return
    end
    self:aggregate()
    
    local hasUnits = playerDroneTotal > 0
    
    if not hasUnits then
        for k, unit in ipairs(self.units) do
            if unit.amount > 0 then
                hasUnits = true
                break
            end
        end
    end
    
    if not hasUnits then
        self.visible = false
        return
    end
    
    self.visible = true
    
    local mainHeader = ReadText(1001, 22) .. "\27Z -- \27X" .. Helper.unlockInfo(self.amountKnown, unitTotal) .. "\27Z / \27X" .. Helper.unlockInfo(self.capacityKnown, unitCapacity)
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
function catUnits:aggregate()
    self.unitsByMacro = {}
    for k, unit in ipairs(self.units) do
        self.unitsByMacro[unit.macro] = unit
    end
end
function catUnits:display(setup)
    self.unitRows = {}
    for k, unit in ipairs(self.units) do
        if unit.amount > 0 then
            if IsMacroClass(unit.macro, "npc") then
                AddKnownItem("marines", unit.macro)
            else
                AddKnownItem("shiptypes_xs", unit.macro)
            end
            table.insert(self.unitRows, self:addItem(setup, menu.rowClasses.unit, unit))
        end
    end
    if menu.isPlayerShip then
        local separatorAdded = false
        for k, drone in ipairs(self.playerDrones) do
            if not separatorAdded then
                setup:addRow(false, {Helper.createFontString("", false, nil, nil, nil, nil, nil, nil, 6, nil, nil, nil, 6)}, nil, {#menu.selectColWidths}, false, Helper.defaultHeaderBackgroundColor)
                separatorAdded = true
            end
            self:addItem(setup, menu.rowClasses.playerDrone, drone)
        end
    end
end
catUnits.updateInterval = 3
function catUnits:update()
    if #self.unitRows == 0 then return end
    
    self.units = GetUnitStorageData(menu.object)
    self:aggregate()
    for k, row in ipairs(self.unitRows) do
        local newUnit = self.unitsByMacro[row.unit.macro]
        if newUnit then
            row:updateUnit(newUnit)
        else
            DebugError("No unit with that macro")
        end
    end
end
function catUnits:cleanup()
    self.units = nil
    self.unitsByMacro = nil
end

local catPlayerUpgrades = menu.registerCategory("playerUpgrades")
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
                self:addItem(setup, menu.rowClasses.playerUpgrade, upgrade, factor)
                AddKnownItem("wares", upgrade.ware)
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
function catPlayerUpgrades:cleanup()
    self.upgradesByCat = nil
end

local catSubordinates = menu.registerCategory("subordinates")
catSubordinates.visible = true
catSubordinates.enabled = true
catSubordinates.extended = true
function catSubordinates:init()
    self.visible = (menu.type == "station" or menu.type == "ship") and IsInfoUnlockedForPlayer(menu.object, "managed_ships")
    if not self.visible then return end
    
    self.ships = GetSubordinates(menu.object)
    for i = #self.ships, 1, -1 do
        if GetBuildAnchor(self.ships[i]) then
            table.remove(self.ships, i)
        elseif IsComponentClass(self.ships[i], "drone") then
            table.remove(self.ships, i)
        end
    end
    
    if #self.ships == 0 then
        self.visible = false
        return
    end
    
    for k, ship in pairs(self.ships) do
        if IsComponentClass(ship, "station") then
            AddKnownItem("stationtypes", GetComponentData(ship, "macro"))
        elseif IsComponentClass(ship, "ship_xl") then
            AddKnownItem("shiptypes_xl", GetComponentData(ship, "macro"))
        elseif IsComponentClass(ship, "ship_l") then
            AddKnownItem("shiptypes_l", GetComponentData(ship, "macro"))
        elseif IsComponentClass(ship, "ship_m") then
            AddKnownItem("shiptypes_m", GetComponentData(ship, "macro"))
        elseif IsComponentClass(ship, "ship_s") then
            AddKnownItem("shiptypes_s", GetComponentData(ship, "macro"))
        elseif IsComponentClass(ship, "ship_xs") then
            AddKnownItem("shiptypes_xs", GetComponentData(ship, "macro"))
        end
    end
    
    self.header = #self.ships .. " " .. (#self.ships == 1 and ReadText(1001, 5) or ReadText(1001, 6))
end
function catSubordinates:display(setup)
    for k, ship in pairs(self.ships) do
        self:addItem(setup, menu.rowClasses.subordinate, ship)
    end
end
function catSubordinates:cleanup()
    self.ships = nil
end

local catBuildModules = menu.registerCategory("buildModules")
catBuildModules.visible = true
catBuildModules.enabled = true
catBuildModules.extended = true
catBuildModules.header = ReadText(1001, 2439)
function catBuildModules:scanBuildStage(sequence, stage)
    local seqModules = GetBuildStageModules(menu.object, sequence, stage)
    for k, moduleData in ipairs(seqModules) do
        if moduleData.library == "moduletypes_build" and moduleData.component and IsComponentOperational(moduleData.component) then
            DebugError("Here is a build module called " .. GetComponentData(moduleData.component, "name") .. "! (" .. tostring(moduleData.component) .. ")")
            table.insert(self.modules, moduleData.component)
        end
    end
end
function catBuildModules:init()
    self.visible = menu.type == "station"
    if not self.visible then return end
    
    self.modules = {}
    
    self:scanBuildStage("", 0)
    
    local buildTree = GetBuildTree(menu.object)
    for k, sequence in ipairs(buildTree) do
        for stage = 1, sequence.currentstage do
            self:scanBuildStage(sequence.sequence, stage)
        end
    end
    
    if #self.modules == 0 then
        self.visible = false
        return
    end
end
function catBuildModules:display(setup)
    for k, module in ipairs(self.modules) do
        self:addItem(setup, menu.rowClasses.buildModule, module)
    end
end
function catBuildModules:cleanup()
    self.modules = nil
end
    
--end of categories
--===================================================================

menu.baseItemLib = {}

menu.rowClasses = {}

function menu.registerRowClass(name)
    local rc = {}
    setmetatable(rc, {__index = menu.baseItemLib})
    menu.rowClasses[name] = rc
    rc.metaTable = {__index = rc}
    rc.className = name
    
    return rc
end

menu.categoryScheme = {
    left = {
        menu.categories.general,
        menu.categories.crew,
        menu.categories.subordinates
    },
    right = {
        menu.categories.upkeep,
        menu.categories.buildModules,
        menu.categories.production,
        menu.categories.shoppingList,
        menu.categories.cargo,
        menu.categories.units,
        menu.categories.playerUpgrades,
        menu.categories.arms
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
    
    cat.headerRow = setup:addSimpleRow(cells, rowData, colSpans, nil, Helper.defaultHeaderBackgroundColor)
    
    if isExtended then
        cat:display(setup)
    end
end

local function setupColWidths()
    local colFracs = {1/3, 1/6, 1/6, 1/12, 1/4}
    local colWidths = {Helper.standardButtonWidth}
    
    local fullWidth = menu.lowResMode and (Helper.standardSizeX/2 - 11) or (Helper.standardSizeX/2)
    
    local totalWidth = GetUsableTableWidth(fullWidth - Helper.standardButtonWidth, 0, #colFracs, true)
    
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
    
    menu.selectTableHeight = Helper.standardSizeY - 30
    menu.lowResMode = (not Helper.largePDA) and GetFullscreenDetailmonitorOption()
    
    if not menu.lowResMode then
        Helper.standardFontSize = 11
        Helper.standardTextHeight = 18
    end
    
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

local function checkTradeOffers()
    local tradeOffers = GetComponentData(menu.object, "tradeoffers") or {}
    local switch
    local hasSellOffers, hasBuyOffers
    for _, tradeid in ipairs(tradeOffers) do
        local tradedata = GetTradeData(tradeid)
        if tradedata.isbuyoffer then
            hasBuyOffers = true
            if hasSellOffers then
                break
            end
        elseif tradedata.isselloffer then
            hasSellOffers = true
            if hasBuyOffers then
                break
            end
        end
    end
    if hasSellOffers and (not hasBuyOffers) then
        switch = true
    elseif (not hasSellOffers) and hasBuyOffers then
        switch = false
    end
    
    return switch, #tradeOffers > 0
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
        Helper.createFontString(menu.statusMessage, false, "left", menu.statusMsgColor.r, menu.statusMsgColor.g, menu.statusMsgColor.b, menu.statusMsgColor.a, Helper.headerRow2Font, Helper.headerRow2FontSize)
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
    
    local selectRightDesc = setup:createCustomWidthTable(clone(menu.selectColWidths), false, false, true, tabRight, 0, (Helper.standardSizeX/2), 0, menu.selectTableHeight, true, topRowRight, curRowRight)
    
    local rowDataRight = clone(menu.rowDataMap)
    menu.rowDataMap = {}

    --table for ABXY buttons
    --=========================================
    
    setup = Helper.createTableSetup(menu)
    
    local tradeButtonSwitch, tradeButtonEnabled = checkTradeOffers()
    menu.tradeButtonSellBuySwitch = tradeButtonSwitch
    
    setup:addSimpleRow({ 
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 2669), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, true, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_B", true)),
        Helper.getEmptyCellDescriptor(),
        Helper.createButton(Helper.createButtonText(ReadText(1001, 1113), "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, tradeButtonEnabled, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_BACK", true)),
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
    Helper.setButtonScript(menu, nil, menu.selectTableLeft, 1, 1, menu.buttonEncyclopedia)
    
    iterateSelectRows(function(row, tab, rowData)
        if not rowData then return end
        if rowData.kind == "catheader" then
            local category = rowData.category
            category.tab = tab
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

function menu.buttonEncyclopedia()
    if not menu.closeIfDead() then return end
    Helper.closeMenuForSubSection(menu, false, "gEncyclopedia_object", { 0, 0, menu.category, GetComponentData(menu.object, "macro"), menu.category == "stationtypes" })
end

function menu.tradeOffers()
    if not menu.closeIfDead() then return end
    Helper.closeMenuForSubSection(menu, false, "gTrade_offerselect", { 0, 0, menu.tradeButtonSellBuySwitch, nil, nil, menu.object })
end

function menu.plotCourse()
    if not menu.closeIfDead() then return end
    Helper.closeMenuForSection(menu, false, "gMainNav_select_plotcourse", {menu.object, menu.type, IsSameComponent(GetActiveGuidanceMissionComponent(), menu.object)})
end

function menu.refreshDetailButton(rowData)
    if not rowData then
        rowData = menu.rowDataColumns[menu.currentColumn][Helper.currentTableRow[menu.currentColumn]]
    end
    
    local text = "--"
    local enabled = false
    
    local obj
    if rowData then
        if rowData.kind == "regular" then
            obj = rowData
        elseif rowData.kind == "catheader" then
            obj = rowData.category
        end
    end
    
    if obj and obj.getDetailButtonProps then
        text, enabled = obj:getDetailButtonProps()
        text = TruncateText(text, Helper.standardFont, Helper.standardFontSize, menu.buttonTableButtonWidth)
    end
    
    if not menu.nowDisplaying then
        Helper.removeButtonScripts(menu, menu.buttonTable, 1, 8)
    end
    
    local button = Helper.createButton(Helper.createButtonText(text, "center", Helper.standardFont, 11, 255, 255, 255, 100), nil, false, enabled, 0, 0, 150, 25, nil, Helper.createButtonHotkey("INPUT_STATE_DETAILMONITOR_X", true))
    SetCellContent(menu.buttonTable, button, 1, 8)
    
    if enabled then
        Helper.setButtonScript(menu, nil, menu.buttonTable, 1, 8, function()
            if IsComponentOperational(menu.object) then
                obj:onDetailButtonPress()
            end
        end)
    end
end

menu.updateInterval = 0.1
function menu.onUpdate()
    if menu.nowDisplaying then
        DebugError("Error detected while displaying Improved Object Menu!")
        menu.updateInterval = 3600
        return
    end
    
    if not menu.closeIfDead() then return end
    
    local timeNow = C.GetCurrentGameTime()
    
    if menu.nextRefreshTime and menu.nextRefreshTime < timeNow then
        DebugError("Delayed refresh has now triggered!")
        menu.nextRefreshTime = nil
        menu.displayMenu()
        return
    end
    
    for k, v in pairs(menu.categories) do
        if v.updateInterval and v.update and v.visible then
            local nextUpd = v.nextUpdate or 0
            if timeNow > nextUpd then
                v.nextUpdate = timeNow + v.updateInterval
                v:update()
            end
        end
    end
    
    iterateSelectRows(function(row, tab, rowData)
        if not rowData or rowData.kind ~= "regular" then return end
        
        if rowData.updateInterval and rowData.update then
            local nextUpd = rowData.nextUpdate or 0
            if timeNow > nextUpd then
                rowData.nextUpdate = timeNow + rowData.updateInterval
                rowData:update(tab, row)
            end
        end
    end)
end

function menu.onHotkey(action)
    if not IsComponentOperational(menu.object) then return end
    
    if action == "INPUT_ACTION_ADDON_DETAILMONITOR_C" then
        if not (menu.type == "station" or menu.type == "ship") then return end
        if not GetComponentData(menu.object, "caninitiatecomm") then return end
        
        local rowData = menu.rowDataColumns[menu.currentColumn][Helper.currentTableRow[menu.currentColumn]]
        
        if rowData and rowData.kind == "regular" and rowData.className == "npc" then
            Helper.closeMenuForSubConversation(menu, false, "default", rowData.npc, menu.object, (not Helper.useFullscreenDetailmonitor()) and "facecopilot" or nil)
            
        else
            local entities = Helper.getSuitableControlEntities(menu.object, true)
            if #entities == 1 then
                Helper.closeMenuForSubConversation(menu, false, "default", entities[1], menu.object, (not Helper.useFullscreenDetailmonitor()) and "facecopilot" or nil)
            else
                Helper.closeMenuForSubSection(menu, false, "gMain_propertyResult", menu.object)
            end
        end
        
    end
end

function menu.updateStatusMessage(msg)
    local tab = menu.currentColumn
    
    msg = msg or "Table = " .. menu.tableNames[tab] .. ", Row = " .. Helper.currentTableRow[tab]
    
    menu.statusMessage = msg
    Helper.updateCellText(menu.selectTableLeft, 2, 1, menu.statusMessage)
end

local function kludgeSetInteractive(tab)
    while GetInteractiveObject(menu.frame) ~= tab do
        SwitchInteractiveObject(menu.frame)
    end
end

function menu.onTableMouseOver(tab, row)
    if tab == menu.selectTableLeft or tab == menu.selectTableRight then
        kludgeSetInteractive(tab)
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
    local rowData = menu.rowDataColumns[tab][row]
    
    menu.updateStatusMessage()
    menu.refreshDetailButton(rowData)
end

function menu.setDelayedRefresh(delay)
    if not menu.nextRefreshTime then
        menu.nextRefreshTime = C.GetCurrentGameTime()+delay;
    else
        menu.nextRefreshTime = math.max(menu.nextRefreshTime, C.GetCurrentGameTime()+delay);
    end
    DebugError("Delayed refresh time set at " .. menu.nextRefreshTime)
end

function menu.cleanup()
    UnregisterAddonBindings("ego_detailmonitor")
    
    for k, cat in pairs(menu.categories) do
        cat.rows = nil
        cat.tab = nil
        cat.headerRow = nil
        if cat.cleanup then
            cat:cleanup()
        end
    end
    
    Helper.standardFontSize = 14
    Helper.standardTextHeight = 24
    
    menu.selectColWidths = nil
    menu.unlocked = nil
    menu.playerShip = nil
    menu.isPlayerShip = nil
    menu.isPlayerOwned = nil
    menu.type = nil
    menu.title = nil
    menu.container = nil
    menu.isBigShip = nil
    menu.buildingModule = nil
    menu.buildingContainer = nil
    menu.buildingArchitect = nil
    menu.category = nil
    menu.holomapColor = nil
    menu.buttonTableSpacerWidth = nil
    menu.buttonTableButtonWidth = nil
    menu.statusMessage = nil
    menu.nextRows = nil
    menu.tableNames = nil
    menu.namedTables = nil
    menu.rowDataColumns = nil
    menu.objNameColor = nil
    menu.tradeButtonSellBuySwitch = nil
    menu.selectTableHeight = nil
    menu.lowResMode = nil
    menu.nextRefreshTime = nil
end

init()