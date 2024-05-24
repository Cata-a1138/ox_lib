---@class RadialItem
---@field icon string | {[1]: IconProp, [2]: string};
---@field label string
---@field menu? string
---@field onSelect? fun(currentMenu: string | nil, itemIndex: number) | string
---@field [string] any
---@field keepOpen? boolean
---@field iconWidth? number
---@field iconHeight? number

---@class RadialMenuItem: RadialItem
---@field id string

---@class RadialMenuProps
---@field id string
---@field items RadialItem[]
---@field [string] any

---@type table<string, RadialMenuProps>
local menus = {}

---@type RadialMenuItem[]
local menuItems = {}

---@type table<{id: string, option: string}>
local menuHistory = {}

---@type RadialMenuProps?
local currentRadial = nil

---Open a the global radial menu or a registered radial submenu with the given id.
---@param id string
---@param option number?
function lib.showRadial(id, option, sub)
    if not id then
        return error('Please provide id.')
    end

    local radial = menus[id]

    if not radial then
        return error('No radial menu with such id found.')
    end

    currentRadial = radial

    -- Hide current menu and allow for transition
    SendNUIMessage({
        action = 'openRadialMenu',
        data = false
    })

    Wait(100)

    -- If menu was closed during transition, don't open the submenu
    if not currentRadial then return end

    SendNUIMessage({
        action = 'openRadialMenu',
        data = {
            items = radial.items,
            sub = sub,
            option = option
        }
    })

    if not (sub or option) then
        lib.setNuiFocus(true)
        SetCursorLocation(0.5, 0.5)
    end

    CreateThread(function()
        while currentRadial do
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(2, 199, true)
            DisableControlAction(2, 200, true)
            Wait(0)
        end
    end)
end

---Refresh the current menu items or return from a submenu to its parent.
local function refreshRadial(menuId)
    if not currentRadial then return end

    if currentRadial and menuId then
        if menuId == currentRadial.id then
            return lib.showRadial(menuId)
        else
            for i = 1, #menuHistory do
                local subMenu = menuHistory[i]

                if subMenu.id == menuId then
                    local parent = menus[subMenu.id]

                    for j = 1, #parent.items do
                        -- If we still have a path to the current submenu, refresh instead of returning
                        if parent.items[j].menu == currentRadial.id then
                            return -- lib.showRadial(currentRadial.id)
                        end
                    end

                    currentRadial = parent

                    for j = #menuHistory, i, -1 do
                        menuHistory[j] = nil
                    end

                    return lib.showRadial(currentRadial.id)
                end
            end
        end

        return
    end

    table.wipe(menuHistory)
    lib.showRadial()
end

---Registers a radial sub menu with predefined options.
---@param radial RadialMenuProps
function lib.registerRadial(radial)
    menus[radial.id] = radial
    radial.resource = GetInvokingResource()

    if currentRadial then
        refreshRadial(radial.id)
    end
end

function lib.getCurrentRadialId()
    return currentRadial and currentRadial.id
end

function lib.hideRadial()
    if not currentRadial then return end

    SendNUIMessage({
        action = 'openRadialMenu',
        data = false
    })

    lib.resetNuiFocus()
    table.wipe(menuHistory)

    currentRadial = nil
end

---Registers an item or array of items in the global radial menu.
---@param id string
---@param items RadialMenuItem | RadialMenuItem[]
function lib.addRadialItem(id, items)
    if not id then
        return error('Please provide id.')
    end

    local radial = menus[id]?.items

    if not radial then
        return error('No radial menu with such id found.')
    end

    local menuSize = #radial
    local invokingResource = GetInvokingResource()

    items = table.type(items) == 'array' and items or { items }

    for i = 1, #items do
        local item = items[i]
        item.resource = invokingResource

        if menuSize == 0 then
            menuSize += 1
            radial[menuSize] = item
        else
            for j = 1, menuSize do
                if radial[j].id == item.id then
                    radial[j] = item
                    break
                end

                if j == menuSize then
                    menuSize += 1
                    radial[menuSize] = item
                end
            end
        end
    end

    if not currentRadial then
        refreshRadial()
    end
