local _, ns = ...
local UI = ns.UI

local LABELS = { main = "Main hand", off = "Off hand", ranged = "Ranged", target = "Target" }
local COLORS = {
	main = { 1, 0.78, 0.15 },
	off = { 0.95, 0.55, 0.2 },
	ranged = { 0.35, 0.75, 0.9 },
	target = { 0.86, 0.25, 0.25 },
}

local frame, anchor
local bars = {}
local testing
ns.unlocked = false

local function visible()
	if ns.unlocked or testing then return true end
	if not ns.Active() then return false end
	if not ns.db.hideOOC then return true end
	local s = ns.state
	return s.combat or s.attacking or s.autorepeat
end

local function layout()
	if not frame then return end
	local db = ns.db
	local y, shown = 0, 0
	for _, hand in ipairs(ns.HANDS) do
		local bar = bars[hand]
		local s = ns.swings[hand]
		if db[hand] and (s or ns.unlocked) then
			bar:SetHeight(db.height)
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1 - y)
			bar:SetPoint("RIGHT", frame, "RIGHT", -1, 0)
			local c = COLORS[hand]
			bar:SetColor(c[1], c[2], c[3], (s and s.est) and 0.55 or 0.9)
			bar.left:SetText(db.height >= 12 and LABELS[hand] or "")
			if not s then
				bar:SetMinMaxValues(0, 1)
				bar:SetValue(1)
				bar.right:SetText("")
			end
			bar:Show()
			y = y + db.height + 1
			shown = shown + 1
		else
			bar:Hide()
		end
	end
	frame:SetSize(db.width, math.max(db.height + 2, y + 1))
	frame:EnableMouse(ns.unlocked)
	frame:SetShown(shown > 0 and visible())
end

local function onUpdate()
	ns.Tick()
	local t = GetTime()
	for _, hand in ipairs(ns.HANDS) do
		local s = ns.swings[hand]
		local bar = bars[hand]
		if s and bar:IsShown() then
			local v = t - s.start
			if v > s.dur then v = s.dur end
			if v < 0 then v = 0 end
			bar:SetMinMaxValues(0, s.dur)
			bar:SetValue(v)
			if ns.db.time then
				bar.right:SetFormattedText("%.1f", s.dur - v)
			else
				bar.right:SetText("")
			end
		end
	end
	if testing and t > testing then
		testing = nil
		layout()
	end
end

local function build()
	frame = CreateFrame("Frame", "ASwingFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	UI.Fill(frame, { 0.04, 0.04, 0.05, 0.85 })
	UI.Border(frame, { 0, 0, 0, 1 })
	UI.Movable(frame, ns.db)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartDrag() end)
	frame:SetScript("OnDragStop", function(self) self:StopDrag() end)
	for _, hand in ipairs(ns.HANDS) do
		bars[hand] = UI.Bar(frame, ns.db.height)
	end
	local ticker = CreateFrame("Frame", nil, UIParent)
	ticker:SetScript("OnUpdate", onUpdate)
	frame.ticker = ticker
	ns.frame = frame
	ns.bars = bars
	layout()
end

function ns.Apply()
	if not frame then return end
	frame:Restore()
	layout()
end

function ns.SetLocked(locked)
	ns.db.locked = locked and true or false
	ns.unlocked = not ns.db.locked
	ns.Apply()
end

function ns.Test()
	testing = GetTime() + 4
	for _, hand in ipairs(ns.HANDS) do
		if ns.db[hand] then
			ns.swings[hand] = { start = GetTime(), dur = hand == "off" and 1.8 or hand == "ranged" and 3 or 2.6, est = false }
		end
	end
	layout()
end

function ns.OpenMenu()
	if not frame then return end
	if not anchor then
		anchor = CreateFrame("Frame", nil, UIParent)
		anchor:SetSize(1, 1)
		anchor:SetPoint("CENTER", UIParent, "CENTER", -90, 160)
	end
	local db = ns.db
	local entries = {
		{ text = "ASwing", title = true },
		{ text = db.locked and "Unlock to move" or "Lock", func = function() ns.SetLocked(not db.locked) end },
		{ text = "Show test swings", func = ns.Test },
		{
			text = "Reset position",
			func = function()
				db.pos = nil
				db.scale = 1
				ns.Apply()
			end,
		},
		{ text = "Bars", title = true },
		UI.Toggle(db, "main", "Main hand", ns.Apply),
		UI.Toggle(db, "off", "Off hand", ns.Apply),
		UI.Toggle(db, "ranged", "Ranged and wand", ns.Apply),
		UI.Toggle(db, "target", "Target's swing", ns.Apply),
		{ text = "Options", title = true },
		UI.Toggle(db, "hideOOC", "Hide out of combat", ns.Apply),
		UI.Toggle(db, "time", "Time text"),
		{ text = "Width", title = true },
	}
	for _, w in ipairs({ 160, 220, 280, 340 }) do
		entries[#entries + 1] = {
			text = tostring(w), checked = db.width == w,
			func = function()
				db.width = w
				ns.Apply()
			end,
		}
	end
	entries[#entries + 1] = { text = "Bar height", title = true }
	for _, h in ipairs({ 6, 12, 16, 20 }) do
		entries[#entries + 1] = {
			text = tostring(h), checked = db.height == h,
			func = function()
				db.height = h
				ns.Apply()
			end,
		}
	end
	for _, e in ipairs(UI.ScaleEntries(db, ns.Apply)) do entries[#entries + 1] = e end
	UI.Menu(anchor, entries)
end

ns:Listen("LOGIN", function()
	ns.unlocked = not ns.db.locked
	build()
end)
ns:Listen("SWING_CHANGED", layout)

SLASH_ASWING1 = "/aswing"
SlashCmdList["ASWING"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if not frame then return end
	if msg == "unlock" then
		ns.SetLocked(false)
		ns.Print("unlocked, drag the bars and type /aswing lock")
	elseif msg == "lock" then
		ns.SetLocked(true)
	elseif msg == "test" then
		ns.Test()
	elseif msg == "reset" then
		ns.db.pos = nil
		ns.db.scale = 1
		ns.Apply()
	else
		ns.OpenMenu()
	end
end
