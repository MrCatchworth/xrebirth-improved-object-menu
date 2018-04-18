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
    data = {}
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
    },
    right = {
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
    
    --attempt to replace vanilla ObjectMenu
    --[[
    local objectMenu
    for k, otherMenu in pairs(Menus) do
        if otherMenu.name == "ObjectMenu" then
            objectMenu = otherMenu
            break
        end
    end
    if objectMenu then
        Helper.unregisterMenu(objectMenu)
        RegisterEvent("showObjectMenu", menu.showMenuCallback)
        RegisterEvent("showNonInteractiveObjectMenu", menu.showNonInteractiveMenuCallback)
    else
        error("Improved Object Menu: Failed to find vanilla ObjectMenu to replace!")
    end
    ]]
    
    --spoof register ourselves as the vanilla object menu
    RegisterEvent("showObjectMenu", menu.showMenuCallback)
    RegisterEvent("showNonInteractiveObjectMenu", menu.showNonInteractiveMenuCallback)
    
    --somewhat strange hack to override other mods (e.g. xsalvation) that also register themselves for the object menu
    --i have to do it in an update handler because that menu might be loaded after this one
    SetScript("onUpdate", scrubObjectMenus)
end

function scrubObjectMenus()
    DebugError("Starting to scrub object menus")
    
    for k, otherMenu in pairs(Menus) do
        if otherMenu.name == "ObjectMenu" then
            DebugError("Scrubbing an object menu...")
            Helper.unregisterMenu(otherMenu)
        end
    end
    
    DebugError("Done scrubbing")
    RemoveScript("onUpdate", scrubObjectMenus)
end

function menu.onShowMenu()
	menu.object = menu.param[3]
	menu.category = ""
	menu.unlocked = {}
	menu.playerShip = GetPlayerPrimaryShipID()
	menu.isPlayerShip = IsSameComponent(menu.object, menu.playerShip)
	menu.isPlayerOwned, menu.primaryPurpose = GetComponentData(menu.object, "isplayerowned", "primarypurpose")
    menu.objectClass = ffi.string(C.GetComponentClass(ConvertIDTo64Bit(menu.object)))
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
    
    menu.statusMessage = menu.statusMessage or ReadText(1001, 14)
    
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
    
    for k, datum in pairs(menu.data) do
        datum:init()
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
    
    local titleFontSize
    local titleTextHeight
    if menu.lowResMode then
        titleFontSize = 16
    else
        titleFontSize = 16
    end
    
    local setup = Helper.createTableSetup(menu)
    setup:addSimpleRow({
        Helper.createButton(nil, Helper.createButtonIcon("menu_info", nil, 255, 255, 255, 100), false),
        Helper.createFontString(menu.title, false, "left", titleColor.r, titleColor.g, titleColor.b, titleColor.a, Helper.headerRow1Font, titleFontSize, false, Helper.headerRow1Offsetx, Helper.headerRow1Offsety, Helper.headerRow1Height)
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
        DebugError("Error detected while displaying Improved Object Menu! Please contact MegaJohnny with the relevant error messages")
        menu.updateInterval = 3600
        return
    end
    
    if not menu.closeIfDead() then return end
    
    local timeNow = C.GetCurrentGameTime()
    
    if menu.nextRefreshTime and menu.nextRefreshTime < timeNow then
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
    if tab ~= menu.lastTableMoused then
        if tab == menu.selectTableLeft or tab == menu.selectTableRight then
            kludgeSetInteractive(tab)
            menu.interactiveElementChanged(nil, tab)
        end
    end
    menu.lastTableMoused = tab
end

menu.ignoreRowChange = 0
function menu.onRowChanged(row, rowData, tab)
    if menu.ignoreRowChange > 0 then
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
	else
        if menu.param[4] and IsValidComponent(menu.object) then
            Helper.closeMenuAndReturn(menu, false, { nil, 0, "zone", GetContextByClass(menu.object, "zone"), menu.param[4], menu.object })
        else
            Helper.closeMenuAndReturn(menu)
        end
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
    
    -- menu.updateStatusMessage()
    menu.refreshDetailButton(rowData)
end

function menu.setDelayedRefresh(delay)
    if not menu.nextRefreshTime then
        menu.nextRefreshTime = C.GetCurrentGameTime()+delay;
    else
        menu.nextRefreshTime = math.max(menu.nextRefreshTime, C.GetCurrentGameTime()+delay);
    end
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
    
    for k, datum in pairs(menu.data) do
        datum:cleanup()
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
    menu.lastTableMoused = nil
end

init()