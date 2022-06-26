local M = {}
local api = vim.api

local win = nil
local buf = nil
local ns = api.nvim_create_namespace("color-picker-popup")

local function rgbToHex(r, g, b) --{{{
	return string.format("#%02x%02x%02x", r, g, b)
end --}}}

local function round(num, numDecimalPlaces) --{{{
	return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end --}}}

local function HSLtoRGB(h, s, l) --{{{
	h = h / 360
	s = s / 100
	l = l / 100

	if s == 0 then
		return l, l, l
	end
	local function to(p, q, t)
		if t < 0 then
			t = t + 1
		end
		if t > 1 then
			t = t - 1
		end
		if t < 0.16667 then
			return p + (q - p) * 6 * t
		end
		if t < 0.5 then
			return q
		end
		if t < 0.66667 then
			return p + (q - p) * (0.66667 - t) * 6
		end
		return p
	end
	local q = l < 0.5 and l * (1 + s) or l + s - l * s
	local p = 2 * l - q
	return { round(to(p, q, h + 0.33334) * 255), round(to(p, q, h) * 255), round(to(p, q, h - 0.33334) * 255) }
end --}}}

local function RGBToHSL(r, g, b) --{{{
	-- Make r, g, and b fractions of 1
	r = r / 255
	g = g / 255
	b = b / 255

	local max = math.max(r, g, b)
	local min = math.min(r, g, b)

	local h = (max + min) / 2
	local s = (max + min) / 2
	local l = (max + min) / 2

	if max == min then -- acromatic
		h = 0
		s = 0
	else
		local d = max - min

		if l > 0.5 then
			s = d / (2 - max - min)
		else
			s = d / (max + min)
		end

		local x = nil
		if max == r then
			if g < b then
				x = 6
			else
				x = 0
			end
			h = (g - b) / d + x
		elseif max == g then
			h = (b - r) / d + 2
		elseif max == b then
			h = (r - g) / d + 4
		end

		h = round(h / 6 * 360)
	end

	return "hsl(" .. h .. "," .. round(s * 100, 1) .. "%," .. round(l * 100, 1) .. "%)"
end --}}}

vim.cmd(":highlight ColorPickerOutput guifg=#c3ccdc")

local output_type = "rgb"
local color_mode = "rgb"

local color_mode_extmarks = {}
local color_value_extmarks = {}
local color_values = { 0, 0, 0 }
local boxes_extmarks = {}
local output_extmark = {}

local function create_empty_lines() ---create empty lines in the popup so we can set extmarks{{{
	api.nvim_buf_set_lines(buf, 0, -1, false, {
		"",
		"",
		"",
		"",
	})
end --}}}

local function ext(row, col, text, hl_group, virt_text_pos) ---shortcut to create extmarks{{{
	return api.nvim_buf_set_extmark(buf, ns, row, col, {
		virt_text = { { text, hl_group or "Normal" } },
		virt_text_pos = virt_text_pos or "eol",
	})
end --}}}

local function setup_virt_text() ---create initial virtual text{{{
	-- first column
	local rgb = { "R", "G", "B" }

	for i, value in ipairs(rgb) do
		color_mode_extmarks[i] = ext(i - 1, 0, value, nil, "overlay")
	end

	-- third column
	local boxes_text = { "", "", "" }
	for i, value in ipairs(boxes_text) do
		boxes_extmarks[i] = ext(i - 1, 0, value, nil, "right_align")
	end

	-- second column
	local color_values_text = { "   0", "   0", "   0" }

	for i, value in ipairs(color_values_text) do
		color_value_extmarks[i] = ext(i - 1, 0, value)
	end

	--- last row
	output_extmark = ext(3, 0, "rgb(0,0,0)", nil, "right_align")
end --}}}

local function delete_ext(id) -- shortcut for delete extmarks given an id{{{
	api.nvim_buf_del_extmark(buf, ns, id)
end

local function string_fix_right(str, width)
	if type(str) == "number" then
		str = tostring(str)
	end

	local number_of_spaces = width - #str

	return string.rep(" ", number_of_spaces) .. str
end --}}}

