--luacheck: globals love
local samples = {}
local canvas = love.graphics.newCanvas(480, 480)
local blackFrameInsertion = true
local scope = {}
local rgb = require("lib.color2RGB")
local resizeClock = 0
local resizeDelay = 0.5

local function getDistance(x1,y1,x2,y2)
	local dx = x2 - x1
	local dy = y2 - y1
	local distance = math.sqrt(dx * dx + dy * dy)

	local minDistance = 1/100
	local maxDistance = 99/100

	local normalizedDistance = (distance - minDistance) / (maxDistance - minDistance)

	normalizedDistance = math.max(0, math.min(1, normalizedDistance))

	local intensity = 1 - normalizedDistance

	--intensity = 0.1 + intensity-- * 0.9
	--print(intensity)

	return intensity
end

function scope.update(dt, inputSamples)
	if type(inputSamples) == "table" then
		samples = inputSamples
	end
	resizeClock = math.max(resizeClock - dt, 0)
	love.graphics.push("all")
	local success, res = pcall(scope.updateCanvas)
	if not success then
		print(res, dt)
	end
	love.graphics.pop()
end

function scope.resize(w, h)
	if resizeClock == 0 then
		resizeClock = resizeDelay
		canvas = love.graphics.newCanvas(w, h)
	end
end


function scope.draw(inputx, inputy)
	local x = inputx or 0
	local y = inputy or 0
	love.graphics.draw(canvas, x - canvas:getWidth() / 2, y - canvas:getHeight() / 2)
end


function scope.updateCanvas()
	love.graphics.setCanvas(canvas)
	love.graphics.origin()
	if #samples > 4  and #samples % 2 == 0 then
		-- if blackFrameInsertion then
		-- 	local r, g, b = rgb("#000000")
		-- 	local alpha = 0.9
		-- 	love.graphics.setColor(r, g, b, alpha)
		-- 	love.graphics.rectangle("fill", 0, 0, canvas:getWidth(), canvas:getHeight())
		-- end
		--love.graphics.clear()
		love.graphics.translate(canvas:getWidth() / 2, canvas:getHeight() / 2)
		for i = 1, #samples, 2 do
			--Short distances will give time to the "BEAM"
			--to excite a non-existent phosphor layer
			local oscCenx = canvas:getWidth() / 2
			local oscCeny = canvas:getHeight() / 2 -- + (showVUMeter and (vumeter:getHeight() / 2) or 0)
			local x1 = samples[i + 0] or oscCenx or 0
			local y1 = samples[i + 1] or oscCeny or 0
			local x2 = samples[i + 2] or x1 or oscCenx
			local y2 = samples[i + 3] or y1 or oscCeny
			--luacheck: push ignore
			local intensity = getDistance(x1, y1, x2, y2)
			intensity = 1
			--luacheck: pop
			y1, y2 = -y1, -y2
			local r, g, b = rgb("#AABBFF")
			love.graphics.setColor(r,g,b)


			--love.graphics.setColor(0, intensity, 0, intensity / 2)
			love.graphics.line(x1 * oscCenx, y1 * oscCeny, x2 * oscCenx, y2 * oscCeny)
			love.graphics.circle("fill", 0, 0, 3)
		end
		love.graphics.circle("line", 0, 0, 10)
	end
end

function scope.getCanvas()
	return canvas
end

return scope