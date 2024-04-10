local aman = {}

function aman.getSamplesInRange(start, finish, source, channel)
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

function aman.getSampleBulk(channel, truncate, lastTell, currentTell, soundData)
	local samples = aman.getSamplesInRange(lastTell, currentTell, soundData, channel)

	if #samples %2 == 1 and truncate then
		print(string.format("truncate triggered: %d --> %d", #samples, #samples - 1))
		table.remove(samples)
	end

	return samples
end

function aman.processSamples(truncate, soundData)
	local processedSamples = {}
	local channelCount = soundData:getChannelCount()
	local leftChannel = aman.getSampleBulk(1, truncate)
	local rightChannel = {}
	if channelCount == 2 then
		rightChannel = aman.getSampleBulk(2, truncate)
	end

	for i = 1, #leftChannel do
		table.insert(processedSamples, leftChannel[i] or 0)
		if rightChannel[i] then
			table.insert(processedSamples, rightChannel[i])
		end
	end
	return processedSamples
end

function aman.scaleTable(array, factor)
	local scaledArray = {}
	for _, v in ipairs(array) do
		table.insert(scaledArray, v * factor)
	end
	return scaledArray
end

function aman.flipTable(array, modCond)
	local flippedArray = {}
	for i,v in ipairs(array) do
		if i % 2 == modCond then
			v = -v
		end
		table.insert(flippedArray, v)
	end
	return flippedArray
end

function aman.translateTable(array, modCond, amount)
	local translatedArray = {}
	for i, v in ipairs(array) do
		if i % 2 == modCond then
			v = v + amount
		end
		table.insert(translatedArray, v)
	end
	return translatedArray
end

function aman.getAverage(array, combine)
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

function aman.getAbsoluteAverage(array, combine)
	local averageLeft = 0
	local countLeft = 0
	local averageRight = 0
	local countRight = 0

	for i,v in ipairs(array) do
		local value = math.abs(v)
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


return aman
