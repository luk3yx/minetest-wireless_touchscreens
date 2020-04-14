--
-- Minetest wireless touchscreens mod
--

wireless_touchscreens = {}
local storage = minetest.get_mod_storage()

-- Node protection checking, copied from scriptblocks.
if minetest.get_modpath('scriptblocks') then
    wireless_touchscreens.check_protection = scriptblocks.check_protection
else
    wireless_touchscreens.check_protection = function(pos, name)
        if type(name) ~= 'string' then
            name = name:get_player_name()
        end

        if minetest.is_protected(pos, name) and
          not minetest.check_player_privs(name, {protection_bypass=true}) then
            minetest.record_protection_violation(pos, name)
            return true
        end

        return false
    end
end

-- Allowed touchscreens
wireless_touchscreens.parents = {}
wireless_touchscreens.screens = {}

-- Override formspec updates
wireless_touchscreens.update_ts_formspec = digistuff.update_ts_formspec
digistuff.update_ts_formspec = function(pos, ...)
    wireless_touchscreens.update_ts_formspec(pos, ...)

    local spos = minetest.pos_to_string(pos)

    local nodes = storage:get_string(spos)
    if not nodes or #nodes < 5 then
        return
    end

    local save = false
    local any  = false

    nodes = minetest.deserialize(nodes)
    local formspec = minetest.get_meta(pos):get_string('formspec')

    -- Update the nodes
    for node, _ in pairs(nodes) do
        any = true
        local remote = minetest.string_to_pos(node)
        local name   = minetest.get_node(remote).name
        if _ and wireless_touchscreens.screens[name] then
            local meta = minetest.get_meta(remote)
            local owner, r = meta:get_string('owner'), meta:get_string('remote')
            if r ~= spos or
              wireless_touchscreens.check_protection(remote, owner) then
                wireless_touchscreens.on_construct(remote)
                nodes[node] = nil
                save = true
            else
                meta:set_string('formspec', formspec)
            end
        elseif name ~= 'ignore' then
            nodes[node] = nil
            save = true
        end
    end

    if not any then
        storage:set_string(spos, '')
    elseif save then
        storage:set_string(spos, minetest.serialize(nodes))
    end
end

-- Node handlers
wireless_touchscreens.on_construct = function(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string('formspec', 'field[remote;Remote touchscreen position;]')
    meta:set_string('owner', '')
    meta:set_string('remote', '')
end

wireless_touchscreens.on_receive_fields = function(pos,formname,fields,sender)
    local victim = sender:get_player_name()
    local meta   = minetest.get_meta(pos)
    local remote = meta:get_string('remote')
    local owner  = meta:get_string('owner')

    if remote then remote = minetest.string_to_pos(remote) end

    -- Forward fields onto digistuff if the touchscreen protection hasn't
    --    changed
    if remote and owner then
        local name = minetest.get_node(remote).name
        if minetest.is_protected(remote, owner) or not
                wireless_touchscreens.parents[name] then
            storage:set_string(minetest.pos_to_string(remote), '')
            -- TODO: Make this close_formspec more specific.
            minetest.close_formspec(victim, '')
            if name ~= 'ignore' then
                minetest.chat_send_player(victim,
                    'The remote touchscreen is no longer accessible!')
                wireless_touchscreens.on_construct(pos)
            else
                minetest.chat_send_player(victim,
                    'The remote touchscreen is not loaded!')
            end
        else
            digistuff.ts_on_receive_fields(remote, formname, fields, sender)
        end
        return
    elseif wireless_touchscreens.check_protection(pos, victim) or
      not fields.remote then
        return
    end

    remote = minetest.string_to_pos(fields.remote)

    if not remote then
        return minetest.chat_send_player(victim, 'Invalid position!')
    end

    local name = minetest.get_node(remote).name
    if wireless_touchscreens.check_protection(remote, victim) then
        return
    elseif not wireless_touchscreens.parents[name] then
        minetest.chat_send_player(victim, 'That block is not a touchscreen!')
        return
    end

    local sremote = minetest.pos_to_string(remote)
    meta:set_string('remote', sremote)
    meta:set_string('owner', victim)

    -- Add the touchscreen to the list to update
    local data = storage:get_string(sremote)
    if data and #data > 5 then
        data = minetest.deserialize(data)
    else
        data = {}
    end
    data[minetest.pos_to_string(pos)] = true
    storage:set_string(sremote, minetest.serialize(data))

    -- Make the remote touchscreen updated.
    meta:set_string('formspec',
        minetest.get_meta(remote):get_string('formspec'))

    minetest.chat_send_player(victim, 'Remote touchscreen set!')
end

-- Register a wireless node
wireless_touchscreens.register_node = function(name, parent, texture_overlay)
    local def2 = minetest.registered_nodes[parent]
    if not def2 then error('Node ' .. parent .. ' does not exist!') end
    local def = {}

    for key, value in pairs(def2) do
        def[key] = value
    end

    def.name              = nil
    def.digiline          = nil
    def.description       = 'Wireless ' .. def.description
    def.on_construct      = wireless_touchscreens.on_construct
    def.on_receive_fields = wireless_touchscreens.on_receive_fields
    texture_overlay       = texture_overlay or '^[colorize:#24f2'

    wireless_touchscreens.parents[parent] = true
    wireless_touchscreens.screens[name]   = true

    for n, tile in ipairs(def.tiles) do
        def.tiles[n] = tile .. texture_overlay
    end

    minetest.register_node(name, def)
end

-- Create the node
wireless_touchscreens.register_node('wireless_touchscreens:ts',
    'digistuff:touchscreen')

minetest.register_craft({
    output = 'wireless_touchscreens:ts',
    type   = 'shapeless',
    recipe = {
        'digistuff:touchscreen',
        minetest.get_modpath('pipeworks') and 'pipeworks:teleport_tube_1'
            or 'default:mese',
        'default:diamond'
    }
})
