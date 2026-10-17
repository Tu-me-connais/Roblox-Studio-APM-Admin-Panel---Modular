-- Administration sources and saved bundles are not active game content.
-- Shared by structural discovery and native tool distribution; unrelated Packages stay eligible.
local ServerStorage = game:GetService("ServerStorage")
local SourceScope = {}

function SourceScope.IsInactive(instance)
	if typeof(instance) ~= "Instance" then return false end
	local node = instance
	while node do
		if node.Parent == ServerStorage and (node.Name == "APM_Core" or node.Name == "APM_RestorePoints") then
			return true
		end
		if node:IsA("Model") then
			local schema = node:GetAttribute("APMDistributionSchema")
			if node:GetAttribute("APMCore") == true or node:GetAttribute("APM_Kit") == true
				or (type(schema) == "number" and schema > 0) then
				return true
			end
		end
		node = node.Parent
	end
	return false
end

return SourceScope
