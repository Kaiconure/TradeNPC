require('pack')
bit = require('bit')
res_items = require('resources').items
packets = require('packets')

_addon.name = 'TradeNPC'
_addon.author = 'Ivaar,Kaiconure'
_addon.version = '1.2025.1212'
_addon.command = 'tradenpc'

function write_message(format, ...)
    print(string.format(format, ...))
end

-- Waits for the player to be idle (status 0)
function wait_for_idle(min_duration, max_duration)
    min_duration = math.max(tonumber(min_duration) or 1, 1)
    max_duration = math.max(tonumber(max_duration) or 30, 5)
    local sleep_start = os.clock()
    coroutine.sleep(min_duration)
    while 
        windower.ffxi.get_mob_by_target('me').status ~= 0 
    do
        if ((os.clock() - sleep_start) > max_duration) then
            return false
        end
        coroutine.sleep(1)
    end

    return true
end

-- Waits for the player to be in event status (status 4)
function wait_for_event(max_duration)
    min_duration = 1
    max_duration = math.max(tonumber(max_duration) or 5, 5)
    local sleep_start = os.clock()
    coroutine.sleep(min_duration)
    while 
        windower.ffxi.get_mob_by_target('me').status ~= 4 
    do
        if ((os.clock() - sleep_start) > max_duration) then
            return false
        end
        coroutine.sleep(1)
    end

    return true
end

function get_item_res(item)
    for k,v in pairs(res_items) do
        if v.en:lower() == item or v.enl:lower() == item then
            return v
        end
    end
    return nil
end

function count_item(inventory, item_id)
    local count = 0
    for k, v in ipairs(inventory) do
        if v.id == item_id and v.count >= 0 and v.status == 0 then
            count = count + v.count
        end
    end

    return count
end

function find_item(inventory, item_id, count, exclude)
    for k, v in ipairs(inventory) do
        if v.id == item_id and v.count >= count and v.status == 0 and not exclude[k] then
            return k
        end
    end
    return nil
end

function format_price(price)
    price = not string.match(price,'%a') and price:gsub('%p', '')
    price = price and tonumber(price)
    if price and price > 0 then
        return price
    end
    return nil
end

function valid_target(npc)
    if npc.distance < (6*6) and npc.valid_target and npc.is_npc and bit.band(npc.spawn_type, 0xDF) == 2 then
        return true
    end
    return false
end

function find_npc(name, mobs)
    mobs = mobs or windower.ffxi.get_mob_array()
    for index, npc in pairs(mobs) do
        if npc and npc.name:ieq(name) and valid_target(npc) then
            return npc
        end
    end
end

function find_valid_npc(name, mobs)
    mobs = mobs or windower.ffxi.get_mob_array()
    local target = find_npc(name, mobs)
    if target and valid_target(target) then
        return target
    end
end

function get_target()
    local npc = windower.ffxi.get_mob_by_target('t')
    if npc and valid_target(npc) then
        return npc
    end
end

function poke_npc(npc)
    if npc and npc.id and npc.index then
        local packet = packets.new('outgoing', 0x01A, {
            ["Target"] = npc.id,
            ["Target Index"] = npc.index,
            ["Category"] = 0,
            ["Param"] = 0,
            ["_unknown1"] = 0
        })
        packets.inject(packet)
    end
end

function tap_key(key)
    windower.send_command('setkey %s down; wait 0.25; setkey %s up;':format(key, key))
end


