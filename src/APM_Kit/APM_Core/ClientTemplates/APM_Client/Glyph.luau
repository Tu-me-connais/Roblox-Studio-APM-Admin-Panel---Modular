--[[
	Glyph : les flèches de Sentinel, dessinées (pas de police, pas d'image) — signature graphique de l'assistant.
	  · Traits COURBES : chaque flèche est un chevron aux bras galbés (courbes de Bézier, trait plus fin aux extrémités et plus appuyé à la pointe, bouts arrondis).
	  · Exclusivement monochrome : blanc, noir et gris, aucun fond.
	  · Une orientation = une rotation du même dessin (0 ° : « >>| », 180 ° : « |<< » vue de côté), donc cohérente partout et nette même minuscule.
	  · Option Double (celle de Sentinel) : DEUX flèches collées l'une à l'autre, sans jamais se chevaucher, suivies de la barre :
	      flèche 1 = le premier chevron ; flèche 2 = le second chevron et la barre. Elles ont des teintes OPPOSÉES (l'une noire, l'autre blanche) et, à chaque onde
	      (toutes les 30 s par défaut), ÉCHANGENT leurs couleurs en douceur : l'échange traverse le symbole le long de son axe, puis tout redevient fixe.
	  · Sans Double : une seule flèche, nuances claires, avec l'onde de luminosité d'origine (un crête plus claire suivie d'un creux plus sombre).
	    Dans les deux cas l'animation ne tourne que pendant l'onde (≈ 2 s) et se déconnecte ensuite : aucune boucle de rendu permanente.
]]
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Glyph = {}

local function gray(value)
	value = math.clamp(value, 0, 1)
	return Color3.new(value, value, value)
end

local function smooth(value)
	return value * value * (3 - 2 * value)
end

----------------------------------------------------------------------------------------------------------
-- Dessin : une liste de segments { x1, y1, x2, y2, épaisseur, groupe } dans une boîte 24 x 24, centrée. Orientation de référence : pointes vers la droite, barre à droite.

local function bezier(p0, p1, p2, t)
	local u = 1 - t
	return u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1], u * u * p0[2] + 2 * u * t * p1[2] + t * t * p2[2]
end

-- Courbe approchée par `count` segments dont l'épaisseur varie : thickness(t) avec t de 0 à 1
local function curve(list, group, p0, p1, p2, count, thickness)
	local px, py = bezier(p0, p1, p2, 0)
	for step = 1, count do
		local t = step / count
		local x, y = bezier(p0, p1, p2, t)
		table.insert(list, { px, py, x, y, thickness((step - .5) / count), group })
		px, py = x, y
	end
end

-- Un chevron dont la pointe est en (tipX, 12) : bras légèrement CONCAVES (galbe vers l'axe) qui donnent une pointe nette et élégante, plus fins aux extrémités, plus appuyés à la pointe
local function chevron(list, group, tipX)
	local reach, half = 5.8, 6.4
	local fine, bold = 1.5, 2.8
	local bow = -1.0 -- négatif : concave ; positif bombé (pointe plus émoussée)
	local function thickness(t) return fine + (bold - fine) * smooth(t) end
	local length = math.sqrt(reach * reach + half * half)
	for _, sign in { -1, 1 } do
		local p0, p2 = { tipX - reach, 12 + sign * half }, { tipX, 12 }
		-- normale du côté extérieur (vers le haut et la droite pour le bras du haut)
		local nx, ny = half / length, sign * reach / length
		local p1 = { (p0[1] + p2[1]) / 2 + bow * nx, (p0[2] + p2[2]) / 2 + bow * ny }
		curve(list, group, p0, p1, p2, 10, thickness)
	end
end

-- La barre, légèrement galbée (plus épaisse au milieu, fine aux bouts)
local function bar(list, group, x)
	curve(list, group, { x, 12 - 7 }, { x + 1.1, 12 }, { x, 12 + 7 }, 8, function(t) return 1.3 + 1.2 * math.sin(math.pi * t) end)
end

local SINGLE = {}
chevron(SINGLE, 1, 11)
bar(SINGLE, 1, 17.5)

-- Deux chevrons ESPACÉS d'une valeur supérieure à l'épaisseur des traits (jamais en contact), puis la barre
local DOUBLE = {}
local SPACING = 5.3
chevron(DOUBLE, 1, 8.2)
chevron(DOUBLE, 2, 8.2 + SPACING)
bar(DOUBLE, 2, 8.2 + SPACING + 4.4)

-- Centre le dessin dans la boîte 24 x 24 et renvoie ses bornes en abscisse (sert à placer chaque trait le long de l'axe de l'onde)
local function normalize(list)
	local minX, maxX = math.huge, -math.huge
	for _, s in list do
		minX = math.min(minX, s[1] - s[5] / 2, s[3] - s[5] / 2)
		maxX = math.max(maxX, s[1] + s[5] / 2, s[3] + s[5] / 2)
	end
	local shift = 12 - (minX + maxX) / 2
	for _, s in list do
		s[1] += shift
		s[3] += shift
	end
	return minX + shift, maxX + shift
end
local SINGLE_MIN, SINGLE_MAX = normalize(SINGLE)
local DOUBLE_MIN, DOUBLE_MAX = normalize(DOUBLE)

--[[
	Crée une flèche dans `parent`. options : Size (px), Rotation (degrés), Tone (gris de repos 0..1), Name, Double (true : les deux flèches opposées qui échangent leurs couleurs).
	Renvoie { Root, SetRotation(degrés, durée), SetTone(valeur), SetTransparency(valeur), PlayWave(vitesse), Destroy() }.
	En mode Double, Tone règle seulement le contraste (repos .78, survol .98) : les deux flèches restent noire et blanche.
]]
function Glyph.Create(parent, options)
	options = options or {}
	local size = options.Size or 22
	local tone = options.Tone or .8
	local double = options.Double == true
	local shape, minX, maxX = double and DOUBLE or SINGLE, double and DOUBLE_MIN or SINGLE_MIN, double and DOUBLE_MAX or SINGLE_MAX

	local root = Instance.new("Frame")
	root.Name = options.Name or "Glyph"
	root.AnchorPoint = Vector2.new(.5, .5)
	root.Position = UDim2.fromScale(.5, .5)
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Rotation = options.Rotation or 0
	root.Active = false
	root.Parent = parent

	-- état de repos du couple : 0 = flèche 1 sombre / flèche 2 claire ; 1 = l'inverse. Chaque onde bascule de l'un à l'autre.
	local phase, target = 0, 0
	local function levels()
		local contrast = math.clamp(.88 + (tone - .78) * .6, 0, 1)
		return .5 - contrast / 2, .5 + contrast / 2 -- noir, blanc (le contraste monte au survol)
	end
	local function pairColors(mix)
		local dark, light = levels()
		return gray(dark + (light - dark) * mix), gray(light + (dark - light) * mix) -- flèche 1, flèche 2
	end

	local segments = {} -- { Frame, abscisse normalisée 0..1 le long de l'axe, groupe }
	for _, def in shape do
		local x1, y1, x2, y2, thickness, group = table.unpack(def)
		local dx, dy = x2 - x1, y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)
		local segment = Instance.new("Frame")
		segment.AnchorPoint = Vector2.new(.5, .5)
		segment.Position = UDim2.fromScale((x1 + x2) / 2 / 24, (y1 + y2) / 2 / 24)
		-- chaque segment dépasse un peu sur le suivant : la courbe est continue, sans marche
		segment.Size = UDim2.fromScale((length + thickness * .8) / 24, thickness / 24)
		segment.Rotation = math.deg(math.atan2(dy, dx))
		segment.BorderSizePixel = 0
		segment.Active = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(.5, 0)
		corner.Parent = segment
		segment.Parent = root
		table.insert(segments, { segment, math.clamp(((x1 + x2) / 2 - minX) / (maxX - minX), 0, 1), group })
	end

	local api = { Root = root }
	local waveConnection, rotationTween
	local alive = true

	local function paint(progress)
		if double then
			-- progress : avancement de l'échange (0..1) ou nil au repos. Chaque trait suit l'onde avec un léger retard selon sa place le long de l'axe.
			for _, entry in segments do
				local mix = phase
				if progress then
					local local_ = smooth(math.clamp((progress - entry[2] * .4) / .6, 0, 1))
					mix = phase + (target - phase) * local_
				end
				local first, second = pairColors(mix)
				entry[1].BackgroundColor3 = entry[3] == 1 and first or second
			end
			return
		end
		-- progress : position de la crête le long de l'axe (-0.5 … 1.5) ; hors onde, tout est au gris de repos
		for _, entry in segments do
			local value = tone
			if progress then
				local distance = (entry[2] - progress) / .32
				if distance > -1 and distance < 1 then
					-- crête plus clair devant, creux plus sombre derrière, continu et nul aux deux bouts : une onde, pas un clignotement
					value += .3 * math.sin(math.pi * distance) * math.sqrt(1 - math.abs(distance))
				end
			end
			entry[1].BackgroundColor3 = gray(value)
		end
	end
	paint(nil)

	function api.SetTone(value)
		tone = value
		if not waveConnection then paint(nil) end
	end
	function api.SetRotation(degrees, duration)
		if rotationTween then rotationTween:Cancel() rotationTween = nil end
		if not duration or duration <= 0 then
			root.Rotation = degrees
			return
		end
		-- le plus court chemin entre deux orientations (jamais un tour complet)
		local delta = (degrees - root.Rotation + 180) % 360 - 180
		rotationTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Rotation = root.Rotation + delta })
		rotationTween:Play()
	end
	function api.SetTransparency(value)
		for _, entry in segments do entry[1].BackgroundTransparency = value end
	end

	-- Une onde (≈ 2 s à vitesse 1) puis retour au repos. Un seul rendu actif à la fois ; rappeler pendant l'onde ne fait rien.
	-- En mode Double, l'onde est l'ÉCHANGE des deux couleurs : la flèche 1 passe de sombre à claire (ou l'inverse) pendant que la flèche 2 fait le chemin contraire.
	function api.PlayWave(speed)
		if waveConnection or not alive then return end
		local duration = 2.2 / math.clamp(speed or 1, .5, 2)
		local started = os.clock()
		target = 1 - phase
		waveConnection = RunService.Heartbeat:Connect(function()
			local progress = (os.clock() - started) / duration
			if progress >= 1 or not root.Parent then
				waveConnection:Disconnect()
				waveConnection = nil
				phase = target
				paint(nil)
				return
			end
			if double then
				paint(smooth(progress)) -- avancement doux de l'échange ; le retard par trait le fait traverser le symbole le long de son axe
			else
				paint(-.35 + 1.7 * smooth(progress))
			end
		end)
	end

	function api.Destroy()
		alive = false
		if waveConnection then waveConnection:Disconnect() waveConnection = nil end
		if rotationTween then rotationTween:Cancel() rotationTween = nil end
		root:Destroy()
	end
	return api
end

return Glyph
