local _, ns = ...
local side = UnitFactionGroup and UnitFactionGroup('player')
if side == 'Alliance' and ns.DA then ns.D = ns.DA end
ns.DA = nil
local D = ns.D
ns.Side = D.side or 'Horde'
local h = D.waylaid.handIn
ns.HandInAt = h.npc .. (ns.Side == 'Alliance' and ' at Three Corners in Redridge Mountains' or ' in the Crossroads')
