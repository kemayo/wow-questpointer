local myname, ns = ...
local myfullname = C_AddOns.GetAddOnMetadata(myname, "Title")
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
	if C_EventUtils.IsEventValid("SUPER_TRACKING_CHANGED") then
		self:RegisterEvent("SUPER_TRACKING_CHANGED")
	end
	if C_EventUtils.IsEventValid("ENCOUNTER_LOOT_RECEIVED") then
		self:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
	end
	self:RegisterEvent("QUEST_WATCH_LIST_CHANGED")

	local update = function() self:UpdatePOIs() end
	if C_QuestLog.AddQuestWatch then
		hooksecurefunc(C_QuestLog, "AddQuestWatch", update)
		hooksecurefunc(C_QuestLog, "RemoveQuestWatch", update)
	else
		-- these are passed the index rather than the ID, but we don't really care
		hooksecurefunc("AddQuestWatch", update)
		hooksecurefunc("RemoveQuestWatch", update)
	end

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

function ns:ClosestPOI()
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

	local x, y, mapid = HBD:GetPlayerZonePosition()
	if not (mapid and x and y) then
		-- Means that this was probably a change triggered by the world map being
		-- opened and browsed around. Since this is the case, we won't update any POIs for now.
		self.Debug("Skipped UpdatePOIs because of no player position")
		return
	end
	if WorldMapFrame:IsVisible() and WorldMapFrame.mapID ~= mapid then
		-- TODO: handle microdungeons
		self.Debug("Skipped UpdatePOIs because map is open and not viewing current zone")
		return
	end

	self:ResetPOIs(pois)

	self:UpdateLogPOIs(mapid)
	self:UpdateWorldPOIs(mapid)

	self:UpdateEdges()
	self:UpdateGlow()
end
ns.QUEST_POI_UPDATE = ns.UpdatePOIs
ns.QUEST_LOG_UPDATE = ns.UpdatePOIs
ns.ZONE_CHANGED_NEW_AREA = ns.UpdatePOIs
ns.PLAYER_ENTERING_WORLD = ns.UpdatePOIs
ns.QUEST_WATCH_LIST_CHANGED = ns.UpdatePOIs

-- 11.0.0+
function ns:UpdateLogPOIs(mapID)
	local cvar = GetCVarBool("questPOI")
	SetCVar("questPOI", 1)
	-- Interestingly, even if this isn't called, *some* POIs will show up. Not sure why.
	QuestPOIUpdateIcons()

	-- Fetches all the quests the player is on, *including* bonus-objective ones (IsQuestTask)
	-- local taskInfo = GetQuestsForPlayerByMapIDCached(mapID)
	local quests = C_QuestLog.GetQuestsOnMap(mapID)
	if quests and #quests > 0 then
		for i, info in ipairs(quests) do
			local questId = info and info.questID
			if
				questId
				and HaveQuestData(questId)
				and not (C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(questId))
				and (not self.db.watchedOnly or self:IsQuestWatched(questId))
			then
				self.Debug("POI", questId, info.x, info.y)

				-- TODO: handle callings properly
				local poi = self:GetPOI('QPL' .. i, questId, mapID, info.x, info.y, i)
				-- print("Obtained quest POI", poi.questId, poi.title)

				HBDPins:AddMinimapIconMap(self, poi, mapID, info.x, info.y, false, true)
			end
		end
	end

	SetCVar("questPOI", cvar and 1 or 0)
end

function ns:UpdateWorldPOIs(mapID)
	if not (ns.db.worldQuest and C_QuestLog.IsWorldQuest) then
		return
	end
	local taskInfo
	if C_TaskQuest.GetQuestsOnMap then
		taskInfo = C_TaskQuest.GetQuestsOnMap(mapID)
	else
		taskInfo = C_TaskQuest.GetQuestsForPlayerByMapID(mapID)
	end
	if taskInfo == nil or #taskInfo == 0 then
		return
	end
	local taskIconIndex = 0
	for i, info in ipairs(taskInfo) do
		local questId = info and (info.questID or info.questId)
		if
			questId
			and HaveQuestData(questId)
			and C_QuestLog.IsWorldQuest(questId)
			and (not ns.db.watchedOnly or self:WorldQuestIsWatched(questId))
		then
			-- info.mapID might not be the current mapID, if the quest is
			-- technically in another map, *but* info.x and info.y are placed
			-- on the current mapID
			local poi = self:GetPOI('QPWQ' .. taskIconIndex, questId, mapID, info.x, info.y, i)

			taskIconIndex = taskIconIndex + 1

			HBDPins:AddMinimapIconMap(self, poi, mapID, info.x, info.y, false, true)
		end
	end
end

function ns:WorldQuestIsWatched(questId)
	if C_QuestLog.GetQuestWatchType(questId) ~= nil then
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

function ns:GetPOI(id, questId, mapID, x, y, index)
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
	if not poi.poiButton then
		-- Classic resets the poiButton because it maintains a pool whose setup differs based on type
		local button = self:GetPOIButton(questId, mapID, x, y, index)
		button:SetPoint("CENTER", poi)
		button:EnableMouse(false)
		poi.poiButton = button
	end

	poi.poiButton:SetScale(self.db.iconScale * (poi.poiButton.scaleFactor or 1))
	poi.arrow:SetScale(self.db.arrowScale)

	poi.questId = questId
	poi.title = (C_QuestLog.GetTitleForQuestID or C_QuestLog.GetQuestInfo)(questId)
	poi.m = mapID
	poi.x = x
	poi.y = y
	poi.worldquest = C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questId)
	poi.complete = (C_QuestLog.IsComplete or IsQuestComplete)(questId)

	poi.active = true

	poi.poiButton:SetQuestID(questId)
	poi.poiButton:_RefreshStyle()

	return poi
end
function ns:ResetPOI(poi)
	HBDPins:RemoveMinimapIcon(self, poi)
	poi.arrow:Hide()
	poi.active = false
	if poi.poiButton then
		poi.poiButton:ChangeSelected(false)
	end
end

function ns:UpdateGlow()
	for _, poi in pairs(ns.pois) do
		if poi.poiButton then
			poi.poiButton:ChangeSelected(false)
		end
	end
	local selected = self:ClosestPOI()
	if selected and selected.poiButton then
		selected.poiButton:ChangeSelected(true)
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
		QuestMapFrame_OpenToQuestDetails(self.questId)
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
		if not angle then
			-- Reports of this being nil right after hearthing. Can't reproduce, but it's an easy check.
			return
		end
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
	local superTrackedQuestId = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID or GetSuperTrackedQuestID)()
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
					if superTrackedQuestId == poi.questId then
						poi.poiButton:Hide()
					else
						poi.poiButton:Show()
						poi.arrow:Hide()
						poi.poiButton:SetAlpha(ns.db.iconAlpha * (ns.db.fadeEdge and 0.6 or 1))
					end
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
ns.SUPER_TRACKING_CHANGED = ns.UpdateEdges

-- This would be needed for switching to a different look when icons are on the edge of the minimap.
C_Timer.NewTicker(1, function(...)
	ns:UpdateEdges()
end)

function ns.Print(...) print("|cFF33FF99".. myfullname.. "|r:", ...) end
