-- Test pur : Tests.Run(sourceShell). Aucun Instance ni service Studio modifié.
local Tests = {}

function Tests.Run(shellSource)
	local passed = 0
	local function check(value, message)
		assert(value, message)
		passed += 1
	end
	local function node(class, name, children, attributes, definition)
		local object = { Name = name, Children = children or {}, Attributes = attributes or {}, Definition = definition }
		function object:IsA(wanted) return wanted == class end
		function object:GetChildren() return table.clone(self.Children) end
		function object:GetAttribute(key) return self.Attributes[key] end
		function object:GetFullName() return self.Name end
		function object:FindFirstChild(wanted)
			for _, child in self.Children do if child.Name == wanted then return child end end
			return nil
		end
		function object:WaitForChild(wanted) return assert(self:FindFirstChild(wanted), wanted) end
		return object
	end
	local permission = "Extensions.Example.View"
	local function definition(id, order, handles)
		return { ApiVersion = 1, Id = id, Permission = permission, Order = order, Handles = handles, Build = function() end }
	end
	local function page(name, def, attributes)
		return node("ModuleScript", name, nil, attributes or { Permission = permission, ApiVersion = 1 }, def)
	end
	local safe = page("A_Page", definition("ExampleDashboard", 10, { "Economy", "Moderation", "Foreign" }))
	local duplicate = page("B_Duplicate", definition("ExampleDashboard", 10))
	local sameOrder = page("C_Second", definition("ExampleOther", 10))
	local homeCollision = page("D_Home", definition("Home", 1))
	local nativeCategory = page("E_NativeCategory", definition("Tools", 1))
	local missingMetadata = page("F_Missing", definition("Missing", 1), {})
	local unsupportedVersion = page("G_Version", definition("Version", 1), { Permission = permission, ApiVersion = 2 })
	local wrongDefinition = definition("WrongPermission", 1)
	wrongDefinition.Permission = "Extensions.Other.View"
	local mismatch = page("H_Mismatch", wrongDefinition)
	local foreignCategory = page("I_Foreign", definition("Foreign", 1))
	local ownCategory = page("J_OwnCategory", definition("ExampleOwn", 10, { "ExampleOwn" }))
	local definitions = { ownCategory, foreignCategory, mismatch, unsupportedVersion, missingMetadata, nativeCategory, homeCollision, sameOrder, duplicate, safe }
	local nested = node("Folder", "Nested", definitions)
	local extension = node("Folder", "Example", { nested })
	local root = node("Folder", "APM_Client", {
		node("Folder", "Pages", {
			page("Home", { Id = "Home", Order = 0, Build = function() end }),
			page("Moderation", { Id = "Moderation", Order = 4, Handles = { "Moderation" }, Build = function() end }),
		}),
		node("Folder", "ExtensionPages", { extension }),
		node("ModuleScript", "CategoryPage", nil, nil, { Build = function() end }),
	})
	local required, warnings = {}, {}
	local alive = true
	local environment = setmetatable({
		game = { GetService = function() return {} end },
		script = { Parent = root },
		require = function(source)
			required[source] = (required[source] or 0) + 1
			return source.Definition
		end,
		warn = function(message) table.insert(warnings, message) end,
	}, { __index = getfenv() })
	local exposed = shellSource:gsub("return Shell%s*$", "return pageDefinitions")
	check(exposed ~= shellSource, "Hook extraction must replace final return Shell")
	local compiled, compileError = loadstring(exposed)
	check(compiled ~= nil, tostring(compileError))
	setfenv(compiled, environment)
	local discover = compiled()
	local hasPermission = true
	local core = {
		Session = {}, Alive = function() return alive end,
		HasPermission = function(name) return hasPermission and name == permission end,
		ServerModules = {
			{ Category = "Moderation", Mode = "action" },
			{ Category = "Tools", Mode = "action" },
			{ Category = "Economy", Mode = "action", ExtensionId = "Example" },
			{ Category = "Foreign", Mode = "action", ExtensionId = "Other" },
			{ Category = "ExampleOwn", Mode = "action", ExtensionId = "Example" },
		},
	}
	local function byId(defs)
		local map = {}
		for _, def in defs do
			check(map[def.Id] == nil, "Duplicate navigation ID " .. def.Id)
			map[def.Id] = def
		end
		return map
	end
	local defs = discover(core)
	local map = byId(defs)
	check(defs[1].Id == "Home", "Home must remain first")
	check(map.Home.ExtensionId == nil, "Extension cannot replace Home")
	check(map.Tools.ExtensionId == nil, "Extension cannot replace native category")
	check(map.Foreign.ExtensionId == nil, "Extension cannot replace another extension category")
	check(map.ExampleDashboard and map.ExampleDashboard.ExtensionId == "Example", "Recursive extension discovery")
	check(map.Economy == nil, "Owned Handles must avoid automatic category duplicate")
	check(map.Moderation ~= nil, "Native Handles cannot be hijacked")
	check(#map.ExampleDashboard.Handles == 1 and map.ExampleDashboard.Handles[1] == "Economy", "Only owned Handles accepted")
	check(#safe.Definition.Handles == 3, "Definition must not be mutated")
	check(map.ExampleOwn.ExtensionId == "Example", "Page can handle own category ID")
	check(map.Missing == nil and not required[missingMetadata], "No require for missing metadata")
	check(map.Version == nil and not required[unsupportedVersion], "No require for API version mismatch")
	check(map.WrongPermission == nil and required[mismatch], "Returned permission must match manifest")
	local dashboardIndex, otherIndex
	for index, def in defs do
		if def.Id == "ExampleDashboard" then dashboardIndex = index end
		if def.Id == "ExampleOther" then otherIndex = index end
	end
	check(dashboardIndex < otherIndex, "Stable Id sort for equal Order")
	check(#warnings >= 6, "Invalid/colliding pages and Handles must emit diagnostics")

	required = {}
	hasPermission = false
	map = byId(discover(core))
	check(map.ExampleDashboard == nil, "Unpermitted extension must not be registered")
	check(required[safe] == nil and required[sameOrder] == nil, "Unpermitted extension must not be required")
	check(map.Economy ~= nil, "Unpermitted custom page must not hide automatic command category")

	required = {}
	hasPermission = true
	environment.require = function(source)
		required[source] = (required[source] or 0) + 1
		if source == safe then hasPermission = false end
		return source.Definition
	end
	map = byId(discover(core))
	check(map.ExampleDashboard == nil, "Permission revoked during require must filter definition")
	check(required[sameOrder] == nil, "Do not require subsequent page after permission revocation")

	required = {}
	hasPermission = true
	environment.require = function(source)
		required[source] = (required[source] or 0) + 1
		if source == safe then alive = false end
		return source.Definition
	end
	discover(core)
	check(required[sameOrder] == nil, "Discovery must stop after session replacement")
	return { Passed = passed, Warnings = #warnings }
end

return Tests
