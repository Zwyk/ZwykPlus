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

local function ParseBasic(description)
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

-- Keep weapon and seal wording separate from the conservative general parser.
-- These descriptors contain only values actually stated in the tooltip; the
-- runtime resolves the player's current public weapon values when it is shown.
-- Narrow Forever families verified against ElliotWood/Forever 56c11f4. Holy
-- Strike takes the displayed percentage of (normalized weapon + flat amount).
-- Righteousness and Command use explicitly labelled models at runtime, because
-- their native text omits the current per-hit formula or proc frequency.
local holyStrikeIDs = {[678] = true, [679] = true, [680] = true, [1866] = true,
    [2495] = true, [5569] = true, [10332] = true, [10333] = true}
local righteousIDs = {[20154] = true, [21084] = true, [20287] = true, [20288] = true,
    [20289] = true, [20290] = true, [20291] = true, [20292] = true, [20293] = true}
local commandIDs = {[20375] = true, [20915] = true, [20918] = true, [20919] = true, [20920] = true}

local function SpellName(context)
    if not Readable(context) or type(context) ~= "table" then return nil end
    return Normalize(context.spellName)
end

local function IsHolyStrike(context)
    local name = SpellName(context)
    local id = Readable(context) and type(context) == "table" and context.spellID
    return (Number(id) and holyStrikeIDs[id]) or name == "holy strike" or name == "frappe sacree"
end

local function Amount(text, french)
    local low, high, tail = text:match("^%s*(%d[%d%.,]*)%s+to%s+(%d[%d%.,]*)(.*)$")
    if not low then low, high, tail = text:match("^%s*(%d[%d%.,]*)%s+a%s+(%d[%d%.,]*)(.*)$") end
    if not low then low, high, tail = text:match("^%s*(%d[%d%.,]*)%s*%-%s*(%d[%d%.,]*)(.*)$") end
    if low then
        low, high = Numeric(low, french), Numeric(high, french)
        if not low or not high or high < low then return nil end
        return (low + high) / 2, tail
    end
    local raw
    raw, tail = text:match("^%s*(%d[%d%.,]*)(.*)$")
    return raw and Numeric(raw, french), tail
end

local function FlatOutput(amount, kind, suffix)
    if not amount or amount <= 0 then return nil end
    local component = {kind = kind or "damage", total = amount, aoe = false, overtime = false}
    return {[component.kind] = amount, components = {component}, aoe = false, overtime = false, hasDirect = true,
        conditional = suffix or nil}
end

local function DamageTail(text)
    text = text:gsub("^%s+as%s+", " "):gsub("^%s+en%s+", " "):gsub("[%s%p]+$", "")
    local before, after = text:match("^(%s*[%a%s']-)damage(.*)$")
    if before then return Bridge(before) and after == "" end
    before, after = text:match("^(%s*[%a%s']-)degats(.*)$")
    return before and Bridge(before) and Bridge(after)
end

