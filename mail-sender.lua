-- udapte
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local MailboxItemCatalog = require(
    game:GetService("Players").LocalPlayer.PlayerScripts.Controllers.MailboxController.MailboxItemCatalog
)
local PlayerState = require(game:GetService("ReplicatedStorage").ClientModules.PlayerStateClient)
local Networking = require(ReplicatedStorage.SharedModules.Networking)
local replica = PlayerState:WaitForLocalReplica()
local Backpack = Players.LocalPlayer:WaitForChild("Backpack")
local watchers = {}

-- Forward-declared so early references (watchInventory calls, Backpack
-- ChildAdded/Removed below, and the Send Mail success handler) resolve to
-- the SAME upvalue that gets assigned further down the file. Previously
-- these were re-declared with `local` at their assignment sites, which
-- silently created brand new variables and left these early references
-- permanently bound to nil -- so the grids never refreshed after sending
-- mail or after any inventory change.
local refreshPets, refreshSeeds, refreshGears, refreshFruits

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Theme = {
    Background   = Color3.fromRGB(18, 20, 26),
    TopBar       = Color3.fromRGB(24, 27, 34),
    Panel        = Color3.fromRGB(26, 29, 37),
    PanelAlt     = Color3.fromRGB(30, 33, 42),
    Stroke       = Color3.fromRGB(54, 59, 71),
    Divider      = Color3.fromRGB(45, 49, 59),
    Accent       = Color3.fromRGB(88, 132, 255),
    AccentHover  = Color3.fromRGB(108, 150, 255),
    Danger       = Color3.fromRGB(230, 90, 90),
    DangerHover  = Color3.fromRGB(240, 110, 110),
    Text         = Color3.fromRGB(240, 241, 245),
    SubText      = Color3.fromRGB(160, 166, 180),
    Success      = Color3.fromRGB(90, 200, 130),
}

local MAIL_ICONS = {
    Pets = "🐶",
    Seeds = "🌱",
    HarvestedFruits = "🍎",
    Sprinklers = "⚙️",
    Trowels = "⚙️",
    WateringCans = "⚙️",
    Eggs = "🥚",
}

local batch = {}
local petNameById = {}
local fruitNameById = {}
local userId
local noteText = ""

local function sendMail(targetUserId, mailBatch, mailNote)
    return Networking.Mailbox.SendBatch:Fire(targetUserId, mailBatch, mailNote)
end

local function deepCopy(tbl)
    local copy = {}
    for k, v in pairs(tbl or {}) do
        copy[k] = type(v) == "table" and deepCopy(v) or v
    end
    return copy
end

local function watchInventory(category, callback)
    watchers[category] = {
        Cache = deepCopy(replica.Data.Inventory[category] or {}),
        Callback = callback
    }
end

replica:OnChange(function(_, path)
    if path[1] ~= "Inventory" then
        return
    end

    local watcher = watchers[path[2]]
    if not watcher then
        return
    end

    local oldCache = watcher.Cache
    local newCache = deepCopy(replica.Data.Inventory[path[2]] or {})

    watcher.Cache = newCache
    watcher.Callback(oldCache, newCache)
end)

watchInventory("Pets", function()
    if refreshPets then
        refreshPets()
    end
end)

watchInventory("Seeds", function()
    if refreshSeeds then
        refreshSeeds()
    end
end)

for _, category in ipairs({
    "Sprinklers",
    "WateringCans",
    "Trowels",
    "Eggs",
}) do
    watchInventory(category, function()
        if refreshGears then
            refreshGears()
        end
    end)
end

Backpack.ChildAdded:Connect(function(item)
    if item:IsA("Tool") then refreshFruits() end
end)
Backpack.ChildRemoved:Connect(function(item)
    if item:IsA("Tool") then refreshFruits() end
end)

local FONT_BOLD = Enum.Font.GothamBold
local FONT_SEMI = Enum.Font.GothamSemibold
local FONT_REG  = Enum.Font.Gotham

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "JayHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local camera = workspace.CurrentCamera
local viewport = camera.ViewportSize

local IsMobile = viewport.X < 600 or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)

local WIDTH = math.clamp(math.floor(viewport.X * (IsMobile and 0.94 or 0.9)), IsMobile and 300 or 340, 920)
local HEIGHT = math.clamp(math.floor(viewport.Y * (IsMobile and 0.82 or 0.75)), IsMobile and 460 or 420, 620)

-- Height (in px, before UIScale) that the Recipient/Note/Profile row takes
-- up on the Main tab. Every other section on that tab (Current Mail,
-- Actions) derives its size from this instead of a hardcoded magic number,
-- so it can't silently collapse when the window is a different size on
-- mobile than it is on desktop.
local SPLIT_HEIGHT = IsMobile and 360 or 200
local ACTIONS_HEIGHT = 40
local MAIN_LIST_GAP = 12 -- mainListLayout.Padding, applied twice (Split->MailSection, MailSection->Actions)

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(WIDTH, HEIGHT)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.fromScale(0.5, 0.5)
Main.BackgroundColor3 = Theme.Background
Main.BorderSizePixel = 0
Main.ClipsDescendants = false
Main.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 14)
UICorner.Parent = Main

local UIStroke = Instance.new("UIStroke")
UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
UIStroke.Color = Theme.Stroke
UIStroke.Thickness = 1
UIStroke.Parent = Main

local UIScale = Instance.new("UIScale")
-- On mobile we already shrink WIDTH/HEIGHT to fit the viewport, so an
-- additional flat 0.88 downscale just makes every tap target smaller and
-- harder to hit. Only apply the shrink on desktop.
UIScale.Scale = IsMobile and 1 or 0.88
UIScale.Parent = Main

local Shadow = Instance.new("ImageLabel")
Shadow.Name = "Shadow"
Shadow.AnchorPoint = Vector2.new(0.5, 0.5)
Shadow.Position = UDim2.fromScale(0.5, 0.5)
Shadow.Size = UDim2.new(1, 60, 1, 60)
Shadow.BackgroundTransparency = 1
Shadow.Image = "rbxassetid://1316045217"
Shadow.ImageColor3 = Color3.new(0, 0, 0)
Shadow.ImageTransparency = 0.35
Shadow.ScaleType = Enum.ScaleType.Slice
Shadow.SliceCenter = Rect.new(10, 10, 118, 118)
Shadow.ZIndex = 0
Shadow.Parent = Main

local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 42)
TopBar.BackgroundColor3 = Theme.TopBar
TopBar.BorderSizePixel = 0
TopBar.ZIndex = 2
TopBar.Parent = Main

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 14)
TopCorner.Parent = TopBar

local TopBarMask = Instance.new("Frame")
TopBarMask.Name = "Mask"
TopBarMask.BackgroundColor3 = Theme.TopBar
TopBarMask.BorderSizePixel = 0
TopBarMask.Size = UDim2.new(1, 0, 0, 14)
TopBarMask.Position = UDim2.new(0, 0, 1, -14)
TopBarMask.ZIndex = 2
TopBarMask.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(18, 0)
Title.Size = UDim2.new(1, -180, 1, 0)
Title.Font = FONT_BOLD
Title.TextSize = 18
Title.TextColor3 = Theme.Text
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "Jay Hub  •  Mail Sender"
Title.ZIndex = 3
Title.Parent = TopBar

local function makeControlButton(name, order, glyph)
    local Btn = Instance.new("TextButton")
    Btn.Name = name
    Btn.Size = UDim2.fromOffset(32, 32)
    Btn.Position = UDim2.new(1, -14 - (order * 38), 0.5, -16)
    Btn.BackgroundColor3 = Theme.PanelAlt
    Btn.BackgroundTransparency = 0.2
    Btn.AutoButtonColor = false
    Btn.Text = glyph
    Btn.Font = FONT_SEMI
    Btn.TextSize = 14
    Btn.TextColor3 = Theme.SubText
    Btn.ZIndex = 3
    Btn.Parent = TopBar

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = Btn

    Btn.MouseEnter:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.12), {BackgroundTransparency = 0}):Play()
    end)
    Btn.MouseLeave:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.12), {BackgroundTransparency = 0.2}):Play()
    end)

    return Btn
end

local Close = makeControlButton("Close", 1, "X")
local Maximize = makeControlButton("Maximize", 2, "[]")
local Minimize = makeControlButton("Minimize", 3, "-")

Close.MouseEnter:Connect(function()
    TweenService:Create(Close, TweenInfo.new(0.12), {BackgroundColor3 = Theme.Danger, BackgroundTransparency = 0}):Play()
    TweenService:Create(Close, TweenInfo.new(0.12), {TextColor3 = Color3.new(1,1,1)}):Play()
end)
Close.MouseLeave:Connect(function()
    TweenService:Create(Close, TweenInfo.new(0.12), {BackgroundColor3 = Theme.PanelAlt, BackgroundTransparency = 0.2}):Play()
    TweenService:Create(Close, TweenInfo.new(0.12), {TextColor3 = Theme.SubText}):Play()
end)

local Divider = Instance.new("Frame")
Divider.Name = "Divider"
Divider.Size = UDim2.new(1, 0, 0, 1)
Divider.Position = UDim2.new(0, 0, 0, 48)
Divider.BorderSizePixel = 0
Divider.BackgroundColor3 = Theme.Divider
Divider.ZIndex = 2
Divider.Parent = Main

