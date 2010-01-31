local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")

----------------------
--      Locals      --
----------------------

local tekcheck = LibStub("tekKonfig-Checkbox")
local tekslider = LibStub("tekKonfig-Slider")
local GAP = 8

local icon = LibStub("LibDBIcon-1.0", true)

---------------------
--      Panel      --
---------------------

local frame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
frame.name = myfullname
frame:Hide()
frame:SetScript("OnShow", function(frame)
	local title, subtitle = LibStub("tekKonfig-Heading").new(frame, myfullname, ("General settings for %s."):format(myfullname))
	
	local tracked = tekcheck.new(frame, nil, "Tracked quests only", "TOPLEFT", subtitle, "BOTTOMLEFT", -2, -GAP)
	tracked.tiptext = "Only show icons on the minimap for quests you are tracking"
	local checksound = tracked:GetScript("OnClick")
	tracked:SetScript("OnClick", function(self)
		checksound(self)
		ns.db.watchedOnly = not ns.db.watchedOnly
		ns:UpdatePOIs()
	end)
	tracked:SetChecked(ns.db.watchedOnly)

	local scaleslider, scaleslidertext, scalecontainer = tekslider.new(frame, string.format("Icon scale: %.2f", ns.db.iconScale or 1), 0.3, 2, "TOPLEFT", tracked, "BOTTOMLEFT", 2, -GAP)
	scaleslider.tiptext = "Set the POI icon scale."
	scaleslider:SetValue(ns.db.iconScale or 1)
	scaleslider:SetValueStep(.05)
	scaleslider:SetScript("OnValueChanged", function(self)
		ns.db.iconScale = self:GetValue()
		scaleslidertext:SetText(string.format("Icon scale: %.2f", ns.db.iconScale or 1))
		ns:UpdatePOIs()
	end)

	frame:SetScript("OnShow", nil)
end)

InterfaceOptions_AddCategory(frame)

-----------------------------
--      Slash command      --
-----------------------------

_G["SLASH_".. myname:upper().."1"] = GetAddOnMetadata(myname, "X-LoadOn-Slash")
SlashCmdList[myname:upper()] = function(msg)
	InterfaceOptionsFrame_OpenToCategory(myname)
end

----------------------------------------
--      Quicklaunch registration      --
----------------------------------------

LibStub:GetLibrary("LibDataBroker-1.1"):NewDataObject(myname, {
	type = "launcher",
	icon = [[Interface\WorldMap\UI-WorldMap-QuestIcon.tga]],
	iconCoords = {0, 0.5, 0, 0.5},
	OnClick = function()
		InterfaceOptionsFrame_OpenToCategory(myname)
	end,
})
