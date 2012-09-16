local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")
local Debug = ns.Debug

local f
local tomtomopts = {
	crazy = true,
	persistent = false,
	minimap = false,
	world = false,
	silent = true,
	title = "Quest", -- placeholder
}
function ns:AutoTomTom()
	if not (TomTom and TomTom.AddZWaypoint and TomTom.RemoveWaypoint) then
		return
	end

	if UnitIsGhost("player") then return end

	if not self.db.autoTomTom then
		return f and f:Hide()
	end
	if not f then
		local tomtompoint, last_waypoint
		local t = 0
		f = CreateFrame("Frame")
		f:SetScript("OnUpdate", function(self, elapsed)
			t = t + elapsed
			if t > 3 then -- this doesn't change very often at all; maybe more than 3 seconds?
				t = 0
				local closest = ns:ClosestPOI()
				if closest then
					if closest.questId ~= last_waypoint then
						Debug("Making new tomtom waypoint", closest.questId, closest.title)
						last_waypoint = closest.questId
						tomtomopts.title = closest.title
						tomtompoint = TomTom:AddMFWaypoint(closest.m, closest.f, closest.x, closest.y, tomtomopts)
					end
				elseif tomtompoint then
					tomtompoint = TomTom:RemoveWaypoint(tomtompoint)
				end
			end
		end)
	end
	f:Show()
end
