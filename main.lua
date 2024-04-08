local moonshine = require("moonshine")
local rgb = require("color2RGB")
local srt = require("srt")
local vumeter = love.graphics.newImage("vugradient.png")
local captions = srt.new("")
--Un-comment to load automatically a file and play it immediately
local soundData -- = love.sound.newSoundData("music.ogg")
local music -- = love.audio.newSource(soundData)
local lines = {0,0,10,10}
local lastTell = 0
local currentTell = 0
local vuL = 0
local vuR = 0
local dBvuL = 0
local dBvuR = 0
local normalizeddBvuL = 0
local normalizeddBvuR = 0
local gravity = 0.5
local acceleration = 10
local vubarL = 0
local vubarvelL = 0
local vubarR = 0
local vubarvelR = 0
local vuColorL = "#ffffff"
local vuColorR = "#ffffff"
local showPerformance = false
local showCaptions = true
local showVUMeter = true
local useShaders = false
local samples = {}
local warningMsg = [[
Disclaimer: Remeber that some files are
too spicy and may trigger seizures
on some people with that out of he way
]]
local welcomeMsg = [[
Welcome to Alejandro's Oscilloscope.
]]
local dropfileMsg = [[
To start just drop an audio file.
]]
local loadingMsg = [[
Loading file %s...
]]
local waitingMsg = [[
You can play this again by pressing space,
Or just drop another file.
]]
local titleMsg = [[Alejandro's Oscilloscope]]
local shader = moonshine(moonshine.effects.crt).chain(moonshine.effects.glow).chain(moonshine.effects.scanlines)
shader.scanlines.phase = 1
shader.scanlines.width = 1
shader.scanlines.thickness = 1
shader.scanlines.opacity = 0.3

function love.load(args, unfilteredArgs)
	love.graphics.setLineWidth(1)
	love.graphics.setNewFont(24)
	love.graphics.setDefaultFilter("nearest", "nearest")
	love.window.setTitle(titleMsg)
	if music then
		music:play()
	end
end

local function getSamplesInRange(start, finish, source, channel)
	local sampleCount = source:getSampleCount()
	local sampleRate = source:getSampleRate()

	local startSample = math.floor(start * sampleRate) + 1
	local finishSample = math.min(math.floor(finish * sampleRate), sampleCount)

	local samples = {}

	for i = startSample, finishSample do
		local sample = source:getSample(i, channel)
		table.insert(samples, sample)
	end

	return samples
end

local function getSampleBulk(channel, truncate)
	local samples = getSamplesInRange(lastTell, currentTell, soundData, channel)

	if #samples %2 == 1 and truncate then
		print(string.format("truncate triggered: %d --> %d", #samples, #samples - 1))
		table.remove(samples)
	end

	if #samples > 0 then
		--print(channel, #samples, currentTell)
	end

	return samples
end

local function processSamples(truncate)
	local processedSamples = {}
	local channelCount = soundData:getChannelCount()
	local leftChannel = getSampleBulk(1, truncate)
	local rightChannel = {}
	if channelCount == 2 then
		rightChannel = getSampleBulk(2, truncate)
	end

	for i = 1, #leftChannel do
		table.insert(processedSamples, leftChannel[i] or 0)
		if rightChannel[i] then
			table.insert(processedSamples, rightChannel[i])
		end
	end
	return processedSamples
end

local function scaleTable(array, factor)
	local scaledArray = {}
	for i,v in ipairs(array) do
		table.insert(scaledArray, v * factor)
	end
	return scaledArray
end

local function flipTable(array, modCond)
	local flippedArray = {}
	for i,v in ipairs(array) do
		if i % 2 == modCond then
			v = -v
		end
		table.insert(flippedArray, v)
	end
	return flippedArray
end

local function translateTable(array, modCond, amount)
	local translatedArray = {}
	for i, v in ipairs(array) do
		if i % 2 == modCond then
			v = v + amount
		end
		table.insert(translatedArray, v)
	end
	return translatedArray
end

local function getAverage(array, combine)
	local averageLeft = 0
	local countLeft = 0
	local averageRight = 0
	local countRight = 0

	for i,v in ipairs(array) do
		if i % 2 == 0 then
			averageRight = averageRight + v
			countRight = countRight + 1
		else
			averageLeft = averageLeft + v
			countLeft = countLeft + 1
		end
	end
	averageLeft = averageLeft / countLeft
	averageRight = averageRight / countRight

	if combine then
		return (averageLeft + averageRight) / 2
	end

	return averageLeft, averageRight
end

local function getAbsoluteAverage(array, combine)
	local averageLeft = 0
	local countLeft = 0
	local averageRight = 0
	local countRight = 0

	for i,v in ipairs(array) do
		value = math.abs(v)
		if i % 2 == 0 then
			averageRight = averageRight + value
			countRight = countRight + 1
		else
			averageLeft = averageLeft + value
			countLeft = countLeft + 1
		end
	end
	averageLeft = averageLeft / countLeft
	averageRight = averageRight / countRight

	if combine then return (averageLeft + averageRight) / 2	end

	return averageLeft, averageRight
end

-- I did not came up to linearToDecibels and normalizeDecibels
-- I looked them up to be completely honest
local function linearToDecibels(linearValue, referenceValue)
	-- Ensure positive linear and reference values for logarithm calculation
	linearValue = math.max(linearValue, 1e-12)  -- Prevent log10(0) or negative values
	referenceValue = referenceValue or 1  -- Default reference value is 1

	-- Calculate decibels using the formula: dB = 20 * log10(linearValue / referenceValue)
	local dB = 20 * math.log10(linearValue / referenceValue)
	return dB
end

local function normalizeDecibels(dB)
    -- Define the minimum and maximum dB values for mapping
    local minDB = -99
    local maxDB = 0
    
    -- Ensure dB value is within the range [minDB, maxDB]
    dB = math.max(dB, minDB)
    dB = math.min(dB, maxDB)
    
    -- Linear interpolation to map dB to the range [0, 1]
    local normalizedValue = (dB - minDB) / (maxDB - minDB)
    
    return normalizedValue
end

local function categorizeDB(dB)
    -- Define thresholds for each section
    local whisperThreshold = -30  -- dB threshold for whisper-like (quiet) sounds
    local audibleThreshold = -10  -- dB threshold for audible (normal) sounds
    -- Noisy range will be above audibleThreshold

    -- Categorize the dB level based on the thresholds
    if dB <= whisperThreshold then
        return 1
    elseif dB <= audibleThreshold then
        return 2
    else
        return 3
    end
end

local function changeMusicVolume(source, changeAmountPercent)
	local currentVolume = source:getVolume()
	local maxVolume = 1.0
	local minVolume = 0.0

	-- Calculate logarithmic change in volume
	local scaleFactor = 10  -- Adjust this scale factor for logarithmic effect
	local logChange = math.log10(currentVolume + 1) * (changeAmountPercent / 100.0 * scaleFactor)
	
	-- Calculate new volume based on logarithmic change
	local newVolume = currentVolume + (logChange / 100.0)
	
	-- Clamp the new volume between 0.0 and 1.0
	newVolume = math.max(minVolume, math.min(maxVolume, newVolume))

	-- Set the new volume for the music source
	source:setVolume(newVolume)
end

local function getMusicVolumePercentage(source)
	local currentVolume = source:getVolume()
	local scaleFactor = 50  -- Adjust this scale factor for logarithmic effect

	-- Calculate logarithmic percentage of current volume
	local logVolumePercent = (math.log10(currentVolume + 1) / math.log10(maxVolume + 1)) * 100.0
	return logVolumePercent
end

local function setMusicVolume(source, logPercentage)
	local maxVolume = 1.0
	local minVolume = 0.0

	-- Calculate linear volume from logarithmic percentage
	local linearVolume = math.pow(10, (logPercentage / 100.0) * math.log10(maxVolume + 1)) - 1

	-- Clamp the new volume between 0.0 and 1.0
	local newVolume = math.max(minVolume, math.min(maxVolume, linearVolume))

	-- Set the new volume for the music source
	source:setVolume(newVolume)
end


local function changevuBarColor()
	local colors = {
		"#4CFF4C",
		"#FFFF4C",
		"#FF4C4C",
	}
	vuColorL = colors[categorizeDB(dBvuL)] or "#FF1C1C"
	vuColorR = colors[categorizeDB(dBvuR)] or "#FF1C1C"
end

local function updatevumeterBar(dt, volL, volR)
	--Falls slowy
	vubarL = vubarL - gravity * dt
	vubarR = vubarR - gravity * dt

	--Forcefully goes up
	vubarL = math.max(volL, vubarL)
	vubarR = math.max(volR, vubarR)

 	local max = 1
 	local min = 0

 	--Clamp it
 	vubarL = math.max(min, math.min(max, vubarL))
 	vubarR = math.max(min, math.min(max, vubarR))
end

function love.update(dt)
	if music then
		if music:isPlaying() then
			currentTell = music:tell()
			captions:setTime(currentTell)
			lines = {0,0,0,0}
			samples = {}
			samples = processSamples()
			if #samples > 0 then
				local volume = music:getVolume()
				local referenceValue = 0.8
				vuL, vuR = getAbsoluteAverage(samples)
				vuL = vuL * volume
				vuR = vuR * volume
				dBvuL, dBvuR = linearToDecibels(vuL, referenceValue), linearToDecibels(vuR, referenceValue)
				normalizeddBvuL = normalizeDecibels(dBvuL)
				normalizeddBvuR = normalizeDecibels(dBvuR)
				updatevumeterBar(dt, normalizeddBvuL, normalizeddBvuR)
				changevuBarColor()
			end
			samples = scaleTable(samples, math.min(love.graphics.getWidth(), (love.graphics.getHeight()) / 2) - ( showVUMeter and (vumeter:getHeight() / 2) or 0))
			samples = flipTable(samples, 1)
			samples = flipTable(samples, 0)
			samples = flipTable(samples, 1)
			samples = translateTable(samples, 1, love.graphics.getWidth() / 2)
			samples = translateTable(samples, 0, (love.graphics.getHeight() / 2) + (showVUMeter and (vumeter:getHeight() / 2) or 0))
			lines = samples
			lastTell = music:tell()
		end
		if love.keyboard.isDown("down") then
			changeMusicVolume(music, -50)
		end
		if love.keyboard.isDown("up") then
			changeMusicVolume(music,  50)
		end
	end
end

function love.draw()
	if music then
		love.graphics.setColor(0, 1, 0)
		if #lines > 4 then
			if useShaders then
				shader(function()love.graphics.line(lines)end)
			else
				love.graphics.line(lines)
			end
		end
	else
		love.graphics.setColor(1,1,1)
		love.graphics.printf(welcomeMsg.."\n"..warningMsg.."\n"..dropfileMsg, 0, love.graphics.getHeight() / 2, love.graphics.getWidth(), "center")
	end
	--Please use it, took way to much time to do a pleasant vu meter
	if showVUMeter then
		--BG
		love.graphics.setColor(1,1,1)
		love.graphics.draw(vumeter, 0, 0, 0, love.graphics.getWidth() / vumeter:getWidth(), 1)

		--Mask 1
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("fill", normalizeddBvuL * love.graphics.getWidth(), 0, love.graphics.getWidth(), vumeter:getHeight() / 2)
		--Bar 1
		love.graphics.setColor(rgb(vuColorL))
		love.graphics.rectangle("fill", vubarL * love.graphics.getWidth(), 0, 10,  vumeter:getHeight() / 2)
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("line", vubarL * love.graphics.getWidth(), 0, 10,  vumeter:getHeight() / 2)
		--Mask 2
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("fill", normalizeddBvuR * love.graphics.getWidth(), vumeter:getHeight() / 2, love.graphics.getWidth(), vumeter:getHeight() / 2)
		--Bar 2
		love.graphics.setColor(rgb(vuColorR))
		love.graphics.rectangle("fill", vubarR * love.graphics.getWidth(), vumeter:getHeight() / 2, 10,  vumeter:getHeight() / 2)
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("line", vubarR * love.graphics.getWidth(), vumeter:getHeight() / 2, 10,  vumeter:getHeight() / 2)
		--Vu meter Text
		love.graphics.setColor(1, 0, 1)
		local formattedvuL = string.format("%.3f", dBvuL)
		local formattedvuR = string.format("%.3f", dBvuR)
		love.graphics.print(formattedvuL, (love.graphics.getWidth() / 2) - (love.graphics.getFont():getWidth(formattedvuL) / 2), vumeter:getHeight() * 0.25 - (love.graphics.getFont():getHeight() / 2))
		love.graphics.print(formattedvuR, (love.graphics.getWidth() / 2) - (love.graphics.getFont():getWidth(formattedvuR) / 2), vumeter:getHeight() * 0.75 - (love.graphics.getFont():getHeight() / 2))
	end
	if showCaptions then
		--Captions
		local text = captions:getText()
		love.graphics.setColor(1,1,1)
		local x = (love.graphics.getWidth() / 2) - (love.graphics.getFont():getWidth(text) / 2)
		local y = showVUMeter and (vumeter:getHeight() * 1.25 - (love.graphics.getFont():getHeight() / 2)) or 0
		x = showPerformance and love.graphics.getWidth() / 2 or 0
		x = math.floor(x)
		y = math.floor(y)
		love.graphics.printf(text, x, y, showPerformance and love.graphics.getWidth() / 2 or love.graphics.getWidth(), "center")
	end
	if showPerformance then
		local text = "FPS: %d\nSample troughput: %d\n"
		local text = string.format(text, love.timer.getFPS(), #samples)
		text = (showVUMeter and "\n\n" or "") .. text
		love.graphics.setColor(0,0,0)
		love.graphics.print(text, 1, 1)
		love.graphics.setColor(1,1,1)
		love.graphics.print(text)
	end
end

local function releaseSources()
	if music then
		pcall(music.release, music)
	end
	if soundData then
		pcall(soundData.release, soundData)
	end
end

function love.filedropped(file)
	local lastDotIndex = file:getFilename():find("[^%.]+$")
	local extension = ""
	if lastDotIndex then
		extension = file:getFilename():sub(lastDotIndex):lower() or ""
		--print(extension)
	end
	if extension ~= "srt" then
		local res, msg = pcall(love.sound.newSoundData, file)
		if res then
			print(string.format("loading \"%s\" as sound source.", file:getFilename()))
			local filename = file:getFilename():match("[\\/]?([^\\/]+)$") or file:getFilename()
			love.window.setTitle(titleMsg .. ": " .. filename)
			if music then
				music:stop()
			end
			releaseSources()
			soundData = love.sound.newSoundData(file)
			music = love.audio.newSource(soundData)
			music:play()
		else
			print(msg)
		end
	else
		print(string.format("Loading \"%s\" as captions.", file:getFilename()))
		local content = file:read() or ""
		captions = srt.new(content)
	end
end

function love.keypressed(key, scancode, isrepeat)
	--Actions / visuals
	if key == "f1" then showPerformance = not showPerformance end
	if key == "f2" then useShaders = not useShaders end
	if key == "f3" then showVUMeter = not showVUMeter end
	if key == "f4" then
		if love.keyboard.isDown("lshift", "rshift") then
			--Drop current captions
			captions = srt.new("")
		else
			showCaptions = not showCaptions
		end
	end
	if key == "f5" then love.event.quit("restart") end

	--Playback
	if music then
		if key == "space" then
			if music:isPlaying()
			then music:pause()
			else music:play() end
		end
		if key == "left" then music:seek(math.max(0, music:tell() - 5)) lastTell = music:tell() currentTell = music:tell() end
		if key == "right" then music:seek(math.min(music:getDuration(), music:tell() + 5)) lastTell = music:tell() currentTell = music:tell() end
		if key == "," and love.keyboard.isDown("lshift", "rshift") then music:setPitch(math.max(music:getPitch() - 0.1, 0.1)) end
		if key == "." and love.keyboard.isDown("lshift", "rshift") then music:setPitch(math.min(music:getPitch() + 0.1, math.huge)) end

	end
	--print(key, scancode, isrepeat)
end