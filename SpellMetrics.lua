local addonName, ZP = ...

-- Parse the amounts the client actually displays. No expansion-specific spell
-- coefficients are applied: unfamiliar or conditional effects stay unlabelled.
local function Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return not canaccessvalue or canaccessvalue(value)
end

local function Number(value)
    if not Readable(value) or type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge or value < 0 or value > 1e10 then return nil end
    return value
end

local accents = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["Î"] = "i", ["Ï"] = "i", ["ô"] = "o", ["ö"] = "o", ["Ô"] = "o", ["Ö"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["ç"] = "c", ["Ç"] = "c",
}

local function Normalize(text)
    if not Readable(text) or type(text) ~= "string" or #text == 0 or #text > 6000 then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", " "):gsub("|A.-|a", " ")
        :gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("\226\128\153", "'")
        :gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
    for from, to in pairs(accents) do text = text:gsub(from, to) end
    text = text:lower():gsub("d'", "de "):gsub("%s+", " ")
    -- The French client groups thousands with spaces, including narrow NBSP.
    local changed
    repeat text, changed = text:gsub("(%d)%s+(%d%d%d)%f[^%d]", "%1%2") until changed == 0
    return text
end

local function Numeric(text, french)
    text = text:gsub("[.,]+$", "")
    local comma, dot = text:find(",", 1, true), text:find(".", 1, true)
    if comma and dot then
        local lastComma, lastDot = text:match(".*(),"), text:match(".*()%.")
        if lastComma > lastDot then text = text:gsub("%.", ""):gsub(",", ".")
        else text = text:gsub(",", "") end
    elseif comma then
        if french then text = text:gsub(",", ".")
        elseif text:match("^%d%d?%d?,%d%d%d$") or select(2, text:gsub(",", "")) > 1 then text = text:gsub(",", "")
        else text = text:gsub(",", ".") end
    elseif dot and select(2, text:gsub("%.", "")) > 1 then return nil end
    return Number(tonumber(text))
end

local forbidden = {
    "weapon", "arme", "attack power", "puissance d'attaque", "combo point", "points de combo",
    "absorb", "reflect", "renvoi", "renvoie", "retaliat", "retourne", "chance", "probabilite",
    "when struck", "when hit", "when attacked", "when an ", "when the ", "whenever", "%f[%a]if ", "%f[%a]si ",
    "each attack", "each melee", "every attack",
    "melee attacks", "your attacks", "attackers", "attacking you", "striking you", "strikes you",
    "chaque attaque", "attaques de melee", "lorsqu", "a chaque coup", "vous frappe", "vous frappent",
    "per stack", "par charge", "for each", "pour chaque", "jumps", "rebond", "chain", "chaine",
    "divided", "split", "reparti", "partage", "random", "aleatoire", "summons", "invoque", "totem",
    "remaining rage", "remaining energy", "rage restante", "energie restante", "up to %d+ damage",
    "spell power", "puissance des sorts", "next .-attack", "next attack", "prochaine attaque", "prochain coup",
    "twice", "two times", "deux fois", "immediate tick", "initial tick", "tick immediately", "tic immediat",
    "after a delay", "after %d", "apres un delai", "additional health", "additional healing",
    "up to %d+ health", "for a maximum of", "jusqu'a %d+ points de vie",
    "maximum health", "sante maximale", "vie maximum", "maximum mana", "mana maximum",
    "increases .-damage", "increases .-healing", "reduces .-damage", "reduces .-healing",
    "augmente .-degats", "augmente .-soins", "reduit .-degats", "reduit .-soins",
    "damage is reduced", "degats sont reduits", "damage taken", "degats subis",
    "restores .-mana", "rend .-mana", "restores .-energy", "restores .-rage",
}

local schools = {
    physical = true, fire = true, frost = true, nature = true, arcane = true, holy = true, shadow = true,
    spell = true, additional = true, extra = true, bonus = true, points = true, point = true, of = true,
    de = true, du = true, des = true, degats = true, feu = true, givre = true, sacre = true, ombre = true,
    physique = true, physiques = true, arcanes = true, supplementaire = true, supplementaires = true,
}

local function Bridge(text)
    if #text > 65 or text:find("[^%a%s']") then return false end
    for word in text:gmatch("[%a']+") do if not schools[word] then return false end end
    return true
end

local function HasHealVerb(text)
    return text:find("%f[%a]heals?%f[%A]") or text:find("%f[%a]healing%f[%A]")
        or text:find("%f[%a]restor[ei]") or text:find("%f[%a]soign")
        or text:find("%f[%a]gueri") or text:find("%f[%a]rend%f[%A]")
