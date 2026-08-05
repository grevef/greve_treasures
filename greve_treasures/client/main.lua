local isPlacing = false
local isBusy = false
local previewObject
local placedObjects = {}
local uncoveredStashes = {}
local buriedStashes = {}
local nextBuriedStashId = 0
local registerBuriedStash
local unburyStash
local addUncoveredTarget
local loadPersistentStashes

local function notify(description, notificationType)
    lib.notify({
        description = description,
        type = notificationType or 'inform',
    })
end

local function rotationToDirection(rotation)
    local adjusted = vector3(
        math.rad(rotation.x),
        math.rad(rotation.y),
        math.rad(rotation.z)
    )

    return vector3(
        -math.sin(adjusted.z) * math.abs(math.cos(adjusted.x)),
        math.cos(adjusted.z) * math.abs(math.cos(adjusted.x)),
        math.sin(adjusted.x)
    )
end

local function raycastFromCamera(distance, ignoredEntity)
    local cameraCoords = GetFinalRenderedCamCoord()
    local cameraRotation = GetFinalRenderedCamRot(2)
    local direction = rotationToDirection(cameraRotation)
    local headingRadians = math.rad(cameraRotation.z)
    local cameraRight = vector3(math.cos(headingRadians), math.sin(headingRadians), 0.0)
    local destination = cameraCoords
        + direction * distance
        + cameraRight * Config.Placement.rightOffset
    local handle = StartShapeTestRay(
        cameraCoords.x, cameraCoords.y, cameraCoords.z,
        destination.x, destination.y, destination.z,
        273, ignoredEntity or PlayerPedId(), 7 -- world, objects, and vegetation
    )
    local status, hit, endCoords, surfaceNormal, materialHash

    repeat
        status, hit, endCoords, surfaceNormal, materialHash = GetShapeTestResultIncludingMaterial(handle)
        if status == 1 then Wait(0) end
    until status ~= 1

    if materialHash and materialHash > 2147483647 then
        materialHash = materialHash - 4294967296
    end

    return hit == 1, endCoords, surfaceNormal, materialHash
end

local function loadModel(model)
    if not IsModelInCdimage(model) or not IsModelValid(model) then
        return false
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(model) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end

    return true
end

local function loadAnimationDictionary(dictionary)
    RequestAnimDict(dictionary)
    local timeout = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dictionary) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end

    return true
end

local function hasShovel()
    return (exports.ox_inventory:Search('count', Config.ShovelItem) or 0) > 0
end

local function clearPreview()
    if previewObject and DoesEntityExist(previewObject) then
        DeleteEntity(previewObject)
    end

    previewObject = nil
    isPlacing = false
    lib.hideTextUI()
end

local function isOutside()
    return GetInteriorFromEntity(PlayerPedId()) == 0
end

local function walkToObject(object)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local objectCoords = GetEntityCoords(object)
    local directionToPlayer = vector3(
        playerCoords.x - objectCoords.x,
        playerCoords.y - objectCoords.y,
        0.0
    )
    local directionLength = math.sqrt(
        directionToPlayer.x * directionToPlayer.x
        + directionToPlayer.y * directionToPlayer.y
    )

    if directionLength < 0.01 then
        directionToPlayer = vector3(0.0, -1.0, 0.0)
        directionLength = 1.0
    end

    local approachCoords = vector3(
        objectCoords.x + (directionToPlayer.x / directionLength) * Config.Placement.approachDistance,
        objectCoords.y + (directionToPlayer.y / directionLength) * Config.Placement.approachDistance,
        objectCoords.z
    )
    local faceHeading = GetHeadingFromVector_2d(
        objectCoords.x - approachCoords.x,
        objectCoords.y - approachCoords.y
    )

    if #(playerCoords - approachCoords) > Config.Placement.arrivalTolerance then
        TaskGoStraightToCoord(
            playerPed,
            approachCoords.x, approachCoords.y, approachCoords.z,
            1.0,
            Config.Placement.walkTimeout,
            faceHeading,
            0.1
        )

        local timeout = GetGameTimer() + Config.Placement.walkTimeout
        repeat
            Wait(100)
            playerCoords = GetEntityCoords(playerPed)
        until #(playerCoords - approachCoords) <= Config.Placement.arrivalTolerance
            or #(playerCoords - objectCoords) <= Config.Placement.maxDigDistance
            or GetGameTimer() >= timeout

    end

    ClearPedTasks(playerPed)
    playerCoords = GetEntityCoords(playerPed)
    SetEntityHeading(playerPed, GetHeadingFromVector_2d(
        objectCoords.x - playerCoords.x,
        objectCoords.y - playerCoords.y
    ))
    Wait(250)
    return true