local function Weapon(text, context, french)
    -- Do not apply this route to proc, bleed, retaliation or combo-point text.
    for _, pattern in ipairs({"chance", "probabilite", "each attack", "every attack", "each melee", "chaque attaque",
        "combo", "when ", "lorsqu", "over%s+%d", "every%s+%d", "sur%s+%d", "pendant%s+%d", "reflect", "renvoi"}) do
        if text:find(pattern) then return nil end
    end
    -- An explicit weapon DPS multiplier has no hidden damage or proc formula.
    local dps = text:match("equal to%s+(%d[%d%.,]*)%s+times the damage per second of your main hand weapon")
        or text:match("egal.-(%d[%d%.,]*)%s+fois les degats par seconde de votre arme.-main droite")
    if dps then
        dps = Numeric(dps, french)
        if not dps or dps <= 0 or dps > 100 then return nil end
        local additional = text:match("up to (%d+) additional nearby targets")
            or text:match("jusqu'a (%d+) cibles supplementaires")
        local cap = additional and tonumber(additional) + 1
        if cap and (cap < 1 or cap > 80) then return nil end
        return {components = {{kind = "damage", weaponDPSCoefficient = dps, aoe = cap ~= nil, overtime = false}},
            aoe = cap ~= nil, aoeTargetCap = cap, overtime = false, hasDirect = true, weaponEstimate = true}
    end
    local percent, suffix = text:match("(%d[%d%.,]*)%%%s+weapon damage(.*)$")
    if not percent then percent, suffix = text:match("(%d[%d%.,]*)%%%s+of normal weapon damage(.*)$") end
    if not percent then percent, suffix = text:match("(%d[%d%.,]*)%%%s+of weapon damage(.*)$") end
    if not percent then percent, suffix = text:match("(%d[%d%.,]*)%%%s+normal weapon damage(.*)$") end
    if not percent then percent, suffix = text:match("(%d[%d%.,]*)%%%s+des degats de l'arme(.*)$") end
    if not percent then percent, suffix = text:match("(%d[%d%.,]*)%%%s+des degats de votre arme(.*)$") end
    if not percent then
        if text:find("%%") then return nil end
        suffix = text:match("weapon damage(.*)$") or text:match("degats de l'arme(.*)$")
        if suffix then percent = "100" end
    end
    local coefficient = percent and Numeric(percent, french)
    if not coefficient or coefficient <= 0 or coefficient > 1000 then return nil end
    coefficient = coefficient / 100
    local flat, tail = 0, suffix
    local bonus = suffix:match("^%s+plus%s+an?%s+additional%s+(.+)$")
        or suffix:match("^%s+plus%s+(.+)$")
    if bonus then
        flat, tail = Amount(bonus, french)
        if not flat or flat <= 0 then return nil end
        if not DamageTail(tail)
            and not tail:match("^%s+to the target[%s%p]*$") then return nil end
    elseif not tail:match("^[%s%p]*$") and not tail:match("^%s+to the target[%s%p]*$")
        and not DamageTail(tail) then return nil end
    local holyStrike = IsHolyStrike(context)
    local nativeFlat = flat
    if holyStrike then flat = flat * coefficient end
    local area = Area(text) ~= nil
    return {components = {{kind = "damage", weaponCoefficient = coefficient, flatBonus = flat,
        nativeFlatBonus = nativeFlat, normalizedWeapon = holyStrike and true or "unknown", aoe = area, overtime = false}},
        aoe = area, overtime = false, hasDirect = true, weaponEstimate = true, holyStrike = holyStrike}
end

