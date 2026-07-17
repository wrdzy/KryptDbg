local Diagnostics = {}

local CAPABILITIES = {
    { "hookmetamethod", "Remote namecall capture" },
    { "getnamecallmethod", "Namecall method inspection" },
    { "newcclosure", "Native-style callback wrapper" },
    { "setclipboard", "Clipboard integration", { "toclipboard" } },
    { "decompile", "Script source recovery" },
    { "getnilinstances", "Nil-instance Explorer roots" },
    { "saveinstance", "Place/model serialization" },
    { "writefile", "Local source export" },
    { "getcustomasset", "Bundled Lucide icon loading", { "getsynasset" } },
    { "loadstring", "Console command execution" },
    { "gethui", "Protected UI parent" },
    { "getcallingscript", "Calling-script metadata" },
    { "protect_gui", "GUI protection wrapper" },
}

function Diagnostics.mount(ctx)
    local UI = ctx.ui
    local Theme = ctx.theme
    local page = ctx.page
    local state = {
        fps = 0,
        frameTime = 0,
        frameCount = 0,
        frameTotal = 0,
        elapsed = 0,
        statsElapsed = 2,
        memory = nil,
        ping = nil,
    }
    local saveLoader

    ctx:cleanup(function()
        if saveLoader then
            saveLoader:destroy()
            saveLoader = nil
        end
    end)

    local toolbar = UI.toolbar(page)
    local copyButton = UI.button({
        Icon = "copy",
        Parent = toolbar,
        Text = "Copy report",
        TextColor3 = Theme.cyan,
        Width = 104,
    })
    local saveButton = UI.button({
        Icon = "save",
        Parent = toolbar,
        Text = "Save instance",
        TextColor3 = Theme.green,
        Width = 110,
    })
    local refreshButton = UI.button({
        Icon = "refresh-cw",
        Parent = toolbar,
        Text = "Refresh",
        Width = 84,
    })
    local summary = UI.label({
        Size = UDim2.fromOffset(330, 30),
        Text = "Capability-gated runtime overview",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = toolbar,
    })

    local content = UI.create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 52),
        Size = UDim2.new(1, -20, 1, -62),
        Parent = page,
    })

    local metrics = UI.create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 92),
        Parent = content,
    })

    local function metricCard(title, position)
        local card = UI.panel({
            Parent = metrics,
            Position = UDim2.new(position, position == 0 and 0 or 5, 0, 0),
            Size = UDim2.new(0.25, -8, 1, 0),
        })
        local label = UI.label({
            Font = Enum.Font.GothamBold,
            Position = UDim2.fromOffset(12, 9),
            Size = UDim2.new(1, -24, 0, 18),
            Text = title:upper(),
            TextColor3 = Theme.textFaint,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })
        local value = UI.label({
            Font = Enum.Font.GothamBold,
            Position = UDim2.fromOffset(12, 30),
            Size = UDim2.new(1, -24, 0, 30),
            Text = "—",
            TextColor3 = Theme.text,
            TextSize = 20,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })
        local detail = UI.label({
            Position = UDim2.fromOffset(12, 64),
            Size = UDim2.new(1, -24, 0, 14),
            Text = "Collecting…",
            TextColor3 = Theme.textMuted,
            TextSize = 8,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })
        return value, detail
    end

    local fpsValue, fpsDetail = metricCard("Frame rate", 0)
    local frameValue, frameDetail = metricCard("Frame time", 0.25)
    local memoryValue, memoryDetail = metricCard("Memory", 0.5)
    local pingValue, pingDetail = metricCard("Network", 0.75)

    local capabilityPanel = UI.panel({
        Parent = content,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 102),
        Size = UDim2.new(0.58, -5, 1, -102),
    })
    local capabilityHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = capabilityPanel,
    })
    local capabilityTitle = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 3),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "CAPABILITY MATRIX",
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = capabilityHeader,
    })
    local capabilityMeta = UI.label({
        Position = UDim2.fromOffset(12, 20),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Unavailable features remain disabled",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = capabilityHeader,
    })
    local capabilityList, capabilityLayout = UI.scroller({
        Parent = capabilityPanel,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 1, -42),
        Padding = 7,
        Spacing = 4,
    })

    local modulePanel = UI.panel({
        Parent = content,
        ClipsDescendants = true,
        Position = UDim2.new(0.58, 5, 0, 102),
        Size = UDim2.new(0.42, -5, 1, -102),
    })
    local moduleHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = modulePanel,
    })
    local moduleTitle = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 3),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "LAZY MODULES",
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = moduleHeader,
    })
    local moduleMeta = UI.label({
        Position = UDim2.fromOffset(12, 20),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Loaded modules stay mounted and share state",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = moduleHeader,
    })
    local moduleList, moduleLayout = UI.scroller({
        Parent = modulePanel,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 1, -42),
        Padding = 7,
        Spacing = 5,
    })

    local environment = (getgenv and getgenv()) or _G

    local function resolveCapability(definition)
        local names = { definition[1] }
        for _, alias in ipairs(definition[3] or {}) do
            table.insert(names, alias)
        end
        for _, name in ipairs(names) do
            local value = rawget(environment, name) or rawget(_G, name)
            if type(value) == "function" then
                return true, name, value
            end
        end
        return false, definition[1], nil
    end

    local renderModules
    local function renderCapabilities()
        UI.clear(capabilityList)
        local available = 0

        for order, definition in ipairs(CAPABILITIES) do
            local supported, resolvedName = resolveCapability(definition)
            if supported then
                available = available + 1
            end

            local row = UI.panel({
                Parent = capabilityList,
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, 42),
                Radius = 6,
                StrokeTransparency = 0.4,
            })
            local dot = UI.create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = supported and Theme.green or Theme.red,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(12, 21),
                Size = UDim2.fromOffset(7, 7),
                Parent = row,
            })
            UI.corner(dot, 7)
            UI.label({
                Font = Enum.Font.Code,
                Position = UDim2.fromOffset(28, 3),
                Size = UDim2.new(0.48, -28, 0, 20),
                Text = definition[1],
                TextColor3 = supported and Theme.text or Theme.textMuted,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            UI.label({
                Position = UDim2.fromOffset(28, 21),
                Size = UDim2.new(1, -36, 0, 15),
                Text = definition[2],
                TextColor3 = Theme.textFaint,
                TextSize = 8,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            UI.label({
                AnchorPoint = Vector2.new(1, 0.5),
                Font = Enum.Font.GothamBold,
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.fromOffset(74, 18),
                Text = supported and ("READY · " .. resolvedName) or "UNAVAILABLE",
                TextColor3 = supported and Theme.green or Theme.red,
                TextSize = 7,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = row,
            })
        end

        capabilityTitle.Text = ("CAPABILITY MATRIX · %d / %d"):format(available, #CAPABILITIES)
    end

    renderModules = function()
        UI.clear(moduleList)
        local loadedSet = {}
        for _, id in ipairs(ctx.app:getLoadedModules()) do
            loadedSet[id] = true
        end

        for order, feature in ipairs(ctx.app.manifest.features) do
            local loaded = loadedSet[feature.id] == true
            local loading = ctx.app.loading[feature.id] == true
            local row = UI.panel({
                Parent = moduleList,
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, 54),
                Radius = 6,
                StrokeColor = loaded and Theme.accentSoft or Theme.borderSoft,
            })
            local iconTile = UI.create("Frame", {
                BackgroundColor3 = loaded and Theme.accentSoft or Theme.surfaceRaised,
                BorderSizePixel = 0,
                Position = UDim2.fromOffset(8, 10),
                Size = UDim2.fromOffset(30, 30),
                Parent = row,
            })
            UI.corner(iconTile, 6)
            UI.icon({
                AnchorPoint = Vector2.new(0.5, 0.5),
                Color = loaded and Theme.cyan or Theme.textFaint,
                Icon = feature.icon,
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(16, 16),
                Parent = iconTile,
            })
            UI.label({
                Font = Enum.Font.GothamMedium,
                Position = UDim2.fromOffset(46, 6),
                Size = UDim2.new(1, -54, 0, 20),
                Text = feature.title,
                TextSize = 10,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            UI.label({
                Position = UDim2.fromOffset(46, 26),
                Size = UDim2.new(1, -54, 0, 16),
                Text = loading and "Loading…"
                    or loaded and "Mounted · shared state active"
                    or "Not fetched yet",
                TextColor3 = loading and Theme.yellow
                    or loaded and Theme.green
                    or Theme.textFaint,
                TextSize = 8,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
        end

        moduleTitle.Text = ("LAZY MODULES · %d / %d LOADED"):format(
            #ctx.app:getLoadedModules(),
            #ctx.app.manifest.features
        )
    end

    local function pingText()
        local ok, result = pcall(function()
            local network = ctx.services.Stats.Network
            local serverStats = network and network.ServerStatsItem
            local ping = serverStats and serverStats["Data Ping"]
            return ping and ping:GetValueString() or nil
        end)
        return ok and result or nil
    end

    local function memoryText()
        local ok, result = pcall(function()
            return ctx.services.Stats:GetTotalMemoryUsageMb()
        end)
        return ok and result or nil
    end

    local function updateMetrics(deltaTime)
        state.frameCount = state.frameCount + 1
        state.frameTotal = state.frameTotal + deltaTime
        state.elapsed = state.elapsed + deltaTime
        state.statsElapsed = state.statsElapsed + deltaTime
        if state.elapsed < 0.75 then
            return
        end

        state.fps = state.frameCount / state.frameTotal
        state.frameTime = state.frameTotal / state.frameCount * 1000
        state.frameCount = 0
        state.frameTotal = 0
        state.elapsed = 0

        if not ctx:isActive() then
            return
        end

        fpsValue.Text = ("%d FPS"):format(math.floor(state.fps + 0.5))
        fpsDetail.Text = state.fps >= 55 and "Healthy render cadence" or "Frame rate is below target"
        fpsValue.TextColor3 = state.fps >= 55 and Theme.green
            or state.fps >= 30 and Theme.yellow
            or Theme.red

        frameValue.Text = ("%.1f ms"):format(state.frameTime)
        frameDetail.Text = "Average over the last half-second"
        frameValue.TextColor3 = state.frameTime <= 18 and Theme.green
            or state.frameTime <= 32 and Theme.yellow
            or Theme.red

        if state.statsElapsed >= 2 then
            state.statsElapsed = 0
            state.memory = memoryText()
            state.ping = pingText()
        end

        memoryValue.Text = state.memory and ("%.0f MB"):format(state.memory) or "N/A"
        memoryDetail.Text = state.memory and "Total client memory" or "Stats API unavailable"
        memoryValue.TextColor3 = state.memory and Theme.cyan or Theme.textMuted

        pingValue.Text = state.ping or "N/A"
        pingDetail.Text = state.ping and "Data ping reported by Stats" or "Network metric unavailable"
        pingValue.TextColor3 = state.ping and Theme.cyan or Theme.textMuted
    end

    local function report()
        local memory = memoryText()
        local ping = pingText()
        local lines = {
            ("KryptDbg %s diagnostics"):format(ctx.app.manifest.version),
            ("Active feature: %s"):format(ctx.app.window.activeTab or "None"),
            ("Loaded modules: %s"):format(table.concat(ctx.app:getLoadedModules(), ", ")),
            ("FPS: %.1f"):format(state.fps),
            ("Frame time: %.2f ms"):format(state.frameTime),
            ("Memory: %s"):format(memory and ("%.1f MB"):format(memory) or "N/A"),
            ("Ping: %s"):format(ping or "N/A"),
            "",
            "Capabilities:",
        }
        for _, definition in ipairs(CAPABILITIES) do
            local supported, resolvedName = resolveCapability(definition)
            table.insert(
                lines,
                ("- %s: %s"):format(
                    definition[1],
                    supported and ("available as " .. resolvedName) or "unavailable"
                )
            )
        end
        return table.concat(lines, "\n")
    end

    ctx:connect(ctx.services.RunService.Heartbeat, updateMetrics)
    ctx:connect(copyButton.MouseButton1Click, function()
        ctx:copy(report(), "Diagnostic report copied")
    end)
    ctx:connect(saveButton.MouseButton1Click, function()
        if saveLoader then
            ctx:toast("Save Instance is already running", Theme.yellow)
            return
        end
        local supported, _, saveInstance = resolveCapability({ "saveinstance", "" })
        if not supported then
            ctx:toast("saveinstance is unavailable", Theme.red)
            return
        end

        local loader = UI.loader({
            BackgroundColor3 = Theme.canvas,
            BackgroundTransparency = 0.08,
            Detail = "This can take a while for large places.",
            Parent = page,
            Position = UDim2.fromOffset(10, 52),
            Size = UDim2.new(1, -20, 1, -62),
            Title = "Saving instance…",
            ZIndex = 20,
        })
        saveLoader = loader
        task.spawn(function()
            ctx:status("Saving instance…", Theme.yellow)
            local ok, message = pcall(saveInstance, {
                FileName = "KryptDbg-place",
                IsolatePlayers = true,
            })
            if not ok then
                ok, message = pcall(saveInstance)
            end
            loader:destroy()
            if saveLoader == loader then
                saveLoader = nil
            end
            if not ctx.app.alive then
                return
            end
            if ok then
                ctx:toast("Save Instance completed", Theme.green)
                ctx:status("Diagnostics ready", Theme.green)
            else
                ctx:toast("Save Instance failed: " .. tostring(message), Theme.red, 4)
                ctx:status("Save Instance failed", Theme.red)
            end
        end)
    end)
    ctx:connect(refreshButton.MouseButton1Click, function()
        renderCapabilities()
        renderModules()
        ctx:status("Diagnostics refreshed", Theme.green)
    end)
    ctx:on("moduleLoaded", renderModules)
    ctx:on("activeFeatureChanged", function(id)
        if id == ctx.id then
            renderCapabilities()
            renderModules()
        end
    end)

    renderCapabilities()
    renderModules()
    return {
        report = report,
        destroy = function() end,
    }
end

return Diagnostics
