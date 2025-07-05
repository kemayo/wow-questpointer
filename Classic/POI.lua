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

function ns:GetPOIButton(questId, mapID, x, y, index)
	if not self.poi_parent then
		self.poi_parent = CreateFrame("Frame")
		QuestPOI_Initialize(self.poi_parent)
		self.poi_parent.numCompleted = 0
	end
	local completed = IsQuestComplete(questId)
	self.poi_parent.numCompleted = self.poi_parent.numCompleted + (completed and 1 or 0)
	local button = QuestPOI_GetButton(self.poi_parent, questId, completed and "completed" or "numeric", index - self.poi_parent.numCompleted)
	Mixin(button, POIButtonMixin)
	return button
end

function ns:ResetPOIs(pois)
	for _, poi in pairs(pois) do
		self:ResetPOI(poi)
	end
	if self.poi_parent then
		self.poi_parent.numCompleted = 0
		QuestPOI_HideAllButtons(self.poi_parent)
	end
end

function ns:IsQuestWatched(questId)
	for i=1, GetNumQuestWatches() do
		local questIndex = GetQuestIndexForWatch(i)
		if questIndex then
			local watchId = GetQuestIDFromLogIndex(questIndex)
			if watchId == questId then
				print("IsQuestComplete", questId, true)
				return true
			end
		end
	end
	print("IsQuestComplete", questId, false)
	return false
end
