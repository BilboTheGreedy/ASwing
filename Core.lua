local ADDON, ns = ...

local defaults = {
	locked = true,
	scale = 1,
	width = 220,
	height = 12,
	main = true,
	off = true,
	ranged = true,
	target = false,
	hideOOC = true,
	time = true,
	default = { "CENTER", "CENTER", 0, -170 },
}

ACore.New(ADDON, ns, { db = "ASwingDB", defaults = defaults, profile = true })

ACore.Register({
	name = "ASwing",
	title = "ASwing",
	slash = "/aswing",
	desc = "swing timer",
	toggle = function() ns.OpenMenu() end,
})
