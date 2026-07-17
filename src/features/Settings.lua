local Settings = {}

local MAX_INSTANCES_WITH_APPEND = 50000
local MAX_INSTANCES_WITHOUT_APPEND = 15000
local MAX_SCRIPTS = 1000
local MAX_SOURCE_CHARS = 500000
local MAX_PROPERTIES_PER_INSTANCE = 180
local MAX_REMOTES = 8000
local FLUSH_EVERY = 200

-- Instances worth surfacing in their own index because they define the
-- client/server (and client-internal) call surface an AI most often needs.
local REMOTE_CLASSES = {
    RemoteEvent = "server",
    RemoteFunction = "server",
    UnreliableRemoteEvent = "server",
    BindableEvent = "bindable",
    BindableFunction = "bindable",
}

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

-- JSONEncode rejects non-finite numbers, so normalize them to tags.
local function safeNumber(value)
    if value ~= value then
        return "nan"
    elseif value == math.huge then
        return "inf"
    elseif value == -math.huge then
        return "-inf"
    end
    return value
end

-- JSONEncode also rejects invalid UTF-8, which obfuscated games frequently put
-- in instance names. Keep valid text as-is; scrub only genuinely broken bytes.
local function safeString(value)
    local text = tostring(value)
    if utf8.len(text) ~= nil then
        return text
    end
    local rebuilt = table.create(#text)
    for index = 1, #text do
        local byte = string.byte(text, index)
        rebuilt[index] = (byte >= 32 and byte < 127) and string.char(byte) or "?"
    end
    return table.concat(rebuilt)
end

local function safePath(instance)
    local ok, fullName = pcall(instance.GetFullName, instance)
    return safeString(ok and fullName or instance.Name)
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
    if kind == "nil" or kind == "boolean" then
        return value
    elseif kind == "string" then
        return safeString(value)
    elseif kind == "number" then
        return safeNumber(value)
    elseif kind == "Instance" then
        return {
            type = "Instance",
            className = safeString(value.ClassName),
            path = safePath(value),
        }
    elseif kind == "Vector2" then
        return { type = kind, x = safeNumber(value.X), y = safeNumber(value.Y) }
    elseif kind == "Vector3" then
        return {
            type = kind,
            x = safeNumber(value.X),
            y = safeNumber(value.Y),
            z = safeNumber(value.Z),
        }
    elseif kind == "Color3" then
        return {
            type = kind,
            r = safeNumber(value.R),
            g = safeNumber(value.G),
            b = safeNumber(value.B),
        }
    elseif kind == "UDim" then
        return { type = kind, scale = safeNumber(value.Scale), offset = value.Offset }
    elseif kind == "UDim2" then
        return {
            type = kind,
            x = { scale = safeNumber(value.X.Scale), offset = value.X.Offset },
            y = { scale = safeNumber(value.Y.Scale), offset = value.Y.Offset },
        }
    elseif kind == "CFrame" then
        local components = { value:GetComponents() }
        for index = 1, #components do
            components[index] = safeNumber(components[index])
        end
        return { type = kind, components = components }
    elseif kind == "BrickColor" or kind == "EnumItem"
        or kind == "NumberRange" or kind == "NumberSequence"
        or kind == "ColorSequence" or kind == "Rect"
    then
        return { type = kind, value = safeString(value) }
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
            result[safeString(key)] = encodeValue(nested, depth + 1, seen)
        end
        seen[value] = nil
        return result
    end
    return { type = kind, value = safeString(value) }
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
            and "Workspace ready. Dumps contain metadata, session context, a JSONL instance tree, a remote index, attributes, selected properties, and available script sources."
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
                -- Belt-and-suspenders around the sanitizers: never let a single
                -- unencodable value abort a dump. Returns nil so the caller can
                -- fall back or skip the line.
                local function safeEncode(payload)
                    local ok, json = pcall(function()
                        return HttpService:JSONEncode(payload)
                    end)
                    return ok and json or nil
                end
                local instancesPath = rootPath .. "/instances.jsonl"
                local remotesPath = rootPath .. "/remotes.jsonl"
                local scriptIndexPath = rootPath .. "/scripts/index.jsonl"
                write(instancesPath, "")
                write(remotesPath, "")
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
                local remotes = {}
                local classCounts = {}
                local remoteCount = 0
                local bindableCount = 0
                local nilInstanceCount = 0
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

                        local record = {
                            id = id,
                            parentId = item.parentId,
                            name = safeString(instance.Name),
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
                        local encodedRecord = safeEncode(record)
                        if not encodedRecord then
                            -- Almost always an attribute/property value; keep the
                            -- structural record so the tree stays complete.
                            encodedRecord = safeEncode({
                                id = record.id,
                                parentId = record.parentId,
                                name = record.name,
                                className = record.className,
                                path = record.path,
                                nilInstance = record.nilInstance,
                                encodeError = "attributes/properties omitted (unencodable value)",
                            })
                        end
                        if encodedRecord then
                            table.insert(instanceLines, encodedRecord)
                        end

                        if record.nilInstance then
                            nilInstanceCount = nilInstanceCount + 1
                        end
                        local remoteKind = REMOTE_CLASSES[className]
                        if remoteKind then
                            if remoteKind == "server" then
                                remoteCount = remoteCount + 1
                            else
                                bindableCount = bindableCount + 1
                            end
                            if #remotes < MAX_REMOTES then
                                table.insert(remotes, {
                                    instanceId = id,
                                    name = record.name,
                                    className = className,
                                    path = record.path,
                                    kind = remoteKind,
                                    nilInstance = record.nilInstance,
                                })
                            end
                        end

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

                local remoteLines = {}
                for _, remote in ipairs(remotes) do
                    local encodedRemote = safeEncode(remote)
                    if encodedRemote then
                        table.insert(remoteLines, encodedRemote)
                    end
                end
                appendLines(remotesPath, remoteLines)

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
                    local encodedScript = safeEncode({
                        instanceId = item.instanceId,
                        name = safeString(item.name),
                        className = item.className,
                        path = safeString(item.path),
                        file = filename,
                        sourceMethod = sourceMethod,
                        truncated = sourceTruncated,
                    })
                    if encodedScript then
                        table.insert(scriptLines, encodedScript)
                    end
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

                -- Runtime state an AI cannot reconstruct from the static tree:
                -- who the local player is, where their character/camera are, and
                -- what the operator had selected when they took the snapshot.
                local session = { formatVersion = 1, generatedAt = timestamp }
                pcall(function()
                    local localPlayer = ctx.services.Players.LocalPlayer
                    if not localPlayer then
                        return
                    end
                    local info = {
                        name = tostring(localPlayer.Name),
                        userId = localPlayer.UserId,
                        displayName = tostring(localPlayer.DisplayName),
                    }
                    pcall(function()
                        info.accountAge = localPlayer.AccountAge
                    end)
                    pcall(function()
                        if localPlayer.Team then
                            info.teamPath = safePath(localPlayer.Team)
                        end
                    end)
                    local character = localPlayer.Character
                    if character then
                        info.characterPath = safePath(character)
                        local humanoid = character:FindFirstChildOfClass("Humanoid")
                        if humanoid then
                            info.humanoid = {
                                health = humanoid.Health,
                                maxHealth = humanoid.MaxHealth,
                                walkSpeed = humanoid.WalkSpeed,
                                jumpPower = humanoid.JumpPower,
                                state = tostring(humanoid:GetState()),
                            }
                        end
                        local root = character:FindFirstChild("HumanoidRootPart")
                        if root then
                            local position = root.Position
                            info.position = { x = position.X, y = position.Y, z = position.Z }
                        end
                    end
                    session.localPlayer = info
                end)
                pcall(function()
                    local list = ctx.services.Players:GetPlayers()
                    session.playerCount = #list
                    local names = {}
                    for index = 1, math.min(#list, 100) do
                        names[index] = tostring(list[index].Name)
                    end
                    session.playerNames = names
                end)
                pcall(function()
                    local camera = workspace.CurrentCamera
                    if not camera then
                        return
                    end
                    local position = camera.CFrame.Position
                    session.camera = {
                        cameraType = tostring(camera.CameraType),
                        fieldOfView = camera.FieldOfView,
                        position = { x = position.X, y = position.Y, z = position.Z },
                    }
                    if camera.CameraSubject then
                        session.camera.subjectPath = safePath(camera.CameraSubject)
                    end
                end)
                pcall(function()
                    session.world = {
                        gravity = workspace.Gravity,
                        streamingEnabled = workspace.StreamingEnabled,
                        distributedGameTime = workspace.DistributedGameTime,
                    }
                end)
                pcall(function()
                    local focus = ctx:getSelection()
                    if focus then
                        session.focusInstance = {
                            path = safePath(focus),
                            className = tostring(focus.ClassName),
                        }
                    end
                end)
                -- Runtime values such as Humanoid.MaxHealth can be math.huge,
                -- which JSONEncode rejects. encodeValue normalizes inf/NaN, and a
                -- guarded fallback keeps a late session failure from sinking a
                -- dump whose heavy files are already on disk.
                local sessionOk, sessionJson = pcall(function()
                    return HttpService:JSONEncode(encodeValue(session))
                end)
                if not sessionOk then
                    sessionJson = HttpService:JSONEncode({
                        formatVersion = 1,
                        generatedAt = timestamp,
                        error = "session snapshot could not be encoded",
                    })
                end
                write(rootPath .. "/session.json", sessionJson)

                local metadata = {
                    formatVersion = 1,
                    generatedAt = timestamp,
                    executor = safeString(ctx.app.executorName),
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
                    bindableCount = bindableCount,
                    remoteIndexCount = #remotes,
                    nilInstanceCount = nilInstanceCount,
                    distinctClassCount = (function()
                        local total = 0
                        for _ in pairs(classCounts) do
                            total = total + 1
                        end
                        return total
                    end)(),
                    classCounts = classCounts,
                    files = {
                        "summary.md",
                        "game.json",
                        "session.json",
                        "instances.jsonl",
                        "remotes.jsonl",
                        "scripts/index.jsonl",
                    },
                    options = {
                        attributes = ctx.settings.dumpAttributes,
                        properties = ctx.settings.dumpProperties,
                        propertyDiscovery = type(getProperties) == "function"
                            and "getproperties + curated fallback" or "curated fallback",
                        scriptSources = ctx.settings.dumpScriptSources,
                        nilInstances = ctx.settings.includeNilInstances,
                    },
                }
                local metadataJson = safeEncode(metadata)
                if not metadataJson then
                    metadata.classCounts = nil
                    metadataJson = safeEncode(metadata)
                        or HttpService:JSONEncode({
                            formatVersion = 1,
                            generatedAt = timestamp,
                            instanceCount = count,
                            encodeError = "metadata partially omitted",
                        })
                end
                write(rootPath .. "/game.json", metadataJson)

                local sortedClasses = {}
                for className, amount in pairs(classCounts) do
                    table.insert(sortedClasses, { className = className, amount = amount })
                end
                table.sort(sortedClasses, function(left, right)
                    if left.amount == right.amount then
                        return left.className < right.className
                    end
                    return left.amount > right.amount
                end)

                local summary = {
                    "# KryptDbg AI Debug Dump",
                    "",
                    ("Generated: %s"):format(timestamp),
                    ("Executor: %s"):format(ctx.app.executorName),
                    ("Place ID: %s"):format(tostring(placeId)),
                    ("Game ID: %s"):format(tostring(gameId)),
                    "",
                    "## Snapshot",
                    "",
                    ("- Instances: %d%s"):format(
                        count,
                        truncated and " (truncated at safety limit)" or ""
                    ),
                    ("- Distinct classes: %d"):format(#sortedClasses),
                    ("- Scripts indexed: %d (%d sources saved)"):format(#scripts, dumpedSources),
                    ("- Client/server remotes: %d"):format(remoteCount),
                    ("- Bindable events/functions: %d"):format(bindableCount),
                    ("- Nil-parented instances: %d"):format(nilInstanceCount),
                    "",
                    "## Files",
                    "",
                    "- `summary.md`: this overview — start here.",
                    "- `game.json`: place metadata, options, counts, limits, and the file list.",
                    "- `session.json`: local player, character, camera, and world state.",
                    "- `instances.jsonl`: one instance per line with hierarchy IDs, attributes, and properties.",
                    "- `remotes.jsonl`: every RemoteEvent/RemoteFunction and Bindable with its path.",
                    "- `scripts/index.jsonl`: script paths and source-file mapping.",
                    "- `scripts/*.lua`: available bounded script sources.",
                    "",
                    "## Top classes",
                    "",
                }
                for index = 1, math.min(#sortedClasses, 25) do
                    local entry = sortedClasses[index]
                    table.insert(summary, ("- %s x %d"):format(entry.className, entry.amount))
                end
                if #sortedClasses > 25 then
                    table.insert(
                        summary,
                        ("- ... and %d more classes (see game.json classCounts)"):format(
                            #sortedClasses - 25
                        )
                    )
                end
                for _, line in ipairs({
                    "",
                    "## How to use this dump",
                    "",
                    "1. Read this summary and `game.json` for shape and scale.",
                    "2. Use `remotes.jsonl` to map the client/server surface.",
                    "3. Search `instances.jsonl` by class or path for the subsystem you care about.",
                    "4. Open only the relevant `scripts/*.lua` via `scripts/index.jsonl`.",
                    "",
                    "Treat every runtime value as a client-side snapshot from a single moment.",
                }) do
                    table.insert(summary, line)
                end
                write(rootPath .. "/summary.md", table.concat(summary, "\n"))
                return {
                    path = rootPath,
                    count = count,
                    scripts = #scripts,
                    sources = dumpedSources,
                    remotes = remoteCount,
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
                    "Dump complete.\n%d instances | %d scripts | %d sources | %d remotes%s"
                ):format(
                    result.count,
                    result.scripts,
                    result.sources,
                    result.remotes,
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
