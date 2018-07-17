local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")
local Debug = ns.Debug

local HBD = LibStub("HereBeDragons-2.0")
local HBDPins = LibStub("HereBeDragons-Pins-2.0")

ns.defaults = {
	iconScale = 0.7,
	arrowScale = 0.7,
	iconAlpha = 1,
	arrowAlpha = 1,
	watchedOnly = false,
	useArrows = false,
	fadeEdge = true,
	autoTomTom = false,
	worldQuest = true,
}
ns.defaultsPC = {}

ns:RegisterEvent("ADDON_LOADED")
function ns:ADDON_LOADED(event, addon)
	if addon ~= myname then return end
	self:InitDB()

	self:RegisterEvent("QUEST_POI_UPDATE")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("SUPER_TRACKED_QUEST_CHANGED")
	self:RegisterEvent("QUEST_WATCH_LIST_CHANGED")

	local update = function() self:UpdatePOIs() end
	hooksecurefunc("AddQuestWatch", update)
	hooksecurefunc("RemoveQuestWatch", update)

	LibStub("tekKonfig-AboutPanel").new(myfullname, myname) -- Make first arg nil if no parent config panel

	ns.poi_parent = CreateFrame("Frame")
	QuestPOI_Initialize(ns.poi_parent)

	self:UnregisterEvent("ADDON_LOADED")
	self.ADDON_LOADED = nil

	if IsLoggedIn() then self:PLAYER_LOGIN() else self:RegisterEvent("PLAYER_LOGIN") end
end

function ns:PLAYER_LOGIN()
	self:RegisterEvent("PLAYER_LOGOUT")

	-- Do anything you need to do after the player has entered the world

	self:UpdatePOIs()
	if ns.AutoTomTom then
		Debug("Calling AutoTomTom")
		ns:AutoTomTom()
	end

	self:UnregisterEvent("PLAYER_LOGIN")
	self.PLAYER_LOGIN = nil
end

function ns:PLAYER_LOGOUT()
	self:FlushDB()
	-- Do anything you need to do as the player logs out
end

local pois = {}
local POI_OnEnter, POI_OnLeave, POI_OnMouseUp, Arrow_OnUpdate

ns.pois = pois

function ns:ClosestPOI(all)
	local closest, closest_distance, poi_distance, _
	for id, poi in pairs(ns.pois) do
		if poi.active then
			_, poi_distance = HBDPins:GetVectorToIcon(poi)
			
			if closest then
				if poi_distance and closest_distance and poi_distance < closest_distance then
					closest = poi
					closest_distance = poi_distance
				end
			else
				closest = poi
				closest_distance = poi_distance
			end
		end
	end
	return closest
end

function ns:UpdatePOIs(...)
	self.Debug("UpdatePOIs", ...)

	local x, y, mapid, maptype = HBD:GetPlayerZonePosition()
	if not (mapid and x and y) then
		-- Means that this was probably a change triggered by the world map being
		-- opened and browsed around. Since this is the case, we won't update any POIs for now.
		self.Debug("Skipped UpdatePOIs because of no player position")
		return
	end
	if WorldMapFrame:IsVisible() then
		-- TODO: handle microdungeons
		self.Debug("Skipped UpdatePOIs because map is open and not viewing current zone")
		return
	end

	for id, poi in pairs(pois) do
		self:ResetPOI(poi)
	end

	self:UpdateLogPOIs(mapid, floor)
	self:UpdateWorldPOIs(mapid, floor)

	self:UpdateEdges()
	self:UpdateGlow()
end
ns.QUEST_POI_UPDATE = ns.UpdatePOIs
ns.QUEST_LOG_UPDATE = ns.UpdatePOIs
ns.ZONE_CHANGED_NEW_AREA = ns.UpdatePOIs
ns.PLAYER_ENTERING_WORLD = ns.UpdatePOIs
ns.QUEST_WATCH_LIST_CHANGED = ns.UpdatePOIs

