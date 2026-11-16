local _, ns = ...
local IsSecret = ns.IsSecret

local HANDS = { "main", "off", "ranged", "target" }
local NEXT_MELEE = { 78, 845, 6807, 2973 }
local RANGED = { 75, 5019, 2480, 7918, 7919 }
local MELEE_HIT = { WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true, ABSORB = true, IMMUNE = true, EVADE = true }

local swings = {}
local state = {
	attacking = false,
	autorepeat = false,
	combat = false,
	casting = false,
	logSeen = 0,
}
local nextMelee, rangedSpells

ns.HANDS = HANDS
ns.swings = swings
ns.state = state

local function num(v)
	if type(v) ~= "number" or IsSecret(v) then return nil end
	if v <= 0 then return nil end
	return v
end

local function plain(v)
	if v == nil or IsSecret(v) then return nil end
	return v
end

function ns.Speed(hand)
	if hand == "ranged" then
		if not UnitRangedDamage then return nil end
		return num((UnitRangedDamage("player")))
	elseif hand == "target" then
		return num((UnitAttackSpeed("target")))
	end
	local main, off = UnitAttackSpeed("player")
	if hand == "off" then return num(off) end
	return num(main)
end

local function changed()
	ns:Fire("SWING_CHANGED")
end

function ns.Stop(hand)
	if swings[hand] then
		swings[hand] = nil
		changed()
	end
end

function ns.Start(hand, estimated)
	local speed = ns.Speed(hand)
	if not speed or not ns.db[hand] then
		ns.Stop(hand)
		return
	end
	swings[hand] = { start = GetTime(), dur = speed, est = estimated and true or false }
	changed()
end

function ns.LogActive()
	return state.logSeen > 0 and GetTime() - state.logSeen < 15
end

local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function names(ids)
	local out = {}
	for _, id in ipairs(ids) do
		out[id] = true
		local n = plain(spellName(id))
		if n then out[n] = true end
	end
	return out
end

local function isSpell(set, id)
	id = plain(id)
	if not id then return false end
	if set[id] then return true end
	local n = plain(spellName(id))
	return n ~= nil and set[n] == true
end

local function parryHaste()
	local s = swings.main
	if not s then return end
	local left = s.start + s.dur - GetTime()
	local floor = 0.2 * s.dur
	if left <= floor then return end
	local cut = 0.4 * s.dur
	if left - cut < floor then cut = left - floor end
	s.start = s.start - cut
	changed()
end
ns.ParryHaste = parryHaste

local function rescale(hand)
	local s = swings[hand]
	if not s then return end
	local speed = ns.Speed(hand)
	if not speed or speed == s.dur then return end
	local frac = (GetTime() - s.start) / s.dur
	if frac > 1 then frac = 1 end
	s.dur = speed
	s.start = GetTime() - frac * speed
	changed()
end

local function near(hand, tolerance)
	local s = swings[hand]
	if not s then return nil end
	local t = GetTime()
	local d = math.abs(s.start + s.dur - t)
	local fresh = s.est and (t - s.start)
	if fresh and fresh < d then d = fresh end
	if d <= tolerance then return d end
	return nil
end

local function meleeHint()
	if not state.attacking then return end
	local main, off = near("main", 0.35), near("off", 0.35)
	if not swings.main and not swings.off then
		ns.Start("main", true)
	elseif main and (not off or main <= off) then
		ns.Start("main", false)
	elseif off then
		ns.Start("off", false)
	end
end

local function targetHint()
	if not ns.db.target or not UnitExists or not UnitExists("target") then return end
	local s = swings.target
	if not s or near("target", 0.4) or GetTime() > s.start + s.dur then
		ns.Start("target", false)
	end
end

local function fromLog(_, sub, _, src, _, _, _, dst, _, _, _, a12, a13, ...)
	sub, src, dst = plain(sub), plain(src), plain(dst)
	if not sub or not src then return end
	local me = UnitGUID("player")
	local target = UnitExists and UnitExists("target") and plain(UnitGUID("target"))
	if src ~= me and dst ~= me then return end
	state.logSeen = GetTime()
	if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
		local offhand
		if sub == "SWING_DAMAGE" then
			offhand = plain(select(8, ...))
		else
			offhand = plain(a13)
		end
		if src == me then
			ns.Start(offhand and "off" or "main", false)
		elseif dst == me then
			if sub == "SWING_MISSED" and plain(a12) == "PARRY" then parryHaste() end
			if target and src == target then ns.Start("target", false) end
		end
	elseif (sub == "SPELL_DAMAGE" or sub == "SPELL_MISSED") and src == me then
		if isSpell(nextMelee, a12) or (plain(a13) and nextMelee[plain(a13)]) then ns.Start("main", false) end
	end
