local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
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
    UniverseID GetPlayerID(void);
]]

local menu
for k, otherMenu in pairs(Menus) do
    if otherMenu.name == "MeJ_ImprovedObjectMenu" then
        menu = otherMenu
        break
    end
end
if not menu then
    error("Category file: couldn't find the proper menu to inject into!")
end

menu.data.crew = {}
menu.data.crew.typeOrdering = {
    manager = 1,
    commander = 2,
    pilot = 3,
    engineer = 4,
    defencecontrol = 5,
    architect = 6
}
function menu.data.crew:init()
    self.namesKnown = IsInfoUnlockedForPlayer(menu.object, "operator_name")
    self.commandsKnown = IsInfoUnlockedForPlayer(menu.object, "operator_commands")
    
    self.npcs = GetNPCs(menu.object)
    
    self.displayedNpcs = {}
    for k, npc in pairs(self.npcs) do
        local isControlEntity, isPlayer, typeString, typeName, name = GetComponentData(npc, "iscontrolentity", "isplayerowned", "typestring", "typename", "name")
        if isControlEntity or (menu.isPlayerOwned and isPlayer) then
            local fullName = typeName .. " " .. name
            table.insert(self.displayedNpcs, {npc = npc, isControlEntity = isControlEntity, isPlayer = isPlayer, typeString = typeString, fullName = fullName})
        end
    end
    if menu.buildingArchitect then
        local name, typeName = GetComponentData(menu.buildingArchitect, "name", "typename")
        local fullName = typeName .. " " .. name
        table.insert(self.displayedNpcs, {npc = menu.buildingArchitect, isControlEntity = true, isPlayer = true, typeString = "architect", fullName = fullName})
    end
    
    table.sort(self.displayedNpcs, function(a, b)
        local aControl, bControl = a.isControlEntity, b.isControlEntity
        
        --npcs that are control entities go first
        if aControl ~= bControl then
            return aControl
        end
        
        local aType, bType = a.typeString, b.typeString
        local aIndex, bIndex = self.typeOrdering[aType], self.typeOrdering[bType]
        
        --if both types are sorted, put them in that order
        if aIndex and bIndex then
            return aIndex < bIndex
        end
        
        --if only one type is sorted, the npc with the sorted type goes first
        if aIndex and not bIndex then return true end
        if bIndex and not aIndex then return false end
        
        --if neither types are sorted, sort the types in alphabetical order
        return aType < bType
    end)
end
function menu.data.crew:cleanup()
    self.npcs = nil
    self.displayedNpcs = nil
    self.namesKnown = nil
    self.commandsKnown = nil
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
function catCrew:init()
    self.visible = menu.type ~= "block" and not menu.isPlayerShip
    if not self.visible then return end
    
    self.npcs = menu.data.crew.npcs
    self.displayedNpcs = menu.data.crew.displayedNpcs
    
    --[[
    for k, npc in ipairs(self.displayedNpcs) do
        DebugError(GetComponentData(npc, "typestring"))
    end
    ]]
    
    self.enabled = #self.npcs > 0
    self.namesKnown = menu.data.crew.namesKnown
    self.commandsKnown = menu.data.crew.commandsKnown
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
    self.namesKnown = nil
    self.commandsKnown = nil
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
    
    local totalShips = 0
    
    self.shipsByEntity = {}
    
    if menu.isPlayerShip then
        local playerSquad = GetSubordinates(menu.object)
        for i = #playerSquad, 1, -1 do
            if GetBuildAnchor(playerSquad[i]) then
                table.remove(playerSquad, i)
            elseif IsComponentClass(playerSquad[i], "drone") then
                table.remove(playerSquad, i)
            end
        end
        totalShips = #playerSquad
        self.playerSquad = playerSquad
    else
        self.shipsByEntity = {}
        for k, npcData in ipairs(menu.data.crew.displayedNpcs) do
            if npcData.isControlEntity then
                local entityShips = GetSubordinates(menu.object, npcData.typeString)
                for i = #entityShips, 1, -1 do
                    if GetBuildAnchor(entityShips[i]) then
                        table.remove(entityShips, i)
                    elseif IsComponentClass(entityShips[i], "drone") then
                        table.remove(entityShips, i)
                    end
                end
                if #entityShips > 0 then
                    table.insert(self.shipsByEntity, {entData = npcData, ships = entityShips})
                    totalShips = totalShips + #entityShips
                end
            end
        end
    end
    
    if totalShips == 0 then
        self.visible = false
        return
    end
    
    self.header = totalShips .. " " .. (totalShips == 1 and ReadText(1001, 5) or ReadText(1001, 6))
end
function catSubordinates:display(setup)
    if menu.isPlayerShip then
        for k, ship in pairs(self.playerSquad) do
            self:addItem(setup, menu.rowClasses.subordinate, ship)
        end
    else
        for k, entry in pairs(self.shipsByEntity) do
            setup:addHeaderRow({"", Helper.unlockInfo(menu.data.crew.namesKnown, entry.entData.fullName)}, nil, {1, #menu.selectColWidths-1})
            
            for k, ship in pairs(entry.ships) do
                self:addItem(setup, menu.rowClasses.subordinate, ship)
                
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
        end
    end
end
function catSubordinates:cleanup()
    self.playerSquad = nil
    self.shipsByEntity = nil
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

table.insert(menu.categoryScheme.left, menu.categories.general)
table.insert(menu.categoryScheme.left, menu.categories.crew)
table.insert(menu.categoryScheme.left, menu.categories.subordinates)

table.insert(menu.categoryScheme.right, menu.categories.upkeep)
table.insert(menu.categoryScheme.right, menu.categories.buildModules)
table.insert(menu.categoryScheme.right, menu.categories.production)
table.insert(menu.categoryScheme.right, menu.categories.shoppingList)
table.insert(menu.categoryScheme.right, menu.categories.cargo)
table.insert(menu.categoryScheme.right, menu.categories.units)
table.insert(menu.categoryScheme.right, menu.categories.playerUpgrades)
table.insert(menu.categoryScheme.right, menu.categories.arms)