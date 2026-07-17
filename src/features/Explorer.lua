local Explorer = {}

local ROOT_SERVICES = {
    "Workspace",
    "Players",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "Lighting",
    "SoundService",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "Teams",
}

-- Roblox's class icon atlas and class groupings, following the tree treatment
-- used by DarkDex. Expand/collapse controls use Lucide chevrons separately.
local CLASS_ICON_ASSET = "rbxasset://textures/ClassImages.PNG"
local CLASS_ICON_INDEX = {
    Workspace = 19,
    Players = 21,
    ReplicatedFirst = 72,
    ReplicatedStorage = 72,
    Lighting = 13,
    SoundService = 31,
    StarterGui = 46,
    StarterPack = 20,
    StarterPlayer = 88,
    Teams = 23,
    Folder = 70,
    Model = 2,
    Part = 1,
    MeshPart = 1,
    UnionOperation = 77,
    Camera = 5,
    Humanoid = 9,
    Player = 12,
    Backpack = 20,
    Script = 6,
    LocalScript = 18,
    ModuleScript = 71,
    RemoteEvent = 80,
    RemoteFunction = 79,
    UnreliableRemoteEvent = 80,
    BindableEvent = 67,
    BindableFunction = 66,
    ScreenGui = 47,
    Frame = 48,
    ScrollingFrame = 48,
    TextLabel = 50,
    TextButton = 51,
    TextBox = 51,
    ImageLabel = 49,
    ImageButton = 52,
    BillboardGui = 64,
    SurfaceGui = 64,
    Attachment = 34,
    Weld = 34,
    WeldConstraint = 34,
    Motor6D = 34,
    BoolValue = 4,
    IntValue = 4,
    NumberValue = 4,
    StringValue = 4,
    ObjectValue = 4,
    Vector3Value = 4,
    CFrameValue = 4,
    Color3Value = 4,
    Sound = 11,
    Animation = 60,
    Animator = 60,
    ParticleEmitter = 69,
    Decal = 7,
    Texture = 10,
    PointLight = 13,
    SpotLight = 13,
    SurfaceLight = 13,
    ProximityPrompt = 124,
    ClickDetector = 41,
    TouchTransmitter = 37,
    Tool = 17,
}

local CLASS_ICON_FALLBACKS = {
    { "BasePart", 1 },
    { "LuaSourceContainer", 6 },
    { "GuiButton", 51 },
    { "GuiObject", 48 },
    { "LayerCollector", 47 },
    { "Light", 13 },
    { "ValueBase", 4 },
    { "Constraint", 89 },
    { "JointInstance", 34 },
}

local COMMON_PROPERTIES = {
    "Name",
    "Archivable",
}

local CLASS_PROPERTIES = {
    BasePart = {
        "Anchored",
        "CanCollide",
        "CanQuery",
        "CanTouch",
        "CastShadow",
        "Color",
        "Material",
        "Position",
        "Rotation",
        "Size",
        "Transparency",
    },
    GuiObject = {
        "Active",
        "AnchorPoint",
        "AutomaticSize",
        "BackgroundColor3",
        "BackgroundTransparency",
        "Position",
        "Rotation",
        "Size",
        "Visible",
        "ZIndex",
    },
    Humanoid = {
        "AutoRotate",
        "DisplayDistanceType",
        "Health",
        "HipHeight",
        "JumpHeight",
        "JumpPower",
        "MaxHealth",
        "WalkSpeed",
    },
    Model = {
        "PrimaryPart",
        "WorldPivot",
    },
    Sound = {
        "Looped",
        "PlaybackSpeed",
        "Playing",
        "SoundId",
        "TimePosition",
        "Volume",
    },
    ValueBase = {
        "Value",
    },
}

local function trim(value)
    return tostring(value):match("^%s*(.-)%s*$")
end

