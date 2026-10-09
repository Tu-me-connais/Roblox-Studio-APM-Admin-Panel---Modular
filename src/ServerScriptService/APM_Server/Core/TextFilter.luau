--[[
	TextFilter : filtrage Roblox (TextService) des textes écrits par les admins et affichés à d'autres joueurs (motifs, annonces).
	Obligatoire selon les règles Roblox. Un échec du filtrage ne diffuse JAMAIS le texte brut : l'action est annulée.
]]
local TextService = game:GetService("TextService")

local Filter = {}

-- Coupe un texte à `count` caractères (UTF-8) ; nil si ce n'est pas un texte valide
function Filter.Clamp(text, count)
	if type(text) ~= "string" or #text > 4000 or not utf8.len(text) then
		return nil
	end
	local last = utf8.offset(text, count + 1)
	return last and string.sub(text, 1, last - 1) or text
end

-- Filtre un texte : { Broadcast = pour tout le monde, Personal = pour recipientId } ou nil si le filtrage est indisponible
function Filter.Strings(text, authorId, recipientId)
	text = Filter.Clamp(text, 200)
	if not text then
		return nil
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, authorId, Enum.TextFilterContext.PublicChat)
		local broadcast = filtered:GetNonChatStringForBroadcastAsync()
		local personal = recipientId and filtered:GetNonChatStringForUserAsync(recipientId) or broadcast
		return { Broadcast = broadcast, Personal = personal }
	end)
	if not ok then
		warn("[APM] Filtrage indisponible : texte non diffusé (" .. tostring(result) .. ")")
		return nil
	end
	return result
end

return Filter

