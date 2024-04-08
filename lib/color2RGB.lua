local function color2RGB(htmlColor)
	-- Default to white if no color is provided
	local htmlColor = htmlColor or "white"
	local hex, ocurrences = string.gsub(htmlColor, "#", "") -- Remove '#' if present

	-- Color mapping table from color names to hexadecimal values
	local colors = {
		white		= "FFFFFF",
		black		= "000000",
		red			= "FF0000",
		green		= "00FF00",
		blue		= "0000FF",
		cyan		= "00FFFF",
		magenta		= "FF00FF",
		yellow		= "FFFF00",
		orange		= "FFA500",
		purple		= "800080",
		pink		= "FFC0CB",
		teal		= "008080",
		lime		= "00FF00",
		lavender	= "E6E6FA",
		brown		= "A52A2A",
		maroon		= "800000",
		olive		= "808000",
		coral		= "FF7F50",
		navy		= "000080",
		indigo		= "4B0082",
		silver		= "C0C0C0",
		gray		= "808080"
	}

	-- If the color provided is a color name, replace it with its hexadecimal value
	if ocurrences == 0 then
		hex = colors[hex] or colors["white"]
	end

	-- Convert hexadecimal to RGB values in the range of 0 to 1
	local r = tonumber(hex:sub(1,2), 16) / 255
	local g = tonumber(hex:sub(3,4), 16) / 255
	local b = tonumber(hex:sub(5,6), 16) / 255
	return {r, g, b} -- Return RGB values as a table
end

return color2RGB