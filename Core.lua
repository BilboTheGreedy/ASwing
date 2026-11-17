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
	total = false,
	labels = true,
	clip = true,
	colors = { main = "gold", off = "orange", ranged = "blue", target = "red" },
	default = { "CENTER", "CENTER", 0, -170 },
}
ns.defaults = defaults

ACore.New(ADDON, ns, { db = "ASwingDB", defaults = defaults, profile = true })

ACore.Register({
	name = "ASwing",
	title = "ASwing",
	slash = "/aswing",
	desc = "swing timer",
	toggle = function() ns.OpenMenu() end,
	options = function()
		if not ns.db or not ns.Options or not ns.frame then return {} end
		return ns.Options()
	end,
})
