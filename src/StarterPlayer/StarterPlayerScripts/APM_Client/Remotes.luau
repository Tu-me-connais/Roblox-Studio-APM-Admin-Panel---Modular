local folder = script.Parent.Parent:WaitForChild("APM_Remotes", 15)
assert(folder, "Session APM expirée")
local Transport = {}
function Transport.All()
 local result = {}
 for _, remote in folder:GetChildren() do result[remote.Name] = remote end
 return result
end
function Transport.Get(name) return folder:WaitForChild(name, 10) end
return Transport
