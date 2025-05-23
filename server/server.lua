local ratelimit = {}

-- Event handler for database creation
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Create table insert
        local createTable = {
            [[CREATE TABLE IF NOT EXISTS `hamblin_vehicles` (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `discordID` varchar(255) NOT NULL,
            `owner` tinyint(1) NOT NULL COMMENT '0 = trusted, 1 = owner',
            `name` varchar(255) NOT NULL,
            `spawncode` varchar(255) NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY unique_user_entry (discordID, spawncode)
            )]],
        }

        -- Create table if needed
        MySQL.transaction.await(createTable, nil)
    end
end)

-- Add personal vehicle to player
RegisterCommand(Config.SetVehicleOwnerCommand, function(source, args, raw)
    -- Save source
    local src = source

    if #args < 3 then return end
    if IsPlayerAceAllowed(source, "JakeHamblin.AddPrivateVehicle") then
        -- Get arguments
        local discordID = StripSpaces(args[1])
        local spawncode = StripSpaces(args[2])

        -- Remove Discord ID and spawncode from args
        local name = args
        table.remove(name, 1)
        table.remove(name, 1)

        -- Concatenate remaining args (the name) by space
        name = StripSpaces(table.concat(name, " "))

        -- Insert into database
        local id = MySQL.insert.await('INSERT INTO `hamblin_vehicles` (discordID, owner, name, spawncode) VALUES (?, 1, ?, ?) ON DUPLICATE KEY UPDATE discordID = discordID', {discordID, name, spawncode})

        -- Check if insert successful
        if id then
            SendMessage(src, "Private vehicle added")
        else
            SendMessage(src, "Error while adding private vehicle")
        end

        -- Update restricted vehicles for everyone
        TriggerEvent('Hamblin:updateRestrictedVehicles')
    else
        SendMessage(src, "Not allowed to add private vehicles")
    end
end, false)

-- Event to update restricted vehicles for all users on database changes
RegisterNetEvent('Hamblin:updateRestrictedVehicles')
AddEventHandler('Hamblin:updateRestrictedVehicles', function()
    -- Create table for restricted vehicles
    local restrictedVehicles = {}

    -- Get all vehicles in database that are restricted
    local response = MySQL.query.await('SELECT `spawncode` FROM `hamblin_vehicles` WHERE owner = 1')
    if response then
        for i = 1, #response do
            table.insert(restrictedVehicles, response[i].spawncode)
        end
    end

    -- Send updated list to all clients
    TriggerClientEvent("Hamblin:updateRestrictedVehicles", -1, restrictedVehicles)
end)

-- Event to get allowed and trusted vehicles
RegisterNetEvent('Hamblin:getVehicles')
AddEventHandler('Hamblin:getVehicles', function(remoteTrigger)
    if remoteTrigger or (not ratelimit[source] or (ratelimit[source] + 10000) < GetGameTimer()) then
        if not remoteTrigger then
            -- Update rate limit
            ratelimit[source] = GetGameTimer()
        end

        -- Retain triggering user
        local src = remoteTrigger and remoteTrigger or source

        -- Initalize return tables
        local ownedVehicles = {}
        local trustedVehicles = {}
        
        -- Get Discord ID
        local discordID = GetIdentifier(src, "discord"):gsub("discord:", "")

        -- If Discord ID is valid
        if discordID then
            -- Get all vehicles assigned to Discord ID
            local response = MySQL.query.await('SELECT `owner`, `name`, `spawncode` FROM `hamblin_vehicles` WHERE `discordID` = ?', {discordID})
            if response then
                for i = 1, #response do
                    -- If user is owner, add to owned vehicles
                    if response[i].owner then
                        table.insert(ownedVehicles, {name = response[i].name, spawncode = response[i].spawncode})
                    -- If user is trusted, add to trusted vehicles
                    else
                        table.insert(trustedVehicles, {name = response[i].name, spawncode = response[i].spawncode})
                    end
                end
            end

            -- Return vehicles to client
            TriggerClientEvent('Hamblin:postVehicles', src, ownedVehicles, trustedVehicles)
        end
    end
end)