end

local joins = {" and ", " or ", " et ", " ou ", " plus "}
local function LocalPrefix(text)
    text = text:match("([^.,;]*)$") or text
    local start = 1
    for _, join in ipairs(joins) do
        local cursor = 1
        while true do
            local first, last = text:find(join, cursor, true)
            if not first then break end
            start, cursor = math.max(start, last + 1), last + 1
        end
    end
    return text:sub(start)
end

local function LocalSuffix(text)
    local last = #text
    for _, join in ipairs(joins) do
        local first = text:find(join, 1, true)
        if first then last = math.min(last, first - 1) end
    end
    return text:sub(1, last)
end

local function Area(text)
    return text:find("all .-enemies") or text:find("each enemy") or text:find("every enemy")
        or text:find("enemies within") or text:find("enemies in ") or text:find("enemies who enter")
        or text:find("all .-targets") or text:find("all .-party members") or text:find("all .-group members")
        or text:find("all .-allies") or text:find("tous les ennemis") or text:find("toutes les cibles")
        or text:find("targets in a cone") or text:find("party members within") or text:find("group members within")
        or text:find("to nearby enemies") or text:find("targets in a %d+ yard")
        or text:find("heals your party") or text:find("members of your party")
        or text:find("up to %d+ enemies") or text:find("up to %d+ targets")
        or text:find("chaque ennemi") or text:find("ennemis dans") or text:find("ennemis qui penetrent")
        or text:find("tous les membres") or text:find("tous les allies") or text:find("cibles dans un cone")
        or text:find("membres du groupe dans") or text:find("membres du groupe a moins de")
        or text:find("soigne votre groupe") or text:find("membres de votre groupe")
        or text:find("ennemis proches") or text:find("cibles dans un rayon")
        or text:find("jusqu'a %d+ ennemis") or text:find("jusqu'a %d+ cibles")
end

local targetWords = {to = true, the = true, a = true, an = true, friendly = true, target = true,
    enemy = true, enemies = true, all = true, nearby = true, party = true, group = true, members = true,
    allies = true, caster = true, la = true, le = true, les = true, cible = true, amie = true, alliee = true,
    ennemi = true, ennemis = true, tous = true, au = true, lanceur = true, de = true, du = true, sort = true}
local function TargetBridge(text)
    if #text == 0 or text:find("[^%a%s]") then return false end
    for word in text:gmatch("%a+") do if not targetWords[word] then return false end end
    return true
end

local function Seconds(text, french)
    local amount, unit = text:match("^%s*(%d[%d%.,]*)%s*(%a+)")
    if not amount then return nil end
    local number = Numeric(amount, french)
    if not number or number <= 0 then return nil end
    if unit == "s" or unit == "sec" or unit == "secs" or unit == "second" or unit == "seconds"
        or unit == "seconde" or unit == "secondes" then return number end
    if unit == "min" or unit == "mins" or unit == "minute" or unit == "minutes" then return Number(number * 60) end
    return nil
end

local function Duration(suffix, french)
    -- Only immediate output-duration phrasing is accepted. A subsequent stun,
    -- slow, aura lifetime or cooldown must not become the damage duration.
    suffix = suffix:gsub("^%s*,%s*", " ")
    local intervalText, rest = suffix:match("^%s*every%s+(.+)$"), nil
    if not intervalText then intervalText = suffix:match("^%s*toutes? les%s+(.+)$") end
    if intervalText then
        local interval = Seconds(intervalText, french)
        rest = intervalText:match("^%d[%d%.,]*%s*%a+%s+for%s+(.+)$")
            or intervalText:match("^%d[%d%.,]*%s*%a+%s+pendant%s+(.+)$")
            or intervalText:match("^%d[%d%.,]*%s*%a+%s+sur%s+(.+)$")
        local duration = rest and Seconds(rest, french)
        if not interval or not duration or interval > duration then return nil, nil, false end
        local ticks = duration / interval
        if math.abs(ticks - math.floor(ticks + 0.5)) > 0.0001 or ticks > 1000 then return nil, nil, false end
        return duration, math.floor(ticks + 0.5), true
    end
    local perSecond = suffix:match("^%s*per second%s+(.*)$") or suffix:match("^%s*par seconde%s+(.*)$")
    if perSecond then
        local restDuration = perSecond:match("^for%s+(.+)$") or perSecond:match("^pendant%s+(.+)$")
        local duration = restDuration and Seconds(restDuration, french)
        if not duration then return nil, nil, false end
        return duration, duration, true
    end
    local total = suffix:match("^%s*over%s+(.+)$") or suffix:match("^%s*en%s+(.+)$")
        or suffix:match("^%s*sur%s+(.+)$") or suffix:match("^%s*pendant%s+(.+)$")
    if total then
        local duration = Seconds(total, french)
        if not duration then return nil, nil, false end
        return duration, 1, true
    end
    for _, connector in ipairs({"over", "en", "sur", "pendant"}) do
        local target, tail = suffix:match("^(.-)%s+" .. connector .. "%s+(.+)$")
        if target and TargetBridge(target) then
            local duration = Seconds(tail, french)
            if not duration then return nil, nil, false end
            return duration, 1, true
        end
    end
    if suffix:find("%f[%a]over%s+%d") or suffix:find("%f[%a]every%s+%d")
        or suffix:find("%f[%a]en%s+%d") or suffix:find("%f[%a]sur%s+%d")
        or suffix:find("%f[%a]pendant%s+%d") or suffix:find("toutes? les%s+%d") then return nil, nil, false end
    -- Unresolved tick counts cannot be treated as one direct hit.
    if suffix:match("^%s*each ") or suffix:match("^%s*par ") or suffix:match("^%s*per ") or suffix:match("^%s*for ")
        or suffix:match("^%s*every ") or suffix:match("^%s*toutes? ") then return nil, nil, false end
    return nil, 1, true
