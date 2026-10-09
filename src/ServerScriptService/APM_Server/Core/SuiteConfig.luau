-- Nouvelle clé additive : aucun format v1 n'est réécrit.
local SuiteConfig = {}
local ranks, sections = nil, {}
local supported = true
local KEY = "SuiteSettings_v2"
function SuiteConfig.Init(context)
 ranks = context.Ranks
 local store = ranks.GetStore()
 if not store then return end
 local ok, data = pcall(store.GetAsync, store, KEY)
 if not ok then supported = false warn("[APM] SuiteSettings_v2 inaccessible, lecture seule") return end
 if type(data) ~= "table" then return end
 if data.SchemaVersion ~= 2 then supported = false warn("[APM] Version SuiteSettings non prise en charge") return end
 sections = type(data.Sections) == "table" and data.Sections or {}
end
function SuiteConfig.Snapshot(section)
 local value = sections[section]
 return type(value) == "table" and table.clone(value) or {}
end
function SuiteConfig.Save(section, validated, authorize)
	if authorize and not authorize() then return false,"Accès révoqué." end
 if not supported then return false, "Configuration inaccessible ou version incompatible." end
 if (section ~= "AutoBridge" and section ~= "Sentinel") or type(validated) ~= "table" then return false, "Section invalide." end
 local store = ranks.GetStore()
 if not store then sections[section] = table.clone(validated) return true, "Appliqué pour cette session (mode mémoire)." end
	local ok, result = pcall(store.UpdateAsync, store, KEY, function(old)
	 if authorize and not authorize() then return nil end
  if old ~= nil and (type(old) ~= "table" or old.SchemaVersion ~= 2) then return nil end
  local data = type(old) == "table" and old or {SchemaVersion = 2, Sections = {}}
  data.Sections = type(data.Sections) == "table" and data.Sections or {}
  data.Sections[section] = table.clone(validated)
  data._Revision = (tonumber(data._Revision) or 0) + 1
  return data
 end)
 if not ok or type(result) ~= "table" then return false, "Sauvegarde non confirmée ; aucun changement appliqué." end
 sections = result.Sections
 return true, "Configuration enregistrée."
end
return SuiteConfig
