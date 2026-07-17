local Explorer = {}

-- The built-in Roblox class atlas and zero-based ExplorerImageIndex values are
-- the same mechanism DarkDex uses. Lucide is reserved for interaction icons.
local CLASS_ICON_ASSET = "rbxasset://textures/ClassImages.PNG"
local CLASS_ICON_INDEX = {
    Workspace = 19,
    Players = 21,
    ReplicatedFirst = 72,
    ReplicatedStorage = 72,
    ServerStorage = 72,
    ServerScriptService = 72,
    Lighting = 13,
    SoundService = 31,
    StarterGui = 46,
    StarterPack = 20,
    StarterPlayer = 88,
    Teams = 23,
    Chat = 30,
    LocalizationService = 24,
    TestService = 68,
    Folder = 70,
    Configuration = 58,
    Model = 2,
    Part = 1,
    WedgePart = 1,
    CornerWedgePart = 1,
    TrussPart = 1,
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
    ViewportFrame = 48,
    CanvasGroup = 48,
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
    Beam = 69,
    Trail = 69,
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
    "Archivable",
    "ClassName",
    "Name",
    "Parent",
}

local READ_ONLY_PROPERTIES = {
    ClassName = true,
    Parent = true,
}

local CLASS_PROPERTIES = {
    BasePart = {
        "Anchored",
        "AssemblyAngularVelocity",
        "AssemblyLinearVelocity",
        "CanCollide",
        "CanQuery",
        "CanTouch",
        "CastShadow",
        "Color",
        "Material",
        "Massless",
        "Position",
        "Reflectance",
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
        "BorderSizePixel",
        "LayoutOrder",
        "Position",
        "Rotation",
        "Size",
        "Visible",
        "ZIndex",
    },
    TextLabel = {
        "Font",
        "RichText",
        "Text",
        "TextColor3",
        "TextScaled",
        "TextSize",
        "TextTransparency",
        "TextWrapped",
    },
    TextButton = {
        "AutoButtonColor",
        "Font",
        "RichText",
        "Text",
        "TextColor3",
        "TextScaled",
        "TextSize",
        "TextTransparency",
        "TextWrapped",
    },
    TextBox = {
        "ClearTextOnFocus",
        "Font",
        "MultiLine",
        "PlaceholderText",
        "RichText",
        "Text",
        "TextColor3",
        "TextScaled",
        "TextSize",
        "TextTransparency",
        "TextWrapped",
    },
    ImageLabel = {
        "Image",
        "ImageColor3",
        "ImageTransparency",
        "ScaleType",
    },
    ImageButton = {
        "AutoButtonColor",
        "Image",
        "ImageColor3",
        "ImageTransparency",
        "ScaleType",
    },
    Humanoid = {
        "AutoRotate",
        "DisplayDistanceType",
        "Health",
        "HipHeight",
        "JumpHeight",
        "JumpPower",
        "MaxHealth",
        "PlatformStand",
        "UseJumpPower",
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
        "RollOffMaxDistance",
        "RollOffMinDistance",
        "SoundId",
        "TimePosition",
        "Volume",
    },
    LuaSourceContainer = {
        "Disabled",
    },
    ValueBase = {
        "Value",
    },
}

local ROW_HEIGHT = 30
local POOL_BUFFER = 4
local MAX_VISIBLE_NODES = 12000
local MAX_CHILDREN = 4000
local MAX_SEARCH_VISITS = 30000
local MAX_SEARCH_RESULTS = 1000
local BUILD_BATCH = 240
local AUTO_UPDATE_DELAY = 0.18

