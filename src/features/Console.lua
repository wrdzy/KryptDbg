local Console = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

function Console.mount(ctx)
    local UI = ctx.ui
    local Theme = ctx.theme
    local page = ctx.page
    local state = {
        logs = {},
        query = "",
        filter = "All",
        renderDirty = false,
        renderScheduled = false,
        history = {},
        historyIndex = 1,
        nextId = 0,
    }
    local commandLoader

    ctx:cleanup(function()
        if commandLoader then
            commandLoader:destroy()
            commandLoader = nil
        end
    end)

    local toolbar = UI.toolbar(page)
    local search = UI.input({
        Parent = toolbar,
        PlaceholderText = "Filter output…",
        Size = UDim2.fromOffset(220, 30),
    })
    local allButton = UI.button({ Parent = toolbar, Text = "All", Width = 44 })
    local infoButton = UI.button({ Parent = toolbar, Text = "Info", Width = 50 })
    local warningButton = UI.button({
        Parent = toolbar,
        Text = "Warnings",
        TextColor3 = Theme.yellow,
        Width = 76,
    })
    local errorButton = UI.button({
        Parent = toolbar,
        Text = "Errors",
        TextColor3 = Theme.red,
        Width = 60,
    })
    local clearButton = UI.button({
        Icon = "trash-2",
        Parent = toolbar,
        Text = "Clear",
        TextColor3 = Theme.red,
        Width = 68,
    })

    local outputPanel = UI.panel({
        Parent = page,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(10, 52),
        Size = UDim2.new(1, -20, 1, -110),
    })
    local outputHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 34),
        Parent = outputPanel,
    })
    local countLabel = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = "OUTPUT · 0",
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = outputHeader,
    })
    local output, outputLayout = UI.scroller({
        Parent = outputPanel,
        Position = UDim2.fromOffset(0, 34),
        Size = UDim2.new(1, 0, 1, -34),
        Padding = 7,
        Spacing = 3,
    })

    local commandBar = UI.panel({
        Parent = page,
        Position = UDim2.new(0, 10, 1, -50),
        Size = UDim2.new(1, -20, 0, 40),
        Radius = 7,
    })
    local prompt = UI.label({
        Font = Enum.Font.Code,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.fromOffset(20, 40),
        Text = ">",
        TextColor3 = Theme.accent,
        TextSize = 14,
        Parent = commandBar,
    })
    local command = UI.input({
        Parent = commandBar,
        BackgroundColor3 = Theme.input,
        PlaceholderText = "Run a Luau expression or statement…",
        Position = UDim2.fromOffset(30, 5),
        Size = UDim2.new(1, -120, 0, 30),
        TextSize = 11,
    })
    local runButton = UI.button({
        Icon = "play",
        Parent = commandBar,
        Position = UDim2.new(1, -84, 0, 5),
        Size = UDim2.fromOffset(76, 30),
        Text = "Run",
        TextColor3 = Theme.green,
    })

    local function classify(messageType)
        if messageType == Enum.MessageType.MessageWarning then
            return "Warning", Theme.yellow
        elseif messageType == Enum.MessageType.MessageError then
            return "Error", Theme.red
        elseif messageType == Enum.MessageType.MessageInfo then
            return "Info", Theme.cyan
        end
        return "Output", Theme.textMuted
    end

    local render
    local scheduleRender
    local function addLog(message, messageType, source)
        local level, color = classify(messageType)
        state.nextId = state.nextId + 1
        table.insert(state.logs, {
            id = state.nextId,
            message = tostring(message),
            messageType = messageType,
            level = level,
            color = color,
            source = source or "Roblox",
            time = os.date("%H:%M:%S"),
        })
        if #state.logs > 500 then
            table.remove(state.logs, 1)
        end

        state.renderDirty = true
        scheduleRender()
    end

    local function matches(entry)
        if state.filter ~= "All" and entry.level ~= state.filter then
            return false
        end
        local query = state.query:lower()
        return query == ""
            or entry.message:lower():find(query, 1, true) ~= nil
            or entry.source:lower():find(query, 1, true) ~= nil
    end

    local rows = {}
    local function ensureRow(slotIndex)
        local existing = rows[slotIndex]
        if existing then
            return existing
        end

        local row = UI.create("Frame", {
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 30),
            Parent = output,
        })
        UI.corner(row, 5)
        local bar = UI.create("Frame", {
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 4),
            Size = UDim2.new(0, 2, 1, -8),
            Parent = row,
        })
        local message = UI.label({
            Font = Enum.Font.Code,
            Position = UDim2.fromOffset(9, 4),
            Size = UDim2.new(1, -92, 1, -8),
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = row,
        })
        local timestamp = UI.label({
            AnchorPoint = Vector2.new(1, 0),
            Font = Enum.Font.Code,
            Position = UDim2.new(1, -8, 0, 5),
            Size = UDim2.fromOffset(72, 16),
            TextColor3 = Theme.textFaint,
            TextSize = 8,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = row,
        })

        local slot = {
            row = row,
            bar = bar,
            message = message,
            timestamp = timestamp,
        }
        rows[slotIndex] = slot
        return slot
    end

    render = function()
        if not ctx:isActive() then
            state.renderDirty = true
            return
        end
        state.renderDirty = false

        local filtered = {}
        for _, entry in ipairs(state.logs) do
            if matches(entry) then
                table.insert(filtered, entry)
            end
        end

        local first = math.max(1, #filtered - 119)
        local visibleCount = 0
        for index = first, #filtered do
            visibleCount = visibleCount + 1
            local entry = filtered[index]
            local height = math.clamp(30 + math.floor(#entry.message / 110) * 13, 30, 82)
            local slot = ensureRow(visibleCount)
            slot.row.BackgroundColor3 = visibleCount % 2 == 0 and Theme.surface or Theme.canvas
            slot.row.LayoutOrder = visibleCount
            slot.row.Size = UDim2.new(1, 0, 0, height)
            slot.row.Visible = true
            slot.bar.BackgroundColor3 = entry.color
            slot.message.Text = entry.message
            slot.message.TextColor3 = entry.color == Theme.textMuted and Theme.text or entry.color
            slot.timestamp.Text = entry.time
        end

        for index = visibleCount + 1, #rows do
            rows[index].row.Visible = false
        end

        countLabel.Text = ("OUTPUT · %d / %d"):format(#filtered, #state.logs)
        task.defer(function()
            if output.Parent then
                output.CanvasPosition = Vector2.new(0, math.max(0, output.AbsoluteCanvasSize.Y))
            end
        end)
    end

    scheduleRender = function()
        if state.renderScheduled then
            return
        end

        state.renderScheduled = true
        task.delay(0.14, function()
            state.renderScheduled = false
            if state.renderDirty and ctx:isActive() then
                render()
            end
        end)
    end

    local function setFilter(value)
        state.filter = value
        allButton.TextColor3 = value == "All" and Theme.accent or Theme.text
        infoButton.TextColor3 = value == "Info" and Theme.cyan or Theme.text
        warningButton.TextColor3 = value == "Warning" and Theme.yellow or Theme.text
        errorButton.TextColor3 = value == "Error" and Theme.red or Theme.text
        render()
    end

    local environment = (getgenv and getgenv()) or _G
    local loadString = rawget(environment, "loadstring") or loadstring

    local function runCommand()
        if commandLoader then
            ctx:toast("A command is already running", Theme.yellow)
            return
        end
        local text = command.Text
        if text:match("^%s*$") then
            return
        end

        table.insert(state.history, text)
        if #state.history > 100 then
            table.remove(state.history, 1)
        end
        state.historyIndex = #state.history + 1
        command.Text = ""
        addLog("> " .. text, Enum.MessageType.MessageInfo, "Command")

        if type(loadString) ~= "function" then
            addLog("loadstring is unavailable in this environment", Enum.MessageType.MessageError, "KryptDbg")
            return
        end

        local loader = UI.loader({
            BackgroundColor3 = Theme.canvas,
            BackgroundTransparency = 0.08,
            Detail = text,
            Parent = outputPanel,
            Position = UDim2.fromOffset(0, 34),
            Size = UDim2.new(1, 0, 1, -34),
            Title = "Running command…",
            ZIndex = 20,
        })
        commandLoader = loader
        task.spawn(function()
            local function finish()
                loader:destroy()
                if commandLoader == loader then
                    commandLoader = nil
                end
            end

            local compileOk, chunk, compileError = pcall(loadString, text, "@KryptDbg/Console")
            if not compileOk then
                finish()
                if not ctx.app.alive then
                    return
                end
                addLog(tostring(chunk), Enum.MessageType.MessageError, "Compiler")
                return
            end
            if not chunk then
                finish()
                if not ctx.app.alive then
                    return
                end
                addLog(tostring(compileError), Enum.MessageType.MessageError, "Compiler")
                return
            end

            local results = pack(pcall(chunk))
            finish()
            if not ctx.app.alive then
                return
            end
            if not results[1] then
                addLog(tostring(results[2]), Enum.MessageType.MessageError, "Runtime")
                return
            end

            if results.n == 1 then
                addLog("Command completed", Enum.MessageType.MessageInfo, "Runtime")
            else
                local values = {}
                for index = 2, results.n do
                    table.insert(values, ctx:serialize(results[index]))
                end
                addLog(table.concat(values, ", "), Enum.MessageType.MessageOutput, "Result")
            end
        end)
    end

    ctx:connect(ctx.services.LogService.MessageOut, function(message, messageType)
        addLog(message, messageType, "Roblox")
    end)
    ctx:connect(search:GetPropertyChangedSignal("Text"), function()
        state.query = search.Text
        state.renderDirty = true
        scheduleRender()
    end)
    ctx:connect(allButton.MouseButton1Click, function()
        setFilter("All")
    end)
    ctx:connect(infoButton.MouseButton1Click, function()
        setFilter("Info")
    end)
    ctx:connect(warningButton.MouseButton1Click, function()
        setFilter("Warning")
    end)
    ctx:connect(errorButton.MouseButton1Click, function()
        setFilter("Error")
    end)
    ctx:connect(clearButton.MouseButton1Click, function()
        state.logs = {}
        render()
    end)
    ctx:connect(runButton.MouseButton1Click, runCommand)
    ctx:connect(command.FocusLost, function(enterPressed)
        if enterPressed then
            runCommand()
        end
    end)
    ctx:connect(command.InputBegan, function(input)
        if input.KeyCode == Enum.KeyCode.Up and #state.history > 0 then
            state.historyIndex = math.max(1, state.historyIndex - 1)
            command.Text = state.history[state.historyIndex] or ""
            command.CursorPosition = #command.Text + 1
        elseif input.KeyCode == Enum.KeyCode.Down and #state.history > 0 then
            state.historyIndex = math.min(#state.history + 1, state.historyIndex + 1)
            command.Text = state.history[state.historyIndex] or ""
            command.CursorPosition = #command.Text + 1
        end
    end)
    ctx:on("activeFeatureChanged", function(id)
        if id == ctx.id then
            render()
        end
    end)

    setFilter("All")
    addLog("Console module loaded. Output capture starts now.", Enum.MessageType.MessageInfo, "KryptDbg")
    return {
        focus = function()
            command:CaptureFocus()
        end,
        destroy = function() end,
    }
end

return Console
