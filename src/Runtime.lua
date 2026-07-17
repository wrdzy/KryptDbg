-- Shared runtime, state, events, and lazy feature lifecycle for KryptDbg.

local Runtime = {}

local function quote(value)
    return string.format("%q", tostring(value))
end

local function isIdentifier(value)
    return type(value) == "string" and value:match("^[%a_][%w_]*$") ~= nil
end

local function instancePath(instance)
    if typeof(instance) ~= "Instance" then
        return "nil"
    end

    local parts = {}
    local cursor = instance
    while cursor and cursor ~= game do
        local name = cursor.Name
        if isIdentifier(name) then
            table.insert(parts, 1, "." .. name)
        else
            table.insert(parts, 1, "[" .. quote(name) .. "]")
        end
        cursor = cursor.Parent
    end

    return "game" .. table.concat(parts)
end

local function serialize(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 7 then
        return "nil --[[ depth limit ]]"
    end

    local kind = typeof(value)
    if kind == "nil" then
        return "nil"
    elseif kind == "string" then
        return quote(value)
    elseif kind == "number" then
        if value ~= value then
            return "0/0"
        elseif value == math.huge then
            return "math.huge"
        elseif value == -math.huge then
            return "-math.huge"
        end
        return tostring(value)
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "Instance" then
        return instancePath(value)
    elseif kind == "Vector2" then
        return ("Vector2.new(%s, %s)"):format(value.X, value.Y)
    elseif kind == "Vector3" then
        return ("Vector3.new(%s, %s, %s)"):format(value.X, value.Y, value.Z)
    elseif kind == "Color3" then
        return ("Color3.new(%s, %s, %s)"):format(value.R, value.G, value.B)
    elseif kind == "UDim" then
        return ("UDim.new(%s, %s)"):format(value.Scale, value.Offset)
    elseif kind == "UDim2" then
        return ("UDim2.new(%s, %s, %s, %s)"):format(
            value.X.Scale,
            value.X.Offset,
            value.Y.Scale,
            value.Y.Offset
        )
    elseif kind == "CFrame" then
        local components = { value:GetComponents() }
        for index, component in ipairs(components) do
            components[index] = tostring(component)
        end
        return "CFrame.new(" .. table.concat(components, ", ") .. ")"
    elseif kind == "EnumItem" then
        return tostring(value)
    elseif kind == "table" then
        if seen[value] then
            return "nil --[[ cycle ]]"
        end
        seen[value] = true

        local lines = { "{" }
        local count = 0
        for key, nested in pairs(value) do
            count = count + 1
            if count > 100 then
                table.insert(lines, "    --[[ item limit ]]")
                break
            end

            local keyText
            if type(key) == "string" and isIdentifier(key) then
                keyText = key
            else
                keyText = "[" .. serialize(key, depth + 1, seen) .. "]"
            end
            table.insert(lines, "    " .. keyText .. " = " .. serialize(nested, depth + 1, seen) .. ",")
        end
        table.insert(lines, "}")
        seen[value] = nil
        return table.concat(lines, "\n")
    end

    return "nil --[[ unsupported " .. kind .. " ]]"
end

local function copyText(text)
    local environment = (getgenv and getgenv()) or _G
    local clipboard = rawget(environment, "setclipboard")
        or rawget(environment, "toclipboard")
        or setclipboard
        or toclipboard

    if type(clipboard) ~= "function" then
        return false, "Clipboard API is unavailable"
    end

    local ok, message = pcall(clipboard, tostring(text))
    return ok, ok and nil or tostring(message)
end

function Runtime.start(config)
    assert(type(config) == "table", "Runtime.start requires a config table")
    assert(type(config.execute) == "function", "Runtime.start requires a module executor")
    assert(type(config.manifest) == "table", "Runtime.start requires a manifest")
    assert(type(config.ui) == "table", "Runtime.start requires KryptUI")

    local UI = config.ui
    local Theme = UI.Theme
    local manifest = config.manifest
    local UserInputService = game:GetService("UserInputService")

    local app = {
        alive = true,
        loading = {},
        loaded = {},
        loadOrder = {},
        modules = {},
        contexts = {},
        connections = {},
        selectedInstance = nil,
        manifest = manifest,
        baseUrl = config.baseUrl,
    }

    app.services = {
        Players = game:GetService("Players"),
        CoreGui = game:GetService("CoreGui"),
        GuiService = game:GetService("GuiService"),
        HttpService = game:GetService("HttpService"),
        LogService = game:GetService("LogService"),
        RunService = game:GetService("RunService"),
        Stats = game:GetService("Stats"),
        TweenService = game:GetService("TweenService"),
        UserInputService = UserInputService,
    }

    app.events = {
        selectionChanged = UI.Signal(),
        activeFeatureChanged = UI.Signal(),
        moduleLoaded = UI.Signal(),
        shuttingDown = UI.Signal(),
    }

    local window = UI.new({
        Name = "KryptDbg",
        Title = manifest.name,
        Subtitle = "One workspace · lazy feature modules",
        Size = Vector2.new(1100, 700),
        MinimumSize = Vector2.new(860, 520),
        MaximumSize = Vector2.new(1380, 860),
    })
    app.window = window

    local featureById = {}
    for order, feature in ipairs(manifest.features) do
        feature.order = order
        featureById[feature.id] = feature
        window:addTab(feature)
    end

    local highlight = UI.create("Highlight", {
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        FillColor = Theme.accent,
        FillTransparency = 0.82,
        Name = "KryptDbgSelection",
        OutlineColor = Theme.cyan,
        OutlineTransparency = 0.15,
        Parent = window.screen,
    })
    app.highlight = highlight

    function app:setStatus(message, color)
        window:setStatus(message, color)
    end

    function app:toast(message, color, duration)
        window:toast(message, color, duration)
    end

    function app:setSelection(instance, source)
        if instance ~= nil and typeof(instance) ~= "Instance" then
            return
        end

        if self.selectedInstance == instance then
            return
        end

        self.selectedInstance = instance
        highlight.Adornee = instance
        self.events.selectionChanged:fire(instance, source)
    end

    function app:getSelection()
        return self.selectedInstance
    end

    function app:isActive(id)
        return window.activeTab == id
    end

    function app:getLoadedModules()
        local result = {}
        for _, id in ipairs(self.loadOrder) do
            table.insert(result, id)
        end
        return result
    end

    local function makeContext(feature)
        local context = {
            id = feature.id,
            definition = feature,
            page = window.tabs[feature.id].page,
            app = app,
            ui = UI,
            theme = Theme,
            services = app.services,
            connections = {},
            cleanups = {},
        }

        function context:connect(signal, callback)
            local connection = signal:Connect(callback)
            table.insert(self.connections, connection)
            return connection
        end

        function context:cleanup(callback)
            table.insert(self.cleanups, callback)
            return callback
        end

        function context:on(eventName, callback)
            local signal = app.events[eventName]
            assert(signal, "Unknown KryptDbg event: " .. tostring(eventName))
            local connection = signal:connect(callback)
            table.insert(self.connections, connection)
            return connection
        end

        function context:emit(eventName, ...)
            local signal = app.events[eventName]
            if signal then
                signal:fire(...)
            end
        end

        function context:isActive()
            return app:isActive(self.id)
        end

        function context:setSelection(instance)
            app:setSelection(instance, self.id)
        end

        function context:getSelection()
            return app:getSelection()
        end

        function context:status(message, color)
            app:setStatus(message, color)
        end

        function context:toast(message, color, duration)
            app:toast(message, color, duration)
        end

        function context:copy(text, successMessage)
            local ok, message = copyText(text)
            if ok then
                self:toast(successMessage or "Copied to clipboard", Theme.green)
            else
                self:toast(message, Theme.red)
            end
            return ok
        end

        function context:path(instance)
            return instancePath(instance)
        end

        function context:serialize(value)
            return serialize(value)
        end

        function context:destroy()
            for index = #self.cleanups, 1, -1 do
                pcall(self.cleanups[index])
            end
            self.cleanups = {}

            for _, connection in ipairs(self.connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            self.connections = {}
        end

        return context
    end

    function app:loadFeature(id)
        if not self.alive or self.loaded[id] or self.loading[id] then
            return self.modules[id]
        end

        local feature = featureById[id]
        if not feature then
            self:toast("Unknown feature: " .. tostring(id), Theme.red)
            return nil
        end

        self.loading[id] = true
        window:setTabLoading(id, true)
        self:setStatus("Loading " .. id .. "…", Theme.yellow)

        task.spawn(function()
            local context
            local ok, result = pcall(function()
                local module = config.execute(feature.path)
                if type(module) ~= "table" or type(module.mount) ~= "function" then
                    error(feature.path .. " must return a table with mount(context)")
                end

                context = makeContext(feature)
                self.contexts[id] = context
                local controller = module.mount(context)
                self.modules[id] = {
                    definition = module,
                    controller = controller,
                }
            end)

            self.loading[id] = nil
            if not self.alive then
                return
            end

            if ok then
                self.loaded[id] = true
                table.insert(self.loadOrder, id)
                window:setTabLoaded(id)
                self:setStatus(id .. " ready", Theme.green)
                self.events.moduleLoaded:fire(id)
            else
                if context then
                    context:destroy()
                    self.contexts[id] = nil
                end
                window:setTabError(id, result)
                self:setStatus(id .. " failed to load", Theme.red)
                self:toast(tostring(result), Theme.red, 5)
            end
        end)
    end

    function app:switchFeature(id)
        window:selectTab(id)
    end

    function app:destroy()
        if not self.alive then
            return
        end
        self.alive = false
        self.events.shuttingDown:fire()

        for index = #self.loadOrder, 1, -1 do
            local id = self.loadOrder[index]
            local entry = self.modules[id]
            if entry and entry.controller and type(entry.controller.destroy) == "function" then
                pcall(function()
                    entry.controller:destroy()
                end)
            end
            if self.contexts[id] then
                self.contexts[id]:destroy()
            end
        end

        for _, connection in ipairs(self.connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        self.connections = {}

        for _, signal in pairs(self.events) do
            signal:destroy()
        end

        if highlight then
            highlight:Destroy()
        end
        window:destroy()
    end

    table.insert(app.connections, window.onTabSelected:connect(function(id)
        app:loadFeature(id)
        app.events.activeFeatureChanged:fire(id)
    end))

    table.insert(app.connections, window.onDestroyed:connect(function()
        app:destroy()
    end))

    table.insert(app.connections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
            and not UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        then
            return
        end

        for _, feature in ipairs(manifest.features) do
            if input.KeyCode == feature.shortcut then
                app:switchFeature(feature.id)
                return
            end
        end
    end))

    window:selectTab(manifest.defaultFeature)
    return app
end

return Runtime
