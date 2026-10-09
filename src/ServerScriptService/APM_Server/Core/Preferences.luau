-- Préférences d'interface, clé additive par joueur ; écritures regroupées.
local Players=game:GetService("Players")
local Preferences={}
local ctx,cache,dirty={},{},{}
local function key(player) return "Preferences_v2_"..player.UserId end
local function flush(player)
 if not dirty[player] then return end
 local store=ctx.Ranks.GetStore()
 if not store then dirty[player]=nil return end
 local data=cache[player] if not data then return end
 local snapshot=table.clone(data)
 local ok,result=pcall(store.UpdateAsync,store,key(player),function(old)
  if old~=nil and (type(old)~="table" or old.SchemaVersion~=2) then return nil end
  return {SchemaVersion=2,Language=snapshot.Language,Page=snapshot.Page}
 end)
 if ok and type(result)=="table" and cache[player]==data then dirty[player]=nil end
end
function Preferences.Init(context)
 ctx=context
 ctx.Remotes.GetPreferences.OnServerInvoke=function(player)
  if not ctx.Ranks.IsAdmin(player) then return {} end
  if not cache[player] then
   local prefs={} local store=ctx.Ranks.GetStore()
   if store then local ok,data=pcall(store.GetAsync,store,key(player)) if ok and type(data)=="table" and data.SchemaVersion==2 then prefs={Language=data.Language,Page=data.Page} end end
   cache[player]=prefs
  end
  return table.clone(cache[player])
 end
 ctx.Remotes.SetPreferences.OnServerInvoke=function(player,patch)
  if not ctx.Ranks.IsAdmin(player) or type(patch)~="table" then return false end
  local clean={}
  if patch.Language~=nil then
   if type(patch.Language)~="string" or (patch.Language~="auto" and not table.find(ctx.Lang.Codes(),patch.Language)) then return false end
   clean.Language=patch.Language
  end
  if patch.Page~=nil then if type(patch.Page)~="string" or #patch.Page>64 then return false end clean.Page=patch.Page end
  local data=table.clone(cache[player] or {}) for k,v in clean do data[k]=v end cache[player]=data dirty[player]=true
  return true
 end
 Players.PlayerRemoving:Connect(function(player) flush(player) cache[player]=nil dirty[player]=nil end)
 task.spawn(function() while true do task.wait(60) for player in dirty do flush(player) end end end)
 game:BindToClose(function() for player in dirty do flush(player) end end)
end
return Preferences
