-- Merge maps; replace explicit array fields. No secrets belong in SharedConfig.
local Configuration = {}
local arrays = {Ranks=true, ClientTools=true, ToolSources=true, PlayerGroups=true}
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {} for key, item in value do result[key] = copy(item) end return result
end
function Configuration.Merge(defaults, override)
	assert(type(defaults)=="table" and type(override)=="table", "Configuration tables required")
	local result = copy(defaults)
	for key, value in override do
		if key=="RemoveKeys" then
			assert(type(value)=="table", "RemoveKeys must be an array of field names")
		elseif type(value)=="table" and type(result[key])=="table" and not arrays[key] then
			result[key]=Configuration.Merge(result[key],value)
		else result[key]=copy(value) end
	end
	for _,key in override.RemoveKeys or {} do
		assert(type(key)=="string" or type(key)=="number", "Invalid removed configuration key")
		result[key]=nil
	end
	return result
end
return Configuration