end

local function buryObject(object, stashLabel, stashModel, itemName, inventoryId)
    if not object or not DoesEntityExist(object) then return false end

    isBusy = true
    local stashConfig = Config.Stashes[itemName]
    local buryDuration = stashConfig and stashConfig.buryDuration or Config.Placement.buryDuration

    walkToObject(object)

    local playerPed = PlayerPedId()
    local animationDictionary = 'random@burial'
    local animationClip = 'a_burial'
    local shovelModel = `prop_tool_shovel`

    local animationLoaded = loadAnimationDictionary(animationDictionary)
    local shovelLoaded = loadModel(shovelModel)

    local shovelObject
    if shovelLoaded then
        shovelObject = CreateObject(shovelModel, 0.0, 0.0, 0.0, false, false, false)
        AttachEntityToEntity(
            shovelObject,
            playerPed,
            GetPedBoneIndex(playerPed, 28422),
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            true, true, false, true, 1, true
        )
    end

    if animationLoaded then
        TaskPlayAnim(
            playerPed,
            animationDictionary,
            animationClip,
            3.0, -3.0,
            buryDuration,
            1,
            0.0,
            false, false, false
        )
    end

    local startCoords = GetEntityCoords(object)
    local stashHeading = GetEntityHeading(object)
    local minDimension, maxDimension = GetModelDimensions(GetEntityModel(object))
    local objectHeight = math.max(0.25, maxDimension.z - minDimension.z)
    local endCoords = vector3(
        startCoords.x,
        startCoords.y,
        startCoords.z
            - objectHeight * Config.Placement.buryDepthRatio
            - Config.Placement.buryExtraDepth
    )
    local startedAt = GetGameTimer()
    local burying = true

    SetEntityCollision(object, false, false)

    CreateThread(function()
        while burying and DoesEntityExist(object) do
            local elapsed = GetGameTimer() - startedAt
            local progress = math.min(elapsed / buryDuration, 1.0)
            local z = startCoords.z + (endCoords.z - startCoords.z) * progress

            SetEntityCoordsNoOffset(object, startCoords.x, startCoords.y, z, false, false, false)
            Wait(0)
        end
    end)

    local completed = lib.progressCircle({
        duration = buryDuration,
        position = 'bottom',
        label = ('Burying %s'):format(stashLabel),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
            sprint = true,
        },
    })

    burying = false
    Wait(0) -- let the sinking thread stop before setting the final position
    if animationLoaded then
        StopAnimTask(playerPed, animationDictionary, animationClip, 1.0)
        RemoveAnimDict(animationDictionary)
    end

    if shovelObject and DoesEntityExist(shovelObject) then
        DeleteEntity(shovelObject)
    end
    if shovelLoaded then SetModelAsNoLongerNeeded(shovelModel) end

    if completed then
        if DoesEntityExist(object) then
            SetEntityCoordsNoOffset(object, endCoords.x, endCoords.y, endCoords.z, false, false, false)
            Wait(100)
            DeleteEntity(object)
        end

        registerBuriedStash({
            label = stashLabel,
            model = stashModel,
            coords = startCoords,
            buriedCoords = endCoords,
            heading = stashHeading,
            itemName = itemName,
            inventoryId = inventoryId,
        })

        lib.callback.await('greve-treasures:server:setState', false, inventoryId, 'buried')
        notify(('%s buried successfully.'):format(stashLabel), 'success')
    else
        if DoesEntityExist(object) then
            SetEntityCoordsNoOffset(object, startCoords.x, startCoords.y, startCoords.z, false, false, false)
            SetEntityHeading(object, stashHeading)
            SetEntityCollision(object, true, true)
            FreezeEntityPosition(object, true)
            ResetEntityAlpha(object)
            addUncoveredTarget(object, {
                label = stashLabel,
                model = stashModel,
                coords = startCoords,
                buriedCoords = endCoords,
                heading = stashHeading,
                itemName = itemName,
                inventoryId = inventoryId,
            })
        end
        notify('Burying cancelled.', 'error')
    end

    isBusy = false
    return completed == true