local Content = Instance.new("Frame")
Content.Name = "Content"
Content.BackgroundTransparency = 1
Content.Position = UDim2.fromOffset(0, 49)
Content.Size = UDim2.new(1, 0, 1, -49)
Content.Parent = Main

local TabBarHolder = Instance.new("ScrollingFrame")
TabBarHolder.Name = "TabBarHolder"
TabBarHolder.BackgroundTransparency = 1
TabBarHolder.BorderSizePixel = 0
TabBarHolder.Size = UDim2.new(1, 0, 0, 40)
TabBarHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
TabBarHolder.AutomaticCanvasSize = Enum.AutomaticSize.X
TabBarHolder.ScrollingDirection = Enum.ScrollingDirection.X
TabBarHolder.ScrollBarThickness = IsMobile and 3 or 0
TabBarHolder.ScrollBarImageColor3 = Theme.Accent
TabBarHolder.ElasticBehavior = Enum.ElasticBehavior.Never
TabBarHolder.Parent = Content

local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.BackgroundTransparency = 1
TabBar.AutomaticSize = Enum.AutomaticSize.X
TabBar.Size = UDim2.new(0, 0, 1, 0)
TabBar.Parent = TabBarHolder

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingLeft = UDim.new(0, 18)
TabPadding.PaddingRight = UDim.new(0, 18)
TabPadding.Parent = TabBar

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TabLayout.Padding = UDim.new(0, 6)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Parent = TabBar

local TAB_NAMES = {"Main", "Pets", "Seeds", "Gears", "Fruits", "History", "Settings"}
local tabButtons = {}
local tabPages = {}

local function setActiveTab(name)
    for tabName, btn in pairs(tabButtons) do
        local active = tabName == name
        TweenService:Create(btn, TweenInfo.new(0.12), {
            BackgroundTransparency = active and 0 or 1,
            TextColor3 = active and Theme.Text or Theme.SubText,
        }):Play()
    end
    for pageName, page in pairs(tabPages) do
        page.Visible = pageName == name
    end
end

for i, name in ipairs(TAB_NAMES) do
    local Tab = Instance.new("TextButton")
    Tab.Name = name
    Tab.LayoutOrder = i
    Tab.AutomaticSize = Enum.AutomaticSize.X
    Tab.Size = UDim2.new(0, 0, 1, -8)
    Tab.BackgroundColor3 = Theme.Panel
    Tab.BackgroundTransparency = 1
    Tab.AutoButtonColor = false
    Tab.Font = FONT_SEMI
    Tab.TextSize = 15
    Tab.TextColor3 = Theme.SubText
    Tab.Text = name
    Tab.Parent = TabBar

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = Tab

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = Tab

    Tab.MouseButton1Click:Connect(function()
        setActiveTab(name)
    end)

    tabButtons[name] = Tab
end

local TabDivider = Instance.new("Frame")
TabDivider.Size = UDim2.new(1, 0, 0, 1)
TabDivider.Position = UDim2.new(0, 0, 0, 40)
TabDivider.BorderSizePixel = 0
TabDivider.BackgroundColor3 = Theme.Divider
TabDivider.Parent = Content

local Pages = Instance.new("Frame")
Pages.Name = "Pages"
Pages.BackgroundTransparency = 1
Pages.Position = UDim2.new(0, 0, 0, 41)
Pages.Size = UDim2.new(1, 0, 1, -41)
Pages.Parent = Content

local function makePage(name)
    local Page = Instance.new("Frame")
    Page.Name = name
    Page.BackgroundTransparency = 1
    Page.Size = UDim2.fromScale(1, 1)
    Page.Visible = false
    Page.Parent = Pages
    tabPages[name] = Page
    return Page
end

for _, name in ipairs(TAB_NAMES) do
    makePage(name)
end

local function makePlaceholderPage(name, text)
    local page = tabPages[name]
    local Label = Instance.new("TextLabel")
    Label.BackgroundTransparency = 1
    Label.Size = UDim2.fromScale(1, 1)
    Label.Font = FONT_SEMI
    Label.TextSize = 16
    Label.TextColor3 = Theme.SubText
    Label.Text = text
    Label.Parent = page
end

makePlaceholderPage("History", "Mail history coming soon.")
makePlaceholderPage("Settings", "Settings coming soon.")

local MainPage = tabPages["Main"]

local PagePadding = Instance.new("UIPadding")
PagePadding.PaddingLeft = UDim.new(0, 18)
PagePadding.PaddingRight = UDim.new(0, 18)
PagePadding.PaddingTop = UDim.new(0, 14)
PagePadding.PaddingBottom = UDim.new(0, 14)
PagePadding.Parent = MainPage

local function makeLabeledInput(parent, labelText, placeholder, layoutOrder, height)
    local Wrap = Instance.new("Frame")
    Wrap.BackgroundTransparency = 1
    Wrap.Size = UDim2.new(1, 0, 0, height or 62)
    Wrap.LayoutOrder = layoutOrder
    Wrap.Parent = parent

    local Label = Instance.new("TextLabel")
    Label.BackgroundTransparency = 1
    Label.Size = UDim2.new(1, 0, 0, 20)
    Label.Font = FONT_SEMI
    Label.TextSize = 15
    Label.TextColor3 = Theme.SubText
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Text = labelText
    Label.Parent = Wrap

    local Box = Instance.new("Frame")
    Box.BackgroundColor3 = Theme.Panel
    Box.Position = UDim2.new(0, 0, 0, 24)
    Box.Size = UDim2.new(1, 0, 0, (height or 62) - 24)
    Box.Parent = Wrap

    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0, 8)
    boxCorner.Parent = Box

    local boxStroke = Instance.new("UIStroke")
    boxStroke.Color = Theme.Stroke
    boxStroke.Thickness = 1
    boxStroke.Parent = Box

    local Input = Instance.new("TextBox")
    Input.BackgroundTransparency = 1
    Input.Size = UDim2.new(1, -20, 1, 0)
    Input.Position = UDim2.fromOffset(10, 0)
    Input.Font = FONT_REG
    Input.TextSize = 15
    Input.TextColor3 = Theme.Text
    Input.PlaceholderText = placeholder
    Input.PlaceholderColor3 = Theme.SubText
    Input.TextXAlignment = Enum.TextXAlignment.Left
    Input.TextYAlignment = Enum.TextYAlignment.Top
    Input.ClearTextOnFocus = false
    Input.MultiLine = (height or 62) > 70
    Input.TextWrapped = true
    Input.Text = ""
    Input.Parent = Box

    boxStroke.Color = Theme.Stroke
    Input.Focused:Connect(function()
        TweenService:Create(boxStroke, TweenInfo.new(0.12), {Color = Theme.Accent}):Play()
    end)
    Input.FocusLost:Connect(function()
        TweenService:Create(boxStroke, TweenInfo.new(0.12), {Color = Theme.Stroke}):Play()
    end)

    return Wrap, Input, boxStroke
end

local Split = Instance.new("Frame")
Split.Name = "Split"
Split.BackgroundTransparency = 1
Split.Size = UDim2.new(1, 0, 0, SPLIT_HEIGHT)
Split.LayoutOrder = 1
Split.Parent = MainPage

if IsMobile then
    -- Stack Recipient/Note above the Profile card instead of squeezing both
    -- into ~45%-wide columns, which left profile text truncated/overlapping
    -- and the avatar cramped on narrow phone screens.
    local SplitLayout = Instance.new("UIListLayout")
    SplitLayout.Padding = UDim.new(0, 12)
    SplitLayout.SortOrder = Enum.SortOrder.LayoutOrder
    SplitLayout.Parent = Split
end

local LeftCol = Instance.new("Frame")
LeftCol.Name = "LeftCol"
LeftCol.BackgroundTransparency = 1
LeftCol.LayoutOrder = 1
if IsMobile then
    LeftCol.Size = UDim2.new(1, 0, 0, 176)
else
    LeftCol.Size = UDim2.new(0.56, -8, 1, 0)
end
LeftCol.Parent = Split

local LeftLayout = Instance.new("UIListLayout")
LeftLayout.Padding = UDim.new(0, 12)
LeftLayout.SortOrder = Enum.SortOrder.LayoutOrder
LeftLayout.Parent = LeftCol

local _, RecipientInput, RecipientStroke = makeLabeledInput(LeftCol, "Recipient", "Enter username...", 1, 64)
local _, NoteInput = makeLabeledInput(LeftCol, "Note","Write a message to include...", 2, 100)

NoteInput:GetPropertyChangedSignal("Text"):Connect(function()
    noteText = NoteInput.Text
end)

-- ==========================================================================
-- Profile card -- redesigned as a header (avatar + name/username stacked
-- beside it) plus a User ID chip below, built with a UIListLayout instead
-- of hand-placed pixel offsets. That's both what makes it look nicer and
-- what stops it from ever overlapping again if the card's size changes.
-- ==========================================================================
local ProfileCard = Instance.new("Frame")
ProfileCard.Name = "ProfileCard"
ProfileCard.BackgroundColor3 = Theme.Panel
ProfileCard.LayoutOrder = 2
ProfileCard.ClipsDescendants = true
if IsMobile then
    ProfileCard.Size = UDim2.new(1, 0, 0, 168)
    ProfileCard.Position = UDim2.new(0, 0, 0, 0)
else
    ProfileCard.Size = UDim2.new(0.44, -8, 1, 0)
    ProfileCard.Position = UDim2.new(0.56, 16, 0, 0)
