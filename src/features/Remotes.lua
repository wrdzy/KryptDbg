local Remotes = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

local function unpackArgs(arguments)
    return table.unpack(arguments, 1, arguments.n or #arguments)
end

local function shallowValue(value)
    local kind = typeof(value)
    if kind == "Instance" then
        return value:GetFullName()
    elseif kind == "table" then
        return "table:" .. tostring(value)
    end
    return tostring(value)
end

function Remotes.mount(ctx)
    local UI = ctx.ui
    local Theme = ctx.theme
    local page = ctx.page
    local state = {
        logs = {},
        selected = nil,
        paused = false,
        query = "",
        filter = "All",
        nextId = 0,
        renderPending = false,
        maxLogs = 500,
        blockedInstances = setmetatable({}, { __mode = "k" }),
        blockedNames = {},
        excludedInstances = setmetatable({}, { __mode = "k" }),
        excludedNames = {},
        replayThreads = setmetatable({}, { __mode = "k" }),
    }
    local rowConnections = {}

    local function clearRowConnections()
        for _, connection in ipairs(rowConnections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(rowConnections)
    end

    ctx:cleanup(clearRowConnections)

    local toolbar = UI.toolbar(page)
    local search = UI.input({
        Parent = toolbar,
        PlaceholderText = "Search captured calls…",
        Size = UDim2.fromOffset(210, 30),
    })
    local allButton = UI.button({ Parent = toolbar, Text = "All", Width = 48 })
    local eventButton = UI.button({ Parent = toolbar, Text = "Events", Width = 64 })
    local functionButton = UI.button({ Parent = toolbar, Text = "Functions", Width = 78 })
    local pauseButton = UI.button({ Parent = toolbar, Text = "Pause", Width = 66 })
    local clearButton = UI.button({
        Parent = toolbar,
        Text = "Clear",
        TextColor3 = Theme.red,
        Width = 60,
    })

    local body = UI.create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 52),
        Size = UDim2.new(1, -20, 1, -62),
        Parent = page,
    })
    local listPanel = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Size = UDim2.new(0.43, -5, 1, 0),
    })
    local listHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = listPanel,
    })
    local countLabel = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 3),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "REMOTE TRAFFIC · 0",
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = listHeader,
    })
    local hookLabel = UI.label({
        Position = UDim2.fromOffset(12, 20),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Preparing capture hook…",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = listHeader,
    })
    local list, listLayout = UI.scroller({
        Parent = listPanel,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 1, -42),
        Padding = 6,
        Spacing = 4,
    })

    local inspector = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Position = UDim2.new(0.43, 5, 0, 0),
        Size = UDim2.new(0.57, -5, 1, 0),
    })
    local inspectorHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 76),
        Parent = inspector,
    })
    local selectedName = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -124, 0, 20),
        Text = "No captured call",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inspectorHeader,
    })
    local methodBadge = UI.label({
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = Theme.accentSoft,
        BackgroundTransparency = 0,
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(1, -12, 0, 8),
        Size = UDim2.fromOffset(98, 22),
        Text = "NO CALL",
        TextColor3 = Theme.textMuted,
        TextSize = 8,
        Parent = inspectorHeader,
    })
    UI.corner(methodBadge, 5)
    local selectedPath = UI.label({
        Font = Enum.Font.Code,
        Position = UDim2.fromOffset(12, 33),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inspectorHeader,
    })
    local selectedMeta = UI.label({
        Position = UDim2.fromOffset(12, 51),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Select a captured call to inspect it",
        TextColor3 = Theme.textMuted,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inspectorHeader,
    })

    local actions = UI.create("Frame", {
        BackgroundColor3 = Theme.chrome,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 76),
        Size = UDim2.new(1, 0, 0, 42),
        Parent = inspector,
    })
    UI.padding(actions, 8, 8, 6, 6)
    UI.list(actions, Enum.FillDirection.Horizontal, 7)
    local copyButton = UI.button({ Parent = actions, Text = "Copy code", Width = 82 })
    local replayButton = UI.button({
        Parent = actions,
        Text = "Run captured",
        TextColor3 = Theme.green,
        Width = 92,
    })
    local blockButton = UI.button({
        Parent = actions,
        Text = "Block exact",
        TextColor3 = Theme.red,
        Width = 84,
    })
    local excludeButton = UI.button({
        Parent = actions,
        Text = "Exclude exact",
        TextColor3 = Theme.yellow,
        Width = 90,
    })

    local code = UI.input({
        Parent = inspector,
        Font = Enum.Font.Code,
        MultiLine = true,
        Position = UDim2.fromOffset(8, 126),
        Size = UDim2.new(1, -16, 1, -134),
        Text = "-- Select a remote call",
        TextSize = 11,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    code.TextEditable = false
    UI.padding(code, 10, 10, 8, 8)

    local function fingerprint(remote, method, arguments)
        local parts = { tostring(remote), method, tostring(arguments.n or #arguments) }
        for index = 1, math.min(arguments.n or #arguments, 5) do
            table.insert(parts, shallowValue(arguments[index]))
        end
        return table.concat(parts, "|")
    end

    local function generate(entry)
        local lines = {
            "local remote = " .. ctx:path(entry.remote),
            "local args = {",
        }
        for index = 1, entry.args.n or #entry.args do
            table.insert(lines, ("    [%d] = %s,"):format(index, ctx:serialize(entry.args[index])))
        end
        table.insert(lines, ("    n = %d,"):format(entry.args.n or #entry.args))
        table.insert(lines, "}")
        table.insert(lines, "")
        table.insert(
            lines,
            ("remote:%s(table.unpack(args, 1, args.n))"):format(entry.method)
        )
        return table.concat(lines, "\n")
    end

    local function matches(entry)
        if state.filter == "Events" and entry.method ~= "FireServer" then
            return false
        elseif state.filter == "Functions" and entry.method ~= "InvokeServer" then
            return false
        end

        local query = state.query:lower()
        return query == ""
            or entry.remote.Name:lower():find(query, 1, true) ~= nil
            or entry.remote:GetFullName():lower():find(query, 1, true) ~= nil
            or entry.method:lower():find(query, 1, true) ~= nil
    end

    local render
    local function selectEntry(entry)
        state.selected = entry
        if not entry then
            selectedName.Text = "No captured call"
            selectedPath.Text = ""
            selectedMeta.Text = "Select a captured call to inspect it"
            methodBadge.Text = "NO CALL"
            methodBadge.TextColor3 = Theme.textMuted
            code.Text = "-- Select a remote call"
            return
        end

        selectedName.Text = entry.remote.Name
        selectedPath.Text = ctx:path(entry.remote)
        selectedMeta.Text = ("%d arguments · captured %s · repeated %d×"):format(
            entry.args.n or #entry.args,
            os.date("%H:%M:%S", entry.time),
            entry.count
        )
        methodBadge.Text = entry.method
        methodBadge.TextColor3 = entry.method == "FireServer" and Theme.cyan or Theme.yellow
        code.Text = entry.code or generate(entry)
        entry.code = code.Text
        ctx:setSelection(entry.remote)
        render()
    end

    render = function()
        if not ctx:isActive() then
            state.renderPending = true
            return
        end
        state.renderPending = false
        clearRowConnections()
        UI.clear(list)

        local filtered = {}
        for _, entry in ipairs(state.logs) do
            if matches(entry) then
                table.insert(filtered, entry)
            end
        end

        local first = math.max(1, #filtered - 139)
        for index = first, #filtered do
            local entry = filtered[index]
            local active = entry == state.selected
            local row = UI.create("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = active and Theme.accentSoft or Theme.surface,
                BorderSizePixel = 0,
                LayoutOrder = index,
                Size = UDim2.new(1, 0, 0, 46),
                Text = "",
                Parent = list,
            })
            UI.corner(row, 6)
            UI.stroke(row, active and Theme.accent or Theme.borderSoft, active and 0.3 or 0.45)
            UI.label({
                BackgroundColor3 = entry.method == "FireServer" and Theme.accentSoft or Theme.surfaceRaised,
                BackgroundTransparency = 0,
                Font = Enum.Font.GothamBold,
                Position = UDim2.fromOffset(7, 7),
                Size = UDim2.fromOffset(28, 16),
                Text = entry.method == "FireServer" and "EV" or "FN",
                TextColor3 = entry.method == "FireServer" and Theme.cyan or Theme.yellow,
                TextSize = 7,
                Parent = row,
            })
            UI.label({
                Font = Enum.Font.GothamMedium,
                Position = UDim2.fromOffset(42, 4),
                Size = UDim2.new(1, -84, 0, 20),
                Text = entry.remote.Name,
                TextSize = 10,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            UI.label({
                Font = Enum.Font.Code,
                Position = UDim2.fromOffset(42, 23),
                Size = UDim2.new(1, -84, 0, 16),
                Text = ("%s · %d args"):format(entry.method, entry.args.n or #entry.args),
                TextColor3 = Theme.textFaint,
                TextSize = 8,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            UI.label({
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -9, 0.5, 0),
                Size = UDim2.fromOffset(34, 18),
                Text = entry.count > 1 and ("×" .. entry.count) or ("#" .. entry.id),
                TextColor3 = entry.count > 1 and Theme.yellow or Theme.textFaint,
                TextSize = 8,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = row,
            })
            table.insert(rowConnections, row.MouseButton1Click:Connect(function()
                selectEntry(entry)
            end))
        end

        countLabel.Text = ("REMOTE TRAFFIC · %d / %d"):format(#filtered, #state.logs)
    end

    local function requestRender()
        if state.renderPending then
            return
        end
        state.renderPending = true
        task.defer(render)
    end

    local function isExcluded(remote)
        return state.excludedInstances[remote] or state.excludedNames[remote.Name]
    end

    local function isBlocked(remote)
        return state.blockedInstances[remote] or state.blockedNames[remote.Name]
    end

    local function capture(remote, method, arguments)
        if not ctx.app.alive or state.paused or isExcluded(remote) then
            return
        end

        local key = fingerprint(remote, method, arguments)
        local last = state.logs[#state.logs]
        if last and last.fingerprint == key and os.clock() - last.clock < 0.5 then
            last.count = last.count + 1
            last.clock = os.clock()
            requestRender()
            return
        end

        state.nextId = state.nextId + 1
        local entry = {
            id = state.nextId,
            remote = remote,
            method = method,
            args = arguments,
            time = os.time(),
            clock = os.clock(),
            count = 1,
            fingerprint = key,
        }
        table.insert(state.logs, entry)
        if #state.logs > state.maxLogs then
            local removed = table.remove(state.logs, 1)
            if state.selected == removed then
                state.selected = nil
            end
        end
        requestRender()
    end

    local environment = (getgenv and getgenv()) or _G
    local hookMetamethod = rawget(environment, "hookmetamethod") or hookmetamethod
    local getNamecallMethod = rawget(environment, "getnamecallmethod") or getnamecallmethod
    local newClosure = rawget(environment, "newcclosure") or newcclosure or function(callback)
        return callback
    end
    local oldNamecall

    if type(hookMetamethod) == "function" and type(getNamecallMethod) == "function" then
        local ok, result = pcall(function()
            oldNamecall = hookMetamethod(game, "__namecall", newClosure(function(self, ...)
                local method = getNamecallMethod()
                if (method == "FireServer" or method == "InvokeServer")
                    and typeof(self) == "Instance"
                    and not state.replayThreads[coroutine.running()]
                then
                    local arguments = pack(...)
                    task.defer(capture, self, method, arguments)
                    if isBlocked(self) then
                        return nil
                    end
                end
                return oldNamecall(self, ...)
            end))
            return oldNamecall
        end)

        if ok and type(result) == "function" then
            hookLabel.Text = "Namecall capture active · bounded history"
            hookLabel.TextColor3 = Theme.green
            ctx:status("Remote capture active", Theme.green)
        else
            hookLabel.Text = "Capture hook failed"
            hookLabel.TextColor3 = Theme.red
            ctx:toast("Remote capture hook failed: " .. tostring(result), Theme.red)
        end
    else
        hookLabel.Text = "This environment does not expose remote hook APIs"
        hookLabel.TextColor3 = Theme.yellow
    end

    local function setFilter(value)
        state.filter = value
        allButton.TextColor3 = value == "All" and Theme.accent or Theme.text
        eventButton.TextColor3 = value == "Events" and Theme.cyan or Theme.text
        functionButton.TextColor3 = value == "Functions" and Theme.yellow or Theme.text
        render()
    end

    ctx:connect(search:GetPropertyChangedSignal("Text"), function()
        state.query = search.Text
        requestRender()
    end)
    ctx:connect(allButton.MouseButton1Click, function()
        setFilter("All")
    end)
    ctx:connect(eventButton.MouseButton1Click, function()
        setFilter("Events")
    end)
    ctx:connect(functionButton.MouseButton1Click, function()
        setFilter("Functions")
    end)
    ctx:connect(pauseButton.MouseButton1Click, function()
        state.paused = not state.paused
        pauseButton.Text = state.paused and "Resume" or "Pause"
        pauseButton.TextColor3 = state.paused and Theme.yellow or Theme.text
        ctx:status(state.paused and "Remote capture paused" or "Remote capture active", Theme.yellow)
    end)
    ctx:connect(clearButton.MouseButton1Click, function()
        state.logs = {}
        selectEntry(nil)
        render()
    end)
    ctx:connect(copyButton.MouseButton1Click, function()
        if state.selected then
            ctx:copy(state.selected.code or generate(state.selected), "Captured call copied")
        else
            ctx:toast("Select a captured call first", Theme.yellow)
        end
    end)
    ctx:connect(replayButton.MouseButton1Click, function()
        local entry = state.selected
        if not entry then
            ctx:toast("Select a captured call first", Theme.yellow)
            return
        end

        task.spawn(function()
            local thread = coroutine.running()
            state.replayThreads[thread] = true
            local result = pack(pcall(function()
                return entry.remote[entry.method](entry.remote, unpackArgs(entry.args))
            end))
            state.replayThreads[thread] = nil

            if result[1] then
                ctx:toast("Captured call completed", Theme.green)
            else
                ctx:toast("Replay failed: " .. tostring(result[2]), Theme.red, 4)
            end
        end)
    end)
    ctx:connect(blockButton.MouseButton1Click, function()
        local entry = state.selected
        if not entry then
            ctx:toast("Select a captured call first", Theme.yellow)
            return
        end
        state.blockedInstances[entry.remote] = not state.blockedInstances[entry.remote]
        blockButton.Text = state.blockedInstances[entry.remote] and "Unblock exact" or "Block exact"
        ctx:toast(
            state.blockedInstances[entry.remote] and "Remote blocked" or "Remote unblocked",
            Theme.yellow
        )
    end)
    ctx:connect(excludeButton.MouseButton1Click, function()
        local entry = state.selected
        if not entry then
            ctx:toast("Select a captured call first", Theme.yellow)
            return
        end
        state.excludedInstances[entry.remote] = not state.excludedInstances[entry.remote]
        excludeButton.Text = state.excludedInstances[entry.remote] and "Include exact" or "Exclude exact"
        ctx:toast(
            state.excludedInstances[entry.remote] and "Remote excluded" or "Remote included",
            Theme.yellow
        )
    end)
    ctx:on("activeFeatureChanged", function(id)
        if id == ctx.id and state.renderPending then
            render()
        end
    end)

    setFilter("All")
    selectEntry(nil)

    return {
        destroy = function()
            if type(hookMetamethod) == "function" and type(oldNamecall) == "function" then
                pcall(hookMetamethod, game, "__namecall", oldNamecall)
            end
        end,
    }
end

return Remotes
