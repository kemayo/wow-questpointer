local myname, ns = ...

local POIButtonMixin = {
	SetQuestID = function(self, questID)
		self.questID = questID
	end,
	SetStyle = function(self, style)
	end,
	ChangeSelected = function(self, selected)
		if selected then
			QuestPOI_SelectButton(self)
		elseif self.poiParent and self.poiParent.poiSelectedButton == self then
			QuestPOI_ClearSelection(self.poiParent)
		end
	end,
	_RefreshStyle = function(self)
		self.style = self:_ComputeStyle()
		QuestPOI_UpdateButtonStyle(self)
	end,
	_ComputeStyle = function(self)
		if IsQuestComplete(self.questID) then
			return "normal"
		else
			return "numeric"
		end
	end
}

local poi_parent = CreateFrame("Frame")
QuestPOI_Initialize(poi_parent, function(button)
	Mixin(button, POIButtonMixin)
end)
poi_parent.numCompleted = 0

function ns:GetPOIButton(questId, mapID, x, y, index)
	local completed = IsQuestComplete(questId)
	poi_parent.numCompleted = poi_parent.numCompleted + (completed and 1 or 0)
	local button = QuestPOI_GetButton(poi_parent, questId, completed and "completed" or "numeric", index - poi_parent.numCompleted)
	return button
end

function ns:ResetPOIs(pois)
	for _, poi in pairs(pois) do
		self:ResetPOI(poi)
		poi.poiButton = nil
	end
	if poi_parent then
		poi_parent.numCompleted = 0
		QuestPOI_HideAllButtons(poi_parent)
	end
end

function ns:IsQuestWatched(questId)
	for i=1, GetNumQuestWatches() do
		local questIndex = GetQuestIndexForWatch(i)
		if questIndex then
			local watchId = GetQuestIDFromLogIndex(questIndex)
			if watchId == questId then
				return true
			end
		end
	end
	return false
end
