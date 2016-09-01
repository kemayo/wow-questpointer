local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")
local Debug = ns.Debug

local HBD = LibStub("HereBeDragons-1.0")
local HBDPins = LibStub("HereBeDragons-Pins-1.0")

ns.defaults = {
	iconScale = 0.7,
	arrowScale = 0.7,
	iconAlpha = 1,
	arrowAlpha = 1,
	watchedOnly = false,
	useArrows = false,
	fadeEdge = true,
	autoTomTom = false,
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
	for k,poi in pairs(ns.pois) do
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
	
	for id, poi in pairs(pois) do
		HBDPins:RemoveMinimapIcon(self, poi)
		if poi.poiButton then
			poi.poiButton:Hide()
			poi.poiButton:SetParent(Minimap)
			poi.poiButton = nil
		end
		poi.arrow:Hide()
		poi.active = false
	end
	
	local x,y,m,f = HBD:GetPlayerZonePosition()
	if not (m and f and x and y) then
		-- Means that this was probably a change triggered by the world map being
		-- opened and browsed around. Since this is the case, we won't update any POIs for now.
		self.Debug("Skipped UpdatePOIs because of no player position")
		return
	end
	
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
			if posX and posY and (IsQuestWatched(questLogIndex) or not self.db.watchedOnly) then
				local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questId, startEvent, displayQuestId, isOnMap, hasLocalPOI, isTask, isBounty, isStory = GetQuestLogTitle(questLogIndex)
				self.Debug("POI", questId, posX, posY, objective, title, isComplete)

				local poi = pois[i]
				if not poi then
					poi = CreateFrame("Frame", "QuestPointerPOI"..i, Minimap)
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
				end

				local poiButton
				-- IsQuestComplete seems to test for "is quest in a turnable-in state?", distinct from IsQuestFlaggedCompleted...
				isComplete = IsQuestComplete(questId)
				if isComplete then
					self.Debug("Making with QUEST_POI_COMPLETE_IN", i)
					numCompletedQuests = numCompletedQuests + 1
					poiButton = QuestPOI_GetButton(ns.poi_parent, questId, hasLocalPOI and 'normal' or 'remote', numCompletedQuests, isStory)
				else
					self.Debug("Making with QUEST_POI_NUMERIC", i - numCompletedQuests)
					numNumericQuests = numNumericQuests + 1
					poiButton = QuestPOI_GetButton(ns.poi_parent, questId, hasLocalPOI and 'numeric' or 'remote', numNumericQuests, isStory)
				end
				poiButton:SetPoint("CENTER", poi)
				poiButton:SetScale(self.db.iconScale)
				poiButton:SetParent(poi)
				poiButton:EnableMouse(false)
				poi.poiButton = poiButton
				
				poi.arrow:SetScale(self.db.arrowScale)
				
				poi.index = i
				poi.questId = questId
				poi.questLogIndex = questLogIndex
				poi.m = m
				poi.f = f
				poi.x = posX
				poi.y = posY
				poi.title = title
				poi.active = true
				poi.complete = isComplete
				
				HBDPins:AddMinimapIconMF(self, poi, m, f, posX, posY, true)
				
				pois[i] = poi
			else
				self.Debug("Skipped POI", i, posX, posY)
			end
		end
	end
	self:UpdateEdges()
	self:UpdateGlow()
end
ns.QUEST_POI_UPDATE = ns.UpdatePOIs
ns.QUEST_LOG_UPDATE = ns.UpdatePOIs
ns.ZONE_CHANGED_NEW_AREA = ns.UpdatePOIs
ns.PLAYER_ENTERING_WORLD = ns.UpdatePOIs

function ns:UpdateGlow()
	QuestPOI_ClearSelection(ns.poi_parent)
	local closest = self:ClosestPOI()
	if closest then
		-- closest.poiButton.selectionGlow:Show()
		QuestPOI_SelectButton(closest.poiButton)
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
		if UIParent:IsVisible() then
			tooltip:SetParent(UIParent)
		else
			tooltip:SetParent(self)
		end
		
		tooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		
		local link = GetQuestLink(self.questLogIndex)
		if link then
			tooltip:SetHyperlink(link)
		end
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