end
ns.FromLog = fromLog

local function resume()
	state.casting = false
	if state.attacking then
		ns.Start("main", not ns.LogActive())
		ns.Start("off", not ns.LogActive())
	end
end

function ns.Tick()
	local t = GetTime()
	local dirty = false
	local log = ns.LogActive()
	for _, hand in ipairs(HANDS) do
		local s = swings[hand]
		if s and t >= s.start + s.dur then
			local melee = hand == "main" or hand == "off"
			local speed = ns.Speed(hand)
			if melee and speed and state.attacking and not state.casting and not log then
				local late = t - (s.start + s.dur)
				s.dur = speed
				s.start = late < speed and t - late or t
				s.est = true
				dirty = true
			else
				local grace = (melee and log and state.attacking) and 1.5 or 0
				if t >= s.start + s.dur + grace then
					swings[hand] = nil
					dirty = true
				end
			end
		end
	end
	if dirty then changed() end
end

function ns.Active()
	for _, hand in ipairs(HANDS) do
		if swings[hand] then return true end
	end
	return false
end

ns:Listen("LOGIN", function()
	nextMelee = names(NEXT_MELEE)
	rangedSpells = names(RANGED)

	if CombatLogGetCurrentEventInfo and not C_DamageMeter then
		ns:On("COMBAT_LOG_EVENT_UNFILTERED", function()
			pcall(function() fromLog(CombatLogGetCurrentEventInfo()) end)
		end)
	end

	ns:On("PLAYER_ENTER_COMBAT", function()
		state.attacking = true
		if not ns.LogActive() and not state.casting then
			ns.Start("main", true)
			ns.Start("off", true)
		end
		changed()
	end)
	ns:On("PLAYER_LEAVE_COMBAT", function()
		state.attacking = false
		changed()
	end)
	ns:On("PLAYER_REGEN_DISABLED", function()
		state.combat = true
		changed()
	end)
	ns:On("PLAYER_REGEN_ENABLED", function()
		state.combat = false
		changed()
	end)
	ns:On("START_AUTOREPEAT_SPELL", function()
		state.autorepeat = true
		changed()
	end)
	ns:On("STOP_AUTOREPEAT_SPELL", function()
		state.autorepeat = false
		changed()
	end)

	ns:On("UNIT_ATTACK_SPEED", function(unit)
		if unit == "player" then
			rescale("main")
			rescale("off")
		elseif unit == "target" then
			rescale("target")
		end
	end)
	ns:On("UNIT_RANGEDDAMAGE", function(unit)
		if unit == "player" then rescale("ranged") end
	end)
	ns:On("PLAYER_EQUIPMENT_CHANGED", function()
		if state.attacking then
			ns.Start("main", true)
			ns.Start("off", true)
		end
		if state.autorepeat then ns.Start("ranged", true) end
	end)
	ns:On("PLAYER_TARGET_CHANGED", function()
		ns.Stop("target")
	end)

	ns:On("UNIT_SPELLCAST_START", function(unit)
		if unit ~= "player" then return end
		state.casting = true
		swings.main = nil
		swings.off = nil
		changed()
	end)
	ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spell)
		if unit ~= "player" then return end
		if state.casting then
			resume()
		elseif isSpell(rangedSpells, spell) then
			ns.Start("ranged", false)
		elseif isSpell(nextMelee, spell) then
			ns.Start("main", false)
		end
	end)
	local function ended(unit)
		if unit == "player" and state.casting then resume() end
	end
	ns:On("UNIT_SPELLCAST_STOP", ended)
	ns:On("UNIT_SPELLCAST_FAILED", ended)
	ns:On("UNIT_SPELLCAST_INTERRUPTED", ended)

	ns:On("UNIT_COMBAT", function(unit, action, _, _, school)
		if ns.LogActive() then return end
		action = plain(action)
		if not action or not MELEE_HIT[action] then return end
		school = plain(school)
		if school and school ~= 1 and school ~= 0 then return end
		if unit == "target" then
			meleeHint()
		elseif unit == "player" then
			if action == "PARRY" then parryHaste() end
			targetHint()
		end
	end)
end)
