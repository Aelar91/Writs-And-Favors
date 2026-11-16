local _, ns = ...
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GROUP = ns.Guide.GROUP
local POUCHES = ns.Guide.POUCHES
local hooked

local function mine() return RXPCData and RXPCData.currentGuideGroup == GROUP end
local function sync()
	local rxp = RXPItemFrame and RXPItemFrame.parent
	if not (rxp and rxp.activeItems and RXPFrame and RXPFrame.activeSteps and mine()) then return end
	local added
	for _, step in ipairs(RXPFrame.activeSteps) do
		if step.activeItems then
			for id, v in pairs(step.activeItems) do
				if rxp.activeItems[id] == nil then rxp.activeItems[id] = v; added = true end
			end
		end
	end
	for _, id in ipairs(POUCHES) do
		if rxp.activeItems[id] == nil and GetItemCount(id) > 0 then rxp.activeItems[id] = ''; added = true end
	end
	if added and not InCombatLockdown() and rxp.UpdateItemFrame then rxp.UpdateItemFrame() end
end
local function hook()
	if hooked then return true end
	local rxp = RXPItemFrame and RXPItemFrame.parent
	if not (rxp and type(rxp.SetStep) == 'function') then return false end
	hooksecurefunc(rxp, 'SetStep', sync)
	hooked = true
	sync()
	return true
end
local f = CreateFrame('Frame')
f:RegisterEvent('PLAYER_ENTERING_WORLD')
f:RegisterEvent('QUEST_LOG_UPDATE')
f:SetScript('OnEvent', function(self, event)
	if hook() and event ~= 'QUEST_LOG_UPDATE' then self:UnregisterEvent(event) end
	sync()
end)
local bags = CreateFrame('Frame')
bags:RegisterEvent('BAG_UPDATE_DELAYED')
bags:SetScript('OnEvent', function()
	local rxp = RXPItemFrame and RXPItemFrame.parent
	local itemcount = rxp and rxp.functions and rxp.functions.itemcount
	if not (itemcount and RXPFrame and RXPFrame.activeSteps and mine()) then return end
	for _, step in ipairs(RXPFrame.activeSteps) do
		if step.active and not step.completed and step.elements then
			for _, el in ipairs(step.elements) do
				if el.tag == 'itemcount' then pcall(itemcount, { element = el }) end
			end
		end
	end
	sync()
end)

function ns.SendToRXP(name, text, open)
	if not (RXPGuides and RXPGuides.RegisterGuide) then return false, 'RestedXP is not loaded' end
	local ok, err = pcall(RXPGuides.RegisterGuide, text)
	if not ok then return false, tostring(err) end
	if open then
		local rxp = RXPItemFrame and RXPItemFrame.parent
		if rxp and rxp.LoadGuideTable then
			C_Timer.After(0.5, function() pcall(rxp.LoadGuideTable, rxp, GROUP, name) end)
		else
			return true, 'Registered: pick "' .. name .. '" in RestedXP\'s guide list (' .. GROUP .. ')'
		end
	end
	return true
end
