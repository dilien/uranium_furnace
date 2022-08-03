print("This file will be run at load time!")
minetest.chat_send_all("This is a chat message to all players")
local S = default.get_translator

local function can_dig(pos, player)
	local meta = minetest.get_meta(pos);
	local inv = meta:get_inventory()
	return inv:is_empty("dst") and inv:is_empty("src") and inv:is_empty("fuel")
end

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	if listname == "fuel" then
		if stack:get_name() == "uraniumfurnace:uranium_gem" then
			return stack:get_count()
		else
			return 0
		end
	elseif listname == "src" then
		return stack:get_count()
	elseif listname == "dst" then
		return 0
	end
end

local function allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	return allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	return stack:get_count()
end

local function swap_node(pos, name)
	local node = minetest.get_node(pos)
	if node.name == name then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
end
local function get_electric_furnace_inactive_formspec()
	return 		"size[8,8.25]"..
		"list[context;src;1,1;2,2;]"..
		"image[3.5,1;1,1;gui_furnace_arrow_bg.png^[transformR270]"..
		"list[context;dst;5,1;2,2;]"..
		"list[context;fuel;3.5,2;1,1;]"..
		"list[current_player;main;0,4;8,1;]"..
		"list[current_player;main;0,5.25;8,3;8]"..
		"listring[context;dst]"..
		"listring[current_player;main]"..
		"listring[context;src]"..
		"listring[current_player;main]"..
		"listring[current_player;main]"..
		default.get_hotbar_bg(0, 4.25)
end

local function get_electric_furnace_active_formspec(item_percent)
	return "size[8,8.25]"..
		"list[context;src;1,1;2,2;]"..
		"image[3.5,1;1,1;gui_furnace_arrow_bg.png^[lowpart:"..
		(item_percent)..":gui_furnace_arrow_fg.png^[transformR270]"..
		"list[context;dst;5,1;2,2;]"..
		"list[context;fuel;3.5,2;1,1;]"..
		"list[current_player;main;0,4;8,1;]"..
		"list[current_player;main;0,5.25;8,3;8]"..
		"listring[context;dst]"..
		"listring[current_player;main]"..
		"listring[context;src]"..
		"listring[current_player;main]"..
		"listring[current_player;main]"..
		default.get_hotbar_bg(0, 4.25)
end
local function furnace_node_timer(pos, elapsed)
	--
	-- Initialize metadata
	--
	local meta = minetest.get_meta(pos)
	local src_time = meta:get_float("src_time") or 0

	local inv = meta:get_inventory()
	local srclist, fuellist
	local dst_full = false

	local timer_elapsed = meta:get_int("timer_elapsed") or 0
	meta:set_int("timer_elapsed", timer_elapsed + 1)

	local cookable, cooked
	local active = false
	local speed = inv:get_list("fuel")[1]:get_count()
	local update = inv:contains_item("fuel", ItemStack("uraniumfurnace:uranium_gem 1"))
	while elapsed > 0 and update do
		update = false

		srclist = inv:get_list("src")
		local index = -1
		for i = 1, 4 do
			if srclist[i]:get_count() ~= 0 then
				index = i
				srclist = {srclist[i]}
				break
			end
		end
		if index == -1 then
			index = 1
			srclist = {srclist[1]}
		end
		--
		-- Cooking
		--

		-- Check if we have cookable content
		local aftercooked
		cooked, aftercooked = minetest.get_craft_result({method = "cooking", width = 1, items = srclist})
		cookable = cooked.time ~= 0
		if cookable then
			el = math.min(elapsed * speed, cooked.time - src_time)
			active = true
			src_time = src_time + el
			if src_time >= cooked.time then
				-- Place result in dst list if possible
				if inv:room_for_item("dst", cooked.item) then
					inv:add_item("dst", cooked.item)
					inv:set_stack("src", index, aftercooked.items[1])
					src_time = src_time - cooked.time
					update = true
				else
					dst_full = true
				end
				-- Play cooling sound
				--minetest.sound_play("default_cool_lava",
				--	{pos = pos, max_hear_distance = 16, gain = 0.07}, true)
			else
				-- Item could not be cooked: probably missing fuel
				update = true
			end
			elapsed = elapsed - (el / speed)
		end
	end

	if srclist and srclist[1]:is_empty() then
		src_time = 0
	end

	--
	-- Update formspec, infotext and node
	--
	local formspec
	local item_state
	local item_percent = 0
	if cookable then
		item_percent = math.floor(src_time / cooked.time * 100)
		if dst_full then
			item_state = S("100% (output full)")
		else
			item_state = S("@1%", item_percent)
		end
	else
		if srclist and not srclist[1]:is_empty() then
			item_state = S("Not cookable")
		else
			item_state = S("Empty")
		end
	end

	local fuel_state = S("Empty")
	local result = false

	if active then
		infotext = S("Furnace active")
		formspec = get_electric_furnace_active_formspec(item_percent)
		swap_node(pos, "uraniumfurnace:uranium_furnace_active")
		-- make sure timer restarts automatically
		result = true

		-- Play sound every 5 seconds while the furnace is active
		if timer_elapsed == 0 or (timer_elapsed + 1) % 5 == 0 then
			--minetest.sound_play("default_furnace_active",
			--	{pos = pos, max_hear_distance = 16, gain = 0.25}, true)
		end
	else
		infotext = S("Furnace inactive")
		formspec = get_electric_furnace_inactive_formspec()
		swap_node(pos, "uraniumfurnace:uranium_furnace")
		-- stop timer on the inactive furnace
		minetest.get_node_timer(pos):stop()
		meta:set_int("timer_elapsed", 0)
	end
	infotext = infotext .. "\n" .. S("(Item: @1)", item_state)
	--
	-- Set meta values
	--
	meta:set_float("src_time", src_time)
	meta:set_string("formspec", formspec)
	meta:set_string("infotext", infotext)

	return result