end

function ZP:ParseSpellMetrics(description)
    local text = Normalize(description)
    if not text then return nil end
    for _, pattern in ipairs(forbidden) do if text:find(pattern) then return nil end end
    if text:find("%d%s*%%%s*.-damage") or text:find("%d%s*%%%s*.-degats")
        or text:find("%d%s*%%%s*.-health") or text:find("%d%s*%%%s*.-points de vie") then return nil end
    local locale = GetLocale and GetLocale()
    if locale ~= nil and (not Readable(locale) or (locale ~= "enUS" and locale ~= "enGB" and locale ~= "frFR")) then return nil end
    local french = Readable(locale) and locale == "frFR"
    local numbers = {}
    for first, raw, last in text:gmatch("()(%d[%d%.,]*)()") do
        numbers[#numbers + 1] = {first = first, last = last - 1, value = Numeric(raw, french)}
    end
    local components, consumed, previous, damageWords = {}, {}, nil, {}
    for index, token in ipairs(numbers) do
        if not consumed[index] and token.value then
            local final, value = token.last, token.value
            local nextToken = numbers[index + 1]
            if nextToken then
                local join = text:sub(token.last + 1, nextToken.first - 1)
                if join:match("^%s+to%s+$") or join:match("^%s+a%s+$") or join:match("^%s*%-%s*$") then
                    if not nextToken.value or nextToken.value < value then return nil end
                    value, final = (value + nextToken.value) / 2, nextToken.last
                    consumed[index + 1] = true
                end
            end
            local before = LocalPrefix(text:sub(math.max(1, token.first - 180), token.first - 1))
            local after = text:sub(final + 1)
            local between = previous and text:sub(previous.last + 1, token.first - 1) or ""
            local sameEffect = previous and (before:match("^%s*another%s+$") or before:match("^%s*an?%s+additional%s+$")
                or before:match("^%s*then%s+an?%s+additional%s+$") or before:match("^%s*[%a%s]-supplementaires?%s+$")
                or before:match("^%s*encore%s+$") or (before:match("^%s*$")
                    and (between:find("%f[%a]and%s*$") or between:find("%f[%a]et%s*$"))))
            local kind, metricEnd, damageWord
            local bridge, metric = after:match("^(%s*[%a%s']-)(damage)%f[%A]")
            if metric and Bridge(bridge) then
                kind, metricEnd, damageWord = "damage", #bridge + #metric, final + #bridge + 1
            else
                bridge, metric = after:match("^(%s*[%a%s']-)(degats)%f[%A]")
                if metric and Bridge(bridge) then
                    kind, metricEnd, damageWord = "damage", #bridge + #metric, final + #bridge + 1
                    -- French places the school after 'dégâts'.
                    local school = after:sub(metricEnd + 1):match("^(%s+d[eu]s?%s+[%a]+)")
                    if school and Bridge(school) then metricEnd = metricEnd + #school end
                end
            end
            if not kind then
                local heal = after:match("^(%s*healing)%f[%A]") or after:match("^(%s*points? de soins)%f[%A]")
                if heal then kind, metricEnd = "healing", #heal end
            end
            if not kind and (HasHealVerb(before) or (sameEffect and previous.kind == "healing")) then
                local health = after:match("^(%s*health)%f[%A]")
                    or after:match("^(%s*points? of health)%f[%A]") or after:match("^(%s*points? de vie)%f[%A]")
                if health then kind, metricEnd = "healing", #health
                elseif after:match("^%s*[.,;]") or after:match("^%s*$") or after:match("^%s+over%s+")
                    or after:match("^%s+every%s+") or after:match("^%s+and%s+another%s+")
                    or after:match("^%s+en%s+") or after:match("^%s+sur%s+") then
                    kind, metricEnd = "healing", 0
                end
            end
            if not kind and sameEffect then
                    kind, metricEnd = previous.kind, 0
            end
            if kind then
                -- An amount must be a spell's output, rather than a passive
                -- bonus, damage reduction, received-healing debuff, or cost.
                local prefix = before
                if kind == "damage" and not prefix:find("deal") and not prefix:find("caus")
                    and not prefix:find("inflict") and not prefix:find("burn") and not prefix:find("do[ei]")
                    and not prefix:find("inflig") and not prefix:find("subi") and not prefix:find("suffer") and not prefix:find("brul")
                    and not prefix:find("provoqu") and not prefix:find("damage") and not prefix:find("degats")
                    and not prefix:find("for%s*$") and not sameEffect then
                    return nil
                end
                if prefix:find("cost") or prefix:find("cout") or after:match("^%s*%%") then return nil end
                local suffix = LocalSuffix(after:sub(metricEnd + 1))
                local duration, multiplier, valid = Duration(suffix, french)
                if not valid then return nil end
                local total = Number(value * multiplier)
                if not total or total <= 0 then return nil end
                local area = Area(prefix .. " " .. suffix) ~= nil
                local explicitTarget = suffix:find("%f[%a]to%s+") or suffix:find("%f[%a]a%s+")
                    or suffix:find("%f[%a]you%f[%A]") or suffix:find("%f[%a]yourself%f[%A]")
                if sameEffect and previous.kind == kind and not explicitTarget then area = previous.aoe end
                if not area then
                    local scope = prefix .. " " .. suffix
                    for _, plural in ipairs({"enemies", "targets", "allies", "members", "ennemis", "cibles", "membres"}) do
                        if scope:find("%f[%a]" .. plural .. "%f[%A]") then return nil end
                    end
                end
                local component = {kind = kind, total = total, duration = duration, overtime = duration ~= nil, aoe = area}
                components[#components + 1] = component
                if damageWord then damageWords[damageWord] = true end
                previous = {kind = kind, last = final + metricEnd, aoe = area}
            end
        end
    end
    if #components == 0 or #components > 8 then return nil end
    -- A description with an unparsed damage component must not present a
    -- misleading partial total (for example, a direct hit plus a variable DoT).
    for first, word in text:gmatch("()%f[%a](%a+)%f[%A]") do
        if (word == "damage" or word == "degats") and not damageWords[first] then return nil end
    end
    local healWords, heals = 0, 0
    for _, component in ipairs(components) do if component.kind == "healing" then heals = heals + 1 end end
    for word in text:gmatch("%f[%a](%a+)%f[%A]") do
        if HasHealVerb(word) then healWords = healWords + 1 end
    end
    if healWords > heals then return nil end
    local result = {components = components, overtime = false, hasDirect = false, aoe = false,
        channel = text:find("%f[%a]channel") ~= nil or text:find("canalis") ~= nil}
    local anyArea, anySingle = false, false
    for _, component in ipairs(components) do
        result[component.kind] = (result[component.kind] or 0) + component.total
        if not Number(result[component.kind]) then return nil end
        result.overtime = result.overtime or component.overtime
        result.hasDirect = result.hasDirect or not component.overtime
        if component.duration then result.duration = math.max(result.duration or 0, component.duration) end
        anyArea, anySingle = anyArea or component.aoe, anySingle or not component.aoe
    end
    -- Mixed target shapes require spell-specific semantics; do not multiply a
    -- single-target part by four merely because another part is an area effect.
    if anyArea and anySingle then return nil end
    result.aoe = anyArea
    local cap = text:match("up to (%d+) enemies") or text:match("up to (%d+) targets")
        or text:match("jusqu'a (%d+) ennemis") or text:match("jusqu'a (%d+) cibles")
    if cap then
        cap = Number(tonumber(cap))
        if not cap or cap < 1 or cap > 80 or cap ~= math.floor(cap) then return nil end
        result.aoe, result.aoeTargetCap = true, cap
    end
    return result
end
