-- Run this returned function against the actual modules in an isolated Studio test.
-- Pure classifiers/validators and rejected authorization paths; creates no Instances and writes no DataStore.
return function(Sentinel, AutoBridge)
	local passed = {}
	local function check(name, condition)
		assert(condition, name)
		table.insert(passed, name)
	end
	local cfg = assert(Sentinel.ValidateConfig({}))
	check("Default mode only observes", cfg.Mode == "Observation" and cfg.CorrectPosition == false and cfg.EnableKick == false)
	check("Reject NaN interval", Sentinel.ValidateConfig({ Interval = 0 / 0 }) == nil)
	check("Reject infinity tolerance", Sentinel.ValidateConfig({ MaxHorizontalSpeed = math.huge }) == nil)
	check("Bound sampling frequency", Sentinel.ValidateConfig({ Interval = 0.1 }) == nil)
	check("Bound alert memory", Sentinel.ValidateConfig({ MaxAlerts = 301 }) == nil)
	check("Require repeated evidence", Sentinel.ValidateConfig({ RequiredSamples = 1 }) == nil)
	check("Reject remote AllowKick override", Sentinel.ValidateConfig({ AllowKick = true }) == nil)
	check("Reject unknown settings", Sentinel.ValidateConfig({ Arbitrary = true }) == nil)
	local function classify(patch, settings)
		local sample = { Dt = 1, Horizontal = 16, Vertical = 0, WalkSpeed = 16, Grounded = true, Ping = 0 }
		for key, value in patch do sample[key] = value end
		return Sentinel.EvaluateSample(settings or cfg, sample)
	end
	check("Normal movement has no signal", #classify({}) == 0)
	check("Spawn or explicit grace suppresses detection", #classify({ Horizontal = 10000, Vertical = 10000, Grace = true }) == 0)
	check("Excessive movement is observable", #classify({ Horizontal = 1000 }) >= 2)
	check("Latency slack reduces false positives", #classify({ Horizontal = 200, Ping = 0 }) > 0 and #classify({ Horizontal = 200, Ping = 1 }) == 0)
	check("Airborne vertical physics alone is ambiguous", #classify({ Vertical = 1000, Grounded = false }) == 0)
	check("Grounded excessive vertical movement yields evidence", #classify({ Vertical = 1000, Grounded = true }) > 0)
	check("Server-configured legitimate speed is respected", #classify({ Horizontal = 400, WalkSpeed = 200 }) == 0)
	check("Moving platform allowance is respected", #classify({ Horizontal = 200, PlatformSpeed = 100 }) == 0)
	check("Long paused sample is ignored", #classify({ Horizontal = 10000, Dt = 15 }) == 0)
	local strict = assert(Sentinel.ValidateConfig({ Mode = "Strict" }, cfg))
	check("Mode changes tolerance without sanctioning", #classify({ Horizontal = 160 }, cfg) == 0 and #classify({ Horizontal = 160 }, strict) > 0)
	check("AutoBridge safely enabled with team mutation disabled", select(1, AutoBridge.ValidateConfig({})).EnableTeamActions == false)
	check("AutoBridge scans are bounded", AutoBridge.ValidateConfig({ MaxScanInstances = 10001 }) == nil)
	check("AutoBridge unknown configuration refused", AutoBridge.ValidateConfig({ RunDiscoveredScripts = true }) == nil)
	check("Unknown module cannot become executable adapter", AutoBridge.RegisterAdapter("unknown", { Actions = {} }) == false)
	check("Adapter action needs explicit permission and validator", AutoBridge.RegisterAdapter("invalid-contract", { Probe = function() return {} end,
		Actions = { Execute = { Execute = function() end } } }) == false)
	check("Anonymous Sentinel configuration denied", Sentinel.Configure(nil, {}) == false)
	check("Anonymous Sentinel test denied", Sentinel.Test(nil, "normal") == false)
	check("Anonymous AutoBridge configuration denied", AutoBridge.Configure(nil, {}) == false)
	check("Anonymous AutoBridge action denied", AutoBridge.Execute(nil, "teams", "SetTeam", nil, {}) == false)
	return { Passed = #passed, Checks = passed }
end
