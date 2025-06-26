require('pack')
bit = require('bit')
res_items = require('resources').items
packets = require('packets')

_addon.name = 'TradeNPC'
_addon.author = 'Ivaar'
_addon.version = '1.2025.0623'
_addon.command = 'tradenpc'

function write_message(format, ...)
    print(string.format(format, ...))
end

function wait_for_idle(min_duration, max_duration)
    min_duration = math.max(tonumber(min_duration) or 5, 5)
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

function get_item_res(item)
    for k,v in pairs(res_items) do
        if v.en:lower() == item or v.enl:lower() == item then
            return v
        end
    end
    return nil
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

    if target then
        write_message('TradeNPC: Target is [%s] (%d / %03X) (%dx [%s])', target.name, target.id, target.index, tonumber(args[1]) or 1, args[2])
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
        end
        local inventory = windower.ffxi.get_items(0)
        if not inventory then return end
        local exclude = {}
        for x = start, 9 do
            if not args[x*2] then
                break
            end
            local units = tonumber(args[x*2-1])
            local name = windower.convert_auto_trans(args[x*2]):lower()
            local item = get_item_res(name)
            if not item or item.flags['Linkshell'] == true then
                write_message('"%s" not a valid item name: arg %d', name, x*2)
                return
            end
            if not units or units < 1 then
                write_message('Invalid quantity: arg %d', x*2-1)
                return
            end
            
            while units > 0 do
                local count = units > item.stack and item.stack or units
                local index = find_item(inventory, item.id, count, exclude)
                if not index then
                    write_message('%s x%s not found in inventory.', item.name, args[x*2-1])
                    return
                end
                exclude[index] = true
                ind[#ind+1] = index
                qty[#qty+1] = count
                units = units - count
            end
        end
        local num = #ind
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
                poke_npc(target)
                coroutine.sleep(3)
                tap_key('enter')
                coroutine.sleep(1)
            end

            packets.inject(packet)

			return true
        else
            write_message('Too many items')
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