end
minetest.register_craft({
    type = "shapeless",
    output = "uraniumfurnace:uranium_furnace 3",
    recipe = { "default:dirt", "default:stone" },
})
minetest.register_craftitem("uraniumfurnace:uranium_gem", {
	description = S("uranium gem"),
	inventory_image = "uraniumfurnace_uranium_gem.png"
})
minetest.register_craft({
    output = "uraniumfurnace:uranium_gem",
    recipe =  {{"", "dye:dark_green",""},
	           {"dye:dark_green", "default:diamond","dye:dark_green"},
			   {"", "dye:dark_green",""}}
})
minetest.register_craft({
	output = "uraniumfurnace:uranium_furnace",
	recipe = {
		{"group:stone", "group:stone", "group:stone"},
		{"group:stone", "uraniumfurnace:uranium_gem", "group:stone"},
		{"group:stone", "group:stone", "group:stone"},
	}
})
minetest.register_craft({
	type = "cooking",
    output = "minecraft:diamond",
    recipe = "uraniumfurnace:uranium_gem"
})
minetest.register_node("uraniumfurnace:uranium_furnace", {
	description = "uranium furnace",
	tiles = {
		"uraniumfurnace_furnace_top.png", "uraniumfurnace_furnace_bottom.png",
		"uraniumfurnace_furnace_side.png", "uraniumfurnace_furnace_side.png",
		"uraniumfurnace_furnace_side.png", "uraniumfurnace_furnace_front.png"
	},
	groups = {cracky = 2},
	sounds = default.node_sound_stone_defaults(),
	after_place_node = function(pos, placer)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size('src', 4)
		inv:set_size('dst', 4)
		inv:set_size('fuel', 1)
		furnace_node_timer(pos, 0)
	end,
	on_metadata_inventory_move = function(pos)
		minetest.get_node_timer(pos):start(.1)
	end,
	on_metadata_inventory_put = function(pos)
		-- start timer function, it will sort out whether furnace can burn or not.
		minetest.get_node_timer(pos):start(.1)
	end,
	on_metadata_inventory_take = function(pos)
		-- check whether the furnace is empty or not.
		minetest.get_node_timer(pos):start(.1)
	end,
	on_timer = furnace_node_timer,
	can_dig = can_dig,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_take = allow_metadata_inventory_take
})
minetest.register_node("uraniumfurnace:uranium_furnace_active", {
	description = S("Furnace"),
	tiles = {
		"uraniumfurnace_furnace_top.png", "uraniumfurnace_furnace_bottom.png",
		"uraniumfurnace_furnace_side.png", "uraniumfurnace_furnace_side.png",
		"uraniumfurnace_furnace_side.png",
		{
			image = "uraniumfurnace_furnace_front_active.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 1.5
			},
		}
	},
	paramtype2 = "facedir",
	light_source = 8,
	drop = "uraniumfurnace:uranium_furnace",
	groups = {cracky=2, not_in_creative_inventory=1},
	legacy_facedir_simple = true,
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	on_timer = furnace_node_timer,

	can_dig = can_dig,

	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
})