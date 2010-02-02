local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")

local Astrolabe = DongleStub("Astrolabe-0.4")

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

local f
function ns:AutoTomTom()
	self.Debug("AutoTomTom")
	if not self.db.autoTomTom then
		self.Debug("disabled")
		return f and f:Hide()
	end
	if not f then
		self.Debug("creating frame")
		local t = 0
		f = CreateFrame("Frame")
		f:SetScript("OnUpdate", function(self, elapsed)
			t = t + elapsed
			if t > 3 then -- this doesn't change very often at all; maybe more than 3 seconds?
				ns:TomTomClosestPOI()
			end
		end)
	end
	self.Debug("showing frame")
	f:Show()
end