-- Roblox's canonical explorer order for top-level services, so the roots read
-- like Studio/DarkDex instead of being sorted alphabetically by class name.
local SERVICE_ORDER = {
    Workspace = 1,
    Players = 2,
    Lighting = 3,
    MaterialService = 4,
    ReplicatedFirst = 5,
    ReplicatedStorage = 6,
    ServerScriptService = 7,
    ServerStorage = 8,
    StarterGui = 9,
    StarterPack = 10,
    StarterPlayer = 11,
    Teams = 12,
    SoundService = 13,
    TextChatService = 14,
    Chat = 15,
    LocalizationService = 16,
    ProximityPromptService = 17,
    TestService = 18,
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
        local ok, fullName = pcall(value.GetFullName, value)
        return ok and fullName or value.Name
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

local function textEditable(value)
    local kind = typeof(value)
    return kind == "string"
        or kind == "number"
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
    local childState = setmetatable({}, { __mode = "k" })
    local propertyConnections = {}
    local rowConnections = {}
    local visibleNodes = {}
    local rowPool = {}
    local buildToken = 0
    local searchToken = 0
    local updateToken = 0
    local hierarchyUpdateAt
    local pickMode = false
    local treeLoader
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

    local toolbar = UI.toolbar(page)
    local search = UI.input({
        Parent = toolbar,
        PlaceholderText = "Search instances...",
        Size = UDim2.fromOffset(250, 30),
    })
    local pickButton = UI.button({
        Icon = "mouse-pointer-2",
        Parent = toolbar,
        Text = "Pick object",
        Width = 114,
    })
    local copyPathButton = UI.button({
        Icon = "copy",
        Parent = toolbar,
        Text = "Copy path",
        Width = 108,
    })
    UI.label({
        Size = UDim2.fromOffset(190, 30),
        Text = "Live hierarchy - no manual refresh",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = toolbar,
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
        Size = UDim2.new(1, 0, 0, 44),
        Parent = treePanel,
    })
    local treeTitle = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 4),
        Size = UDim2.new(1, -24, 0, 19),
        Text = "DATA MODEL",
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = treeHeader,
    })
    local treeMeta = UI.label({
        Position = UDim2.fromOffset(12, 23),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Collapsed roots - live updates enabled",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = treeHeader,
    })

    local tree = UI.create("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
        BackgroundColor3 = Theme.canvas,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 44),
        ScrollBarImageColor3 = Theme.border,
        ScrollBarThickness = 6,
        Size = UDim2.new(1, 0, 1, -44),
        Parent = treePanel,
    })
    local treeLoadingHost = UI.create("Frame", {
        BackgroundColor3 = Theme.canvas,
        BackgroundTransparency = 0.06,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 44),
        Size = UDim2.new(1, 0, 1, -44),
        Visible = false,
        ZIndex = 12,
        Parent = treePanel,
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
        Size = UDim2.new(1, 0, 0, 82),
        Parent = propertiesPanel,
    })
    local selectedName = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "No selection",
        TextSize = 14,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = propertiesHeader,
    })
    local selectedClass = UI.label({
        Position = UDim2.fromOffset(12, 30),
        Size = UDim2.new(1, -24, 0, 18),
        Text = "Choose an object from the hierarchy",
        TextColor3 = Theme.cyan,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = propertiesHeader,
    })
    local selectedPath = UI.label({
        Font = Enum.Font.Code,
        Position = UDim2.fromOffset(12, 51),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = propertiesHeader,
    })

    local properties = UI.scroller({
        Parent = propertiesPanel,
        Position = UDim2.fromOffset(0, 82),
        Size = UDim2.new(1, 0, 1, -82),
        Padding = 8,
        Spacing = 4,
    })

    local function stopTreeLoader()
        if treeLoader then
            treeLoader:destroy()
            treeLoader = nil
        end
        treeLoadingHost.Visible = false
    end

    local function startTreeLoader(title, detail)
        stopTreeLoader()
        treeLoadingHost.Visible = true
        treeLoader = UI.loader({
            BackgroundTransparency = 1,
            Detail = detail,
            Parent = treeLoadingHost,
            Size = UDim2.fromScale(1, 1),
            Title = title,
            ZIndex = 13,
        })
        return treeLoader
    end

    local function sortAndCap(children)
        if #children > MAX_CHILDREN then
            local capped = {}
            for index = 1, MAX_CHILDREN do
                capped[index] = children[index]
            end
            children = capped
        end
        table.sort(children, function(left, right)
            local leftClass = tostring(left.ClassName)
            local rightClass = tostring(right.ClassName)
            if leftClass == rightClass then
                return tostring(left.Name):lower() < tostring(right.Name):lower()
            end
            return leftClass < rightClass
        end)
        return children
    end

    local function nilChildren()
        if type(getNilInstances) ~= "function" or not ctx.settings.includeNilInstances then
            return {}
        end
        local ok, instances = pcall(getNilInstances)
        if not ok or type(instances) ~= "table" then
            return {}
        end
        local result = {}
        for index = 1, math.min(#instances, 1000) do
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
        return ok and sortAndCap(children) or {}
    end

    local function rawChildren(instance)
        if instance == NIL_ROOT then
            return nilChildren()
        end
        local ok, children = pcall(instance.GetChildren, instance)
        return ok and children or {}
    end

    local function hasChildren(instance)
        local cached = childState[instance]
        if cached ~= nil then
            return cached
        end
        local result
        if instance == NIL_ROOT then
            result = type(getNilInstances) == "function" and ctx.settings.includeNilInstances
        else
            local ok, children = pcall(instance.GetChildren, instance)
            result = ok and #children > 0
        end
        childState[instance] = result == true
        return result == true
    end

    local function roots()
        local ok, children = pcall(game.GetChildren, game)
        local result = ok and children or {}
        if #result > MAX_CHILDREN then
            local capped = {}
            for index = 1, MAX_CHILDREN do
                capped[index] = result[index]
            end
            result = capped
        end
        table.sort(result, function(left, right)
            local leftOrder = SERVICE_ORDER[left.ClassName] or SERVICE_ORDER[left.Name] or 1000
            local rightOrder = SERVICE_ORDER[right.ClassName] or SERVICE_ORDER[right.Name] or 1000
            if leftOrder ~= rightOrder then
                return leftOrder < rightOrder
            end
            return tostring(left.Name):lower() < tostring(right.Name):lower()
        end)
        if type(getNilInstances) == "function" and ctx.settings.includeNilInstances then
            table.insert(result, NIL_ROOT)
        end
        return result
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

    local renderProperties
    local rebuildTree
    local refreshRows

    local function choose(instance)
        if instance == NIL_ROOT then
            expanded[instance] = not expanded[instance]
            rebuildTree()
            return
        end
        if typeof(instance) ~= "Instance" then
            return
        end
        ctx:setSelection(instance)
        renderProperties(instance)
        refreshRows()
    end

    local function createPooledRow()
        local state = {}
        local row = UI.create("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = Theme.surface,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -12, 0, ROW_HEIGHT - 2),
            Text = "",
            Visible = false,
            Parent = tree,
        })
        UI.corner(row, 5)
        local expandButton = UI.create("TextButton", {
            AutoButtonColor = false,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(24, ROW_HEIGHT - 2),
            Text = "",
            Parent = row,
        })
        local arrow = UI.icon({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Color = Theme.icon,
            Icon = "chevron-right",
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            Parent = expandButton,
        })
        -- Match DarkDex: 16x16 ClassImages sprite rendered 1:1 with Crop so the
        -- built-in class icons stay pixel-crisp instead of being upscaled.
        local classIcon = UI.create("ImageLabel", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = CLASS_ICON_ASSET,
            ImageRectOffset = Vector2.new(0, 0),
            ImageRectSize = Vector2.new(16, 16),
            ScaleType = Enum.ScaleType.Crop,
            Size = UDim2.fromOffset(16, 16),
            Parent = row,
        })
        local label = UI.label({
            Font = Enum.Font.GothamMedium,
            Text = "",
            TextColor3 = Theme.text,
            TextSize = 12,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        state.row = row
        state.expandButton = expandButton
        state.arrow = arrow
        state.classIcon = classIcon
        state.label = label

        connectDynamic(rowConnections, row.MouseButton1Click, function()
            local node = state.node
            if node then
                choose(node.instance)
            end
        end)
        connectDynamic(rowConnections, expandButton.MouseButton1Click, function()
            local node = state.node
            if node and node.hasChildren then
                expanded[node.instance] = not expanded[node.instance]
                childState[node.instance] = nil
                rebuildTree()
            end
        end)
        connectDynamic(rowConnections, row.MouseButton2Click, function()
            local node = state.node
            if node and node.hasChildren then
                expanded[node.instance] = not expanded[node.instance]
                childState[node.instance] = nil
                rebuildTree()
            end
        end)
        table.insert(rowPool, state)
        return state
    end

    local function updatePooledRow(state, node, index)
        if not node then
            state.node = nil
            state.row.Visible = false
            return
        end

        state.node = node
        local instance = node.instance
        local indent = math.min(node.depth, 18) * 18
        state.row.Position = UDim2.fromOffset(5, (index - 1) * ROW_HEIGHT + 2)
        state.row.BackgroundColor3 = ctx:getSelection() == instance
            and Theme.accentSoft or Theme.surface
        state.row.Visible = true
        state.expandButton.Position = UDim2.fromOffset(3 + indent, 0)
        state.expandButton.Visible = node.hasChildren
        state.arrow.Visible = node.hasChildren
        if node.hasChildren then
            UI.setIcon(
                state.arrow,
                expanded[instance] and "chevron-down" or "chevron-right",
                Theme.icon
            )
        end
        state.classIcon.ImageRectOffset = Vector2.new(classIconIndex(instance) * 16, 0)
        state.classIcon.Position = UDim2.fromOffset(30 + indent, 6)
        state.label.Position = UDim2.fromOffset(56 + indent, 0)
        state.label.Size = UDim2.new(1, -64 - indent, 1, 0)
        state.label.Text = tostring(instance.Name)
        state.label.TextColor3 = Theme.text
    end

    refreshRows = function()
        if not tree.Parent then
            return
        end
        local visibleHeight = math.max(tree.AbsoluteSize.Y, ROW_HEIGHT)
        local required = math.min(100, math.ceil(visibleHeight / ROW_HEIGHT) + POOL_BUFFER)
        while #rowPool < required do
            createPooledRow()
        end

        local first = math.max(1, math.floor(tree.CanvasPosition.Y / ROW_HEIGHT) + 1)
        for slot, state in ipairs(rowPool) do
            local index = first + slot - 1
            updatePooledRow(state, visibleNodes[index], index)
        end
    end

    local function applyVisibleNodes(nodes, title, detail, previousPosition)
        visibleNodes = nodes
        tree.CanvasSize = UDim2.fromOffset(0, #visibleNodes * ROW_HEIGHT + 4)
        treeTitle.Text = title
        treeMeta.Text = detail
        local maxY = math.max(0, tree.AbsoluteCanvasSize.Y - tree.AbsoluteWindowSize.Y)
        tree.CanvasPosition = Vector2.new(0, math.min(previousPosition.Y, maxY))
        refreshRows()
    end

    local function searchInstances(query, token, loader)
        local matches = {}
        local queue = roots()
        local head = 1
        local visited = 0
        local normalized = query:lower()

        while head <= #queue
            and visited < MAX_SEARCH_VISITS
            and #matches < MAX_SEARCH_RESULTS
        do
            if token ~= searchToken or not ctx:isActive() then
                return nil, visited
            end
            local instance = queue[head]
            head = head + 1
            visited = visited + 1

            if instance ~= NIL_ROOT then
                local name = tostring(instance.Name):lower()
                local className = tostring(instance.ClassName):lower()
                if name:find(normalized, 1, true) or className:find(normalized, 1, true) then
                    table.insert(matches, {
                        instance = instance,
                        depth = 0,
                        hasChildren = hasChildren(instance),
                    })
                end
            end

            local children = rawChildren(instance)
            for index = 1, math.min(#children, MAX_CHILDREN) do
                if #queue < MAX_SEARCH_VISITS + MAX_CHILDREN then
                    table.insert(queue, children[index])
                end
            end
            if visited % BUILD_BATCH == 0 then
                if loader then
                    loader:setDetail(
                        ("%d instances scanned | %d matches"):format(visited, #matches)
                    )
                end
                task.wait()
            end
        end
        return matches, visited
    end

    rebuildTree = function()
        if not ctx:isActive() then
            return
        end
        buildToken = buildToken + 1
        local currentBuild = buildToken
        local previousPosition = tree.CanvasPosition
        local query = trim(search.Text)

        if query ~= "" then
            searchToken = searchToken + 1
            local currentSearch = searchToken
            local loader = startTreeLoader("Searching instances", "Starting bounded DataModel scan...")
            treeTitle.Text = "SEARCHING..."
            task.spawn(function()
                local matches, visited = searchInstances(query, currentSearch, loader)
                if not matches or currentSearch ~= searchToken or not ctx:isActive() then
                    return
                end
                stopTreeLoader()
                applyVisibleNodes(
                    matches,
                    ("SEARCH RESULTS | %d SHOWN"):format(#matches),
                    ("%d scanned | results are virtualized"):format(visited),
                    previousPosition
                )
            end)
            return
        end

        searchToken = searchToken + 1
        local loader = startTreeLoader("Loading Explorer", "Flattening expanded branches...")
        treeTitle.Text = "LOADING DATA MODEL..."
        task.spawn(function()
            task.wait()
            local nodes = {}
            local capped = false

            local function append(instance, depth, knownChildren)
                if currentBuild ~= buildToken or not ctx:isActive() then
                    return false
                end
                if #nodes >= MAX_VISIBLE_NODES then
                    capped = true
                    return false
                end

                local children = knownChildren
                if expanded[instance] and children == nil then
                    children = safeChildren(instance)
                end
                local nodeHasChildren = children ~= nil and #children > 0
                    or children == nil and hasChildren(instance)
                table.insert(nodes, {
                    instance = instance,
                    depth = depth,
                    hasChildren = nodeHasChildren,
                })

                if #nodes % BUILD_BATCH == 0 then
                    loader:setDetail(("%d tree nodes indexed..."):format(#nodes))
                    task.wait()
                    if currentBuild ~= buildToken or not ctx:isActive() then
                        return false
                    end
                end

                if expanded[instance] and children then
                    for _, child in ipairs(children) do
                        if append(child, depth + 1, nil) == false then
                            break
                        end
                    end
                end
                return not capped
            end

            for _, instance in ipairs(roots()) do
                if append(instance, 0, nil) == false then
                    break
                end
            end
            if currentBuild ~= buildToken or not ctx:isActive() then
                return
            end

            stopTreeLoader()
            applyVisibleNodes(
                nodes,
                ("DATA MODEL | %d VISIBLE"):format(#nodes),
                capped
                    and "Visible node cap reached; collapse a branch"
                    or "Live updates | only on-screen rows are rendered",
                previousPosition
            )
        end)
    end

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
            Size = UDim2.new(1, 0, 0, 26),
            Parent = properties,
        })
        UI.label({
            Font = Enum.Font.GothamBold,
            Position = UDim2.fromOffset(2, 0),
            Size = UDim2.fromScale(1, 1),
            Text = text:upper(),
            TextColor3 = Theme.textMuted,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
    end

    local function assignValue(instance, name, attribute, nextValue)
        local ok, message = pcall(function()
            if attribute then
                instance:SetAttribute(name, nextValue)
            else
                instance[name] = nextValue
            end
        end)
        if ok then
            ctx:status(name .. " updated", Theme.green)
            if name == "Name" then
                childState[instance] = nil
                rebuildTree()
                selectedName.Text = instance.Name
                selectedPath.Text = ctx:path(instance)
            end
        else
            ctx:toast(tostring(message), Theme.red, 4)
        end
        return ok
    end

    local function propertyRow(instance, name, value, attribute, order)
        local row = UI.panel({
            Parent = properties,
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 38),
            Radius = 6,
            StrokeTransparency = 0.35,
        })
        UI.label({
            Position = UDim2.fromOffset(10, 0),
            Size = UDim2.new(0.38, -10, 1, 0),
            Text = name,
            TextColor3 = attribute and Theme.cyan or Theme.textMuted,
            TextSize = 11,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })

        local kind = typeof(value)
        local canEdit = attribute or not READ_ONLY_PROPERTIES[name]
        if kind == "boolean" and canEdit then
            local toggle = UI.button({
                BackgroundColor3 = value and Theme.accentSoft or Theme.surfaceRaised,
                Parent = row,
                Position = UDim2.new(0.38, 0, 0, 5),
                Size = UDim2.new(0.62, -6, 1, -10),
                Text = value and "ON" or "OFF",
                TextColor3 = value and Theme.green or Theme.textMuted,
            })
            toggle.Position = UDim2.new(0.38, 0, 0, 5)
            connectDynamic(propertyConnections, toggle.MouseButton1Click, function()
                local nextValue = not value
                if assignValue(instance, name, attribute, nextValue) then
                    value = nextValue
                    toggle.Text = value and "ON" or "OFF"
                    toggle.TextColor3 = value and Theme.green or Theme.textMuted
                    toggle.BackgroundColor3 = value and Theme.accentSoft or Theme.surfaceRaised
                end
            end)
        elseif kind == "EnumItem" and canEdit then
            local enumButton = UI.button({
                Parent = row,
                Position = UDim2.new(0.38, 0, 0, 5),
                Size = UDim2.new(0.62, -6, 1, -10),
                Text = tostring(value):match("[^%.]+$") or tostring(value),
                TextColor3 = Theme.cyan,
            })
            enumButton.Position = UDim2.new(0.38, 0, 0, 5)
            connectDynamic(propertyConnections, enumButton.MouseButton1Click, function()
                local ok, items = pcall(function()
                    return value.EnumType:GetEnumItems()
                end)
                if not ok or #items == 0 then
                    return
                end
                local current = table.find(items, value) or 0
                local nextValue = items[current % #items + 1]
                if assignValue(instance, name, attribute, nextValue) then
                    value = nextValue
                    enumButton.Text = tostring(value):match("[^%.]+$") or tostring(value)
                end
            end)
        elseif textEditable(value) and canEdit then
            local valueField = UI.input({
                Parent = row,
                Position = UDim2.new(0.38, 0, 0, 5),
                Size = UDim2.new(0.62, -6, 1, -10),
                Text = formatValue(value),
                TextSize = 11,
            })
            valueField.Position = UDim2.new(0.38, 0, 0, 5)
            connectDynamic(propertyConnections, valueField.FocusLost, function()
                local currentOk, current = pcall(function()
                    return attribute and instance:GetAttribute(name) or instance[name]
                end)
                if not currentOk then
                    ctx:toast("Property is no longer available", Theme.red)
                    return
                end
                if valueField.Text == formatValue(current) then
                    return
                end
                local parsed, nextValue = parseValue(valueField.Text, current)
                if not parsed then
                    valueField.Text = formatValue(current)
                    ctx:toast("Invalid " .. typeof(current) .. " value", Theme.red)
                    return
                end
                if assignValue(instance, name, attribute, nextValue) then
                    value = nextValue
                else
                    valueField.Text = formatValue(current)
                end
            end)
        else
            UI.label({
                Font = Enum.Font.Code,
                Position = UDim2.new(0.38, 8, 0, 0),
                Size = UDim2.new(0.62, -14, 1, 0),
                Text = formatValue(value),
                TextColor3 = canEdit and Theme.text or Theme.textMuted,
                TextSize = 11,
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
            UI.empty(properties, "Nothing selected", "Select an instance to inspect it.")
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

        connectDynamic(propertyConnections, instance.AttributeChanged, function()
            updateToken = updateToken + 1
            local token = updateToken
            task.delay(0.1, function()
                if token == updateToken and ctx:isActive() and ctx:getSelection() == instance then
                    renderProperties(instance)
                end
            end)
        end)
        connectDynamic(
            propertyConnections,
            instance:GetPropertyChangedSignal("Name"),
            function()
                selectedName.Text = instance.Name
                selectedPath.Text = ctx:path(instance)
                rebuildTree()
            end
        )
    end

    local function scheduleAutoUpdate(parent)
        if parent then
            childState[parent] = nil
        end
        if not ctx.settings.explorerAutoUpdate
            or not ctx:isActive()
            or trim(search.Text) ~= ""
        then
            return
        end
        hierarchyUpdateAt = os.clock() + AUTO_UPDATE_DELAY
    end

    ctx:connect(tree:GetPropertyChangedSignal("CanvasPosition"), refreshRows)
    ctx:connect(tree:GetPropertyChangedSignal("AbsoluteSize"), refreshRows)
    ctx:connect(ctx.services.RunService.Heartbeat, function()
        if hierarchyUpdateAt and os.clock() >= hierarchyUpdateAt then
            hierarchyUpdateAt = nil
            if ctx:isActive() and ctx.settings.explorerAutoUpdate then
                rebuildTree()
            end
        end
    end)
    ctx:connect(search:GetPropertyChangedSignal("Text"), function()
        searchToken = searchToken + 1
        updateToken = updateToken + 1
        local token = searchToken
        task.delay(0.22, function()
            if token == searchToken and ctx:isActive() then
                rebuildTree()
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
        pickButton.Text = pickMode and "Picker armed" or "Pick object"
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

    -- Debounced hierarchy signals keep expanded branches current without the
    -- manual Refresh button or one task allocation per hierarchy mutation.
    ctx:connect(game.DescendantAdded, function(instance)
        scheduleAutoUpdate(instance.Parent)
    end)
    ctx:connect(game.DescendantRemoving, function(instance)
        scheduleAutoUpdate(instance.Parent)
    end)
    ctx:on("settingsChanged", function(key)
        if key == "includeNilInstances" then
            childState = setmetatable({}, { __mode = "k" })
            rebuildTree()
        end
    end)
    ctx:on("selectionChanged", function(instance, source)
        if source ~= ctx.id then
            renderProperties(instance)
        end
        refreshRows()
    end)
    ctx:on("activeFeatureChanged", function(id)
        if id == ctx.id then
            rebuildTree()
            renderProperties(ctx:getSelection())
        else
            buildToken = buildToken + 1
            searchToken = searchToken + 1
            stopTreeLoader()
        end
    end)

    ctx:cleanup(function()
        buildToken = buildToken + 1
        searchToken = searchToken + 1
        updateToken = updateToken + 1
        hierarchyUpdateAt = nil
        stopTreeLoader()
        disconnectAll(rowConnections)
        disconnectAll(propertyConnections)
    end)

    rebuildTree()
    renderProperties(ctx:getSelection())

    return {
        refresh = rebuildTree,
        destroy = function() end,
    }
end

return Explorer