function ns:UpdateLogPOIs(mapid, floor)
	local cvar = GetCVarBool("questPOI")
	SetCVar("questPOI", 1)
	-- Interestingly, even if this isn't called, *some* POIs will show up. Not sure why.
	QuestPOIUpdateIcons()

	local numNumericQuests = 0
	local numCompletedQuests = 0
	local numEntries = QuestMapUpdateAllQuests()
	Debug("Quests on map", numEntries)
	for i=1, numEntries do
		local questId, questLogIndex = QuestPOIGetQuestIDByVisibleIndex(i)
		Debug("Quest", questId, questLogIndex)
		if questId then
			local _, posX, posY, objective = QuestPOIGetIconInfo(questId)
			local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questId, startEvent, displayQuestId, isOnMap, hasLocalPOI, isTask, isBounty, isStory = GetQuestLogTitle(questLogIndex)
			-- IsQuestComplete seems to test for "is quest in a turnable-in state?", distinct from IsQuestFlaggedCompleted...
			isComplete = IsQuestComplete(questId)
			if not isTask then
				self.Debug("Skipped POI", i, posX, posY)
				if IsQuestComplete(questId) then
					numCompletedQuests = numCompletedQuests + 1
				else
					numNumericQuests = numNumericQuests + 1
				end
			end
			if hasLocalPOI and posX and posY and (not self.db.watchedOnly or IsQuestWatched(questLogIndex)) and not isTask then
				self.Debug("POI", questId, posX, posY, objective, title, hasLocalPOI, isTask)

				local poiButton
				if isComplete then
					self.Debug("Making with complete", i)
					poiButton = QuestPOI_GetButton(ns.poi_parent, questId, hasLocalPOI and 'normal' or 'remote', numCompletedQuests)
				else
					self.Debug("Making with numeric", i - numCompletedQuests)
					poiButton = QuestPOI_GetButton(ns.poi_parent, questId, hasLocalPOI and 'numeric' or 'remote', numNumericQuests)
				end

				local poi = self:GetPOI('QPL' .. i, poiButton)

				poi.index = i
				poi.questId = questId
				poi.title = title
				poi.m = mapid
				poi.x = posX
				poi.y = posY
				poi.active = true
				poi.complete = isComplete

				HBDPins:AddMinimapIconMap(self, poi, mapid, posX, posY, false, true)
			end
		end
	end

	SetCVar("questPOI", cvar and 1 or 0)
end

function ns:UpdateWorldPOIs(mapid, floor)
	if not ns.db.worldQuest then
		return
	end
	local taskInfo = C_TaskQuest.GetQuestsForPlayerByMapID(mapid)
	if taskInfo == nil or #taskInfo == 0 then
		return
	end
	local numTaskPOIs = #taskInfo
	local taskIconIndex = 0
	for i, info  in ipairs(taskInfo) do
		if HaveQuestData(info.questId) and QuestUtils_IsQuestWorldQuest(info.questId) and (not ns.db.watchedOnly or self:WorldQuestIsWatched(info.questId)) then
			local id = 'QPWQ' .. taskIconIndex
			local poiButton = WorldMap_TryCreatingWorldQuestPOI(info, id)

			if poiButton then
				local poi = self:GetPOI(id, poiButton)
				poiButton.questID = info.questId
				poiButton.numObjectives = info.numObjectives

				taskIconIndex = taskIconIndex + 1

				poi.index = i
				poi.questId = info.questId
				poi.title = C_TaskQuest.GetQuestInfoByQuestID(info.questId)
				poi.m = mapid
				poi.x = info.x
				poi.y = info.y
				poi.active = true
				poi.worldquest = true
				poi.complete = false -- world quests vanish when complete, so...

				HBDPins:AddMinimapIconMF(self, poi, mapid, info.x, info.y, false, true)
			end
		end
	end
end

function ns:WorldQuestIsWatched(questId)
	if IsWorldQuestWatched(questId) or IsWorldQuestHardWatched(questId) then
		return true
	end
	-- tasks we're currently in the area of count as "watched" for our purposes
	local tasks = GetTasksTable()
	for i, taskId in ipairs(tasks) do
		if taskId == questId then
			return true
		end
	end
	return false
end

function ns:GetPOI(id, button)
	local poi = pois[id]
	if not poi then
		poi = CreateFrame("Frame", "QuestPointerPOI" .. id, Minimap)
		poi:SetWidth(10)
		poi:SetHeight(10)
		poi:SetScript("OnEnter", POI_OnEnter)
		poi:SetScript("OnLeave", POI_OnLeave)
		poi:SetScript("OnMouseUp", POI_OnMouseUp)
		poi:EnableMouse(true)

		local arrow = CreateFrame("Frame", nil, poi)
		arrow:SetPoint("CENTER", poi)
		arrow:SetScript("OnUpdate", Arrow_OnUpdate)
		arrow:SetWidth(32)
		arrow:SetHeight(32)

		local arrowtexture = arrow:CreateTexture(nil, "OVERLAY")
		arrowtexture:SetTexture([[Interface\Minimap\ROTATING-MINIMAPGUIDEARROW.tga]])
		arrowtexture:SetAllPoints(arrow)
		arrow.texture = arrowtexture
		arrow.t = 0
		arrow.poi = poi
		arrow:Hide()

		poi.arrow = arrow

		pois[id] = poi
	end

	button:SetPoint("CENTER", poi)
	button:SetScale(self.db.iconScale)
	button:SetParent(poi)
	button:EnableMouse(false)
	poi.poiButton = button

	poi.arrow:SetScale(self.db.arrowScale)

	return poi
end
function ns:ResetPOI(poi)
	HBDPins:RemoveMinimapIcon(self, poi)
	if poi.poiButton then
		poi.poiButton:Hide()
		poi.poiButton:SetParent(Minimap)
		poi.poiButton = nil
	end
	poi.arrow:Hide()
	poi.active = false
end

