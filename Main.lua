-- Utility for syncing actions and tools across clients
local utility = {}

-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local syncData = ReplicatedStorage:WaitForChild("SyncData") or Instance.new("Folder")
syncData.Name = "SyncData"
syncData.Parent = ReplicatedStorage

-- Create BindableEvents for synchronization
local syncBindable = Instance.new("BindableEvent")
syncBindable.Name = "SyncBindable"
syncBindable.Parent = ReplicatedStorage

-- SyncCode event to synchronize code execution across all clients
utility.SyncCode = Instance.new("BindableEvent")
utility.SyncCode.Name = "SyncCode"
utility.SyncCode.Parent = ReplicatedStorage

-- JoinSync event to handle players running the utility and sync their state
utility.JoinSync = Instance.new("BindableEvent")
utility.JoinSync.Name = "JoinSync"
utility.JoinSync.Parent = ReplicatedStorage

-- A table to store all variables and properties created by the code
local allCreatedVariables = {}
local allExecutedCode = {}

-- A table to track objects and their properties for dynamic syncing
local objectTrackers = {}

-- Sync a piece of code to other players and return the created variables
function utility.Sync(code, Player)
    -- Create a table to store the variables created by the code
    local createdVariables = {}

    -- Save the environment before running the code
    local oldEnv = getfenv(0)
    local newEnv = setmetatable({}, {__index = oldEnv})

    -- Replace LocalPlayer with the name of the player who ran the code
    local originalPlayerName = Player.Name
    newEnv.LocalPlayer = {Name = originalPlayerName}

    -- Redirect the loadstring to use the new environment
    local func, errorMessage = loadstring(code)
    if not func then
        warn("Error loading code: " .. errorMessage)
        return nil
    end

    -- Set the environment for the code to execute in
    setfenv(func, newEnv)

    -- Execute the code in the modified environment
    local success, execError = pcall(func)
    if not success then
        warn("Error executing code: " .. execError)
        return nil
    end

    -- After running the code, collect the created variables
    for name, value in pairs(newEnv) do
        -- Exclude the environment variables that existed before the code execution
        if not oldEnv[name] then
            createdVariables[name] = value
        end
    end

    -- Add the newly created variables to the global state
    table.insert(allCreatedVariables, createdVariables)

    -- Store the executed code for future players to run
    table.insert(allExecutedCode, {code = code, playerName = originalPlayerName})

    -- Fire the SyncCode event to notify other clients to execute the modified code
    utility.SyncCode:Fire(code, Player)

    -- Trigger JoinSync event when utility is run by the player
    utility.JoinSync:Fire(game.Players.LocalPlayer)

    -- Return the table of created variables
    return createdVariables
end

-- Tool creation function that ensures tools are visible to all clients
function utility.Tool(Name, ToolTip, Handle, CanDrop, Callback)
    -- Create the tool object
    local tool = Instance.new("Tool")
    tool.Name = Name
    tool.ToolTip = ToolTip or ""
    tool.RequiresHandle = Handle ~= nil
    tool.CanDrop = CanDrop or true
    
    -- Ensure the handle is created and synced across all clients
    if Handle then
        -- Sync the handle part if it's passed (create if not already created)
        if not workspace:FindFirstChild(Handle.Name) then
            -- If the handle doesn't exist, we create it locally, and sync it across clients
            utility.Sync("Handle = " .. Handle.Name)  -- Sync the handle creation
        end
        tool.Handle = Handle  -- Assign the handle to the tool
    else
        tool.Handle = nil
    end

    -- Sync the tool's properties across all clients
    utility.syncObjectProperties(tool, {
        Name = tool.Name,
        ToolTip = tool.ToolTip,
        RequiresHandle = tool.RequiresHandle,
        CanDrop = tool.CanDrop
    })

    -- If a callback is provided, trigger it when the tool is equipped
    if Callback then
        tool.Equipped:Connect(Callback)
    end

    -- Set up the tool for the local player
    tool.Parent = game.Players.LocalPlayer.Backpack

    -- Trigger the sync for other clients
    utility.triggerSyncPropertyChange(tool, {
        Name = tool.Name,
        ToolTip = tool.ToolTip,
        RequiresHandle = tool.RequiresHandle,
        CanDrop = tool.CanDrop
    })

    -- Return the created tool
    return tool
