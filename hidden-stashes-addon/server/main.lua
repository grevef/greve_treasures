local activeStashes = {}
local stashSequence = 0

local function registerInventory(row)
    local config = Config.Stashes[row.item_name]
    if not config then
        print(('[yy-hidden-stashes] Skipped unknown stash type %s (database id %s).'):format(row.item_name, row.id))
        return
    end

    exports.ox_inventory:RegisterStash(
        row.inventory_id,
        row.label or config.label,
        config.slots,
        config.maxWeight,
        false
    )

    activeStashes[row.inventory_id] = {
        databaseId = row.id,
        itemName = row.item_name,
    }
end

local function reloadActiveStashes()
    local rows = MySQL.query.await('SELECT * FROM `yy_hidden_stashes`') or {}
    activeStashes = {}

    for i = 1, #rows do
        registerInventory(rows[i])
    end

    print(('[yy-hidden-stashes] Loaded %s persistent stashes.'):format(#rows))
end

local function refreshClients()
    TriggerClientEvent('yy-hidden-stashes:client:reloadStashes', -1)
end

MySQL.ready(reloadActiveStashes)

lib.callback.register('yy-hidden-stashes:server:getStashes', function()
    return MySQL.query.await('SELECT * FROM `yy_hidden_stashes`') or {}
end)

lib.callback.register('yy-hidden-stashes:server:createStash', function(source, itemName, placement)
    local stash = Config.Stashes[itemName]
    if not stash or type(placement) ~= 'table' then return false, 'Invalid stash placement.' end

    local x, y, z = tonumber(placement.x), tonumber(placement.y), tonumber(placement.z)
    local buriedZ, heading = tonumber(placement.buriedZ), tonumber(placement.heading)
    if not x or not y or not z or not buriedZ or not heading then
        return false, 'Invalid stash coordinates.'
    end

    if exports.ox_inventory:Search(source, 'count', itemName) < 1 then
        return false, ('You do not have a %s.'):format(stash.label)
    end

    local removed = exports.ox_inventory:RemoveItem(source, itemName, 1)
    if not removed then return false, 'The stash item could not be removed.' end

    stashSequence = stashSequence + 1
    local inventoryId = ('yy_hidden_stash_%s_%s_%s'):format(source, os.time(), stashSequence)
    local player = exports.qbx_core:GetPlayer(source)
    local citizenId = player and player.PlayerData and player.PlayerData.citizenid or nil

    local databaseId = MySQL.insert.await([[
        INSERT INTO `yy_hidden_stashes`
            (`inventory_id`, `item_name`, `label`, `model`, `owner_citizenid`,
             `x`, `y`, `z`, `buried_z`, `heading`, `state`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'unburied')
    ]], {
        inventoryId, itemName, stash.label, tonumber(stash.model), citizenId,
        x, y, z, buriedZ, heading,
    })

    if not databaseId then
        exports.ox_inventory:AddItem(source, itemName, 1)
        return false, 'The stash could not be saved to the database.'
    end

    local row = {
        id = databaseId,
        inventory_id = inventoryId,
        item_name = itemName,
        label = stash.label,
    }
    registerInventory(row)
    refreshClients()
    return inventoryId
end)

lib.callback.register('yy-hidden-stashes:server:setState', function(source, inventoryId, state)
    if state ~= 'buried' and state ~= 'unburied' then return false end
    if not activeStashes[inventoryId] then return false end

    MySQL.update.await(
        'UPDATE `yy_hidden_stashes` SET `state` = ? WHERE `inventory_id` = ?',
        { state, inventoryId }
    )

    refreshClients()
    return true
end)

lib.callback.register('yy-hidden-stashes:server:pickupStash', function(source, inventoryId)
    local stash = activeStashes[inventoryId]
    if not stash then return false, 'This stash is no longer available.' end

    local items = exports.ox_inventory:GetInventoryItems(inventoryId)
    if items and next(items) then
        return false, 'The stash must be empty before it can be picked up.'
    end

    local added, response = exports.ox_inventory:AddItem(source, stash.itemName, 1)
    if not added then
        return false, response or 'You do not have enough inventory space.'
    end

    local deleted = MySQL.update.await(
        'DELETE FROM `yy_hidden_stashes` WHERE `inventory_id` = ?',
        { inventoryId }
    )

    if not deleted or deleted < 1 then
        exports.ox_inventory:RemoveItem(source, stash.itemName, 1)
        return false, 'The stash could not be removed from the database.'
    end

    exports.ox_inventory:RemoveInventory(inventoryId)
    MySQL.query.await(
        'DELETE FROM `ox_inventory` WHERE `name` = ? AND (`owner` IS NULL OR `owner` = ?)',
        { inventoryId, '' }
    )
    activeStashes[inventoryId] = nil
    refreshClients()
    return true
end)
