Config = {}

Config.Placement = {
    maxDistance = 10.0,
    rightOffset = 0.2,
    rotationSpeed = 90.0, -- degrees per second while a rotation key is held
    previewAlpha = 180,
    approachDistance = 1.6,
    arrivalTolerance = 0.9,
    maxDigDistance = 2.5,
    walkTimeout = 8000,
    buryDuration = 20000,
    buryDepthRatio = 0.75,
    buryExtraDepth = 0.1,
}

Config.Stashes = {
    stash_small = {
        label = 'Small Stash',
        tier = 'small',
        model = `prop_coolbox_01`,
        slots = 10,
        maxWeight = 20000,
        buryDuration = 20000,
    },
    stash_medium = {
        label = 'Medium Stash',
        tier = 'medium',
        model = `prop_box_wood05a`,
        slots = 20,
        maxWeight = 50000,
        buryDuration = 40000,
    },
    stash_large = {
        label = 'Large Stash',
        tier = 'large',
        model = `prop_mil_crate_01`,
        slots = 35,
        maxWeight = 100000,
        buryDuration = 60000,
    },
    stash_heavy = {
        label = 'Heavy Stash',
        tier = 'heavy',
        model = `prop_box_wood08a`,
        slots = 50,
        maxWeight = 175000,
        buryDuration = 80000,
    },
}

Config.ShovelItem = 'shovel'

-- GTA surface material hashes that can be dug with a shovel.
-- The current surface hash is shown while placing to make testing easy.
Config.AllowedGroundMaterials = {
    [1333033863] = true,  -- grass
    [-1286696947] = true, -- dry sand
    [-1885547121] = true, -- deep dry sand
    [435688960] = true,   -- wet sand
    [-461750719] = true,  -- compact sand
    [951832588] = true,   -- small gravel
    [2128369009] = true,  -- large gravel
    [-356706482] = true,  -- deep gravel
    [-1942898710] = true, -- dirt / dirt track
    [1109728704] = true,  -- mud
}
