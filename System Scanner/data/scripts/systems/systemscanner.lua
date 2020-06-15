-- System Scanner by MassCraxx 
-- v1.3
package.path = package.path .. ";data/scripts/systems/?.lua"
package.path = package.path .. ";data/scripts/lib/?.lua"
include ("basesystem")
include ("utility")
include ("randomext")

-- optimization so that energy requirement doesn't have to be read every frame
FixedEnergyRequirement = true

-- enables the scanner on any target
local scanAll = false
-- minimum block volume of systems
local minVolume = 2
-- maximum indicator rendered per system
local maxTargets = 15

local entityId
local callbackRegistered = false

local indicators = {}
local currentTarget
local currentTargetID

local level
local range = -1

local function sortSystems(a, b)
    return a.volume > b.volume
end

function getBonuses(seed, rarity, permanent)
    math.randomseed(seed)

    local highlightRange = 100 + (math.random() * 300) * rarity.value

    if rarity.value >= RarityType.Rare then
        highlightRange = 400 + math.random() * 100
    end

    if rarity.value >= RarityType.Exceptional then
        highlightRange = 900 + math.random() * 250
    end

    if rarity.value >= RarityType.Exotic then
        highlightRange = 1500 + math.random() * 500
    end

    if rarity.value > RarityType.Exotic then
        highlightRange = math.huge
    end
	
	if highlightRange < 50 then
		highlightRange = 50
	end

    return rarity.value, highlightRange
end

function onInstalled(seed, rarity, permanent)
    level, range = getBonuses(seed, rarity, permanent)
end

function onUninstalled(seed, rarity, permanent)
end

function onDelete()
end

if(onClient()) then
local inRange = false

function onInstalled(seed, rarity, permanent)
    level, range = getBonuses(seed, rarity, permanent)

    if onClient() then
        Player():registerCallback("onPreRenderHud", "onPreRenderHud")
    end
end

function onUninstalled(seed, rarity, permanent)
    if currentTarget then
        currentTarget:unregisterCallback("onBreak", "onBreak")
        --currentTarget:unregisterCallback("onBlockDestroyed", "onBlockDestroyed")
    end

    if onClient() then
        Player():unregisterCallback("onPreRenderHud", "onPreRenderHud")
        
        if entityId then
            removeShipProblem("SystemScanner", entityId)
            entityId = nil
        end
    end
end

function onDelete()
end

function onPreRenderHud()
    -- Change scan target inside ship with scanner
    local playerCraft = Sector():getEntity(Player().craftIndex)
    if playerCraft and playerCraft:hasScript("systemscanner.lua") then
        local selected = Player().craft.selectedObject
        -- Check if target changed
        if currentTarget ~= selected and (currentTarget == nil or selected == nil or currentTarget.id ~= selected.id) then
            -- cleanup old target
            if currentTarget and callbackRegistered then
                -- unregister old callback if entity is still in sector
                local oldEntity = Sector():getEntity(currentTargetID)
                if oldEntity then
                    --print("Unregister callbacks...")
                    --currentTarget:unregisterCallback("onBlockDestroyed", "onBlockDestroyed")
                    oldEntity:unregisterCallback("onBreak", "onBreak")
                end
                callbackRegistered = false
            end

            -- set new target and parse
            currentTarget = selected
            if selected then
                currentTargetID = selected.id
            else
                currentTargetID = nil
            end
            findSystems(selected)

            -- if something found and wreckage register
            if currentTarget and (scanAll or currentTarget.type == EntityType.Wreckage) and #indicators > 0 then
                -- register new callback
                --print("Register callbacks...")
                --currentTarget:registerCallback("onBlockDestroyed", "onBlockDestroyed")
                currentTarget:registerCallback("onBreak", "onBreak")
                callbackRegistered = true
            end
        end
    end
    
    -- check range
    if currentTarget then
        local ship = Player().craft
        if ship then
            local distance = distance2(currentTarget.translationf, ship.translationf)

            if distance <= range * range then
                inRange = true
            else
                inRange = false
            end
        end
    end

    -- check ship problem
    if #indicators > 0 and inRange then
        if not entityId then
            if  Player().craftIndex == Entity().index then
                entityId = Entity().id
                addShipProblem("SystemScanner", entityId, "Valuable systems detected on target!"%_t, "data/textures/icons/circuitry.png", ColorRGB(0, 1, 1))
            end
        end
    else
        if entityId then
            removeShipProblem("SystemScanner", entityId)
            entityId = nil
        end
    end

    -- check render indicator highlights
    local counter = {}
    if(inRange and level >= RarityType.Rare) then
        for i, entry in pairs(indicators) do
            if entry.parent ~= nil then
                local block = entry.block
                if block ~= nil then
                    -- init counter
                    if counter[block.blockIndex] == nil then
                        counter[block.blockIndex] = 0
                    end

                    -- render if maxTargets for system not reached
                    if maxTargets == nil or (counter[block.blockIndex] < maxTargets) then
                        renderIndicator(entry.parent, entry.offset, block, entry.volume)
                    end

                    -- increase system indicator counter
                    counter[block.blockIndex] = counter[block.blockIndex] + 1
                else
                    -- if block gone remove entry (will never happen since block is a copy not a reference)
                    table.remove(indicators,i)
                    counter[block.blockIndex] = counter[block.blockIndex] - 1
                end
            else
                indicators = {}
                return
            end
        end
    end
