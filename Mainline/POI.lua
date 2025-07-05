local myname, ns = ...

local POIButtonMixinPlus = {
	GetQuestClassification = function(self)
		-- Rewrite to avoid QuestCache:Get, which taints
		local questID = self:GetQuestID()
		if questID then
			return C_QuestInfoSystem.GetQuestClassification(questID)
		end
	end,
	_RefreshStyle = function(self)
		self:SetStyle(self:_ComputeStyle())
		return self:UpdateButtonStyle()
	end,
	_ComputeStyle = function(self)
		if C_QuestLog.IsWorldQuest(self.questID) then
			return POIButtonUtil.Style.WorldQuest
		elseif C_QuestLog.IsComplete(self.questID) then
			return POIButtonUtil.Style.QuestComplete
		elseif C_QuestLog.IsQuestDisabledForSession(self.questID) then
			return POIButtonUtil.Style.QuestDisabled
		else
			return POIButtonUtil.Style.QuestInProgress
		end
	end
}
function ns:GetPOIButton(questId, mapID, x, y, index)
	local button = CreateFrame("Button", nil, poi, "POIButtonTemplate")
	Mixin(button, POIButtonMixinPlus)
	return button
end

function ns:ResetPOIs(pois)
	for _, poi in pairs(pois) do
		self:ResetPOI(poi)
		poi.poiButton:Hide()
	end
end

function ns:IsQuestWatched(questId)
	return C_QuestLog.GetQuestWatchType(questId)
end