end
ProfileCard.Parent = Split

local pcCorner = Instance.new("UICorner")
pcCorner.CornerRadius = UDim.new(0, 10)
pcCorner.Parent = ProfileCard

local pcStroke = Instance.new("UIStroke")
pcStroke.Color = Theme.Stroke
pcStroke.Thickness = 1
pcStroke.Parent = ProfileCard

local pcPadding = Instance.new("UIPadding")
pcPadding.PaddingLeft = UDim.new(0, 14)
pcPadding.PaddingRight = UDim.new(0, 14)
pcPadding.PaddingTop = UDim.new(0, 14)
pcPadding.PaddingBottom = UDim.new(0, 14)
pcPadding.Parent = ProfileCard

local pcLayout = Instance.new("UIListLayout")
pcLayout.Padding = UDim.new(0, 12)
pcLayout.SortOrder = Enum.SortOrder.LayoutOrder
pcLayout.Parent = ProfileCard

-- Header: avatar + name/username stack, side by side
local ProfileHeader = Instance.new("Frame")
ProfileHeader.BackgroundTransparency = 1
ProfileHeader.Size = UDim2.new(1, 0, 0, 60)
ProfileHeader.LayoutOrder = 1
ProfileHeader.Parent = ProfileCard

local Avatar = Instance.new("ImageLabel")
Avatar.Name = "Avatar"
Avatar.Size = UDim2.fromOffset(60, 60)
Avatar.BackgroundColor3 = Theme.PanelAlt
Avatar.Image = ""
Avatar.Parent = ProfileHeader

local avCorner = Instance.new("UICorner")
avCorner.CornerRadius = UDim.new(0, 10)
avCorner.Parent = Avatar

local avStroke = Instance.new("UIStroke")
avStroke.Color = Theme.Stroke
avStroke.Thickness = 1
avStroke.Parent = Avatar

local NameStack = Instance.new("Frame")
NameStack.BackgroundTransparency = 1
NameStack.Position = UDim2.fromOffset(72, 0)
NameStack.Size = UDim2.new(1, -72, 1, 0)
NameStack.Parent = ProfileHeader

local NameStackLayout = Instance.new("UIListLayout")
NameStackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
NameStackLayout.Padding = UDim.new(0, 4)
NameStackLayout.SortOrder = Enum.SortOrder.LayoutOrder
NameStackLayout.Parent = NameStack

local DisplayNameVal = Instance.new("TextLabel")
DisplayNameVal.BackgroundTransparency = 1
DisplayNameVal.Size = UDim2.new(1, 0, 0, 22)
DisplayNameVal.Font = FONT_BOLD
DisplayNameVal.TextSize = 17
DisplayNameVal.TextColor3 = Theme.Text
DisplayNameVal.TextXAlignment = Enum.TextXAlignment.Left
DisplayNameVal.TextTruncate = Enum.TextTruncate.AtEnd
DisplayNameVal.Text = "No recipient yet"
DisplayNameVal.LayoutOrder = 1
DisplayNameVal.Parent = NameStack

local UsernameVal = Instance.new("TextLabel")
UsernameVal.BackgroundTransparency = 1
UsernameVal.Size = UDim2.new(1, 0, 0, 18)
UsernameVal.Font = FONT_REG
UsernameVal.TextSize = 14
UsernameVal.TextColor3 = Theme.SubText
UsernameVal.TextXAlignment = Enum.TextXAlignment.Left
UsernameVal.TextTruncate = Enum.TextTruncate.AtEnd
UsernameVal.Text = "Search a username above"
UsernameVal.LayoutOrder = 2
UsernameVal.Parent = NameStack

-- User ID chip, styled like a small pill instead of a bare label row
local UserIdChip = Instance.new("Frame")
UserIdChip.BackgroundColor3 = Theme.PanelAlt
UserIdChip.Size = UDim2.new(1, 0, 0, 34)
UserIdChip.LayoutOrder = 2
UserIdChip.Parent = ProfileCard

local chipCorner = Instance.new("UICorner")
chipCorner.CornerRadius = UDim.new(0, 8)
chipCorner.Parent = UserIdChip

local chipPadding = Instance.new("UIPadding")
chipPadding.PaddingLeft = UDim.new(0, 10)
chipPadding.PaddingRight = UDim.new(0, 10)
chipPadding.Parent = UserIdChip

local ChipLabel = Instance.new("TextLabel")
ChipLabel.BackgroundTransparency = 1
ChipLabel.Size = UDim2.new(0.4, 0, 1, 0)
ChipLabel.Font = FONT_REG
ChipLabel.TextSize = 13
ChipLabel.TextColor3 = Theme.SubText
ChipLabel.TextXAlignment = Enum.TextXAlignment.Left
ChipLabel.Text = "🪪  User ID"
ChipLabel.Parent = UserIdChip

local UserIdVal = Instance.new("TextLabel")
UserIdVal.BackgroundTransparency = 1
UserIdVal.Position = UDim2.new(0.4, 0, 0, 0)
UserIdVal.Size = UDim2.new(0.6, 0, 1, 0)
UserIdVal.Font = FONT_SEMI
UserIdVal.TextSize = 14
UserIdVal.TextColor3 = Theme.Text
UserIdVal.TextXAlignment = Enum.TextXAlignment.Right
UserIdVal.TextTruncate = Enum.TextTruncate.AtEnd
UserIdVal.Text = "—"
UserIdVal.Parent = UserIdChip

local request =
    syn and syn.request or
    http_request or
    (http and http.request)

local function setAvatar(imageLabel, headshotUserId)
    imageLabel.Image = ""

    task.spawn(function()
        local success, image = pcall(function()
            return MailboxItemCatalog.GetHeadshot(headshotUserId)
        end)

        if success and image ~= "" and imageLabel.Parent then
            imageLabel.Image = image
        end
    end)
end

local function setRecipientStrokeState(state)
    -- state: "idle" | "notfound" | "found"
    local color = Theme.Stroke
    if state == "notfound" then
        color = Theme.Danger
    elseif state == "found" then
        color = Theme.Success
    end
    TweenService:Create(RecipientStroke, TweenInfo.new(0.15), {Color = color}):Play()
end

local function lookupUser(username)
    if username == "" then
        Avatar.Image = ""
        DisplayNameVal.Text = "No recipient yet"
        UsernameVal.Text = "Search a username above"
        UserIdVal.Text = "—"
        userId = nil
        setRecipientStrokeState("idle")
        return
    end

    if not request then
        warn("No HTTP request function available in this environment.")
        return
    end

    task.spawn(function()
        local success, response = pcall(function()
            return request({
                Url = "https://jayhub.onrender.com/userLookup?username=" .. HttpService:UrlEncode(username),
                Method = "GET"
            })
        end)

        if not success or not response or response.StatusCode ~= 200 then
            setRecipientStrokeState("notfound")
            return
        end

        local ok, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)

        if not ok or not data.success or not data.user then
            Avatar.Image = ""
            DisplayNameVal.Text = "Not Found"
            UsernameVal.Text = "—"
            UserIdVal.Text = "—"
            userId = nil
            setRecipientStrokeState("notfound")
            return
        end

        local user = data.user

        setAvatar(Avatar, user.id)
        userId = user.id
        DisplayNameVal.Text = user.displayName
        UsernameVal.Text = "@" .. user.username
        UserIdVal.Text = tostring(user.id)
        setRecipientStrokeState("found")
    end)
end

-- Debounced live search: looks the recipient up ~0.4s after typing stops,
-- instead of only on focus lost, without spamming a request per keystroke.
local searchToken = 0

RecipientInput:GetPropertyChangedSignal("Text"):Connect(function()
    local text = RecipientInput.Text
    searchToken = searchToken + 1
    local myToken = searchToken

    task.delay(0.4, function()
        if searchToken == myToken then
            lookupUser(text)
        end
    end)
end)

RecipientInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        searchToken = searchToken + 1 -- invalidate any pending debounce
        lookupUser(RecipientInput.Text)
    end
end)

-- ---- Current Mail list ----
-- MailSection used to be sized with a hardcoded "1, 0, 1, -264" comment
-- that assumed a desktop-only Split height of 200. On mobile, Split is
-- taller (SPLIT_HEIGHT = 360) so that fixed -264 offset left almost no
-- room at all for this section -- it rendered as the ~2px sliver you saw
-- in the screenshot. It's now derived from SPLIT_HEIGHT + ACTIONS_HEIGHT +
-- the two UIListLayout gaps, so it always leaves the right amount of room
-- no matter which layout (mobile or desktop) is active.
local MailSection = Instance.new("Frame")
MailSection.Name = "MailSection"
MailSection.BackgroundTransparency = 1
MailSection.Size = UDim2.new(1, 0, 1, -(SPLIT_HEIGHT + ACTIONS_HEIGHT + MAIN_LIST_GAP * 2))
MailSection.LayoutOrder = 2
MailSection.Parent = MainPage

local MailLayout = Instance.new("UIListLayout")
MailLayout.Padding = UDim.new(0, 8)
MailLayout.SortOrder = Enum.SortOrder.LayoutOrder
MailLayout.Parent = MailSection

