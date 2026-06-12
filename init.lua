-- ve_radio: A Minetest mod that adds a radio block which plays random music.

ve_radio = {}
ve_radio.playing_sounds = {}

-- 1. Dynamic Track Loading
-- Scan the mod's sounds directory for .ogg files.
local tracks = {}
local modpath = minetest.get_modpath("ve_radio")
local sounds_dir = modpath .. "/sounds"

local files = minetest.get_dir_list(sounds_dir, false)
if files then
    for _, filename in ipairs(files) do
        if filename:sub(-4):lower() == ".ogg" then
            local sound_name = filename:sub(1, -5)
            -- Map known track durations. Fallback to 180s for user-added files.
            local duration = 180
            if sound_name == "ve_radio_coastline" then
                duration = 155
            elseif sound_name == "ve_radio_party" then
                duration = 151
            end
            table.insert(tracks, { name = sound_name, duration = duration })
        end
    end
end

-- Fallback default tracks if directory scan fails or is empty
if #tracks == 0 then
    tracks = {
        { name = "ve_radio_coastline", duration = 155 },
        { name = "ve_radio_party",     duration = 151 },
    }
end

-- 2. Helper Functions for Radio Playback
function ve_radio.start(pos)
    local pos_hash = minetest.hash_node_position(pos)
    
    -- Ensure any existing playback at this position is fully stopped
    ve_radio.stop(pos)
    
    if #tracks == 0 then
        minetest.log("warning", "[ve_radio] No tracks available to play!")
        return
    end
    
    -- Pick a random track
    local idx = math.random(1, #tracks)
    local track = tracks[idx]
    
    -- Play the sound positionally (audible to nearby players up to 25 nodes away)
    local sound_handle = minetest.sound_play(track.name, {
        pos = pos,
        gain = 0.8,
        max_hear_distance = 25,
        loop = false,
    })
    
    -- Spawn floating music note particles while the radio is playing
    local spawner_id = minetest.add_particlespawner({
        amount = 1, -- Spawn 1 particle per second
        time = 0,   -- Infinite spawner (runs until deleted)
        minpos = {x = pos.x - 0.2, y = pos.y + 0.5, z = pos.z - 0.2},
        maxpos = {x = pos.x + 0.2, y = pos.y + 0.7, z = pos.z + 0.2},
        minvel = {x = -0.1, y = 0.1, z = -0.1},
        maxvel = {x = 0.1, y = 0.3, z = 0.1},
        minacc = {x = -0.05, y = 0.05, z = -0.05},
        maxacc = {x = 0.05, y = 0.1, z = 0.05},
        minexptime = 2.0,
        maxexptime = 3.5,
        minsize = 1,
        maxsize = 2,
        texture = "ve_radio_note.png",
    })
    
    -- Save the playing state details
    ve_radio.playing_sounds[pos_hash] = {
        handle = sound_handle,
        spawner_id = spawner_id,
        track_name = track.name,
    }
    
    -- Update node metadata
    local meta = minetest.get_meta(pos)
    meta:set_string("state", "playing")
    
    -- Format sound name for a clean display (e.g. "ve_radio_coastline" -> "COASTLINE")
    local display_name = track.name:gsub("^ve_radio_", ""):gsub("_", " "):upper()
    meta:set_string("infotext", "Radio: playing '" .. display_name .. "'")
    
    -- Start node timer to play the next random track when the current track finishes
    local timer = minetest.get_node_timer(pos)
    timer:start(track.duration)
end

function ve_radio.stop(pos)
    local pos_hash = minetest.hash_node_position(pos)
    local active = ve_radio.playing_sounds[pos_hash]
    
    if active then
        -- Stop the audio playback
        if active.handle then
            minetest.sound_stop(active.handle)
        end
        -- Remove the particle spawner
        if active.spawner_id then
            minetest.delete_particlespawner(active.spawner_id)
        end
        -- Remove from registry
        ve_radio.playing_sounds[pos_hash] = nil
    end
    
    -- Update node metadata
    local meta = minetest.get_meta(pos)
    meta:set_string("state", "stopped")
    meta:set_string("infotext", "Radio (Stopped)")
    
    -- Stop the node timer
    local timer = minetest.get_node_timer(pos)
    timer:stop()
end

-- 3. Node Registration
minetest.register_node("ve_radio:radio", {
    description = "VE Radio",
    tiles = {
        "ve_radio_top.png",
        "ve_radio_bottom.png",
        "ve_radio_side.png",
        "ve_radio_side.png",
        "ve_radio_side.png",
        "ve_radio_side.png"
    },
    groups = {snappy = 2, choppy = 2, oddly_breakable_by_hand = 2},
    sounds = (minetest.node_sound_wood_defaults and minetest.node_sound_wood_defaults()),
    
    on_construct = function(pos)
        local meta = minetest.get_meta(pos)
        meta:set_string("state", "stopped")
        meta:set_string("infotext", "Radio (Stopped)")
    end,
    
    after_place_node = function(pos, placer, itemstack, pointed_thing)
        -- Auto-play on block placement
        ve_radio.start(pos)
    end,
    
    on_destruct = function(pos)
        -- Terminate sounds and particles when node is destroyed
        ve_radio.stop(pos)
    end,
    
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local meta = minetest.get_meta(pos)
        local state = meta:get_string("state")
        local player_name = clicker:get_player_name()
        
        if state == "playing" then
            ve_radio.stop(pos)
            if player_name then
                minetest.chat_send_player(player_name, "Radio turned OFF")
            end
        else
            ve_radio.start(pos)
            if player_name then
                minetest.chat_send_player(player_name, "Radio turned ON")
            end
        end
    end,
    
    on_timer = function(pos, elapsed)
        local meta = minetest.get_meta(pos)
        if meta:get_string("state") == "playing" then
            -- Play another random track when the current one ends
            ve_radio.start(pos)
        end
        return false -- Stop current timer; start() will schedule the next one
    end,
})

-- 4. Crafting Recipe (using default mod items if available)
if minetest.get_modpath("default") then
    minetest.register_craft({
        output = "ve_radio:radio",
        recipe = {
            {"default:steel_ingot", "default:copper_ingot", "default:steel_ingot"},
            {"group:wood",          "group:wood",          "group:wood"},
            {"group:wood",          "group:wood",          "group:wood"},
        }
    })
end