local function update_boxes(line) --{{{
	delete_ext(boxes_extmarks[line])

	local floor = math.floor(color_values[line] / 25.5)
	local arithmetic = color_values[line] / 25.5 - floor

	local box_string = ""

	if arithmetic ~= 0 then
		box_string = ""
	end

	for i = 1, floor, 1 do
		box_string = "ﱢ" .. box_string
	end

	for i = 2, 10 - floor do
		box_string = box_string .. " "
	end

	boxes_extmarks[line] = ext(line - 1, 0, box_string, nil, "right_align")
end --}}}

local function get_fg_color() --{{{
	local fg_color = "white"
	if (color_values[1] + color_values[2] + color_values[3]) > 300 then
		fg_color = "black"
	end

	return fg_color
end --}}}

local function update_output() --{{{
	delete_ext(output_extmark)

	local arg1 = tostring(color_values[1])
	local arg2 = tostring(color_values[2])
	local arg3 = tostring(color_values[3])

	local output = ""
	if output_type == "rgb" then
		output = "rgb(" .. arg1 .. "," .. arg2 .. "," .. arg3 .. ")"
	elseif output_type == "hex" then
		output = rgbToHex(arg1, arg2, arg3)
	end

	local fg_color = get_fg_color()

	vim.cmd(":highlight ColorPickerOutput guifg=" .. fg_color .. " guibg=" .. rgbToHex(arg1, arg2, arg3))
	output_extmark = ext(3, 0, output, "ColorPickerOutput", "right_align")
end --}}}

local function change_output_type() --{{{
	if output_type == "rgb" then
		output_type = "hex"
	elseif output_type == "hex" then
		output_type = "rgb"
	end
	update_output()
end --}}}

local function decrease_color_value(increment) --{{{
	local curline = api.nvim_win_get_cursor(0)[1]
	local colorValue = color_values[curline]

	increment = increment or 1

	if colorValue - increment >= 0 then
		delete_ext(color_value_extmarks[curline])

		local new_value = colorValue - increment
		color_value_extmarks[curline] = ext(curline - 1, 0, string_fix_right(new_value, 4))
		color_values[curline] = new_value

		update_boxes(curline)
		update_output()
	end
end --}}}

local function increase_color_value(increment) --{{{
	local curline = api.nvim_win_get_cursor(0)[1]
	local colorValue = color_values[curline]

	increment = increment or 1

	if colorValue + increment <= 255 then
		delete_ext(color_value_extmarks[curline])

		local new_value = colorValue + increment
		color_value_extmarks[curline] = ext(curline - 1, 0, string_fix_right(new_value, 4))
		color_values[curline] = new_value

		update_boxes(curline)
		update_output()
	end
end --}}}

local function change_color_mode()
	if color_mode == "rgb" then
		-- color_mode = "hsl"

		local hsl = { "H", "S", "L" }

		for i, value in ipairs(hsl) do
			delete_ext(color_mode_extmarks[i])
			color_mode_extmarks[i] = ext(i - 1, 0, value, nil, "overlay")
		end

		P(RGBToHSL(color_values[1], color_values[2], color_values[3]))

		--> update the structure of the extmarks
	end
end

local function set_mappings() ---set default mappings for popup window{{{
	local mappings = {
		["q"] = ":q<cr>",
		["<Esc>"] = ":q<cr>",
		["h"] = function()
			decrease_color_value(5)
		end,
		["l"] = function()
			increase_color_value(5)
		end,
		["o"] = function()
			change_output_type()
		end,
		["m"] = function()
			change_color_mode()
		end,
	}

	for key, mapping in pairs(mappings) do
		vim.keymap.set("n", key, mapping, { buffer = buf, silent = true })
	end
end --}}}

M.pop = function() --{{{
	buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "filetype", "color-picker")

	win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		width = 17,
		col = 0,
		row = 0,
		style = "minimal",
		height = 4,
		border = "rounded",
	})

	-- reset color values
	color_values = { 0, 0, 0 }

	set_mappings()
	create_empty_lines()
	setup_virt_text()

	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end --}}}

vim.keymap.set("n", "<C-A-L>", function()
	P(HSLtoRGB(30, 25, 5))
end, { noremap = true, silent = true })
return M