end

-- Function to sync object properties across clients
function utility.syncObjectProperties(object, properties)
    -- Track the object if not already tracked
    if not objectTrackers[object] then
        objectTrackers[object] = {}
    end

    -- Update the tracked properties of the object
    for property, value in pairs(properties) do
        if object[property] ~= value then
            -- Store the initial value if it doesn't match
            objectTrackers[object][property] = value
        end
    end
end

-- Function to monitor and sync property changes dynamically
function utility.monitorPropertyChanges(object)
    -- Watch for property changes and sync them
    local function propertyChanged(propertyName, oldValue, newValue)
        -- If the value has changed, we need to sync it across all clients
        if oldValue ~= newValue then
            utility.triggerSyncPropertyChange(object, {
                [propertyName] = newValue
            })
        end
    end

    -- Hook into property changes
    local originalProperties = {}
    for propertyName, value in pairs(object) do
        originalProperties[propertyName] = value
        -- Create a property change listener
        local conn = object:GetPropertyChangedSignal(propertyName):Connect(function()
            propertyChanged(propertyName, originalProperties[propertyName], object[propertyName])
        end)
    end

    -- Store the connections for later cleanup
    objectTrackers[object].connections = originalProperties
end

-- Function to trigger silent communication for property changes
function utility.triggerSyncPropertyChange(object, properties)
    -- Notify other clients about the change silently
    syncBindable:Fire(object, properties)
end

-- Listen for silent updates from other clients
syncBindable.Event:Connect(function(object, properties)
    -- Update the object's properties based on what was passed
    for property, value in pairs(properties) do
        if object[property] ~= value then
            object[property] = value
        end
    end
end)

-- Listen for the SyncCode event and run the synchronized code on all clients
utility.SyncCode.Event:Connect(function(code, Player)
    -- Run the code on the local client (safe code execution)
    
    -- Loop through all previously executed code and re-run it for the new player
    for _, executedData in ipairs(allExecutedCode) do
        local executedCode = executedData.code
        local originalPlayerName = executedData.playerName

        -- Replace LocalPlayer with the original player's name in the code
        local modifiedCode = executedCode:gsub("LocalPlayer", originalPlayerName)

        -- Run the modified code with the new environment (without localPlayer)
        local success, execError = pcall(loadstring(modifiedCode))
        if not success then
            warn("Error executing code for new player: " .. execError)
        end
    end
end)

-- Listen for the JoinSync event and sync the player's data when they run the utility
utility.JoinSync.Event:Connect(function(player)
    -- Example: Sync initial tool data for the player who just ran the utility
    utility.syncObjectProperties(player.Name .. "_Tool", {
        Name = "Example Tool",
        ToolTip = "This is a synced tool.",
        RequiresHandle = true,
        CanDrop = true
    })

    -- Sync all previous variables created before they joined
    for _, createdVars in ipairs(allCreatedVariables) do
        for varName, varValue in pairs(createdVars) do
            utility.syncObjectProperties(varName, {
                Value = varValue
            })
        end
    end

    -- Run the previously executed code with the player-specific changes
    -- Replace LocalPlayer with their name in all previously executed code
    for _, executedData in ipairs(allExecutedCode) do
        local executedCode = executedData.code
        local originalPlayerName = executedData.playerName

        -- Replace LocalPlayer with the new player's name
        local modifiedCode = executedCode:gsub("LocalPlayer", player.Name)

        -- Run the modified code on the player's client
        local success, execError = pcall(loadstring(modifiedCode))
        if not success then
            warn("Error executing code for new player: " .. execError)
        end
    end
end)

-- Return the utility object
return utility