do
	local selected
	function ns:UpdateGlow()
		selected = self:ClearSelection(selected)
		selected = self:SetSelection(self:ClosestPOI())
		if closest then
			selected = closest

			if closest.poiButton.poiParent then
				QuestPOI_SelectButton(closest.poiButton)
			else
				closest.poiButton.SelectedGlow:SetShown(true)
			end
		end
	end
	function ns:SetSelection(poi)
		if not poi then return end
		if poi.worldquest then
			local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(poi.questId)
			if rarity == LE_WORLD_QUEST_QUALITY_COMMON then
				-- this is cloning a bunch of ApplyStandardTexturesToPOI, which is local to WorldMapFrame.lua
				poi.poiButton:GetNormalTexture():SetTexCoord(0.500, 0.625, 0.375, 0.5)
				poi.poiButton:GetPushedTexture():SetTexCoord(0.375, 0.500, 0.375, 0.5)
			else
				poi.poiButton.SelectedGlow:SetShown(true)
			end
		else
			QuestPOI_SelectButton(poi.poiButton)
		end
		return poi
	end
	function ns:ClearSelection(poi)
		if (not poi) or (not poi.active) then return end
		if poi.worldquest then
			poi.poiButton.SelectedGlow:SetShown(false)
			local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(poi.questId)
			if rarity == LE_WORLD_QUEST_QUALITY_COMMON then
				poi.poiButton:GetNormalTexture():SetTexCoord(0.875, 1, 0.375, 0.5)
				poi.poiButton:GetPushedTexture():SetTexCoord(0.750, 0.875, 0.375, 0.5)
			end
		else
			QuestPOI_ClearSelection(ns.poi_parent)
		end
	end
end

do
	local t = 0
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		if t > 3 then -- this doesn't change very often at all; maybe more than 3 seconds?
			t = 0
			ns:UpdateGlow()
		end
	end)
end

do
	local tooltip = CreateFrame("GameTooltip", "QuestPointerTooltip", UIParent, "GameTooltipTemplate")
	function POI_OnEnter(self)
		if not self.questId then
			return
		end
		if UIParent:IsVisible() then
			tooltip:SetParent(UIParent)
		else
			tooltip:SetParent(self)
		end
		
		tooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		tooltip:SetHyperlink("quest:" .. self.questId)
	end
	
	function POI_OnLeave(self)
		tooltip:Hide()
	end
	
	function POI_OnMouseUp(self)
		ShowUIPanel(WorldMapFrame)
		local frame = _G["WorldMapQuestFrame"..self.index]
		if not frame then
			return
		end
		WorldMapFrame_SelectQuestFrame(frame)
	end
	
	local square_half = math.sqrt(0.5)
	local rad_135 = math.rad(135)
	local update_threshold = 0.1
	function Arrow_OnUpdate(self, elapsed)
		self.t = self.t + elapsed
		if self.t < update_threshold then
			return
		end
		self.t = 0
		
		local angle = HBDPins:GetVectorToIcon(self.poi)
		angle = angle + rad_135

		if GetCVar("rotateMinimap") == "1" then
			angle = angle - GetPlayerFacing()
		end
		
		if angle == self.last_angle then
			return
		end
		self.last_angle = angle
		
		--rotate the texture
		local sin,cos = math.sin(angle) * square_half, math.cos(angle) * square_half
		self.texture:SetTexCoord(0.5-sin, 0.5+cos, 0.5+cos, 0.5+sin, 0.5-cos, 0.5-sin, 0.5+sin, 0.5-cos)
	end
end

function ns:UpdateEdges()
	local superTrackedQuestId = GetSuperTrackedQuestID()
	for id, poi in pairs(pois) do
		-- ns.Debug("Considering poi", id, poi.questId, poi.active)
		if poi.active then
			if HBDPins:IsMinimapIconOnEdge(poi) then
				if self.db.useArrows then
					poi.poiButton:Hide()
					if superTrackedQuestId == poi.questId then
						poi.arrow:Hide()
					else
						poi.arrow:Show()
						poi.arrow:SetAlpha(ns.db.arrowAlpha)
					end
				else
					poi.poiButton:Show()
					poi.arrow:Hide()
					poi.poiButton:SetAlpha(ns.db.iconAlpha * (ns.db.fadeEdge and 0.6 or 1))
				end
			else
				--hide completed POIs when close enough to see the ?
				if poi.complete then
					poi.poiButton:Hide()
				else
					poi.poiButton:Show()
				end
				poi.arrow:Hide()
				poi.poiButton:SetAlpha(ns.db.iconAlpha)
			end
		end
	end
end
ns.SUPER_TRACKED_QUEST_CHANGED = ns.UpdateEdges

-- This would be needed for switching to a different look when icons are on the edge of the minimap.
C_Timer.NewTicker(1, function(...)
	ns:UpdateEdges()
end)

function ns.Print(...) print("|cFF33FF99".. myfullname.. "|r:", ...) end