-- Event to add trusted user
RegisterNetEvent('Hamblin:trustVehicle')
AddEventHandler('Hamblin:trustVehicle', function(discordID, name, spawncode)
    -- Save source
    local src = source
    local triggeringDiscordID = GetIdentifier(src, "discord"):gsub("discord:", "")

    if triggeringDiscordID then
        -- Check if triggering user is owner
        local response = MySQL.query.await('SELECT COUNT(*) AS count FROM `hamblin_vehicles` WHERE discordID = ? AND owner = 1 AND spawncode = ?', {triggeringDiscordID, spawncode})

        -- Response valid and count is 1 or greater
        if response and response[1].count >= 1 then
            -- Insert into database
            local id = MySQL.insert.await('INSERT INTO `hamblin_vehicles` (discordID, owner, name, spawncode) VALUES (?, 0, ?, ?) ON DUPLICATE KEY UPDATE discordID = discordID', {discordID, name, spawncode})

            -- Check if insert successful
            if id then
                TriggerClientEvent('Hamblin:trustActionStatus', src, 'trust', true)
            else
                TriggerClientEvent('Hamblin:trustActionStatus', src, 'trust', false)
            end
        else
            TriggerClientEvent('Hamblin:trustActionStatus', src, 'trust', false)
        end

        -- Update restricted vehicles for everyone
        TriggerEvent('Hamblin:updateRestrictedVehicles')

        -- Update allowed vehicles for trusted user
        TriggerEvent('Hamblin:updateAllowedVehicles', discordID)
    end
end)

-- Event to remove trusted user
RegisterNetEvent('Hamblin:untrustVehicle')
AddEventHandler('Hamblin:untrustVehicle', function(discordID, spawncode)
    -- Save source
    local src = source
    local triggeringDiscordID = GetIdentifier(src, "discord"):gsub("discord:", "")

    if triggeringDiscordID then
        -- Check if triggering user is owner
        local response = MySQL.query.await('SELECT COUNT(*) AS count FROM `hamblin_vehicles` WHERE discordID = ? AND owner = 1 AND spawncode = ?', {triggeringDiscordID, spawncode})

        -- Response valid and count is 1 or greater
        if response and response[1].count >= 1 then
            -- Insert into database
            local response = MySQL.query.await('DELETE FROM `hamblin_vehicles` WHERE discordID = ? AND owner = 0 AND spawncode = ?', {discordID, spawncode})

            -- Check if insert successful
            if response then
                TriggerClientEvent('Hamblin:trustActionStatus', src, 'untrust', true)
            else
                TriggerClientEvent('Hamblin:trustActionStatus', src, 'untrust', false)
            end
        else
            TriggerClientEvent('Hamblin:trustActionStatus', src, 'untrust', false)
        end

        -- Update restricted vehicles for everyone
        TriggerEvent('Hamblin:updateRestrictedVehicles')

        -- Update allowed vehicles for untrusted user
        TriggerEvent('Hamblin:updateAllowedVehicles', discordID)
    end
end)

-- Event to update user's trusted vehicles
RegisterNetEvent('Hamblin:updateAllowedVehicles')
AddEventHandler('Hamblin:updateAllowedVehicles', function(discordID)
    for _, v in ipairs(GetPlayers()) do
        local identifiers = GetPlayerIdentifiers(v)

        for _, k in pairs(identifiers) do
            if k == "discord:"..tostring(discordID) then
                TriggerEvent('Hamblin:getVehicles', v)
            end
        end
    end
end)

-- Get's specified identifier from player
function GetIdentifier(src, identifier)
	local identifiers = GetPlayerIdentifiers(src)

	for _, v in pairs(identifiers) do
		if string.sub(v, 1, string.len(identifier..":")) == identifier..":" then
			return v
		end
	end

    return nil
end

-- Function to send chat message
function SendMessage(src, message)
    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 0, 0},
        multiline = true,
        args = {'[Personal Vehicle]', message},
    })
end

-- Function to strip spaces to the left of string
function StripSpaces(str)
    return string.gsub(str, "^%s+", "")
end