local function GroundArea(text, context)
    local name = SpellName(context)
    if name ~= "consecration" and not text:find("consecrates the land", 1, true)
        and not text:find("consacre le sol", 1, true) then return nil end
    local first, last, count = text:find("the first (%d+) enemies")
    if not first then first, last, count = text:find("les (%d+) premiers ennemis") end
    local initial = first and text:sub(1, first - 1) or text
    local base = ParseBasic(initial)
    if not base or not base.damage or not base.overtime or not base.aoe then return nil end
    if first then
        count = tonumber(count)
        if not count or count < 1 or count > 80 then return nil end
        local extra = text:sub(last + 1):gsub("will take", "will suffer"):gsub("vont subir", "subissent")
        extra = ParseBasic("all enemies " .. extra)
        if not extra or not extra.damage or not extra.overtime or not extra.aoe or extra.duration ~= base.duration then return nil end
        for _, component in ipairs(extra.components) do
            component.targetCap = count
            base.components[#base.components + 1] = component
        end
        base.damage = base.damage + extra.damage
    end
    base.groundArea = true
    return base
end

local function Seal(text, context, french)
    local name = SpellName(context)
    if not (name and (name:match("^seal of ") or name:match("^sceau de ")))
        and not text:find("only one seal can be active", 1, true) and not text:find("un seul sceau", 1, true) then return nil end
    local start = text:find("unleashing this seal", 1, true) or text:find("liberer l'energie de ce sceau", 1, true)
        or text:find("libere l'energie de ce sceau", 1, true) or text:find("lorsqu'il est libere", 1, true)
    local buff, judgement = start and text:sub(1, start - 1) or text, start and text:sub(start) or nil
    local result = {sections = {{kind = "seal"}, {kind = "judgement"}}}
    local seal, judge = result.sections[1], result.sections[2]
    local durationText = buff:match("for%s+(%d[%d%.,]*%s*%a+)") or buff:match("lasts%s+(%d[%d%.,]*%s*%a+)")
        or buff:match("pendant%s+(%d[%d%.,]*%s*%a+)") or buff:match("dure%s+(%d[%d%.,]*%s*%a+)")
    local duration = durationText and Seconds(durationText, french)
    local amountText = buff:match("each melee attack an additional%s+(.+)$")
        or buff:match("melee attacks to deal an additional%s+(.+)$")
        or buff:match("chaque attaque de melee.-infliger%s+(.+)$")
        or buff:match("attaques de melee.-infliger%s+(.+)$")
        or buff:match("attaques de melee.-inflig%a*%s+(.+)$")
        or buff:match("chaque attaque de melee.-(%d[%d%.,]*.-degats.+)$")
    local procChance = buff:match("(%d[%d%.,]*)%%%s+chance") or buff:match("(%d[%d%.,]*)%%%s+de chances?")
    local ppm = buff:match("(%d[%d%.,]*)%s+procs? per minute") or buff:match("(%d[%d%.,]*)%s+declenchements? par minute")
    procChance, ppm = procChance and Numeric(procChance, french), ppm and Numeric(ppm, french)
    if procChance and procChance > 100 then procChance = nil end
    if ppm and ppm > 1000 then ppm = nil end
    local id = Readable(context) and type(context) == "table" and Number(context.spellID)
    local righteous = id and righteousIDs[id]
    local command = id and commandIDs[id]
    local weaponPercent = command and (buff:match("equal to%s+(%d[%d%.,]*)%%%s+of normal weapon damage")
        or buff:match("egaux? a%s+(%d[%d%.,]*)%%%s+des degats.-arme")
        or buff:match("egal.-(%d[%d%.,]*)%%%s+des degats.-arme"))
    weaponPercent = weaponPercent and Numeric(weaponPercent, french)
    if duration and (righteous or (command and weaponPercent and weaponPercent > 0 and weaponPercent <= 1000)) then
        local component = {kind = "damage", spellID = id,
            perSwing = true, duration = duration, overtime = true, aoe = false}
        if command then
            -- Current Forever sim's beta-log-validated 7 PPM model. This is
            -- labelled as a model, rather than claimed as a native tooltip rate.
            component.weaponCoefficient, component.procsPerMinute, component.holyWeapon = weaponPercent / 100, 7, true
            component.model = "command"
        else component.sealModel = "righteousness" end
        seal.metrics = {duration = duration, overtime = true, aoe = false, components = {component}, modelEstimate = true}
    elseif (buff:find("chance", 1, true) or buff:find("probabilite", 1, true)) and not procChance and not ppm then
        seal.unsupported = "procChance"
    elseif buff:find("slower weapons", 1, true) or buff:find("armes plus lentes", 1, true) then
        -- This wording gives a range covering different weapon speeds, not an
        -- explicit current-weapon formula. Do not average it into a false DPS.
        seal.unsupported = "weaponRange"
    elseif duration and amountText then
        local amount, tail = Amount(amountText, french)
        if amount and tail and (tail:match("^%s+[%a%s]-damage%f[%A]") or tail:match("^%s+[%a%s]-degats%f[%A]")) then
            local component = {kind = "damage", total = amount, perSwing = true, duration = duration,
                overtime = true, aoe = false}
            if procChance then component.procChance = procChance / 100 end
            if ppm then component.procsPerMinute = ppm end
            seal.metrics = {damage = amount, duration = duration, overtime = true, aoe = false, components = {component}}
            seal.metrics.partialEffects = buff:find("absorb", 1, true) ~= nil or buff:find("absorbe", 1, true) ~= nil
        else seal.unsupported = "noDamage" end
    else seal.unsupported = "noDamage" end
    if judgement then
        -- Command states the normal damage first, followed by a separate
        -- stunned/incapacitated amount. Use that native baseline only.
        local conditional = judgement:find("%f[%a]if ") or judgement:find("%f[%a]si ")
        judge.metrics = ParseBasic(judgement)
        local stunned = judgement:find("stunned", 1, true) or judgement:find("incapacitated", 1, true)
            or judgement:find("etourdi", 1, true) or judgement:find("stupifie", 1, true)
        local before = conditional and stunned and judgement:sub(1, conditional - 1)
        local baseline = before and (before:match("caus%a*%s+(.+)$") or before:match("inflig%a*%s+(.+)$")
            or before:match("provoqu%a*%s+(.+)$"))
        if not judge.metrics and baseline then
            local amount, tail = Amount(baseline, french)
            if amount and tail and (tail:match("^%s+[%a%s]-damage%f[%A]") or tail:match("^%s+[%a%s]-degats%f[%A]")) then
                judge.metrics = FlatOutput(amount, "damage", "unstunned")
            end
        end
        if not judge.metrics then judge.unsupported = judgement:find("chance", 1, true) and "procChance"
            or conditional and "conditional" or "noDamage" end
    else judge.unsupported = "noDamage" end
    return result
end

function ZP:ParseSpellMetrics(description, context)
    local text = Normalize(description)
    if not text then return nil end
    local locale = GetLocale and GetLocale()
    if locale ~= nil and (not Readable(locale) or (locale ~= "enUS" and locale ~= "enGB" and locale ~= "frFR")) then return nil end
    local french = locale == "frFR"
    local seal = Seal(text, context, french)
    if seal then return seal end
    local ground = GroundArea(text, context)
    if ground then return ground end
    if text:find("weapon", 1, true) or text:find("arme", 1, true) then return Weapon(text, context, french) end
    return ParseBasic(description)
end