end

-- parse entity for valuable blocks
function findSystems(entity)
    indicators = {}

    if entity and (scanAll or entity.type == EntityType.Wreckage) then
        local plan = entity:getFullPlanCopy()
        local blocks = {plan:getBlockIndices()}

        for i=1,#blocks do
            local block = plan:getBlock(blocks[i])
            -- 5: Cargo 52:Generator 50:Shield 55:Hyperspace Core
            if block and (block.blockIndex == 5
            or (level >= RarityType.Rare and block.blockIndex == 52)
            or (level >= RarityType.Exceptional and block.blockIndex == 50) 
            or (level >= RarityType.Exotic and block.blockIndex == 55)) then
                local box = block.box
                if box then
                    -- Only add big blocks
                    local volume = box.size.x * box.size.y * box.size.z
                    if volume >= minVolume then
                        -- Create entry
                        local center = block.box.center

                        table.insert(indicators, {
                            block = block,
                            parent = entity,
                            offset = center,
                            volume = volume})
                    end
                end
            end
        end
        table.sort(indicators, sortSystems)
    end
end

function renderIndicator(parentEntity, offset, block, volume)
    local parentPos = parentEntity.position
    local offsetRotVec = (parentPos.right * offset.x) + (parentPos.up * offset.y) + (parentPos.look * offset.z)
    local offsetMatrix = Matrix()

    offsetMatrix.pos = parentPos.pos + offsetRotVec
    offsetMatrix.position = parentPos.position + offsetRotVec
    offsetMatrix.translation = parentPos.translation + offsetRotVec

    local color = ColorRGB(1,1,1)
    if block.blockIndex == 50 then
        -- Shield gen blue
        color = ColorRGB(0,0,1)
    elseif block.blockIndex == 52 then
        -- Generator core yellow
        color = ColorRGB(1,1,0)
    elseif block.blockIndex == 55 then
        -- Hyperspace core red
        color = ColorRGB(1,0,0)
    elseif block.blockIndex == 5 then
        -- Cargo green
        color = ColorRGB(0,1,0)
    end

    local size = math.sqrt(volume) + 3

    Sector():createGlow(offsetMatrix.position, size, color)
end

-- Will not be called if wreckage breaks, so reparsing every break
-- WRONG DOC: damageType seems to be index...
--function onBlockDestroyed(objectIndex, damageType, index)
--    local blockIndex = damageType
--
--    for i, entry in pairs(indicators) do
--        if entry.block.index == blockIndex then
--            table.remove(indicators,i)
--        end
--    end
--end

function onBreak(objectIndex, ...)
    --print("onBreak")
    if currentTarget and currentTarget.id == objectIndex then
        findSystems(currentTarget)
    end
end
end

function printVec(vec)
    if vec then
        return "X:"..vec.x.." Y:"..vec.y.." Z:"..vec.z
    else
        return "null"
    end
end

function getName(seed, rarity)
    local name = "System Scanner"
    if rarity == Rarity(RarityType.Legendary) then
        name = name.." of Doom"
    end
    return name
end

function getIcon(seed, rarity)
    return "data/textures/icons/treasure-map.png"
end

function getEnergy(seed, rarity, permanent)
    local level, range = getBonuses(seed, rarity)
	range = math.min(range, 1000) * 0.0005 * level * 1000 * 1000 * 1000
	
	if range < 0 then
		range = 0
	end
	
    return range
end

function getPrice(seed, rarity)
    local level, range = getBonuses(seed, rarity)
    range = math.min(range, 1000);

    local price = range * 25 + (rarity.value + 1) * 7500;

    return price * 2.5 ^ rarity.value
end

function getTooltipLines(seed, rarity, permanent)
    local texts = {}

    local level, range = getBonuses(seed, rarity)

    if range and range > 0 then
        local rangeText = "Sector"%_t
        if range < math.huge then
            rangeText = string.format("%g", round(range / 100, 2))
        end

        table.insert(texts, {ltext = "Detection Range"%_t, rtext = rangeText, icon = "data/textures/icons/rss.png"})

        if level and level >= RarityType.Rare then
            table.insert(texts, {ltext = "Highlight Range"%_t, rtext = rangeText, icon = "data/textures/icons/rss.png"})
        end
    end

    return texts
end

function getDescriptionLines(seed, rarity, permanent)
    local texts = {}

    local level, range = getBonuses(seed, rarity)
    
    table.insert(texts, {ltext = "Detects valuable systems in wrecks."%_t, rtext = "", icon = ""})

    if level and level >= RarityType.Uncommon then
        table.insert(texts, {ltext = "Highlights cargo bays in green."%_t, rtext = "", icon = ""})
    end

    if level and level >= RarityType.Rare then
        table.insert(texts, {ltext = "Highlights generators in yellow."%_t, rtext = "", icon = ""})
    end

    if level and level >= RarityType.Exceptional then
        table.insert(texts, {ltext = "Highlights shield generators in blue."%_t, rtext = "", icon = ""})
    end

    if level and level >= RarityType.Exotic then
        table.insert(texts, {ltext = "Highlights hyperspace cores in red."%_t, rtext = "", icon = ""})
    end

    return texts
end