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
		local tomtompoint
		local last_waypoint = {}
		local t = 0
		f = CreateFrame("Frame")
		f:SetScript("OnUpdate", function(self, elapsed)
			t = t + elapsed
			if t > 3 then -- this doesn't change very often at all; maybe more than 3 seconds?
				t = 0
				local closest = ns:ClosestPOI()
				if closest then
					if not (closest.questId == last_waypoint.questId and closest.m == last_waypoint.m and closest.z == last_waypoint.z and closest.x == last_waypoint.x and closest.y == last_waypoint.y) then
						if tomtompoint then
							tomtompoint = TomTom:RemoveWaypoint(tomtompoint)
						end
						Debug("Making new tomtom waypoint", closest.questId, closest.title)
						tomtomopts.title = closest.title
						tomtompoint = TomTom:AddMFWaypoint(closest.m, closest.f, closest.x, closest.y, tomtomopts)

						last_waypoint = table.wipe(last_waypoint)
						last_waypoint.questId = closest.questId
						last_waypoint.m = closest.m
						last_waypoint.f = closest.f
						last_waypoint.x = closest.x
						last_waypoint.y = closest.y
					end
				elseif tomtompoint then
					tomtompoint = TomTom:RemoveWaypoint(tomtompoint)
				end
			end
		end)
	end
	f:Show()
end
