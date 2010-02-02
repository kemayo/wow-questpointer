local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")

local Astrolabe = DongleStub("Astrolabe-0.4")
-- Astrolabe.MinimapUpdateTime = 0.1 -- Speed up minimap updates

ns.defaults = {
	iconScale = 0.7,
	watchedOnly = false,
	useArrows = false,
}
ns.defaultsPC = {}

ns:RegisterEvent("ADDON_LOADED")
function ns:ADDON_LOADED(event, addon)
	if addon ~= myname then return end
	self:InitDB()

	self:RegisterEvent("QUEST_POI_UPDATE")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")

	local update = function() self:UpdatePOIs() end
	hooksecurefunc("AddQuestWatch", update)
	hooksecurefunc("RemoveQuestWatch", update)

	LibStub("tekKonfig-AboutPanel").new(myfullname, myname) -- Make first arg nil if no parent config panel

	self:UnregisterEvent("ADDON_LOADED")
	self.ADDON_LOADED = nil

	if IsLoggedIn() then self:PLAYER_LOGIN() else self:RegisterEvent("PLAYER_LOGIN") end
end

function ns:PLAYER_LOGIN()
	self:RegisterEvent("PLAYER_LOGOUT")

	-- Do anything you need to do after the player has entered the world

	self:UpdatePOIs()

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

function ns:UpdatePOIs(...)
	self.Debug("UpdatePOIs", ...)
	
	local c,z,x,y = Astrolabe:GetCurrentPlayerPosition()
	if not c then
		-- Means that this was probably a change triggered by the world map being
		-- opened and browsed around. Since this is the case, we won't update any POIs for now.
		self.Debug("Skipped UpdatePOIs because of no player position")
		return
	end
	
	-- Interestingly, even if this isn't called, *some* POIs will show up. Not sure why.
	QuestPOIUpdateIcons()
	
	for id, poi in pairs(pois) do
		Astrolabe:RemoveIconFromMinimap(poi)
		poi.active = false
	end
	
	-- self:ClearTomTom()
	
	local numCompletedQuests = 0
	local numEntries = QuestMapUpdateAllQuests()
	for i=1, numEntries do
		local questId, questLogIndex = QuestPOIGetQuestIDByVisibleIndex(i)
		local _, posX, posY, objective = QuestPOIGetIconInfo(questId)
		if posX and posY and (IsQuestWatched(questLogIndex) or not self.db.watchedOnly) then
			local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily = GetQuestLogTitle(questLogIndex)
			local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
			if isComplete and isComplete < 0 then
				isComplete = false
			elseif numObjectives == 0 then
				isComplete = true
			end
			self.Debug("POI", questId, posX, posY, objective, title, isComplete)
			
			local poi = pois[i]
			if not poi then
				poi = CreateFrame("Frame", "QuestPointerPOI"..i, Minimap)
				poi:SetWidth(10)
				poi:SetHeight(10)
				poi:SetScript("OnEnter", POI_OnEnter)
				poi:SetScript("OnLeave", POI_OnLeave)
				poi:SetScript("OnMouseUp", POI_OnMouseUp)
				poi:EnableMouse()
				
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
			if isComplete then
				self.Debug("Making with QUEST_POI_COMPLETE_IN", i)
				-- Using QUEST_POI_COMPLETE_SWAP gets the ? without any circle
				-- Using QUEST_POI_COMPLETE_IN gets the ? in a brownish circle
				poiButton = QuestPOI_DisplayButton("Minimap", QUEST_POI_COMPLETE_SWAP, i, questId)
				numCompletedQuests = numCompletedQuests + 1
			else
				self.Debug("Making with QUEST_POI_NUMERIC", i - numCompletedQuests)
				poiButton = QuestPOI_DisplayButton("Minimap", QUEST_POI_NUMERIC, i - numCompletedQuests, questId)
			end
			poiButton:SetPoint("CENTER", poi)
			poiButton:SetScale(self.db.iconScale)
			poiButton:SetParent(poi)
			poiButton:EnableMouse(false)
			poi.poiButton = poiButton
			
			poi.arrow:SetScale(self.db.iconScale)
			
			poi.index = i
			poi.questId = questId
			poi.questLogIndex = questLogIndex
			poi.c = c
			poi.z = z
			poi.x = posX
			poi.y = posY
			poi.title = title
			poi.active = true
			
			Astrolabe:PlaceIconOnMinimap(poi, c, z, posX, posY)
			-- self:AddTomTom(c, z, posX, posY, title)
			
			pois[i] = poi
		else
			self.Debug("Skipped POI", i, posX, posY)
		end
	end
	
	self:UpdateEdges()
end
ns.QUEST_POI_UPDATE = ns.UpdatePOIs
ns.QUEST_LOG_UPDATE = ns.UpdatePOIs
ns.ZONE_CHANGED_NEW_AREA = ns.UpdatePOIs

do
	local tooltip = CreateFrame("GameTooltip", "QuestPointerTooltip", UIParent, "GameTooltipTemplate")
	function POI_OnEnter(self)
		if UIParent:IsVisible() then
			tooltip:SetParent(UIParent)
		else
			tooltip:SetParent(self)
		end
		
		tooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		
		local title = GetQuestLogTitle(self.questLogIndex)
		tooltip:AddLine(title)
		
		tooltip:Show()
	end
	
	function POI_OnLeave(self)
		tooltip:Hide()
	end
	
	function POI_OnMouseUp(self)
		WorldMapFrame:Show()
		local frame = _G["WorldMapQuestFrame"..self.index]
		if not frame then
			return
		end
		WorldMapFrame_SelectQuest(frame)
	end
	
	local square_half = math.sqrt(0.5)
	local rad_135 = math.rad(135)
	function Arrow_OnUpdate(self, elapsed)
		self.t = self.t + elapsed
		if self.t < Astrolabe.MinimapUpdateTime then
			return
		end
		
		local angle = Astrolabe:GetDirectionToIcon(self.poi)
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
	for id, poi in pairs(pois) do
		if Astrolabe:IsIconOnEdge(poi) then
			self.Debug("On edge", id, poi)
			if self.db.useArrows then
				poi.poiButton:Hide()
				poi.arrow:Show()
			else
				poi.poiButton:Show()
				poi.arrow:Hide()
				poi.poiButton:SetAlpha(0.5)
			end
		else
			self.Debug("Not on edge", id, poi)
			poi.poiButton:Show()
			poi.arrow:Hide()
			poi.poiButton:SetAlpha(1)
		end
	end
end

-- This would be needed for switching to a different look when icons are on the edge of the minimap.
Astrolabe:Register_OnEdgeChanged_Callback(function(...)
	ns.Debug("OnEdgeChanged", ...)
	ns:UpdateEdges()
end, "QuestPointer")

local tomtompoint
function ns:TomTomClosestPOI()
	if not (TomTom and TomTom.AddZWaypoint and TomTom.RemoveWaypoint) then
		return
	end
	if tomtompoint then
		tomtompoint = TomTom.RemoveWaypoint(tomtompoint)
	end
	local closest
	for k,poi in pairs(ns.pois) do
		if poi.active then
			if closest then
				if Astrolabe:GetDistanceToIcon(poi) < Astrolabe:GetDistanceToIcon(closest) then
					closest = poi
				end
			else
				closest = poi
			end
		end
	end
	if closest then
		TomTom:AddZWaypoint(closest.c, closest.z, closest.x * 100, closest.y * 100, closest.title, false, false, false, false, false, true)
	end
end