function doTrades(...)
	local args = {...}
    if #args < 2 then
        write_message('tradenpc <quantity> <item name>\ne.g. //tradenpc 100 "1 byne bill"')
        return
    end

    if windower.ffxi.get_mob_by_target('me').status ~= 0 then return end

    local target

    if #args%2 == 1 then
        target = find_npc(args[#args])
        args[#args] = nil
    else
        target = get_target()
    end

    local commands = {}

    local quantity_marker
    if string.lower(args[1]) == 'all' or args[1] == '*' then
        quantity_marker = 'All'
    else
        quantity_marker = (tonumber(args[1]) or 1) .. 'x'
    end

    if target then
        write_message('TradeNPC: Target is [%s] (%d / %03X)',
            target.name,
            target.id,
            target.index,
            quantity_marker,    -- Ignored
            args[2])            -- Ignored

        local ind = {}
        local qty = {}
        local start = 1
        if args[2]:lower() == 'gil' then
            local units = format_price(args[1])
            if not units or units > windower.ffxi.get_items('gil') then
                write_message('Invalid gil amount')
                return
            end
            ind[1] = 0
            qty[1] = units
            start = 2

            write_message('Adding %d gil to the trade!':format(units))
        end
        local inventory = windower.ffxi.get_items(0)
        if not inventory then return end
        local exclude = {}

        -- Note: The number of actual items added to the trade is calculated as:
        --
        --  num_items = #ind - start
        --
        -- That is, it's the number of things we have in our array minus the index
        -- at which we started adding items. This is to account for gil being added
        -- in the first slot.
        --
        -- The end result is that we will continue allowing items to be added until
        -- we've filled in all 8 slots -OR- we run out of items to examine.
        -- 
        local x = start
        while #ind - start < 8 do
            if not args[x*2] then
                break
            end

            local name = windower.convert_auto_trans(args[x*2]):lower()
            local item = get_item_res(name)

            local units = string.lower(args[x*2-1] or '')
            if item and units == 'all' or units == '*' then
                units = count_item(inventory, item.id)                
            else
                units = tonumber(units)
            end

            if not item or item.flags['Linkshell'] == true then
                write_message('[%s] not a valid item name: arg %d', name, x*2)
                return
            end

            -- We will not validate the actual number of units here. The original implementation would bail here
            -- if no items were found, but the "all" option would often lead to zero items if the player had none 
            -- a partcular item. By allowing zero through, we will skip adding that item to the trade and will
            -- move on. The check added below the for loop will catch the case where nothing is added at all.
            if not units then
                write_message('Invalid quantity: arg %d', x*2-1)
                return
            end

            if units > 0 then
                write_message('Adding [%s] x%d to the trade!':format(item.name, units))
                
                while units > 0 do
                    local count = units > item.stack and item.stack or units
                    local index = find_item(inventory, item.id, count, exclude)
                    if not index then
                        write_message('Could not find [%s] x%d in your inventory.', item.name, units)
                        return
                    end
                    exclude[index] = true
                    ind[#ind+1] = index
                    qty[#qty+1] = count
                    units = units - count
                end
            else
                write_message('Skipping [%s] as quantity is zero.', item.name)
            end

            x = x + 1
        end

        if #ind == 0 then
            write_message('No items or gil were added to the trade.')
            return
        end

        local num = #ind

        -- Limit to first 8 items (plus gil). This would previously result in an error, but now the trade will
        -- proceed with the first 8 items and a message will be displayed. This will allow the user to just
        -- attempt the trade again as inventory numbers decrease.
        if num >= start + 8 then
            ind = {unpack(ind, 1, start + 7)}
            qty = {unpack(qty, 1, start + 7)}

            write_message('Too many items were added to the trade, only the first %d will be traded.':format(start + 7))

            num = #ind
        end

        if num > 0 and num < start+8 then
            for x = num, 8 do
                ind[x+1] = 0
                qty[x+1] = 0
            end

            local packet = packets.new('outgoing', 0x036, {
                ["Target"] = target.id,
                ["Target Index"] = target.index,
                ["Number of Items"] = num,
                ["_unknown1"] = 0,
                ["_unknown2"] = 0
            })

            for i = 1, 9 do
                packet['Item Index %d':format(i)] = ind[i] or 0
                packet['Item Count %d':format(i)] = qty[i] or 0
            end

            if
                target.name == 'Saldinor' or
                target.name == 'Felmsy' or
                target.name == 'Pudith'
            then
                -- These Adoulin Fame NPCs require special handling before they accept trades
                poke_npc(target)
                coroutine.sleep(3)
                tap_key('enter')
                coroutine.sleep(1)
            end

            packets.inject(packet)

            if
                target.name == 'Rolandienne' or
                target.name == 'Isakoth' or
                target.name == 'Fhelm Jobeizat' or
                target.name == 'Eternal Flame'
            then
                -- Sparks NPCs require one further interaction after the trade packet is sent
                coroutine.sleep(3)
                tap_key('enter')
            end

            if
                target.name == 'Shami' or
                target.name == 'Monisette'
            then
                -- For certain NPC's, we need to confirm the trade by pressing enter repeatedly
                -- until we exit the event state.
                while wait_for_event(1, 3) do
                    tap_key('enter')
                end
            end

			return true
        end
    else
        write_message('No target or too far away.')
    end
end

windower.register_event('addon command', function(...)
	local args = {...}
	
    local multitrade = false
    local ciphers = false
    local numTrades = 0

    if args[1] == 'multitrade' or args[1] == 'multi' then
        multitrade = true
        table.remove(args, 1)
    elseif args[1] == 'ciphers' or args[1] == 'cipher' then
        ciphers = true
        table.remove(args, 1)
    end

    if ciphers then
        local mobs = windower.ffxi.get_mob_array()
        local target = find_valid_npc('Gondebaud', mobs) or find_valid_npc('Clarion Star', mobs) or find_valid_npc('Wetata', mobs)

        if target then
            local inventory = windower.ffxi.get_items(0)
            for i, iitem in ipairs(inventory) do
                local item = res_items[iitem.id]
                if item and string.sub(item.en, 1, 8) == 'Cipher: ' then
                    write_message('Trading cipher [%s]...':format(item.en))
                    if doTrades(1, item.en, target.name) then
                        numTrades = numTrades + 1
                    else
                        break
                    end

                    coroutine.sleep(3)
                    tap_key('enter')
                    wait_for_idle()
                end
            end
        end
    elseif multitrade then
        while doTrades(table.unpack(args)) do
            numTrades = numTrades + 1
            write_message('TradeNPC: Trade %d completed, continuing shortly...':format(numTrades))
            wait_for_idle()
        end
    else
        if doTrades(table.unpack(args)) then
            numTrades = 1
            coroutine.sleep(1)
        end
    end

    if numTrades > 0 then
        write_message('TradeNPC: Trading complete!')
    else
        write_message('TradeNPC: Trade failed!')
    end
end)
--[[
Copyright © 2025, Kaiconure [Ammended]
Copyright © 2018, Ivaar
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of TradeNPC nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL IVAAR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]