end

unburyStash = function(stashId)
    local stash = buriedStashes[stashId]
    if not stash or isBusy then return end

    if not hasShovel() then
        return notify('You need a shovel to uncover this stash.', 'error')
    end

    if not loadModel(stash.model) then
        return notify('The stash model could not be loaded.', 'error')
    end

    isBusy = true

    local object = CreateObjectNoOffset(
        stash.model,
        stash.buriedCoords.x, stash.buriedCoords.y, stash.buriedCoords.z,
        false, false, false
    )

    if not object or object == 0 then
        isBusy = false
        return notify('The stash could not be uncovered.', 'error')
    end

    SetEntityHeading(object, stash.heading)
    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)

    local playerPed = PlayerPedId()
    TaskTurnPedToFaceCoord(playerPed, stash.coords.x, stash.coords.y, stash.coords.z, 750)
    Wait(750)

    local animationDictionary = 'random@burial'
    local animationClip = 'a_burial'
    local shovelModel = `prop_tool_shovel`
    local stashConfig = Config.Stashes[stash.itemName]
    local buryDuration = stashConfig and stashConfig.buryDuration or Config.Placement.buryDuration
    local animationLoaded = loadAnimationDictionary(animationDictionary)
    local shovelLoaded = loadModel(shovelModel)
    local shovelObject

    if shovelLoaded then
        shovelObject = CreateObject(shovelModel, 0.0, 0.0, 0.0, false, false, false)
        AttachEntityToEntity(
            shovelObject,
            playerPed,
            GetPedBoneIndex(playerPed, 28422),
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            true, true, false, true, 1, true
        )
    end

    if animationLoaded then
        TaskPlayAnim(
            playerPed,
            animationDictionary,
            animationClip,
            3.0, -3.0,
            buryDuration,
            1,
            0.0,
            false, false, false
        )
    end

    local startedAt = GetGameTimer()
    local revealing = true

    CreateThread(function()
        while revealing and DoesEntityExist(object) do
            local elapsed = GetGameTimer() - startedAt
            local progress = math.min(elapsed / buryDuration, 1.0)
            local z = stash.buriedCoords.z + (stash.coords.z - stash.buriedCoords.z) * progress

            SetEntityCoordsNoOffset(object, stash.coords.x, stash.coords.y, z, false, false, false)
            Wait(0)
        end
    end)

    local completed = lib.progressCircle({
        duration = buryDuration,
        position = 'bottom',
        label = ('Uncovering %s'):format(stash.label),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
            sprint = true,
        },
    })

    revealing = false
    Wait(0)

    if animationLoaded then
        StopAnimTask(playerPed, animationDictionary, animationClip, 1.0)
        RemoveAnimDict(animationDictionary)
    end

    if shovelObject and DoesEntityExist(shovelObject) then DeleteEntity(shovelObject) end
    if shovelLoaded then SetModelAsNoLongerNeeded(shovelModel) end

    if not completed then
        if DoesEntityExist(object) then DeleteEntity(object) end
        SetModelAsNoLongerNeeded(stash.model)
        isBusy = false
        notify('Uncovering cancelled.', 'error')
        return
    end

    exports.ox_target:removeZone(stash.zoneId)
    buriedStashes[stashId] = nil
    SetEntityCoordsNoOffset(object, stash.coords.x, stash.coords.y, stash.coords.z, false, false, false)
    SetEntityHeading(object, stash.heading)
    SetEntityCollision(object, true, true)
    FreezeEntityPosition(object, true)
    ResetEntityAlpha(object)
    placedObjects[#placedObjects + 1] = object
    addUncoveredTarget(object, stash)
    lib.callback.await('greve-treasures:server:setState', false, stash.inventoryId, 'unburied')
    notify(('%s uncovered.'):format(stash.label), 'success')

    SetModelAsNoLongerNeeded(stash.model)
    isBusy = false
end

addUncoveredTarget = function(object, stash)
    local openOption = ('yy_hidden_stash_open_%s'):format(stash.inventoryId)
    local pickupOption = ('yy_hidden_stash_pickup_%s'):format(stash.inventoryId)
    local reburyOption = ('yy_hidden_stash_rebury_%s'):format(stash.inventoryId)
    uncoveredStashes[object] = stash

    exports.ox_target:addLocalEntity(object, {
        {
            name = openOption,
            icon = 'fa-solid fa-box-open',
            label = 'Open Stash',
            distance = 2.0,
            canInteract = function()
                return not isBusy
            end,
            onSelect = function()
                exports.ox_inventory:openInventory('stash', stash.inventoryId)
            end,
        },
        {
            name = pickupOption,
            icon = 'fa-solid fa-hand',
            label = 'Pick Up Stash',
            distance = 2.0,
            canInteract = function()
                return not isBusy
            end,
            onSelect = function()
                if isBusy then return end
                isBusy = true

                local pickedUp, errorMessage = lib.callback.await(
                    'greve-treasures:server:pickupStash',
                    false,
                    stash.inventoryId
                )

                if pickedUp then
                    exports.ox_target:removeLocalEntity(object, { openOption, pickupOption, reburyOption })
                    uncoveredStashes[object] = nil
                    if DoesEntityExist(object) then DeleteEntity(object) end
                    notify(('%s picked up.'):format(stash.label), 'success')
                else
                    notify(errorMessage or 'The stash could not be picked up.', 'error')
                end

                isBusy = false
            end,
        },
        {
            name = reburyOption,
            icon = 'fa-solid fa-arrow-down',
            label = 'Bury Stash',
            distance = 2.0,
            canInteract = function()
                return not isBusy and hasShovel()
            end,
            onSelect = function()
                if isBusy or not DoesEntityExist(object) then return end

                local coords = GetEntityCoords(object)
                local heading = GetEntityHeading(object)
                exports.ox_target:removeLocalEntity(object, { openOption, pickupOption, reburyOption })
                uncoveredStashes[object] = nil

                local burialRan, burialError = pcall(
                    buryObject,
                    object,
                    stash.label,
                    stash.model,
                    stash.itemName,
                    stash.inventoryId
                )

                if not burialRan then
                    if DoesEntityExist(object) then DeleteEntity(object) end

                    local minDimension, maxDimension = GetModelDimensions(stash.model)
                    local objectHeight = math.max(0.25, maxDimension.z - minDimension.z)
                    registerBuriedStash({
                        label = stash.label,
                        model = stash.model,
                        coords = coords,
                        buriedCoords = vector3(
                            coords.x,
                            coords.y,
                            coords.z
                                - objectHeight * Config.Placement.buryDepthRatio
                                - Config.Placement.buryExtraDepth
                        ),
                        heading = heading,
                        itemName = stash.itemName,
                        inventoryId = stash.inventoryId,
                    })

                    ClearPedTasks(PlayerPedId())
                    isBusy = false
                    notify(('%s reburied despite an animation error.'):format(stash.label), 'success')
                    print(('[greve-treasures] Rebury error: %s'):format(burialError))
                end
            end,
        },
    })
end

registerBuriedStash = function(stash)
    nextBuriedStashId = nextBuriedStashId + 1
    local stashId = nextBuriedStashId

    stash.zoneId = exports.ox_target:addSphereZone({
        coords = stash.coords,
        radius = 1.5,
        debug = false,
        options = {
            {
                name = ('yy_hidden_stash_unbury_%s'):format(stashId),
                icon = 'fa-solid fa-arrow-up',
                label = 'Unbury Stash',
                distance = 2.0,
                canInteract = function()
                    return not isBusy and hasShovel()
                end,
                onSelect = function()
                    local ran, unburyError = pcall(unburyStash, stashId)
                    if not ran then
                        isBusy = false
                        print(('[greve-treasures] Unbury error: %s'):format(unburyError))
                        notify('The stash could not be uncovered.', 'error')
                    end
                end,
            },
        },
    })

    buriedStashes[stashId] = stash
end

local function clearLoadedStashes()
    for _, stash in pairs(buriedStashes) do
        if stash.zoneId then exports.ox_target:removeZone(stash.zoneId) end
    end
    buriedStashes = {}

    for object, stash in pairs(uncoveredStashes) do
        if DoesEntityExist(object) then
            exports.ox_target:removeLocalEntity(object, {
                ('yy_hidden_stash_open_%s'):format(stash.inventoryId),
                ('yy_hidden_stash_pickup_%s'):format(stash.inventoryId),
                ('yy_hidden_stash_rebury_%s'):format(stash.inventoryId),
            })
            DeleteEntity(object)
        end
    end
    uncoveredStashes = {}
    placedObjects = {}
end

loadPersistentStashes = function()
    while isBusy or isPlacing do Wait(250) end

    local rows = lib.callback.await('greve-treasures:server:getStashes', false) or {}
    clearLoadedStashes()

    for i = 1, #rows do
        local row = rows[i]
        local model = tonumber(row.model)
        local stash = {
            databaseId = tonumber(row.id),
            inventoryId = row.inventory_id,
            itemName = row.item_name,
            label = row.label,
            model = model,
            coords = vector3(tonumber(row.x), tonumber(row.y), tonumber(row.z)),
            buriedCoords = vector3(tonumber(row.x), tonumber(row.y), tonumber(row.buried_z)),
            heading = tonumber(row.heading) or 0.0,
        }

        if row.state == 'buried' then
            registerBuriedStash(stash)
        elseif loadModel(model) then
            local object = CreateObjectNoOffset(
                model,
                stash.coords.x, stash.coords.y, stash.coords.z,
                false, false, false
            )

            if object and object ~= 0 then
                SetEntityHeading(object, stash.heading)
                PlaceObjectOnGroundProperly(object)
                SetEntityCollision(object, true, true)
                FreezeEntityPosition(object, true)
                placedObjects[#placedObjects + 1] = object
                addUncoveredTarget(object, stash)
            end

            SetModelAsNoLongerNeeded(model)
        end
    end
end

RegisterNetEvent('greve-treasures:client:reloadStashes', function()
    CreateThread(loadPersistentStashes)
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(1000)
    loadPersistentStashes()
end)

local function startPlacement(itemName)
    if isPlacing or isBusy then
        return notify('You are already placing or burying a stash.', 'error')
    end

    local stash = Config.Stashes[itemName]
    if not stash then
        return notify('This is not a configured stash item.', 'error')
    end

    if not isOutside() then
        return notify('Stashes can only be placed outdoors.', 'error')
    end

    if not loadModel(stash.model) then
        return notify(('Could not load the model for %s.'):format(stash.label), 'error')
    end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    previewObject = CreateObjectNoOffset(stash.model, playerCoords.x, playerCoords.y, playerCoords.z, false, false, false)

    if not previewObject or previewObject == 0 then
        SetModelAsNoLongerNeeded(stash.model)
        return notify('Could not create the placement preview.', 'error')
    end

    isPlacing = true
    SetEntityAlpha(previewObject, Config.Placement.previewAlpha, false)
    SetEntityCollision(previewObject, true, true)
    FreezeEntityPosition(previewObject, true)

    local heading = GetEntityHeading(playerPed)
    lib.showTextUI('[Q/E or LEFT/RIGHT] Rotate  [ENTER] Place  [X] Cancel')

    CreateThread(function()
        while isPlacing and DoesEntityExist(previewObject) do
            DisableControlAction(0, 38, true)  -- E
            DisableControlAction(0, 44, true)  -- Q
            DisableControlAction(0, 51, true)  -- E alternate
            DisableControlAction(0, 73, true)  -- X
            DisableControlAction(0, 174, true) -- Left arrow
            DisableControlAction(0, 175, true) -- Right arrow

            local rotationAmount = Config.Placement.rotationSpeed * GetFrameTime()
            if IsDisabledControlPressed(0, 44) or IsDisabledControlPressed(0, 174) then
                heading = heading - rotationAmount
            elseif IsDisabledControlPressed(0, 38) or IsDisabledControlPressed(0, 51)
                or IsDisabledControlPressed(0, 175) then
                heading = heading + rotationAmount
            end

            local hit, coords, _, materialHash = raycastFromCamera(Config.Placement.maxDistance, previewObject)
            local validGround = hit
                and Config.AllowedGroundMaterials[materialHash] == true
                and isOutside()
                and #(GetEntityCoords(playerPed) - coords) <= Config.Placement.maxDistance

            if hit then
                SetEntityCoordsNoOffset(previewObject, coords.x, coords.y, coords.z, false, false, false)
                PlaceObjectOnGroundProperly(previewObject)
                SetEntityRotation(previewObject, 0.0, 0.0, heading, 2, true)

                DrawMarker(
                    1, coords.x, coords.y, coords.z + 0.02,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.55, 0.55, 0.06,
                    validGround and 60 or 220,
                    validGround and 200 or 50,
                    50, 150,
                    false, false, 2, false, nil, nil, false
                )
            end

            if IsControlJustPressed(0, 191) then -- Enter
                if not validGround then
                    notify('Move the stash onto dirt, grass, sand, or gravel.', 'error')
                else
                    local finalCoords = GetEntityCoords(previewObject)
                    local finalHeading = GetEntityHeading(previewObject)
                    local minDimension, maxDimension = GetModelDimensions(stash.model)
                    local objectHeight = math.max(0.25, maxDimension.z - minDimension.z)
                    local buriedZ = finalCoords.z
                        - objectHeight * Config.Placement.buryDepthRatio
                        - Config.Placement.buryExtraDepth
                    local inventoryId, createError = lib.callback.await(
                        'greve-treasures:server:createStash',
                        false,
                        itemName,
                        {
                            x = finalCoords.x,
                            y = finalCoords.y,
                            z = finalCoords.z,
                            buriedZ = buriedZ,
                            heading = finalHeading,
                        }
                    )

                    if not inventoryId then
                        notify(createError or 'The stash could not be created.', 'error')
                        goto continuePlacement
                    end

                    local placedObject = CreateObjectNoOffset(
                        stash.model,
                        finalCoords.x, finalCoords.y, finalCoords.z,
                        false, false, false
                    )

                    PlaceObjectOnGroundProperly(placedObject)
                    SetEntityHeading(placedObject, finalHeading)
                    FreezeEntityPosition(placedObject, true)
                    placedObjects[#placedObjects + 1] = placedObject

                    clearPreview()
                    SetModelAsNoLongerNeeded(stash.model)
                    addUncoveredTarget(placedObject, {
                        label = stash.label,
                        model = stash.model,
                        coords = finalCoords,
                        buriedCoords = vector3(finalCoords.x, finalCoords.y, buriedZ),
                        heading = finalHeading,
                        itemName = itemName,
                        inventoryId = inventoryId,
                    })
                    notify(('%s placed. Use its target options to bury it.'):format(stash.label), 'success')
                end
            elseif IsDisabledControlJustPressed(0, 73) then -- X
                clearPreview()
                SetModelAsNoLongerNeeded(stash.model)
                notify('Placement cancelled.')
            end

            ::continuePlacement::
            Wait(0)
        end
    end)
end

local function useStash(data)
    startPlacement(data and data.name)
end

exports('useStash', useStash)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    clearPreview()
    for i = 1, #placedObjects do
        if DoesEntityExist(placedObjects[i]) then
            DeleteEntity(placedObjects[i])
        end
    end


    for _, stash in pairs(buriedStashes) do
        if stash.zoneId then exports.ox_target:removeZone(stash.zoneId) end
    end
end)