end

---Removes an item from the global radial menu with the given id.
---@param id string
---@param item string
function lib.removeRadialItem(id, item)
    if not id then
        return error('Please provide id.')
    end

    local radial = menus[id]?.items

    if not radial then
        return error('No radial menu with such id found.')
    end

    local menuItem

    for i = 1, #radial do
        menuItem = radial[i]

        if menuItem.id == item then
            table.remove(radial, i)
            break
        end
    end

    if not currentRadial then return end

    refreshRadial(id)
end

---Removes all items from the global radial menu.
---@param id string
function lib.clearRadialItems(id)
    if not id then
        return error('Please provide id.')
    end

    local radial = menus[id]?.items

    if not radial then
        return error('No radial menu with such id found.')
    end

    table.wipe(radial)

    if currentRadial then
        refreshRadial()
    end
end

RegisterNUICallback('radialClick', function(index, cb)
    cb(1)

    local itemIndex = index + 1
    local item, currentMenu

    if currentRadial then
        item = currentRadial.items[itemIndex]
        currentMenu = currentRadial.id
    else
        return error('No menu open.')
    end

    local menuResource = currentRadial and currentRadial.resource or item.resource

    if item.menu then
        menuHistory[#menuHistory + 1] = { id = currentRadial and currentRadial.id, option = item.menu }
        lib.showRadial(item.menu, nil, true)
    elseif not item.keepOpen then
        lib.hideRadial()
    end

    local onSelect = item.onSelect

    if onSelect then
        if type(onSelect) == 'string' then
            return exports[menuResource][onSelect](0, currentMenu, itemIndex)
        end

        onSelect(currentMenu, itemIndex)
    end
end)

RegisterNUICallback('radialBack', function(_, cb)
    cb(1)

    local numHistory = #menuHistory
    local lastMenu = numHistory > 0 and menuHistory[numHistory]

    if not lastMenu then return end

    menuHistory[numHistory] = nil

    if lastMenu.id then
        return lib.showRadial(lastMenu.id, lastMenu.option)
    end

    --[[ currentRadial = nil

    -- Hide current menu and allow for transition
    SendNUIMessage({
        action = 'openRadialMenu',
        data = false
    })

    Wait(100)

    -- If menu was closed during transition, don't open the submenu
    if not currentRadial then return end

    SendNUIMessage({
        action = 'openRadialMenu',
        data = {
            items = menuItems,
            option = lastMenu.option
        }
    }) ]]
end)

RegisterNUICallback('radialClose', function(_, cb)
    cb(1)

    if not currentRadial then return end

    lib.resetNuiFocus()

    currentRadial = nil
end)

RegisterNUICallback('radialTransition', function(_, cb)
    Wait(100)

    -- If menu was closed during transition, don't open the submenu
    if not currentRadial then return cb(false) end

    cb(true)
end)

local isDisabled = false

---Disallow players from opening the radial menu.
---@param state boolean
function lib.disableRadial(state)
    isDisabled = state

    if currentRadial and state then
        return lib.hideRadial()
    end
end

--[[ lib.addKeybind({
    name = 'ox_lib-radial',
    description = locale('open_radial_menu'),
    defaultKey = 'z',
    onPressed = function()
        if isDisabled then return end

        if isOpen then
            return lib.hideRadial()
        end

        if #menuItems == 0 or IsNuiFocused() or IsPauseMenuActive() then return end


    end,
    -- onReleased = lib.hideRadial,
}) ]]

--[[ AddEventHandler('onClientResourceStop', function(resource)
    for i = #menuItems, 1, -1 do
        local item = menuItems[i]

        if item.resource == resource then
            table.remove(menuItems, i)
        end
    end
end)
 ]]
