-- Additive v2 storage: preserve other sections and remove overrides when returning to script values.
local HttpService = game:GetService("HttpService")
local SuiteConfig = {}
local ranks, sections = nil, {}
local supported, revision = true, 0
local writing = {}
local KEY = "SuiteSettings_v2"
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in value do result[key] = copy(item) end
	return result
end
local function equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in a do if not equal(value, b[key]) then return false end end
	for key in b do if a[key] == nil then return false end end
	return true
end
function SuiteConfig.Init(context)
	ranks = context.Ranks
	local store = ranks.GetStore()
	if not store then return end
	local ok, data = pcall(store.GetAsync, store, KEY)
	if not ok then
		supported = false
		warn("[APM] SuiteSettings_v2 inaccessible, lecture seule")
		return
	end
	if type(data) ~= "table" then return end
	if data.SchemaVersion ~= 2 then
		supported = false
		warn("[APM] Version SuiteSettings non prise en charge")
		return
	end
	sections = type(data.Sections) == "table" and copy(data.Sections) or {}
	revision = tonumber(data._Revision) or 0
end
function SuiteConfig.Snapshot(section)
	local value = sections[section]
	return type(value) == "table" and copy(value) or {}
end
function SuiteConfig.Provenance(section, baseline, effective)
	local stored = type(sections[section]) == "table" and sections[section] or {}
	local storage = not supported and "ReadOnly" or (ranks and ranks.GetStore() and "DataStore" or "Memory")
	local source = storage == "Memory" and "Session" or "Saved"
	local fields, changed, count = {}, {}, 0
	for key, value in effective do
		fields[key] = stored[key] ~= nil and source or "Script"
		if stored[key] ~= nil then
			count += 1
			if not equal(value, stored[key]) then fields[key] = "Server" end
		end
		if not equal(value, baseline[key]) then table.insert(changed, key) end
	end
	table.sort(changed)
	return { Mode = count > 0 and source or "Script", Storage = storage, HasOverrides = count > 0,
		Revision = revision, ScriptConfig = copy(baseline), Fields = fields, OverrideCount = count, ChangedFields = changed }
end
local function write(section, validated, authorize, reset)
	if type(authorize) ~= "function" or authorize() ~= true then return false, { fr = "Accès révoqué.", en = "Access revoked." } end
	if not supported then return false, { fr = "Configuration inaccessible ou version incompatible.", en = "Configuration unavailable or incompatible version." } end
	if (section ~= "AutoBridge" and section ~= "Sentinel" and section ~= "SentinelAssistant") or (not reset and type(validated) ~= "table") then
		return false, { fr = "Section invalide.", en = "Invalid section." }
	end
	if writing[section] then return false, { fr = "Une modification est déjà en cours.", en = "A change is already in progress." } end
	local store = ranks and ranks.GetStore()
	if not store then
		if reset then sections[section] = nil else sections[section] = copy(validated) end
		revision += 1
		if reset then return true, { fr = "Valeurs du script rétablies pour cette session (mode mémoire).", en = "Script values restored for this session (memory mode)." } end
		return true, { fr = "Appliqué pour cette session (mode mémoire, aucune sauvegarde publiée).", en = "Applied for this session (memory mode; published saves unchanged)." }
	end
	writing[section] = true
	local changeId = HttpService:GenerateGUID(false)
	local ok, result = pcall(store.UpdateAsync, store, KEY, function(old)
		-- UpdateAsync can retry: recheck authority at each attempt without touching the old value.
		if authorize() ~= true then return nil end
		if old ~= nil and (type(old) ~= "table" or old.SchemaVersion ~= 2) then return nil end
		local data = type(old) == "table" and copy(old) or { SchemaVersion = 2, Sections = {} }
		data.Sections = type(data.Sections) == "table" and data.Sections or {}
		if reset then data.Sections[section] = nil else data.Sections[section] = copy(validated) end
		data._Revision = (tonumber(data._Revision) or 0) + 1
		data._LastChangeId = changeId
		return data
	end)
	writing[section] = nil
	local confirmed = ok and type(result) == "table" and result.SchemaVersion == 2
		and result._LastChangeId == changeId and type(result.Sections) == "table"
	if confirmed then
		confirmed = reset and result.Sections[section] == nil or (not reset and equal(result.Sections[section], validated))
	end
	if not confirmed then return false, { fr = "Sauvegarde non confirmée ; aucun changement appliqué.", en = "Save not confirmed; no change applied." } end
	local nextRevision = tonumber(result._Revision) or 0
	if nextRevision >= revision then sections, revision = copy(result.Sections), nextRevision end
	if reset then return true, { fr = "Réglages enregistrés supprimés ; valeurs du script rétablies.", en = "Saved overrides removed; script values restored." } end
	return true, { fr = "Configuration enregistrée.", en = "Configuration saved." }
end
function SuiteConfig.Save(section, validated, authorize)
	return write(section, validated, authorize, false)
end
function SuiteConfig.Reset(section, authorize)
	return write(section, nil, authorize, true)
end
return SuiteConfig
