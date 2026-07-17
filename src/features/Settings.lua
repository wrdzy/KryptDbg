local Settings = {}

local MAX_INSTANCES_WITH_APPEND = 50000
local MAX_INSTANCES_WITHOUT_APPEND = 15000
local MAX_SCRIPTS = 1000
local MAX_SOURCE_CHARS = 500000
local MAX_PROPERTIES_PER_INSTANCE = 180
local FLUSH_EVERY = 200

local PROPERTY_GROUPS = {
    Instance = {
        "Archivable",
    },
    BasePart = {
        "Anchored",
        "CanCollide",
        "CanQuery",
        "CanTouch",
        "CastShadow",
        "Color",
        "Material",
        "Massless",
        "Position",
        "Rotation",
        "Size",
        "Transparency",
    },
    Model = {
        "PrimaryPart",
        "WorldPivot",
    },
    Humanoid = {
        "AutoRotate",
        "Health",
        "HipHeight",
        "JumpHeight",
        "JumpPower",
        "MaxHealth",
        "WalkSpeed",
    },
    GuiObject = {
        "Active",
        "AnchorPoint",
        "BackgroundColor3",
        "BackgroundTransparency",
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
        "MultiLine",
        "PlaceholderText",
        "Text",
        "TextColor3",
        "TextSize",
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

local function executorFunction(name)
    local environment = (getgenv and getgenv()) or _G
    local value = rawget(environment, name)
    if value == nil and type(_G) == "table" then
        value = rawget(_G, name)
    end
    return type(value) == "function" and value or nil
end

local function safePath(instance)
    local ok, fullName = pcall(instance.GetFullName, instance)
    return ok and fullName or tostring(instance.Name)
end

local function cleanFileName(value)
    local clean = tostring(value):gsub('[<>:"/\\|%?%*%c]', "_")
    clean = clean:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.+$", "")
    if clean == "" then
        clean = "unnamed"
    end
    return clean:sub(1, 80)
end

local function encodeValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 5 then
        return "<depth-limit>"
    end

    local kind = typeof(value)
    if kind == "nil" or kind == "string" or kind == "boolean" then
        return value
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return tostring(value)
        end
        return value
    elseif kind == "Instance" then
        return {
            type = "Instance",
            className = value.ClassName,
            path = safePath(value),
        }
    elseif kind == "Vector2" then
        return { type = kind, x = value.X, y = value.Y }
    elseif kind == "Vector3" then
        return { type = kind, x = value.X, y = value.Y, z = value.Z }
    elseif kind == "Color3" then
        return { type = kind, r = value.R, g = value.G, b = value.B }
    elseif kind == "UDim" then
        return { type = kind, scale = value.Scale, offset = value.Offset }
    elseif kind == "UDim2" then
        return {
            type = kind,
            x = { scale = value.X.Scale, offset = value.X.Offset },
            y = { scale = value.Y.Scale, offset = value.Y.Offset },
        }
    elseif kind == "CFrame" then
        return {
            type = kind,
            components = { value:GetComponents() },
        }
    elseif kind == "BrickColor" or kind == "EnumItem"
        or kind == "NumberRange" or kind == "NumberSequence"
        or kind == "ColorSequence" or kind == "Rect"
    then
        return { type = kind, value = tostring(value) }
    elseif kind == "table" then
        if seen[value] then
            return "<cycle>"
        end
        seen[value] = true
        local result = {}
        local count = 0
        for key, nested in pairs(value) do
            count = count + 1
            if count > 200 then
                result.__truncated = true
                break
            end
            result[tostring(key)] = encodeValue(nested, depth + 1, seen)
        end
        seen[value] = nil
        return result
    end
    return { type = kind, value = tostring(value) }
end

local function readProperties(instance, getProperties)
    local result = {}
    local seen = {}
    local discovered = 0

    if type(getProperties) == "function" then
        local read, values = pcall(getProperties, instance)
        if read and type(values) == "table" then
            for key, value in pairs(values) do
                local name
                local propertyValue = value
                if type(key) == "string" then
                    name = key
                elseif type(value) == "string" then
                    name = value
                    local valueOk, current = pcall(function()
                        return instance[name]
                    end)
                    if valueOk then
                        propertyValue = current
                    else
                        name = nil
                    end
                end
                if name and name ~= "Source" and name ~= "Parent" and name ~= "ClassName" then
                    discovered = discovered + 1
                    if discovered > MAX_PROPERTIES_PER_INSTANCE then
                        result.__truncated = true
                        break
                    end
                    seen[name] = true
                    result[name] = encodeValue(propertyValue)
                end
            end
        end
    end

    for className, names in pairs(PROPERTY_GROUPS) do
        local ok, matches = pcall(instance.IsA, instance, className)
        if ok and matches then
            for _, name in ipairs(names) do
                if not seen[name] then
                    seen[name] = true
                    local read, value = pcall(function()
                        return instance[name]
                    end)
                    if read then
                        result[name] = encodeValue(value)
                    end
                end
            end
        end
    end
    return result
end

function Settings.mount(ctx)
    local UI = ctx.ui
    local Theme = ctx.theme
    local page = ctx.page
    local running = false
    local dumpLoader
    local toggleRenderers = {}

    local toolbar = UI.toolbar(page)
    UI.label({
        Font = Enum.Font.GothamBold,
        Size = UDim2.fromOffset(220, 30),
        Text = "SETTINGS",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = toolbar,
    })
    UI.label({
        Size = UDim2.fromOffset(470, 30),
        Text = "Preferences persist while this KryptDbg session is open",
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

    local preferencesPanel = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Size = UDim2.new(0.47, -5, 1, 0),
    })
    local preferencesHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 48),
        Parent = preferencesPanel,
    })
    UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 5),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "PREFERENCES",
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = preferencesHeader,
    })
    UI.label({
        Position = UDim2.fromOffset(12, 25),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Explorer behavior and dump contents",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = preferencesHeader,
    })
    local preferences = UI.scroller({
        Parent = preferencesPanel,
        Position = UDim2.fromOffset(0, 48),
        Size = UDim2.new(1, 0, 1, -48),
        Padding = 8,
        Spacing = 6,
    })

    local dumpPanel = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Position = UDim2.new(0.47, 5, 0, 0),
        Size = UDim2.new(0.53, -5, 1, 0),
    })
    local dumpHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 48),
        Parent = dumpPanel,
    })
    UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 5),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "AI DEBUG DUMP",
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = dumpHeader,
    })
    UI.label({
        Position = UDim2.fromOffset(12, 25),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Local, structured, bounded workspace export",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = dumpHeader,
    })

    local dumpContent = UI.create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 60),
        Size = UDim2.new(1, -24, 1, -72),
        Parent = dumpPanel,
    })
    local folderLabel = UI.label({
        Font = Enum.Font.Code,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 38),
        Text = "KryptDbg/DUMP",
        TextColor3 = Theme.cyan,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = dumpContent,
    })
    local workspaceState = UI.label({
        Position = UDim2.fromOffset(0, 44),
        Size = UDim2.new(1, 0, 0, 40),
        Text = ctx.workspace.available
            and "Workspace ready. Dumps contain metadata, a JSONL instance tree, attributes, selected properties, and available script sources."
            or "Filesystem APIs are unavailable. makefolder and writefile are required.",
        TextColor3 = ctx.workspace.available and Theme.textMuted or Theme.red,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = dumpContent,
    })
    local dumpButton = UI.button({
        BackgroundColor3 = Theme.accentSoft,
        Icon = "database-backup",
        Parent = dumpContent,
        Position = UDim2.fromOffset(0, 98),
        Size = UDim2.new(1, 0, 0, 38),
        Text = "Create AI debug dump",
        TextColor3 = Theme.green,
    })
    dumpButton.Position = UDim2.fromOffset(0, 98)
    local copyFolderButton = UI.button({
        Icon = "copy",
        Parent = dumpContent,
        Position = UDim2.fromOffset(0, 146),
        Size = UDim2.new(1, 0, 0, 34),
        Text = "Copy dump folder",
    })
    copyFolderButton.Position = UDim2.fromOffset(0, 146)
    local dumpStatus = UI.label({
        Position = UDim2.fromOffset(0, 192),
        Size = UDim2.new(1, 0, 1, -192),
        Text = "Nothing dumped yet.",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = dumpContent,
    })

    local function settingRow(order, key, title, detail)
        local row = UI.panel({
            Parent = preferences,
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 64),
            Radius = 7,
            StrokeTransparency = 0.3,
        })
        UI.label({
            Font = Enum.Font.GothamMedium,
            Position = UDim2.fromOffset(12, 7),
            Size = UDim2.new(1, -112, 0, 20),
            Text = title,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        UI.label({
            Position = UDim2.fromOffset(12, 29),
            Size = UDim2.new(1, -112, 0, 27),
            Text = detail,
            TextColor3 = Theme.textMuted,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = row,
        })
        local toggle = UI.button({
            Parent = row,
            Position = UDim2.new(1, -94, 0.5, -15),
            Size = UDim2.fromOffset(82, 30),
            Text = "",
        })
        toggle.Position = UDim2.new(1, -94, 0.5, -15)
        local function render()
            local value = ctx.settings[key] == true
            toggle.Text = value and "ON" or "OFF"
            toggle.TextColor3 = value and Theme.green or Theme.textMuted
            toggle.BackgroundColor3 = value and Theme.accentSoft or Theme.surfaceRaised
        end
        toggleRenderers[key] = render
        render()
        ctx:connect(toggle.MouseButton1Click, function()
            ctx:setSetting(key, not ctx.settings[key])
            render()
        end)
    end

    settingRow(
        1,
        "explorerAutoUpdate",
        "Live Explorer updates",
        "Debounces hierarchy changes and refreshes expanded branches automatically."
    )
    settingRow(
        2,
        "includeNilInstances",
        "Include nil instances",
        "Shows and exports executor-visible instances that are no longer parented."
    )
    settingRow(
        3,
        "dumpAttributes",
        "Dump attributes",
        "Adds every readable custom attribute to each instance record."
    )
    settingRow(
        4,
        "dumpProperties",
        "Dump useful properties",
        "Adds curated, AI-friendly properties based on each Roblox class."
    )
    settingRow(
        5,
        "dumpScriptSources",
        "Dump script sources",
        "Uses decompile or readable Source and saves bounded .lua files when available."
    )

    local function createDump()
        if running then
            ctx:toast("A dump is already running", Theme.yellow)
            return
        end

        local makeFolder = executorFunction("makefolder")
        local isFolder = executorFunction("isfolder")
        local writeFile = executorFunction("writefile")
        local appendFile = executorFunction("appendfile")
        local decompile = executorFunction("decompile")
        local getNilInstances = executorFunction("getnilinstances")
        local getProperties = executorFunction("getproperties")
        if type(makeFolder) ~= "function" or type(writeFile) ~= "function" then
            ctx:toast("makefolder and writefile are required", Theme.red, 4)
            return
        end

        running = true
        dumpButton.Text = "Dumping..."
        dumpButton.TextColor3 = Theme.yellow
        dumpStatus.Text = "Preparing workspace..."
        local loader = UI.loader({
            BackgroundColor3 = Theme.canvas,
            BackgroundTransparency = 0.05,
            Detail = "Preparing KryptDbg/DUMP...",
            Parent = dumpPanel,
            Position = UDim2.fromOffset(0, 48),
            Size = UDim2.new(1, 0, 1, -48),
            Title = "Creating AI debug dump",
            ZIndex = 20,
        })
        dumpLoader = loader

        task.spawn(function()
            local ok, result = pcall(function()
                local function ensure(path)
                    if type(isFolder) == "function" then
                        local checked, exists = pcall(isFolder, path)
                        if checked and exists then
                            return
                        end
                    end
                    local made, message = pcall(makeFolder, path)
                    if not made then
                        local cleanMessage = tostring(message)
                        if not cleanMessage:lower():find("exist", 1, true) then
                            error(("Could not create %s: %s"):format(path, cleanMessage))
                        end
                    end
                end
                local function write(path, contents)
                    local written, message = pcall(writeFile, path, contents)
                    if not written then
                        error(("Could not write %s: %s"):format(path, tostring(message)))
                    end
                end

                ensure(ctx.workspace.root)
                ensure(ctx.workspace.dump)
                local dateOk, dateText = pcall(os.date, "%Y%m%d_%H%M%S")
                local timestamp = dateOk and dateText or tostring(math.floor(os.time()))
                local suffix = math.floor(os.clock() * 1000) % 1000
                local function gameValue(name, fallback)
                    local read, value = pcall(function()
                        return game[name]
                    end)
                    return read and value or fallback
                end
                local placeId = gameValue("PlaceId", 0)
                local gameId = gameValue("GameId", 0)
                local dumpName = ("%s_%s_%03d"):format(
                    tostring(placeId),
                    timestamp,
                    suffix
                )
                local rootPath = ctx.workspace.dump .. "/" .. dumpName
                local scriptsPath = rootPath .. "/scripts"
                ensure(rootPath)
                ensure(scriptsPath)

                local HttpService = ctx.services.HttpService
                local instancesPath = rootPath .. "/instances.jsonl"
                local scriptIndexPath = rootPath .. "/scripts/index.jsonl"
                write(instancesPath, "")
                write(scriptIndexPath, "")

                local buffered = {}
                local function appendLines(path, lines)
                    if #lines == 0 then
                        return
                    end
                    local contents = table.concat(lines, "\n") .. "\n"
                    if type(appendFile) == "function" then
                        local appended, message = pcall(appendFile, path, contents)
                        if not appended then
                            error(("Could not append %s: %s"):format(path, tostring(message)))
                        end
                    else
                        local target = buffered[path]
                        if not target then
                            target = {}
                            buffered[path] = target
                        end
                        table.insert(target, contents)
                    end
                    table.clear(lines)
                end

                local instanceLimit = type(appendFile) == "function"
                    and MAX_INSTANCES_WITH_APPEND or MAX_INSTANCES_WITHOUT_APPEND
                local queue = {
                    { instance = game, parentId = nil, nilInstance = false },
                }
                local seen = setmetatable({}, { __mode = "k" })
                local scripts = {}
                local classCounts = {}
                local remoteCount = 0
                local instanceLines = {}
                local head = 1
                local count = 0
                local truncated = false

                if ctx.settings.includeNilInstances and type(getNilInstances) == "function" then
                    local nilOk, nilInstances = pcall(getNilInstances)
                    if nilOk and type(nilInstances) == "table" then
                        for index = 1, math.min(#nilInstances, 2000) do
                            if typeof(nilInstances[index]) == "Instance" then
                                table.insert(queue, {
                                    instance = nilInstances[index],
                                    parentId = nil,
                                    nilInstance = true,
                                })
                            end
                        end
                    end
                end

                while head <= #queue and count < instanceLimit do
                    if not ctx.app.alive then
                        error("Dump cancelled because KryptDbg closed")
                    end
                    local item = queue[head]
                    head = head + 1
                    local instance = item.instance
                    if not seen[instance] then
                        seen[instance] = true
                        count = count + 1
                        local id = count
                        local className = tostring(instance.ClassName)
                        classCounts[className] = (classCounts[className] or 0) + 1
                        if className == "RemoteEvent"
                            or className == "RemoteFunction"
                            or className == "UnreliableRemoteEvent"
                        then
                            remoteCount = remoteCount + 1
                        end

                        local record = {
                            id = id,
                            parentId = item.parentId,
                            name = tostring(instance.Name),
                            className = className,
                            path = instance == game and "game" or safePath(instance),
                            nilInstance = item.nilInstance == true,
                        }
                        if ctx.settings.dumpAttributes and instance ~= game then
                            local attributeOk, attributes = pcall(instance.GetAttributes, instance)
                            if attributeOk and next(attributes) then
                                record.attributes = encodeValue(attributes)
                            end
                        end
                        if ctx.settings.dumpProperties and instance ~= game then
                            local properties = readProperties(instance, getProperties)
                            if next(properties) then
                                record.properties = properties
                            end
                        end
                        table.insert(instanceLines, HttpService:JSONEncode(record))

                        local scriptOk, isScript = pcall(
                            instance.IsA,
                            instance,
                            "LuaSourceContainer"
                        )
                        if scriptOk and isScript and #scripts < MAX_SCRIPTS then
                            table.insert(scripts, {
                                instance = instance,
                                instanceId = id,
                                path = record.path,
                                className = className,
                                name = record.name,
                            })
                        end

                        local childrenOk, children = pcall(instance.GetChildren, instance)
                        if childrenOk then
                            for _, child in ipairs(children) do
                                if #queue < instanceLimit + 4000 then
                                    table.insert(queue, {
                                        instance = child,
                                        parentId = id,
                                        nilInstance = item.nilInstance,
                                    })
                                end
                            end
                        end

                        if #instanceLines >= FLUSH_EVERY then
                            appendLines(instancesPath, instanceLines)
                        end
                        if count % FLUSH_EVERY == 0 then
                            loader:setDetail(
                                ("%d instances indexed | %d scripts found"):format(
                                    count,
                                    #scripts
                                )
                            )
                            task.wait()
                        end
                    end
                end
                if head <= #queue then
                    truncated = true
                end
                appendLines(instancesPath, instanceLines)

                local scriptLines = {}
                local dumpedSources = 0
                for index, item in ipairs(scripts) do
                    if not ctx.app.alive then
                        error("Dump cancelled because KryptDbg closed")
                    end
                    local source
                    local sourceMethod = "unavailable"
                    if ctx.settings.dumpScriptSources then
                        if type(decompile) == "function" then
                            local sourceOk, resultText = pcall(decompile, item.instance)
                            if sourceOk and type(resultText) == "string" and resultText ~= "" then
                                source = resultText
                                sourceMethod = "decompile"
                            end
                        end
                        if not source then
                            local sourceOk, resultText = pcall(function()
                                return item.instance.Source
                            end)
                            if sourceOk and type(resultText) == "string" and resultText ~= "" then
                                source = resultText
                                sourceMethod = "Source"
                            end
                        end
                    end

                    local filename
                    local sourceTruncated = false
                    if source then
                        if #source > MAX_SOURCE_CHARS then
                            source = source:sub(1, MAX_SOURCE_CHARS)
                            sourceTruncated = true
                        end
                        filename = ("%04d_%s_%s.lua"):format(
                            index,
                            cleanFileName(item.className),
                            cleanFileName(item.name)
                        )
                        write(scriptsPath .. "/" .. filename, source)
                        dumpedSources = dumpedSources + 1
                    end
                    table.insert(scriptLines, HttpService:JSONEncode({
                        instanceId = item.instanceId,
                        name = item.name,
                        className = item.className,
                        path = item.path,
                        file = filename,
                        sourceMethod = sourceMethod,
                        truncated = sourceTruncated,
                    }))
                    if #scriptLines >= FLUSH_EVERY then
                        appendLines(scriptIndexPath, scriptLines)
                    end
                    if index % 10 == 0 then
                        loader:setDetail(
                            ("Reading scripts... %d / %d | %d sources saved"):format(
                                index,
                                #scripts,
                                dumpedSources
                            )
                        )
                        task.wait()
                    end
                end
                appendLines(scriptIndexPath, scriptLines)

                for path, chunks in pairs(buffered) do
                    write(path, table.concat(chunks))
                end

                local metadata = {
                    formatVersion = 1,
                    generatedAt = timestamp,
                    executor = ctx.app.executorName,
                    placeId = placeId,
                    gameId = gameId,
                    jobId = gameValue("JobId", ""),
                    placeVersion = gameValue("PlaceVersion", 0),
                    creatorId = gameValue("CreatorId", 0),
                    instanceCount = count,
                    instanceLimit = instanceLimit,
                    instanceTreeTruncated = truncated,
                    scriptCount = #scripts,
                    dumpedScriptSources = dumpedSources,
                    remoteCount = remoteCount,
                    classCounts = classCounts,
                    options = {
                        attributes = ctx.settings.dumpAttributes,
                        properties = ctx.settings.dumpProperties,
                        propertyDiscovery = type(getProperties) == "function"
                            and "getproperties + curated fallback" or "curated fallback",
                        scriptSources = ctx.settings.dumpScriptSources,
                        nilInstances = ctx.settings.includeNilInstances,
                    },
                }
                write(rootPath .. "/game.json", HttpService:JSONEncode(metadata))

                local summary = {
                    "# KryptDbg AI Debug Dump",
                    "",
                    ("Generated: %s"):format(timestamp),
                    ("Executor: %s"):format(ctx.app.executorName),
                    ("Place ID: %s"):format(tostring(placeId)),
                    ("Game ID: %s"):format(tostring(gameId)),
                    ("Instances: %d%s"):format(
                        count,
                        truncated and " (truncated at safety limit)" or ""
                    ),
                    ("Scripts indexed: %d"):format(#scripts),
                    ("Script sources saved: %d"):format(dumpedSources),
                    ("Remotes indexed: %d"):format(remoteCount),
                    "",
                    "## Files",
                    "",
                    "- `game.json`: place metadata, options, counts, and limits.",
                    "- `instances.jsonl`: one instance per line with hierarchy IDs.",
                    "- `scripts/index.jsonl`: script paths and source-file mapping.",
                    "- `scripts/*.lua`: available bounded script sources.",
                    "",
                    "Start AI analysis with this summary and `game.json`, then search",
                    "`instances.jsonl` by class/path and open only relevant script files.",
                    "Treat all runtime values as a client-side snapshot.",
                }
                write(rootPath .. "/summary.md", table.concat(summary, "\n"))
                return {
                    path = rootPath,
                    count = count,
                    scripts = #scripts,
                    sources = dumpedSources,
                    truncated = truncated,
                }
            end)

            loader:destroy()
            if dumpLoader == loader then
                dumpLoader = nil
            end
            running = false
            dumpButton.Text = "Create AI debug dump"
            dumpButton.TextColor3 = Theme.green
            if not ctx.app.alive then
                return
            end
            if ok then
                folderLabel.Text = result.path
                dumpStatus.Text = (
                    "Dump complete.\n%d instances | %d scripts | %d source files%s"
                ):format(
                    result.count,
                    result.scripts,
                    result.sources,
                    result.truncated and "\nSafety limit reached; see summary.md." or ""
                )
                dumpStatus.TextColor3 = Theme.green
                ctx:status("AI debug dump complete", Theme.green)
                ctx:toast("Dump saved to " .. result.path, Theme.green, 5)
            else
                dumpStatus.Text = "Dump failed:\n" .. tostring(result)
                dumpStatus.TextColor3 = Theme.red
                ctx:status("AI debug dump failed", Theme.red)
                ctx:toast(tostring(result), Theme.red, 5)
            end
        end)
    end

    ctx:connect(dumpButton.MouseButton1Click, createDump)
    ctx:connect(copyFolderButton.MouseButton1Click, function()
        ctx:copy(folderLabel.Text, "Dump folder copied")
    end)
    ctx:on("settingsChanged", function(key)
        local render = toggleRenderers[key]
        if render then
            render()
        end
    end)
    ctx:cleanup(function()
        if dumpLoader then
            dumpLoader:destroy()
            dumpLoader = nil
        end
    end)

    return {
        dump = createDump,
        destroy = function() end,
    }
end

return Settings
