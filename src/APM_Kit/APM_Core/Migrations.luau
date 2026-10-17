-- Installation migrations run in Studio Edit. Existing DataStores retain their names/keys/schemas.
local Migrations = {}
Migrations.Plan = table.freeze({
	Id="private-core-and-extensions-v3", FromInstallationSchema=2, ToInstallationSchema=3,
	FromDataSchema=2, ToDataSchema=2, Destructive=false,
	Steps={"Backup independent instance branches", "Extract developer configuration", "Install Core and external bootstrap", "Retire permanent official copies", "Test before publishing"},
})
function Migrations.ValidateRelease(candidate, current)
	if type(candidate)~="table" or candidate.InstallationSchema~=3 or candidate.ExtensionsSchema~=1
		or candidate.BootstrapApiVersion~=1 or candidate.ExtensionApiVersion~=1 or candidate.CoreApiVersion~=1 then
		return false,"Unsupported installation/API; review migration before updating"
	end
	if candidate.DataSchemaVersion~=2 or (current and current.DataSchemaVersion~=candidate.DataSchemaVersion) then
		return false,"Data schema changes need a reviewed separate migration"
	end
	if candidate.Channel~="stable" and candidate.Channel~="experimental" then return false,"Unknown release channel" end
	return true
end
return Migrations