local function formatNumber(value)
    if math.floor(value) == value then
        return tostring(value)
    end
    return string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function formatValue(value)
    local kind = typeof(value)
    if kind == "string" or kind == "boolean" or kind == "number" then
        return tostring(value)
    elseif kind == "Vector2" then
        return ("%s, %s"):format(formatNumber(value.X), formatNumber(value.Y))
    elseif kind == "Vector3" then
        return ("%s, %s, %s"):format(
            formatNumber(value.X),
            formatNumber(value.Y),
            formatNumber(value.Z)
        )
    elseif kind == "Color3" then
        return ("%d, %d, %d"):format(
            math.floor(value.R * 255 + 0.5),
            math.floor(value.G * 255 + 0.5),
            math.floor(value.B * 255 + 0.5)
        )
    elseif kind == "UDim" then
        return ("%s, %s"):format(formatNumber(value.Scale), value.Offset)
    elseif kind == "UDim2" then
        return ("%s, %s, %s, %s"):format(
            formatNumber(value.X.Scale),
            value.X.Offset,
            formatNumber(value.Y.Scale),
            value.Y.Offset
        )
    elseif kind == "CFrame" then
        local position = value.Position
        return ("Position: %s, %s, %s"):format(
            formatNumber(position.X),
            formatNumber(position.Y),
            formatNumber(position.Z)
        )
    elseif kind == "Instance" then
        return value:GetFullName()
    elseif kind == "EnumItem" then
        return tostring(value)
    end
    return tostring(value)
end

local function numbers(text)
    local result = {}
    for token in tostring(text):gmatch("[-+]?%d*%.?%d+") do
        table.insert(result, tonumber(token))
    end
    return result
end

local function parseValue(text, current)
    local kind = typeof(current)
    local clean = trim(text)

    if kind == "string" then
        return true, clean
    elseif kind == "number" then
        local value = tonumber(clean)
        return value ~= nil, value
    elseif kind == "boolean" then
        local lower = clean:lower()
        if lower == "true" or lower == "1" or lower == "yes" then
            return true, true
        elseif lower == "false" or lower == "0" or lower == "no" then
            return true, false
        end
        return false, nil
    elseif kind == "Vector2" then
        local values = numbers(clean)
        return #values >= 2, #values >= 2 and Vector2.new(values[1], values[2]) or nil
    elseif kind == "Vector3" then
        local values = numbers(clean)
        return #values >= 3, #values >= 3 and Vector3.new(values[1], values[2], values[3]) or nil
    elseif kind == "Color3" then
        local values = numbers(clean)
        if #values >= 3 then
            local scale = math.max(values[1], values[2], values[3]) > 1 and 255 or 1
            return true, Color3.new(values[1] / scale, values[2] / scale, values[3] / scale)
        end
    elseif kind == "UDim" then
        local values = numbers(clean)
        return #values >= 2, #values >= 2 and UDim.new(values[1], values[2]) or nil
    elseif kind == "UDim2" then
        local values = numbers(clean)
        return #values >= 4,
            #values >= 4 and UDim2.new(values[1], values[2], values[3], values[4]) or nil
    elseif kind == "CFrame" then
        local values = numbers(clean)
        return #values >= 3, #values >= 3 and CFrame.new(values[1], values[2], values[3]) or nil
    end

    return false, nil
end

local function editable(value)
    local kind = typeof(value)
    return kind == "string"
        or kind == "number"
        or kind == "boolean"
        or kind == "Vector2"
        or kind == "Vector3"
        or kind == "Color3"
        or kind == "UDim"
        or kind == "UDim2"
        or kind == "CFrame"
end