local MailLabel = Instance.new("TextLabel")
MailLabel.BackgroundTransparency = 1
MailLabel.Size = UDim2.new(1, 0, 0, 18)
MailLabel.Font = FONT_SEMI
MailLabel.TextSize = 15
MailLabel.TextColor3 = Theme.SubText
MailLabel.TextXAlignment = Enum.TextXAlignment.Left
MailLabel.Text = "Current Mail"
MailLabel.LayoutOrder = 1
MailLabel.Parent = MailSection

local MailListFrame = Instance.new("ScrollingFrame")
MailListFrame.Name = "MailList"
MailListFrame.BackgroundColor3 = Theme.Panel
MailListFrame.BorderSizePixel = 0
MailListFrame.Size = UDim2.new(1, 0, 1, -26)
MailListFrame.LayoutOrder = 2
MailListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
MailListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
MailListFrame.ScrollBarThickness = 4
MailListFrame.ScrollBarImageColor3 = Theme.Accent
MailListFrame.Parent = MailSection

local mlCorner = Instance.new("UICorner")
mlCorner.CornerRadius = UDim.new(0, 8)
mlCorner.Parent = MailListFrame

local mlStroke = Instance.new("UIStroke")
mlStroke.Color = Theme.Stroke
mlStroke.Thickness = 1
mlStroke.Parent = MailListFrame

local mlPadding = Instance.new("UIPadding")
mlPadding.PaddingLeft = UDim.new(0, 12)
mlPadding.PaddingRight = UDim.new(0, 12)
mlPadding.PaddingTop = UDim.new(0, 8)
mlPadding.PaddingBottom = UDim.new(0, 8)
mlPadding.Parent = MailListFrame

local mlListLayout = Instance.new("UIListLayout")
mlListLayout.Padding = UDim.new(0, 6)
mlListLayout.SortOrder = Enum.SortOrder.LayoutOrder
mlListLayout.Parent = MailListFrame

local EmptyStateLabel = Instance.new("TextLabel")
EmptyStateLabel.Name = "EmptyState"
EmptyStateLabel.BackgroundTransparency = 1
EmptyStateLabel.Size = UDim2.new(1, 0, 0, 30)
EmptyStateLabel.Font = FONT_REG
EmptyStateLabel.TextSize = 14
EmptyStateLabel.TextColor3 = Theme.SubText
EmptyStateLabel.TextXAlignment = Enum.TextXAlignment.Left
EmptyStateLabel.Text = "Nothing in mail yet — add items from the Pets, Seeds, Gears, or Fruits tabs."
EmptyStateLabel.TextWrapped = true
EmptyStateLabel.LayoutOrder = 0
EmptyStateLabel.Parent = MailListFrame

local function addMailItem(icon, text, order)
    local Item = Instance.new("Frame")
    Item.BackgroundTransparency = 1
    Item.Size = UDim2.new(1, 0, 0, 32)
    Item.LayoutOrder = order
    Item.Parent = MailListFrame

    local IconLabel = Instance.new("TextLabel")
    IconLabel.BackgroundTransparency = 1
    IconLabel.Size = UDim2.fromOffset(28, 32)
    IconLabel.Font = FONT_REG
    IconLabel.TextSize = 17
    IconLabel.Text = icon
    IconLabel.Parent = Item

    local TextLbl = Instance.new("TextLabel")
    TextLbl.BackgroundTransparency = 1
    TextLbl.Position = UDim2.fromOffset(32, 0)
    TextLbl.Size = UDim2.new(1, -66, 1, 0)
    TextLbl.Font = FONT_REG
    TextLbl.TextSize = 15
    TextLbl.TextColor3 = Theme.Text
    TextLbl.TextXAlignment = Enum.TextXAlignment.Left
    TextLbl.Text = text
    TextLbl.Parent = Item

    local RemoveX = Instance.new("TextButton")
    RemoveX.BackgroundTransparency = 1
    RemoveX.Size = UDim2.fromOffset(30, 32)
    RemoveX.Position = UDim2.new(1, -30, 0, 0)
    RemoveX.Font = FONT_SEMI
    RemoveX.TextSize = 15
    RemoveX.TextColor3 = Theme.SubText
    RemoveX.Text = "X"
    RemoveX.AutoButtonColor = false
    RemoveX.Parent = Item

    RemoveX.MouseEnter:Connect(function()
        TweenService:Create(RemoveX, TweenInfo.new(0.1), {TextColor3 = Theme.Danger}):Play()
    end)
    RemoveX.MouseLeave:Connect(function()
        TweenService:Create(RemoveX, TweenInfo.new(0.1), {TextColor3 = Theme.SubText}):Play()
    end)

    return RemoveX
end

local function clearMailItems()
    for _, child in ipairs(MailListFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local updateCurrentMail

updateCurrentMail = function()
    clearMailItems()

    EmptyStateLabel.Visible = #batch == 0

    for i, item in ipairs(batch) do
        local text

        if item.Category == "HarvestedFruits" then
            local fruit = fruitNameById[item.ItemKey]
            text = fruit and fruit.Display or "Unknown Fruit"
        else
            text = string.format("%s ×%d", item.ItemKey, item.Count)
        end

        local removeBtn = addMailItem(
            MAIL_ICONS[item.Category] or "📦",
            text,
            i
        )

        removeBtn.MouseButton1Click:Connect(function()
            table.remove(batch, i)
            updateCurrentMail()
        end)
    end
end

local Actions = Instance.new("Frame")
Actions.Name = "Actions"
Actions.BackgroundTransparency = 1
Actions.Size = UDim2.new(1, 0, 0, ACTIONS_HEIGHT)
Actions.LayoutOrder = 3
Actions.Parent = MainPage

local ActionsLayout = Instance.new("UIListLayout")
ActionsLayout.FillDirection = Enum.FillDirection.Horizontal
ActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
ActionsLayout.Padding = UDim.new(0, 10)
ActionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
ActionsLayout.Parent = Actions

local StatusLabel = Instance.new("TextLabel")
StatusLabel.BackgroundTransparency = 1
StatusLabel.Size = UDim2.new(1, -290, 1, 0)
StatusLabel.Font = FONT_REG
StatusLabel.TextSize = 14
StatusLabel.TextColor3 = Theme.SubText
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Text = ""
StatusLabel.Parent = Actions

local function setStatus(text, isError)
    StatusLabel.Text = text
    StatusLabel.TextColor3 = isError and Theme.Danger or Theme.Success
end

local function makeActionButton(text, order, primary)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0, 136, 1, 0)
    Btn.LayoutOrder = order
    Btn.BackgroundColor3 = primary and Theme.Accent or Theme.PanelAlt
    Btn.AutoButtonColor = false
    Btn.Font = FONT_BOLD
    Btn.TextSize = 16
    Btn.TextColor3 = primary and Color3.new(1,1,1) or Theme.SubText
    Btn.Text = text
    Btn.Parent = Actions

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = Btn

    local baseColor = Btn.BackgroundColor3
    local hoverColor = primary and Theme.AccentHover or Theme.Panel

    Btn.MouseEnter:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.12), {BackgroundColor3 = hoverColor}):Play()
    end)
    Btn.MouseLeave:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.12), {BackgroundColor3 = baseColor}):Play()
    end)

    return Btn
end

local ClearBtn = makeActionButton("Clear", 1, false)
local SendBtn = makeActionButton("Send Mail", 2, true)

ClearBtn.MouseButton1Click:Connect(function()
    table.clear(batch)
    updateCurrentMail()
    RecipientInput.Text = ""
    NoteInput.Text = ""
    noteText = ""
    userId = nil
    Avatar.Image = ""
    DisplayNameVal.Text = "No recipient yet"
    UsernameVal.Text = "Search a username above"
    UserIdVal.Text = "—"
    setRecipientStrokeState("idle")
    setStatus("")
end)

local sending = false

SendBtn.MouseButton1Click:Connect(function()
    if sending then return end

    if not userId then
        setStatus("Pick a valid recipient first.", true)
        return
    end

    if #batch == 0 then
        setStatus("Add at least one item to send.", true)
        return
    end

    sending = true
    local originalText = SendBtn.Text
    SendBtn.Text = "Sending..."
    setStatus("Sending mail...", false)

    local success, result = pcall(function()
        return sendMail(userId, batch, noteText)
    end)

    sending = false
    SendBtn.Text = originalText

    if success then
        setStatus("Mail sent!", false)
        table.clear(batch)
        updateCurrentMail()
        refreshPets()
        refreshSeeds()
        refreshGears()
        refreshFruits()
    else
        setStatus("Failed to send mail: " .. tostring(result), true)
        warn("Failed to send mail:", result)
    end
end)

local mainListLayout = Instance.new("UIListLayout")
mainListLayout.Padding = UDim.new(0, MAIN_LIST_GAP)
mainListLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainListLayout.Parent = MainPage

local dragging = false
local dragStart, startPos

TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

local minimized = false
local expandedSize = Main.Size

Minimize.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        expandedSize = Main.Size
        TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.fromOffset(WIDTH, 48)
        }):Play()
        Content.Visible = false
    else
        Content.Visible = true
        TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = expandedSize
        }):Play()
    end
end)

-- Maximize: toggle between default size and near-fullscreen
local maximized = false
local preMaxSize, preMaxPos

Maximize.MouseButton1Click:Connect(function()
    maximized = not maximized
    if maximized then
        preMaxSize = Main.Size
        preMaxPos = Main.Position
        TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.fromOffset(viewport.X - 40, viewport.Y - 40),
            Position = UDim2.fromScale(0.5, 0.5),
        }):Play()
    else
        TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = preMaxSize,
            Position = preMaxPos,
        }):Play()
    end
end)

Close.MouseButton1Click:Connect(function()
    local tween = TweenService:Create(Main, TweenInfo.new(0.15), {
        Size = Main.Size - UDim2.fromOffset(30, 30),
        Position = Main.Position,
    })
    TweenService:Create(UIStroke, TweenInfo.new(0.15), {Transparency = 1}):Play()
    tween:Play()
    task.wait(0.15)
    ScreenGui:Destroy()
end)

local function getPetData()
    if not PlayerState then return {}, {} end

    local replica = PlayerState:GetLocalReplica()
    if not replica then return {}, {} end

    local pets = replica.Data.Inventory.Pets or {}
    local grouped = {}
    local dropdown = {}
    local cache = {}

    for uuid, pet in pairs(pets) do
        if type(pet) == "table" and pet.Name then
            petNameById[uuid] = pet.Name
            grouped[pet.Name] = grouped[pet.Name] or {}
            table.insert(grouped[pet.Name], {
                Id = uuid,
                Name = pet.Name
            })
        end
    end

    for name, list in pairs(grouped) do
        local display = string.format("%s (%d)", name, #list)

        table.insert(dropdown, display)

        cache[display] = {
            Category = "Pets",
            Name = name,
            Pets = list, -- individual pet instances { Id, Name } available for this type
        }
    end

    table.sort(dropdown)

    return dropdown, cache
end

local function getSeedData()
    if not PlayerState then return {}, {} end

    local replica = PlayerState:GetLocalReplica()
    if not replica then return {}, {} end

    local seeds = replica.Data.Inventory.Seeds or {}
    local dropdown = {}
    local cache = {}

    for name, count in pairs(seeds) do
        if type(count) == "number" and count > 0 then
            local display = string.format("%s (%d)", name, count)

            table.insert(dropdown, display)

            cache[display] = {
                Category = "Seeds",
                ItemKey = name,
                Count = count
            }
        end
    end

    table.sort(dropdown)

    return dropdown, cache
end

local function getGearData()
    if not PlayerState then return {}, {} end

    local replica = PlayerState:GetLocalReplica()
    if not replica then return {}, {} end

    local inventory = replica.Data.Inventory
    local dropdown = {}
    local cache = {}

    local categories = {
        "Sprinklers",
        "Trowels",
        "WateringCans",
        "Eggs"
    }

    for _, category in ipairs(categories) do
        local items = inventory[category]

        if type(items) == "table" then
            for name, count in pairs(items) do
                if type(count) == "number" and count > 0 then
                    local display = string.format("[%s] %s (%d)", category, name, count)

                    table.insert(dropdown, display)

                    cache[display] = {
                        Category = category,
                        ItemKey = name,
                        Count = count
                    }
                end
            end
        end
    end

    table.sort(dropdown)

    return dropdown, cache
end

local CalculateFruitValue = require(game:GetService("ReplicatedStorage").SharedModules.FruitValueCalc)

local function formatNumber(value)
    if value >= 1e12 then
        return string.format("%.2fT", value / 1e12)
    elseif value >= 1e9 then
        return string.format("%.2fB", value / 1e9)
    elseif value >= 1e6 then
        return string.format("%.2fM", value / 1e6)
    elseif value >= 1e3 then
        return string.format("%.2fK", value / 1e3)
    else
        return tostring(math.floor(value))
    end
end

formatNumber = formatNumber or function(n) return tostring(n) end
CalculateFruitValue = CalculateFruitValue or function() return 0 end

local fruitOptions = {}
local fruitCache = {}
-- NOTE: intentionally NOT re-declared with `local` here -- it reuses the same
-- `fruitNameById` table declared at the top of the file. Re-declaring it with
-- `local` would shadow that outer variable, leaving the earlier one (the one
-- updateCurrentMail actually reads from) permanently empty.

local function refreshFruitData()
    table.clear(fruitOptions)
    table.clear(fruitCache)
    table.clear(fruitNameById)

    local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return end

    for _, config in ipairs(backpack:GetDescendants()) do
        if config:IsA("Configuration") then
            local fruitName = config:GetAttribute("FruitName")
            local id = config:GetAttribute("Id")
            local size = config:GetAttribute("SizeMultiplier")

            if fruitName and id and size then
                local value = CalculateFruitValue(
                    fruitName,
                    size,
                    config:GetAttribute("Mutation"),
                    Players.LocalPlayer,
                    config:GetAttribute("Decay")
                )

                local display = string.format("%s [%s]", fruitName, formatNumber(value))

                fruitCache[display] = {Id = id, Value = value, Config = config}
                fruitNameById[id] = {Name = fruitName, Display = display, Value = value}

                table.insert(fruitOptions, display)
            end
        end
    end

    table.sort(fruitOptions)
end

refreshFruitData()

-- Given a sheckles target, greedily picks the fewest highest-value fruits
-- from the backpack needed to reach (or get closest to) that value.
local function calculateFruit(targetValue)
    local fruits = {}
    local backpack = Players.LocalPlayer:FindFirstChild("Backpack")

    if backpack then
        for _, config in ipairs(backpack:GetDescendants()) do
            if config:IsA("Configuration") then
                local fruitName = config:GetAttribute("FruitName")
                local id = config:GetAttribute("Id")
                local size = config:GetAttribute("SizeMultiplier")

                if fruitName and id and size then
                    table.insert(fruits, {
                        Id = id,
                        Name = fruitName,
                        Config = config,
                        Value = CalculateFruitValue(
                            fruitName,
                            size,
                            config:GetAttribute("Mutation"),
                            Players.LocalPlayer,
                            config:GetAttribute("Decay")
                        )
                    })
                end
            end
        end
    end

    table.sort(fruits, function(a, b)
        return a.Value > b.Value
    end)

    local selected = {}
    local total = 0
    local inventoryTotal = 0

    for _, fruit in ipairs(fruits) do
        inventoryTotal = inventoryTotal + fruit.Value
    end

    for _, fruit in ipairs(fruits) do
        table.insert(selected, fruit)
        total = total + fruit.Value

        if total >= targetValue then
            break
        end
    end

    return {
        Success = #selected <= 20,
        Fruits = selected,
        TotalValue = total,
        InventoryValue = inventoryTotal,
        TargetValue = targetValue,
        RemainingValue = math.max(0, targetValue - total),
        ReachedTarget = total >= targetValue,
        Count = #selected
    }
end

-- =====================================================================
-- CUSTOM DROPDOWN COMPONENT
-- Roblox has no native dropdown, so this builds a button + floating list.
-- Supports single-select and multi-select (checkbox) modes.
-- =====================================================================
local function createDropdown(parent, position, size, options, placeholder, multiSelect, onChange)
    local Dropdown = {}
    Dropdown.Selected = nil
    Dropdown.SelectedSet = {}

    local Button = Instance.new("TextButton")
    Button.Size = size
    Button.Position = position
    Button.BackgroundColor3 = Theme.Panel
    Button.AutoButtonColor = false
    Button.Font = FONT_REG
    Button.TextSize = 15
    Button.TextColor3 = Theme.SubText
    Button.TextXAlignment = Enum.TextXAlignment.Left
    Button.Text = "   " .. placeholder
    Button.ZIndex = 8
    Button.ClipsDescendants = true
    Button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = Button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Stroke
    stroke.Thickness = 1
    stroke.Parent = Button

    local Arrow = Instance.new("TextLabel")
    Arrow.BackgroundTransparency = 1
    Arrow.Size = UDim2.new(0, 24, 1, 0)
    Arrow.Position = UDim2.new(1, -26, 0, 0)
    Arrow.Text = "▾"
    Arrow.Font = FONT_REG
    Arrow.TextSize = 12
    Arrow.TextColor3 = Theme.SubText
    Arrow.ZIndex = 8
    Arrow.Parent = Button

    local List = Instance.new("Frame")
    List.BackgroundColor3 = Theme.PanelAlt
    List.Position = UDim2.new(0, position.X.Offset, 0, position.Y.Offset + size.Y.Offset + 4)
    List.Size = UDim2.new(0, size.X.Offset, 0, 0)
    List.Visible = false
    List.ClipsDescendants = true
    List.ZIndex = 30
    List.Parent = parent

    local listCorner = Instance.new("UICorner")
    listCorner.CornerRadius = UDim.new(0, 8)
    listCorner.Parent = List

    local listStroke = Instance.new("UIStroke")
    listStroke.Color = Theme.Stroke
    listStroke.Thickness = 1
    listStroke.Parent = List

    local ListScroll = Instance.new("ScrollingFrame")
    ListScroll.BackgroundTransparency = 1
    ListScroll.Size = UDim2.new(1, 0, 1, 0)
    ListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ListScroll.ScrollBarThickness = 3
    ListScroll.ScrollBarImageColor3 = Theme.Accent
    ListScroll.ZIndex = 31
    ListScroll.Parent = List

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 6)
    pad.PaddingRight = UDim.new(0, 6)
    pad.PaddingTop = UDim.new(0, 4)
    pad.Parent = ListScroll

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = ListScroll

    local optionButtons = {}
    local isOpen = false

    local function updateButtonText()
        if multiSelect then
            local count = 0
            for _ in pairs(Dropdown.SelectedSet) do count = count + 1 end
            Button.Text = count == 0 and ("   " .. placeholder) or ("   " .. count .. " selected")
        else
            Button.Text = "   " .. (Dropdown.Selected or placeholder)
        end
    end

    local function closeList()
        isOpen = false
        List.Visible = false
        List.Size = UDim2.new(0, size.X.Offset, 0, 0)
    end

    local function openList()
        isOpen = true
        local h = math.min(#optionButtons * 32 + 8, 192)
        List.Visible = true
        List.Size = UDim2.new(0, size.X.Offset, 0, h)
    end

    Button.MouseButton1Click:Connect(function()
        if isOpen then closeList() else openList() end
    end)

    function Dropdown:SetOptions(newOptions)
        for _, b in ipairs(optionButtons) do b:Destroy() end
        optionButtons = {}
        Dropdown.Selected = nil
        Dropdown.SelectedSet = {}
        updateButtonText()

        for i, opt in ipairs(newOptions) do
            local OptBtn = Instance.new("TextButton")
            OptBtn.Size = UDim2.new(1, 0, 0, 30)
            OptBtn.LayoutOrder = i
            OptBtn.BackgroundColor3 = Theme.Panel
            OptBtn.BackgroundTransparency = 1
            OptBtn.AutoButtonColor = false
            OptBtn.Font = FONT_REG
            OptBtn.TextSize = 14
            OptBtn.TextColor3 = Theme.Text
            OptBtn.TextXAlignment = Enum.TextXAlignment.Left
            OptBtn.Text = (multiSelect and "☐ " or "  ") .. opt
            OptBtn.ZIndex = 32
            OptBtn.Parent = ListScroll

            local optPad = Instance.new("UIPadding")
            optPad.PaddingLeft = UDim.new(0, 6)
            optPad.Parent = OptBtn

            local optCorner = Instance.new("UICorner")
            optCorner.CornerRadius = UDim.new(0, 6)
            optCorner.Parent = OptBtn

            OptBtn.MouseEnter:Connect(function()
                OptBtn.BackgroundTransparency = 0.6
            end)
            OptBtn.MouseLeave:Connect(function()
                OptBtn.BackgroundTransparency = 1
            end)

            OptBtn.MouseButton1Click:Connect(function()
                if multiSelect then
                    if Dropdown.SelectedSet[opt] then
                        Dropdown.SelectedSet[opt] = nil
                        OptBtn.Text = "☐ " .. opt
                    else
                        Dropdown.SelectedSet[opt] = true
                        OptBtn.Text = "☑ " .. opt
                    end
                    updateButtonText()
                else
                    Dropdown.Selected = opt
                    updateButtonText()
                    closeList()
                end
                if onChange then onChange(Dropdown) end
            end)

            table.insert(optionButtons, OptBtn)
        end
    end

    Dropdown:SetOptions(options)
    Dropdown.Frame = Button
    Dropdown.List = List
    Dropdown.GetValue = function() return Dropdown.Selected end
    Dropdown.GetValues = function()
        local list = {}
        for k in pairs(Dropdown.SelectedSet) do table.insert(list, k) end
        return list
    end
    Dropdown.Close = closeList
    Dropdown.Destroy = function()
        Button:Destroy()
        List:Destroy()
    end

    return Dropdown
end

local function createAmountInput(parent, position, size, defaultText)
    local Box = Instance.new("Frame")
    Box.BackgroundColor3 = Theme.Panel
    Box.Position = position
    Box.Size = size
    Box.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = Box

    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Stroke
    stroke.Thickness = 1
    stroke.Parent = Box

    local Input = Instance.new("TextBox")
    Input.BackgroundTransparency = 1
    Input.Size = UDim2.new(1, -16, 1, 0)
    Input.Position = UDim2.fromOffset(8, 0)
    Input.Font = FONT_REG
    Input.TextSize = 15
    Input.TextColor3 = Theme.Text
    Input.PlaceholderColor3 = Theme.SubText
    Input.ClearTextOnFocus = false
    Input.Text = defaultText or "1"
    Input.TextXAlignment = Enum.TextXAlignment.Left
    Input.Parent = Box

    Input.Focused:Connect(function()
        TweenService:Create(stroke, TweenInfo.new(0.12), {Color = Theme.Accent}):Play()
    end)
    Input.FocusLost:Connect(function()
        TweenService:Create(stroke, TweenInfo.new(0.12), {Color = Theme.Stroke}):Play()
        local n = tonumber(Input.Text)
        if not n then
            Input.Text = "1"
        else
            Input.Text = tostring(math.max(1, math.floor(n)))
        end
    end)

    return Box, Input
end

local function createSmallButton(parent, position, size, text, danger)
    local Btn = Instance.new("TextButton")
    Btn.Position = position
    Btn.Size = size
    Btn.BackgroundColor3 = danger and Theme.PanelAlt or Theme.Accent
    Btn.AutoButtonColor = false
    Btn.Font = FONT_BOLD
    Btn.TextSize = 15
    Btn.TextColor3 = danger and Theme.SubText or Color3.new(1, 1, 1)
    Btn.Text = text
    Btn.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = Btn

    local base = Btn.BackgroundColor3
    local hover = danger and Theme.Danger or Theme.AccentHover

    Btn.MouseEnter:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.12), {BackgroundColor3 = hover}):Play()
        if danger then
            TweenService:Create(Btn, TweenInfo.new(0.12), {TextColor3 = Color3.new(1,1,1)}):Play()
        end
    end)
    Btn.MouseLeave:Connect(function()
        TweenService:Create(Btn, TweenInfo.new(0.12), {BackgroundColor3 = base}):Play()
        if danger then
            TweenService:Create(Btn, TweenInfo.new(0.12), {TextColor3 = Theme.SubText}):Play()
        end
    end)

    return Btn