function Explorer.mount(ctx)
    local UI = ctx.ui
    local Theme = ctx.theme
    local page = ctx.page
    local expanded = setmetatable({}, { __mode = "k" })
    local rowByInstance = setmetatable({}, { __mode = "k" })
    local searchToken = 0
    local pickMode = false
    local MAX_ROWS = 320
    local MAX_SEARCH_ROWS = 180
    local RENDER_BATCH = 28
    local treeConnections = {}
    local propertyConnections = {}
    local searchLoader
    local treeLoader
    local renderToken = 0
    local childState = setmetatable({}, { __mode = "k" })
    local environment = (getgenv and getgenv()) or _G
    local getNilInstances = rawget(environment, "getnilinstances")
    local NIL_ROOT = {
        ClassName = "Folder",
        Name = "Nil Instances",
    }

    local function disconnectAll(connections)
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(connections)
    end

    local function connectDynamic(connections, signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    ctx:cleanup(function()
        searchToken = searchToken + 1
        renderToken = renderToken + 1
        disconnectAll(treeConnections)
        disconnectAll(propertyConnections)
        if searchLoader then
            searchLoader:destroy()
            searchLoader = nil
        end
        if treeLoader then
            treeLoader:destroy()
            treeLoader = nil
        end
    end)

    local toolbar = UI.toolbar(page)
    local search = UI.input({
        Parent = toolbar,
        PlaceholderText = "Search instances…",
        Size = UDim2.fromOffset(250, 30),
    })
    local refreshButton = UI.button({
        Icon = "refresh-cw",
        Parent = toolbar,
        Text = "Refresh",
        Width = 90,
    })
    local pickButton = UI.button({
        Icon = "mouse-pointer-2",
        Parent = toolbar,
        Text = "Pick object",
        Width = 108,
    })
    local copyPathButton = UI.button({
        Icon = "copy",
        Parent = toolbar,
        Text = "Copy path",
        Width = 100,
    })

    local body = UI.create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 52),
        Size = UDim2.new(1, -20, 1, -62),
        Parent = page,
    })

    local treePanel = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Size = UDim2.new(0.54, -5, 1, 0),
    })
    local treeHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 40),
        Parent = treePanel,
    })
    local treeTitle = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 4),
        Size = UDim2.new(1, -24, 0, 18),
        Text = "DATA MODEL",
        TextColor3 = Theme.text,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = treeHeader,
    })
    local treeMeta = UI.label({
        Position = UDim2.fromOffset(12, 20),
        Size = UDim2.new(1, -24, 0, 14),
        Text = "Expandable runtime hierarchy",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = treeHeader,
    })

    local tree, treeLayout = UI.scroller({
        Parent = treePanel,
        Position = UDim2.fromOffset(0, 40),
        Size = UDim2.new(1, 0, 1, -40),
        Padding = 5,
        Spacing = 2,
    })

    local propertiesPanel = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Position = UDim2.new(0.54, 5, 0, 0),
        Size = UDim2.new(0.46, -5, 1, 0),
    })
    local propertiesHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 78),
        Parent = propertiesPanel,
    })
    local selectedName = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "No selection",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = propertiesHeader,
    })
    local selectedClass = UI.label({
        Position = UDim2.fromOffset(12, 29),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Choose an object from the hierarchy",
        TextColor3 = Theme.cyan,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = propertiesHeader,
    })
    local selectedPath = UI.label({
        Font = Enum.Font.Code,
        Position = UDim2.fromOffset(12, 49),
        Size = UDim2.new(1, -24, 0, 18),
        Text = "",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = propertiesHeader,
    })

    local properties, propertiesLayout = UI.scroller({
        Parent = propertiesPanel,
        Position = UDim2.fromOffset(0, 78),
        Size = UDim2.new(1, 0, 1, -78),
        Padding = 8,
        Spacing = 4,
    })

    local function sortAndCap(children)
        if #children > 2000 then
            local capped = {}
            for index = 1, 2000 do
                capped[index] = children[index]
            end
            children = capped
        end

        table.sort(children, function(left, right)
            if left.ClassName == right.ClassName then
                return left.Name:lower() < right.Name:lower()
            end
            return left.ClassName < right.ClassName
        end)
        return children
    end

    local function nilChildren()
        if type(getNilInstances) ~= "function" then
            return {}
        end
        local ok, instances = pcall(getNilInstances)
        if not ok or type(instances) ~= "table" then
            return {}
        end

        local result = {}
        for index = 1, math.min(#instances, 500) do
            if typeof(instances[index]) == "Instance" then
                table.insert(result, instances[index])
            end
        end
        return sortAndCap(result)
    end

    local function safeChildren(instance)
        if instance == NIL_ROOT then
            return nilChildren()
        end

        local ok, children = pcall(instance.GetChildren, instance)
        if not ok then
            return {}
        end
        return sortAndCap(children)
    end

    local function hasChildren(instance)
        local cached = childState[instance]
        if cached ~= nil then
            return cached
        end

        local children
        if instance == NIL_ROOT then
            childState[instance] = type(getNilInstances) == "function"
            return childState[instance]
        else
            local ok
            ok, children = pcall(instance.GetChildren, instance)
            if not ok then
                children = {}
            end
        end
        local result = #children > 0
        childState[instance] = result
        return result
    end

    local function rawChildren(instance)
        if instance == NIL_ROOT then
            return nilChildren()
        end
        local ok, children = pcall(instance.GetChildren, instance)
        if not ok then
            return {}
        end
        return children
    end

    local function roots()
        local result = {}
        for _, serviceName in ipairs(ROOT_SERVICES) do
            local ok, service = pcall(game.GetService, game, serviceName)
            if ok and service then
                table.insert(result, service)
            end
        end

        if type(getNilInstances) == "function" then
            table.insert(result, NIL_ROOT)
        end

        return result
    end

    local renderTree
    local renderProperties

    local function propertySet(instance)
        local result = {}
        local seen = {}
        local function add(name)
            if not seen[name] then
                seen[name] = true
                table.insert(result, name)
            end
        end

        for _, name in ipairs(COMMON_PROPERTIES) do
            add(name)
        end
        for className, names in pairs(CLASS_PROPERTIES) do
            local ok, matches = pcall(instance.IsA, instance, className)
            if ok and matches then
                for _, name in ipairs(names) do
                    add(name)
                end
            end
        end
        table.sort(result)
        return result
    end

    local function sectionRow(text, order)
        local row = UI.create("Frame", {
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 24),
            Parent = properties,
        })
        UI.label({
            Font = Enum.Font.GothamBold,
            Size = UDim2.fromScale(1, 1),
            Text = text:upper(),
            TextColor3 = Theme.textFaint,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
    end

    local function propertyRow(instance, name, value, attribute, order)
        local row = UI.panel({
            Parent = properties,
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 34),
            Radius = 6,
            StrokeTransparency = 0.35,
        })
        UI.label({
            Position = UDim2.fromOffset(9, 0),
            Size = UDim2.new(0.38, -9, 1, 0),
            Text = name,
            TextColor3 = attribute and Theme.cyan or Theme.textMuted,
            TextSize = 10,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })

        local canEdit = editable(value)
        local valueField
        if canEdit then
            valueField = UI.input({
                Parent = row,
                Position = UDim2.new(0.38, 0, 0, 4),
                Size = UDim2.new(0.62, -5, 1, -8),
                Text = formatValue(value),
                TextSize = 10,
            })
            valueField.Position = UDim2.new(0.38, 0, 0, 4)

            connectDynamic(propertyConnections, valueField.FocusLost, function(enterPressed)
                if not enterPressed or not instance.Parent and instance ~= game then
                    valueField.Text = formatValue(value)
                    return
                end

                local currentOk, current = pcall(function()
                    return attribute and instance:GetAttribute(name) or instance[name]
                end)
                if not currentOk then
                    ctx:toast("Property is no longer available", Theme.red)
                    return
                end

                local parsed, nextValue = parseValue(valueField.Text, current)
                if not parsed then
                    valueField.Text = formatValue(current)
                    ctx:toast("Invalid " .. typeof(current) .. " value", Theme.red)
                    return
                end

                local ok, message = pcall(function()
                    if attribute then
                        instance:SetAttribute(name, nextValue)
                    else
                        instance[name] = nextValue
                    end
                end)
                if ok then
                    value = nextValue
                    valueField.Text = formatValue(nextValue)
                    ctx:status(name .. " updated", Theme.green)
                    if name == "Name" then
                        renderTree()
                    end
                else
                    valueField.Text = formatValue(current)
                    ctx:toast(tostring(message), Theme.red)
                end
            end)
        else
            valueField = UI.label({
                Font = Enum.Font.Code,
                Position = UDim2.new(0.38, 7, 0, 0),
                Size = UDim2.new(0.62, -12, 1, 0),
                Text = formatValue(value),
                TextColor3 = Theme.text,
                TextSize = 9,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
        end
    end

    renderProperties = function(instance)
        disconnectAll(propertyConnections)
        UI.clear(properties)

        if typeof(instance) ~= "Instance" then
            selectedName.Text = "No selection"
            selectedClass.Text = "Choose an object from the hierarchy"
            selectedPath.Text = ""
            UI.empty(properties, "Nothing selected", "Select an instance to inspect its properties.")
            return
        end

        selectedName.Text = instance.Name
        selectedClass.Text = instance.ClassName
        selectedPath.Text = ctx:path(instance)
        local order = 0
        sectionRow("Properties", order)

        for _, name in ipairs(propertySet(instance)) do
            local ok, value = pcall(function()
                return instance[name]
            end)
            if ok then
                order = order + 1
                propertyRow(instance, name, value, false, order)
            end
        end

        local attributeOk, attributes = pcall(instance.GetAttributes, instance)
        if attributeOk and next(attributes) then
            order = order + 1
            sectionRow("Attributes", order)
            local names = {}
            for name in pairs(attributes) do
                table.insert(names, name)
            end
            table.sort(names)
            for _, name in ipairs(names) do
                order = order + 1
                propertyRow(instance, name, attributes[name], true, order)
            end
        end
    end

    local function choose(instance)
        if instance == NIL_ROOT then
            expanded[instance] = not expanded[instance]
            renderTree()
            return
        end
        ctx:setSelection(instance)
        renderProperties(instance)
        for target, row in pairs(rowByInstance) do
            if row and row.Parent then
                row.BackgroundColor3 = target == instance and Theme.accentSoft or Theme.surface
            end
        end
    end

    local function classIconIndex(instance)
        local exact = CLASS_ICON_INDEX[instance.ClassName]
        if exact then
            return exact
        end
        if typeof(instance) == "Instance" then
            for _, fallback in ipairs(CLASS_ICON_FALLBACKS) do
                local ok, matches = pcall(instance.IsA, instance, fallback[1])
                if ok and matches then
                    return fallback[2]
                end
            end
        end
        return 0
    end

    local function makeClassIcon(instance, parent, position)
        local iconIndex = classIconIndex(instance)
        return UI.create("ImageLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = CLASS_ICON_ASSET,
            ImageRectOffset = Vector2.new(iconIndex * 16, 0),
            ImageRectSize = Vector2.new(16, 16),
            Position = position,
            ScaleType = Enum.ScaleType.Fit,
            Size = UDim2.fromOffset(20, 20),
            Parent = parent,
        })
    end

    local function makeRow(instance, depth, order, knownChildren)
        local nodeHasChildren = knownChildren ~= nil and #knownChildren > 0
            or knownChildren == nil and hasChildren(instance)
        local row = UI.create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = ctx:getSelection() == instance and Theme.accentSoft or Theme.surface,
            BorderSizePixel = 0,
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 32),
            Text = "",
            Parent = tree,
        })
        UI.corner(row, 5)
        rowByInstance[instance] = row

        local expandButton = UI.create("TextButton", {
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(4 + depth * 18, 0),
            Size = UDim2.fromOffset(24, 32),
            Text = "",
            Parent = row,
        })
        if nodeHasChildren then
            UI.icon({
                AnchorPoint = Vector2.new(0.5, 0.5),
                Color = Theme.icon,
                Icon = expanded[instance] and "chevron-down" or "chevron-right",
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(18, 18),
                Parent = expandButton,
            })
        end
        makeClassIcon(instance, row, UDim2.fromOffset(31 + depth * 18, 6))
        UI.label({
            Font = Enum.Font.GothamMedium,
            Position = UDim2.fromOffset(58 + depth * 18, 0),
            Size = UDim2.new(1, -66 - depth * 18, 1, 0),
            Text = instance.Name,
            TextColor3 = Theme.text,
            TextSize = 12,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })

        connectDynamic(treeConnections, row.MouseButton1Click, function()
            choose(instance)
        end)
        if nodeHasChildren then
            connectDynamic(treeConnections, expandButton.MouseButton1Click, function()
                expanded[instance] = not expanded[instance]
                childState[instance] = nil
                renderTree()
            end)
            connectDynamic(treeConnections, row.MouseButton2Click, function()
                expanded[instance] = not expanded[instance]
                childState[instance] = nil
                renderTree()
            end)
        end
    end

    local function searchInstances(query, token, onProgress)
        local matches = {}
        local queue = roots()
        local head = 1
        local visited = 0
        local normalized = query:lower()

        while head <= #queue and visited < 20000 and #matches < 500 do
            if token ~= searchToken or not ctx:isActive() then
                return nil
            end

            local instance = queue[head]
            head = head + 1
            visited = visited + 1
            if instance ~= NIL_ROOT
                and (instance.Name:lower():find(normalized, 1, true)
                    or instance.ClassName:lower():find(normalized, 1, true))
            then
                table.insert(matches, instance)
            end

            local children = rawChildren(instance)
            for index = 1, math.min(#children, 2000) do
                local child = children[index]
                if #queue < 25000 then
                    table.insert(queue, child)
                end
            end

            if visited % 100 == 0 then
                if onProgress then
                    onProgress(visited, #matches)
                end
                task.wait()
            end
        end

        return matches, visited
    end

    renderTree = function()
        if not ctx:isActive() then
            return
        end

        renderToken = renderToken + 1
        local currentRender = renderToken
        if searchLoader then
            searchLoader:destroy()
            searchLoader = nil
        end
        if treeLoader then
            treeLoader:destroy()
            treeLoader = nil
        end
        local scrollPosition = tree.CanvasPosition
        disconnectAll(treeConnections)
        UI.clear(tree)
        rowByInstance = setmetatable({}, { __mode = "k" })
        local query = trim(search.Text)
        local order = 0

        if query ~= "" then
            searchToken = searchToken + 1
            local token = searchToken
            treeTitle.Text = "SEARCHING…"
            local loader = UI.loader({
                Detail = "Preparing bounded DataModel scan…",
                LayoutOrder = -1,
                Parent = tree,
                Size = UDim2.new(1, 0, 0, 136),
                Title = "Searching instances",
            })
            searchLoader = loader
            task.spawn(function()
                local matches, visited = searchInstances(query, token, function(scanned, found)
                    if loader == searchLoader then
                        loader:setDetail(
                            ("%d instances scanned · %d matches"):format(scanned, found)
                        )
                    end
                end)
                if not matches or token ~= searchToken or not ctx:isActive() then
                    return
                end

                local preserve = {
                    [loader.frame] = true,
                }
                UI.clear(tree, preserve)
                local visibleCount = math.min(#matches, MAX_SEARCH_ROWS)
                for index = 1, visibleCount do
                    if token ~= searchToken or not ctx:isActive() then
                        return
                    end
                    local instance = matches[index]
                    makeRow(instance, 0, index, {})
                    if index % RENDER_BATCH == 0 then
                        loader:setDetail(
                            ("Rendering results… %d / %d rows"):format(index, visibleCount)
                        )
                        task.wait()
                    end
                end
                loader:destroy()
                if searchLoader == loader then
                    searchLoader = nil
                end
                treeTitle.Text = ("SEARCH RESULTS · %d / %d SHOWN"):format(
                    visibleCount,
                    #matches
                )
                treeMeta.Text = ("%d instances scanned · results capped for responsiveness"):format(
                    visited
                )
            end)
            return
        end

        searchToken = searchToken + 1
        treeTitle.Text = "LOADING DATA MODEL…"
        treeMeta.Text = "Building visible rows in responsive batches"
        local loader = UI.loader({
            Detail = "Preparing collapsed roots…",
            LayoutOrder = -1,
            Parent = tree,
            Size = UDim2.new(1, 0, 0, 104),
            Title = "Loading Explorer",
        })
        treeLoader = loader

        task.spawn(function()
            task.wait()
            if currentRender ~= renderToken or not ctx:isActive() then
                return
            end

            local function append(instance, depth)
                if currentRender ~= renderToken or order >= MAX_ROWS then
                    return false
                end

                local children = expanded[instance] and safeChildren(instance) or nil
                order = order + 1
                makeRow(instance, depth, order, children)
                if order % RENDER_BATCH == 0 then
                    loader:setDetail(("%d visible rows prepared…"):format(order))
                    task.wait()
                    if currentRender ~= renderToken or not ctx:isActive() then
                        return false
                    end
                end

                if expanded[instance] and children then
                    for _, child in ipairs(children) do
                        if append(child, depth + 1) == false or order >= MAX_ROWS then
                            break
                        end
                    end
                end
                return true
            end

            for _, instance in ipairs(roots()) do
                if append(instance, 0) == false or order >= MAX_ROWS then
                    break
                end
            end

            if currentRender ~= renderToken or not ctx:isActive() then
                return
            end
            loader:destroy()
            if treeLoader == loader then
                treeLoader = nil
            end
            treeTitle.Text = ("DATA MODEL · %d VISIBLE"):format(order)
            treeMeta.Text = order >= MAX_ROWS
                and "Visible row cap reached"
                or "Click a Lucide arrow or right-click a row to expand"
            task.defer(function()
                if tree.Parent and currentRender == renderToken then
                    tree.CanvasPosition = scrollPosition
                end
            end)
        end)
    end

    ctx:connect(refreshButton.MouseButton1Click, function()
        childState = setmetatable({}, { __mode = "k" })
        renderTree()
    end)
    ctx:connect(search:GetPropertyChangedSignal("Text"), function()
        searchToken = searchToken + 1
        local token = searchToken
        task.delay(0.22, function()
            if token == searchToken and ctx:isActive() then
                renderTree()
            end
        end)
    end)
    ctx:connect(copyPathButton.MouseButton1Click, function()
        local selected = ctx:getSelection()
        if selected then
            ctx:copy(ctx:path(selected), "Instance path copied")
        else
            ctx:toast("Select an instance first", Theme.yellow)
        end
    end)
    ctx:connect(pickButton.MouseButton1Click, function()
        pickMode = not pickMode
        pickButton.Text = pickMode and "Pick: armed" or "Pick object"
        pickButton.TextColor3 = pickMode and Theme.green or Theme.text
        ctx:status(
            pickMode and "Click a world object to select it" or "Object picker cancelled",
            pickMode and Theme.yellow or Theme.green
        )
    end)

    local player = ctx.services.Players.LocalPlayer
    local mouse = player and player:GetMouse()
    ctx:connect(ctx.services.UserInputService.InputBegan, function(input, processed)
        if processed or not pickMode or not ctx:isActive() then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 and mouse and mouse.Target then
            pickMode = false
            pickButton.Text = "Pick object"
            pickButton.TextColor3 = Theme.text
            choose(mouse.Target)
            ctx:status("Selected " .. mouse.Target.Name, Theme.green)
        end
    end)

    ctx:on("selectionChanged", function(instance, source)
        if source ~= ctx.id then
            renderProperties(instance)
            for target, row in pairs(rowByInstance) do
                if row and row.Parent then
                    row.BackgroundColor3 = target == instance and Theme.accentSoft or Theme.surface
                end
            end
        end
    end)
    ctx:on("activeFeatureChanged", function(id)
        if id == ctx.id then
            renderTree()
            renderProperties(ctx:getSelection())
        else
            searchToken = searchToken + 1
            renderToken = renderToken + 1
            if searchLoader then
                searchLoader:destroy()
                searchLoader = nil
            end
            if treeLoader then
                treeLoader:destroy()
                treeLoader = nil
            end
        end
    end)

    renderTree()
    renderProperties(ctx:getSelection())

    return {
        refresh = renderTree,
        destroy = function() end,
    }
end

return Explorer