end

local selectedPet, amount = nil, 1
local selectedSeed, seedAmount = nil, 1
local selectedGear, gearAmount = nil, 1

local function buildSimpleCategoryPage(page, itemLabel, getData, setSelected, setAmount)
    local Padding = Instance.new("UIPadding")
    Padding.PaddingLeft = UDim.new(0, 18)
    Padding.PaddingRight = UDim.new(0, 18)
    Padding.PaddingTop = UDim.new(0, 16)
    Padding.PaddingBottom = UDim.new(0, 16)
    Padding.Parent = page

    local gridOptions, cache = getData()

    local AmountLabel = Instance.new("TextLabel")
    AmountLabel.BackgroundTransparency = 1
    AmountLabel.Size = UDim2.fromOffset(120, 20)
    AmountLabel.Font = FONT_SEMI
    AmountLabel.TextSize = 15
    AmountLabel.TextColor3 = Theme.SubText
    AmountLabel.TextXAlignment = Enum.TextXAlignment.Left
    AmountLabel.Text = "Amount"
    AmountLabel.Parent = page

    local _, AmountInput = createAmountInput(
        page,
        UDim2.fromOffset(0, 24),
        UDim2.fromOffset(140, 42),
        "1"
    )

    AmountInput:GetPropertyChangedSignal("Text"):Connect(function()
        setAmount(tonumber(AmountInput.Text) or 1)
    end)

    local GridLabel = Instance.new("TextLabel")
    GridLabel.BackgroundTransparency = 1
    GridLabel.Position = UDim2.fromOffset(0, 78)
    GridLabel.Size = UDim2.new(1, 0, 0, 20)
    GridLabel.Font = FONT_SEMI
    GridLabel.TextSize = 15
    GridLabel.TextColor3 = Theme.SubText
    GridLabel.TextXAlignment = Enum.TextXAlignment.Left
    GridLabel.Text = "Owned " .. itemLabel .. "s"
    GridLabel.Parent = page

    local GridScroll = Instance.new("ScrollingFrame")
    GridScroll.BackgroundColor3 = Theme.Panel
    GridScroll.BorderSizePixel = 0
    GridScroll.Position = UDim2.fromOffset(0, 102)
    GridScroll.Size = UDim2.new(1, 0, 1, -102)
    GridScroll.CanvasSize = UDim2.new()
    GridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    GridScroll.ScrollBarThickness = 4
    GridScroll.ScrollBarImageColor3 = Theme.Accent
    GridScroll.Parent = page

    local gsCorner = Instance.new("UICorner")
    gsCorner.CornerRadius = UDim.new(0, 10)
    gsCorner.Parent = GridScroll

    local gsStroke = Instance.new("UIStroke")
    gsStroke.Color = Theme.Stroke
    gsStroke.Parent = GridScroll

    local gsPadding = Instance.new("UIPadding")
    gsPadding.PaddingLeft = UDim.new(0, 10)
    gsPadding.PaddingRight = UDim.new(0, 10)
    gsPadding.PaddingTop = UDim.new(0, 10)
    gsPadding.PaddingBottom = UDim.new(0, 10)
    gsPadding.Parent = GridScroll

    local gsGrid = Instance.new("UIGridLayout")
    gsGrid.CellSize = IsMobile and UDim2.fromOffset(150, 58) or UDim2.fromOffset(216, 58)
    gsGrid.CellPadding = UDim2.fromOffset(10, 10)
    gsGrid.SortOrder = Enum.SortOrder.LayoutOrder
    gsGrid.Parent = GridScroll

    local function ShowAdded(card)
        local originalColor = card.BackgroundColor3
        TweenService:Create(card, TweenInfo.new(0.08), {BackgroundColor3 = Theme.Accent}):Play()
        task.delay(0.12, function()
            if card.Parent then
                TweenService:Create(card, TweenInfo.new(0.15), {BackgroundColor3 = originalColor}):Play()
            end
        end)
    end

    local function quickAdd(sel, amt, card)
        local info = cache[sel]
        if not info then
            return
        end

        if itemLabel == "Pet" then
            for i = 1, math.min(amt, #info.Pets) do
                table.insert(batch, {
                    Category = "Pets",
                    ItemKey = info.Pets[i].Id,
                    Count = 1
                })
            end

            updateCurrentMail()

            if card then
                ShowAdded(card)
            end

            return
        end

        local item

        if itemLabel == "Seed" then
            item = {
                Category = "Seeds",
                ItemKey = info.ItemKey,
                Count = amt
            }
        elseif itemLabel == "Gear" then
            item = {
                Category = info.Category,
                ItemKey = info.ItemKey,
                Count = amt
            }
        end

        if item then
            table.insert(batch, item)

            updateCurrentMail()

            if card then
                ShowAdded(card)
            end
        end
    end

    local function rebuildGrid()
        for _, child in ipairs(GridScroll:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        if #gridOptions == 0 then
            local EmptyLbl = Instance.new("TextLabel")
            EmptyLbl.BackgroundTransparency = 1
            EmptyLbl.Size = UDim2.fromOffset(400, 24)
            EmptyLbl.Font = FONT_REG
            EmptyLbl.TextSize = 14
            EmptyLbl.TextColor3 = Theme.SubText
            EmptyLbl.TextXAlignment = Enum.TextXAlignment.Left
            EmptyLbl.Text = "You don't own any " .. itemLabel:lower() .. "s yet."
            EmptyLbl.LayoutOrder = 1
            EmptyLbl.Parent = GridScroll
            return
        end

        for i, display in ipairs(gridOptions) do
            local Card = Instance.new("TextButton")
            Card.BackgroundColor3 = Theme.PanelAlt
            Card.AutoButtonColor = false
            Card.LayoutOrder = i
            Card.Text = ""
            Card.Parent = GridScroll

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 8)
            cardCorner.Parent = Card

            local cardPad = Instance.new("UIPadding")
            cardPad.PaddingLeft = UDim.new(0, 10)
            cardPad.PaddingRight = UDim.new(0, 10)
            cardPad.Parent = Card

            local NameLbl = Instance.new("TextLabel")
            NameLbl.BackgroundTransparency = 1
            NameLbl.Size = UDim2.new(1, -60, 1, 0)
            NameLbl.Font = FONT_SEMI
            NameLbl.TextSize = 14
            NameLbl.TextColor3 = Theme.Text
            NameLbl.TextXAlignment = Enum.TextXAlignment.Left
            NameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            NameLbl.Text = display
            NameLbl.Parent = Card

            local PlusLbl = Instance.new("TextLabel")
            PlusLbl.BackgroundTransparency = 1
            PlusLbl.Size = UDim2.fromOffset(40, 58)
            PlusLbl.AnchorPoint = Vector2.new(1, 0.5)
            PlusLbl.Position = UDim2.new(1, -10, 0.5, 0)
            PlusLbl.Font = FONT_BOLD
            PlusLbl.TextSize = 12
            PlusLbl.TextColor3 = Theme.Accent
            PlusLbl.Text = "ADD"
            PlusLbl.Parent = Card

            Card.MouseEnter:Connect(function()
                TweenService:Create(Card, TweenInfo.new(0.1), {
                    BackgroundColor3 = Theme.Panel
                }):Play()
            end)

            Card.MouseLeave:Connect(function()
                TweenService:Create(Card, TweenInfo.new(0.1), {
                    BackgroundColor3 = Theme.PanelAlt
                }):Play()
            end)

            Card.MouseButton1Click:Connect(function()
                local amt = tonumber(AmountInput.Text) or 1
                quickAdd(display, amt, Card)
            end)
        end
    end

    local function refreshData()
        gridOptions, cache = getData()
        rebuildGrid()
    end

    rebuildGrid()

    return refreshData
end

refreshPets  = buildSimpleCategoryPage(tabPages["Pets"], "Pet", getPetData,
    function(v) selectedPet = v end, function(v) amount = v end)

refreshSeeds = buildSimpleCategoryPage(tabPages["Seeds"], "Seed", getSeedData,
    function(v) selectedSeed = v end, function(v) seedAmount = v end)

refreshGears = buildSimpleCategoryPage(tabPages["Gears"], "Gear", getGearData,
    function(v) selectedGear = v end, function(v) gearAmount = v end)

local selectedFruit = nil
local fruitMode = "Selected Fruits"
local fruitValueAmount = 0

do
    local page = tabPages["Fruits"]

    local setFruitMode

    local Padding = Instance.new("UIPadding")
    Padding.PaddingLeft = UDim.new(0, 18)
    Padding.PaddingRight = UDim.new(0, 18)
    Padding.PaddingTop = UDim.new(0, 16)
    Padding.PaddingBottom = UDim.new(0, 16)
    Padding.Parent = page

    -- Controls row: this used to be laid out with fixed pixel offsets
    -- (0 / 316 / 546) that assumed a ~900px-wide desktop window. On a
    -- narrow mobile window (WIDTH can be ~300-378) those offsets pushed the
    -- Mode dropdown and Sheckles input completely off the visible page --
    -- exactly the overlap/cutoff seen in the screenshots. Now we use a
    -- UIListLayout so controls flow left-to-right on desktop and stack
    -- vertically on mobile, always staying inside the page bounds.
    local ControlsRow = Instance.new("Frame")
    ControlsRow.BackgroundTransparency = 1
    ControlsRow.Size = UDim2.new(1, 0, 0, IsMobile and 224 or 66)
    ControlsRow.Parent = page

    local ControlsLayout = Instance.new("UIListLayout")
    ControlsLayout.FillDirection = IsMobile and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
    ControlsLayout.Padding = UDim.new(0, IsMobile and 10 or 16)
    ControlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ControlsLayout.Parent = ControlsRow

    local FruitBlock = Instance.new("Frame")
    FruitBlock.BackgroundTransparency = 1
    FruitBlock.LayoutOrder = 1
    FruitBlock.Size = IsMobile and UDim2.new(1, 0, 0, 66) or UDim2.new(0, 300, 1, 0)
    FruitBlock.Parent = ControlsRow

    local FruitLabel = Instance.new("TextLabel")
    FruitLabel.BackgroundTransparency = 1
    FruitLabel.Size = UDim2.new(1, 0, 0, 20)
    FruitLabel.Font = FONT_SEMI
    FruitLabel.TextSize = 15
    FruitLabel.TextColor3 = Theme.SubText
    FruitLabel.TextXAlignment = Enum.TextXAlignment.Left
    FruitLabel.Text = "Fruit"
    FruitLabel.Parent = FruitBlock

    local ModeBlock = Instance.new("Frame")
    ModeBlock.BackgroundTransparency = 1
    ModeBlock.LayoutOrder = 2
    ModeBlock.Size = IsMobile and UDim2.new(1, 0, 0, 66) or UDim2.new(0, 220, 1, 0)
    ModeBlock.Parent = ControlsRow

    local ModeLabel = Instance.new("TextLabel")
    ModeLabel.BackgroundTransparency = 1
    ModeLabel.Size = UDim2.new(1, 0, 0, 20)
    ModeLabel.Font = FONT_SEMI
    ModeLabel.TextSize = 15
    ModeLabel.TextColor3 = Theme.SubText
    ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
    ModeLabel.Text = "Mode"
    ModeLabel.Parent = ModeBlock

    local ValueBlock = Instance.new("Frame")
    ValueBlock.BackgroundTransparency = 1
    ValueBlock.LayoutOrder = 3
    ValueBlock.Size = IsMobile and UDim2.new(1, 0, 0, 66) or UDim2.new(0, 140, 1, 0)
    ValueBlock.Visible = false
    ValueBlock.Parent = ControlsRow

    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Size = UDim2.new(1, 0, 0, 20)
    ValueLabel.Font = FONT_SEMI
    ValueLabel.TextSize = 15
    ValueLabel.TextColor3 = Theme.SubText
    ValueLabel.TextXAlignment = Enum.TextXAlignment.Left
    ValueLabel.Text = "Sheckles Amount"
    ValueLabel.Parent = ValueBlock

    local ValueBox, ValueInput = createAmountInput(ValueBlock, UDim2.fromOffset(0, 24), UDim2.new(1, 0, 0, 42), "0")
    ValueInput:GetPropertyChangedSignal("Text"):Connect(function()
        fruitValueAmount = tonumber(ValueInput.Text) or 0
    end)

    local AddBlock = Instance.new("Frame")
    AddBlock.BackgroundTransparency = 1
    AddBlock.LayoutOrder = 4
    AddBlock.Size = IsMobile and UDim2.new(1, 0, 0, 42) or UDim2.new(0, 160, 1, 0)
    AddBlock.Visible = false
    AddBlock.Parent = ControlsRow

    local ModeDropdown = createDropdown(
        ModeBlock, UDim2.fromOffset(0, 24), UDim2.new(1, 0, 0, 42),
        {"Selected Fruits", "Fruit Value"}, "Selected Fruits", false,
        function(dd)
            local mode = dd:GetValue() or "Selected Fruits"
            fruitMode = mode
            setFruitMode(mode == "Fruit Value")
        end
    )

    local AddBtn = createSmallButton(AddBlock, UDim2.fromOffset(0, IsMobile and 0 or 24), UDim2.new(1, 0, 0, 42), "Add", false)

    local ControlsHeight = ControlsRow.Size.Y.Offset

    local FruitGridLabel = Instance.new("TextLabel")
    FruitGridLabel.BackgroundTransparency = 1
    FruitGridLabel.Position = UDim2.fromOffset(0, ControlsHeight + 12)
    FruitGridLabel.Size = UDim2.new(1, 0, 0, 20)
    FruitGridLabel.Font = FONT_SEMI
    FruitGridLabel.TextSize = 15
    FruitGridLabel.TextColor3 = Theme.SubText
    FruitGridLabel.TextXAlignment = Enum.TextXAlignment.Left
    FruitGridLabel.Text = "Backpack fruits"
    FruitGridLabel.Parent = page

    local FruitGridScroll = Instance.new("ScrollingFrame")
    FruitGridScroll.BackgroundColor3 = Theme.Panel
    FruitGridScroll.BorderSizePixel = 0
    FruitGridScroll.Position = UDim2.fromOffset(0, ControlsHeight + 36)
    FruitGridScroll.Size = UDim2.new(1, 0, 1, -(ControlsHeight + 36))
    FruitGridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    FruitGridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    FruitGridScroll.ScrollBarThickness = 4
    FruitGridScroll.ScrollBarImageColor3 = Theme.Accent
    FruitGridScroll.Parent = page

    local fgsCorner = Instance.new("UICorner")
    fgsCorner.CornerRadius = UDim.new(0, 10)
    fgsCorner.Parent = FruitGridScroll

    local fgsStroke = Instance.new("UIStroke")
    fgsStroke.Color = Theme.Stroke
    fgsStroke.Thickness = 1
    fgsStroke.Parent = FruitGridScroll

    local fgsPadding = Instance.new("UIPadding")
    fgsPadding.PaddingLeft = UDim.new(0, 10)
    fgsPadding.PaddingRight = UDim.new(0, 10)
    fgsPadding.PaddingTop = UDim.new(0, 10)
    fgsPadding.PaddingBottom = UDim.new(0, 10)
    fgsPadding.Parent = FruitGridScroll

    local fgsGrid = Instance.new("UIGridLayout")
    fgsGrid.CellSize = IsMobile and UDim2.fromOffset(150, 52) or UDim2.fromOffset(216, 52)
    fgsGrid.CellPadding = UDim2.fromOffset(10, 10)
    fgsGrid.SortOrder = Enum.SortOrder.LayoutOrder
    fgsGrid.Parent = FruitGridScroll

    local PreviewFrame = Instance.new("Frame")
    PreviewFrame.BackgroundColor3 = Theme.Panel
    PreviewFrame.Position = UDim2.fromOffset(0, ControlsHeight + 12)
    PreviewFrame.Size = UDim2.new(1, 0, 1, -(ControlsHeight + 12))
    PreviewFrame.Visible = false
    PreviewFrame.Parent = page

    local pfCorner = Instance.new("UICorner")
    pfCorner.CornerRadius = UDim.new(0, 10)
    pfCorner.Parent = PreviewFrame

    local pfStroke = Instance.new("UIStroke")
    pfStroke.Color = Theme.Stroke
    pfStroke.Thickness = 1
    pfStroke.Parent = PreviewFrame

    local pfPadding = Instance.new("UIPadding")
    pfPadding.PaddingLeft = UDim.new(0, 16)
    pfPadding.PaddingRight = UDim.new(0, 16)
    pfPadding.PaddingTop = UDim.new(0, 16)
    pfPadding.Parent = PreviewFrame

    local PreviewText = Instance.new("TextLabel")
    PreviewText.BackgroundTransparency = 1
    PreviewText.Size = UDim2.new(1, 0, 0, 80)
    PreviewText.Font = FONT_REG
    PreviewText.TextSize = 15
    PreviewText.TextColor3 = Theme.SubText
    PreviewText.TextXAlignment = Enum.TextXAlignment.Left
    PreviewText.TextYAlignment = Enum.TextYAlignment.Top
    PreviewText.TextWrapped = true
    PreviewText.Text = "Enter a sheckles target above to preview which fruits would be picked."
    PreviewText.Parent = PreviewFrame

    local function updatePreview()
        local target = tonumber(ValueInput.Text) or 0
        if target <= 0 then
            PreviewText.Text = "Enter a sheckles target above to preview which fruits would be picked."
            return
        end
        local result = calculateFruit(target)
        PreviewText.Text = string.format(
            "%d fruit%s selected — %s / %s sheckles%s",
            result.Count, result.Count == 1 and "" or "s",
            formatNumber(result.TotalValue), formatNumber(target),
            result.ReachedTarget and "" or " (not enough in backpack)"
        )
    end

    ValueInput:GetPropertyChangedSignal("Text"):Connect(updatePreview)

    setFruitMode = function(isValueMode)
        ValueBlock.Visible = isValueMode
        AddBlock.Visible = isValueMode
        FruitGridLabel.Visible = not isValueMode
        FruitGridScroll.Visible = not isValueMode
        PreviewFrame.Visible = isValueMode
        if isValueMode then updatePreview() end
    end

    local function fruitAlreadyInBatch(id)
        for _, entry in ipairs(batch) do
            if entry.Category == "HarvestedFruits" and entry.ItemKey == id then
                return true
            end
        end
        return false
    end

    local function rebuildFruitGrid()
        for _, child in ipairs(FruitGridScroll:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        if #fruitOptions == 0 then
            local EmptyLbl = Instance.new("TextLabel")
            EmptyLbl.BackgroundTransparency = 1
            EmptyLbl.Size = UDim2.fromOffset(400, 24)
            EmptyLbl.Font = FONT_REG
            EmptyLbl.TextSize = 14
            EmptyLbl.TextColor3 = Theme.SubText
            EmptyLbl.TextXAlignment = Enum.TextXAlignment.Left
            EmptyLbl.Text = "No fruits in your backpack yet."
            EmptyLbl.LayoutOrder = 1
            EmptyLbl.Parent = FruitGridScroll
            return
        end

        for i, display in ipairs(fruitOptions) do
            local data = fruitCache[display]

            local Card = Instance.new("TextButton")
            Card.BackgroundColor3 = Theme.PanelAlt
            Card.AutoButtonColor = false
            Card.LayoutOrder = i
            Card.Text = ""
            Card.Parent = FruitGridScroll

            local cardCorner = Instance.new("UICorner")
            cardCorner.CornerRadius = UDim.new(0, 8)
            cardCorner.Parent = Card

            local cardPad = Instance.new("UIPadding")
            cardPad.PaddingLeft = UDim.new(0, 10)
            cardPad.PaddingRight = UDim.new(0, 10)
            cardPad.Parent = Card

            local NameLbl = Instance.new("TextLabel")
            NameLbl.BackgroundTransparency = 1
            NameLbl.Size = UDim2.new(1, -40, 1, 0)
            NameLbl.Font = FONT_SEMI
            NameLbl.TextSize = 14
            NameLbl.TextColor3 = Theme.Text
            NameLbl.TextXAlignment = Enum.TextXAlignment.Left
            NameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            NameLbl.Text = display
            NameLbl.Parent = Card

            local PlusLbl = Instance.new("TextLabel")
            PlusLbl.BackgroundTransparency = 1
            PlusLbl.Size = UDim2.fromOffset(30, Card.AbsoluteSize.Y)
            PlusLbl.AnchorPoint = Vector2.new(1, 0.5)
            PlusLbl.Position = UDim2.new(1, -10, 0.5, 0)
            PlusLbl.Font = FONT_BOLD
            PlusLbl.TextSize = 18
            PlusLbl.TextColor3 = Theme.Accent
            PlusLbl.Text = "+"
            PlusLbl.Parent = Card

            Card.MouseEnter:Connect(function()
                TweenService:Create(Card, TweenInfo.new(0.1), {BackgroundColor3 = Theme.Panel}):Play()
            end)
            Card.MouseLeave:Connect(function()
                TweenService:Create(Card, TweenInfo.new(0.1), {BackgroundColor3 = Theme.PanelAlt}):Play()
            end)

            Card.MouseButton1Click:Connect(function()
                if data and not fruitAlreadyInBatch(data.Id) then
                    table.insert(batch, {
                        Category = "HarvestedFruits",
                        ItemKey = data.Id,
                        Count = 1
                    })
                    updateCurrentMail()
                end
            end)
        end
    end

    refreshFruits = function()
        refreshFruitData()
        rebuildFruitGrid()
        if fruitMode == "Fruit Value" then
            updatePreview()
        end
    end

    rebuildFruitGrid()

    AddBtn.MouseButton1Click:Connect(function()
        local target = tonumber(ValueInput.Text) or 0
        if target <= 0 then return end

        local result = calculateFruit(target)
        for _, fruit in ipairs(result.Fruits) do
            if not fruitAlreadyInBatch(fruit.Id) then
                table.insert(batch, {
                    Category = "HarvestedFruits",
                    ItemKey = fruit.Id,
                    Count = 1
                })
            end
        end

        updateCurrentMail()
    end)
end

setActiveTab("Main")
