
local assert = assert


local oo                     = require("loop.base")

local string                 = require("string")

local Decode                 = require("squeezeplay.decode")
local Stream                 = require("squeezeplay.stream")
local SlimProto              = require("jive.net.SlimProto")

local Task                   = require("jive.ui.Task")
local Timer                  = require("jive.ui.Timer")

local debug                  = require("jive.utils.debug")
local log                    = require("jive.utils.log").logger("audio")


module(..., oo.class)


-- decode and audio states
local DECODE_RUNNING        = (1 << 0)
local DECODE_UNDERRUN       = (1 << 1)
local DECODE_ERROR          = (1 << 2)
local DECODE_NOT_SUPPORTED  = (1 << 3)


function __init(self, jnt, slimproto)
	assert(slimproto)

	local obj = oo.rawnew(self, {})

	obj.jnt = jnt
	obj.slimproto = slimproto

	obj.slimproto:statusPacketCallback(function(_, event, serverTimestamp)
		local status = Decode:status()

		status.opcode = "STAT"
		status.event = event
		status.serverTimestamp = serverTimestamp
		
		-- XXXX fix this missing status field
		status.bytesReceived = 0

		return status
	end)

	obj.slimproto:subscribe("strm", function(_, data)
		return obj:_strm(data)
	end)

	obj.timer = Timer(100, function()
		obj:_timerCallback()
	end)
	obj.timer:start()


	self.threshold = 0
	self.tracksStarted = 0

	self.sentResume = false
	self.sentDecoderFullEvent = false
	self.sentDecoderUnderrunEvent = false
	self.sentOutputUnderrunEvent = false
	self.sentAudioUnderrunEvent = false


	return obj
end


function sendStatus(self, status, event, serverTimestamp)
	status.opcode = "STAT"
	status.event = event
	status.serverTimestamp = serverTimestamp

	self.slimproto:send(status)
end


function _timerCallback(self)
	local status = Decode:status()


	-- XXXX fix this missing status field
	status.bytesReceived = 0

	-- enable stream reads when decode buffer is not full
	if status.decodeFull < status.decodeSize and self.stream then
		self.jnt:t_addRead(self.stream, self.rtask, 0) -- XXXX timeout?
	end

	if status.decodeState & DECODE_UNDERRUN ~= 0 or
		status.decodeState & DECODE_ERROR ~= 0 then

		-- decode underruns are used by the server to determine
		-- when a track has finished decoding (indicating that
		-- we could start decoding the next track).
		-- only send a decoder underrun if:
		-- 1) we haven't sent one before for this underrun
		-- 2) the connection to us has been closed (indicating
		-- that the stream is done) or we have an unrecoverable
		-- decoder error.

		if not self.sentDecoderUnderrunEvent and
			(not self.stream or status.decodeState & DECODE_ERROR ~= 0) then
			if status.decodeState & DECODE_NOT_SUPPORTED ~= 0 then
				-- XXXX not supported event
			end

			log:info("status DECODE UNDERRUN")
			self:sendStatus(status, "STMd")

			self.sentDecoderUnderrunEvent = true
			self.sentDecoderFullEvent = false

			-- XXXX decode:songEnded()
		end
	else
		self.sentDecoderUnderrunEvent = false
	end


	if status.audioState & DECODE_UNDERRUN ~= 0 then

		-- audio underruns are used by the server to determine
		-- whether a track has completed playback. we have to
		-- be careful to send audio underrun messages only when
		-- we know we've readed the end of a track.
		-- only send an audio underrun event if:
		-- 1) we haven't sent on before this underrun
		-- 2) the decoder has underrun

		-- output underruns are used by the server to detect
		-- when XXXX

		if not self.sentAudioUnderrunEvent and
			self.sentDecoderUnderrrunEvent then

			log:info("status AUDIO UNDERRUN")
			self:sendStatus(status, "STMu")

			self.sentAudioUnderrunEvent = true

		elseif not self.sentOutputUnderrunEvent and
			self.stream then

			log:info("status OUTPUT UNDERRUN")
			self:sendStatus(status, "STMo")

			self.sentOutputUnderrunEvent = true
		end
	else
		self.sentOutputUnderrunEvent = false
		self.sentAudioUnderrunEvent = false
	end


	-- XXXX
	if self.stream and (self.tracksStarted < status.tracksStarted) then

		log:info("status TRACK STARTED")
		self:sendStatus(status, "STMs")

		self.tracksStarted = status.tracksStarted
	end


	-- XXXX
	if status.decodeFull > self.threshold and
		status.decodeState & DECODE_RUNNING == 0 then

		if self.autostart == '1' and not self.sentResume then
			log:info("resume")
			Decode:resume()
			self.sentResume = true

		elseif not self.sentDecoderFullEvent then
			log:info("status FULL")
			self:sendStatus(status, "STMl")

			self.sentDecoderFullEvent = true
		end
	end
end


function _streamWrite(self, networkErr)
	-- XXXX networkErr

	local status, err = self.stream:write(self.header)
	self.jnt:t_removeWrite(self.stream)

	if err then
		log:error("write error: ", err)
	end
end


function _streamRead(self, networkErr)
	-- XXXX networkErr

	local n = self.stream:read()
	while n do
		if n == 0 then
			-- buffer full
			self.jnt:t_removeRead(self.stream)
		end

		-- XXXX handle autostart

		_, networkErr = Task:yield(false)

		n = self.stream:read()
	end

	self.jnt:t_removeRead(self.stream)
	self.stream = nil
end


function _strm(self, data)
	log:info("strm ", data.command)

	if data.command == 's' then
		-- start
		Decode:start(string.byte(data.mode),
			     string.byte(data.transitionType),
			     data.transitionPeriod,
			     data.replayGain,
			     data.outputThreshold,
			     data.flags & 0x03,
			     string.byte(data.pcmSampleSize),
			     string.byte(data.pcmSampleRate),
			     string.byte(data.pcmChannels),
			     string.byte(data.pcmEndianness)
		     )

		local serverIp = data.serverIp == 0 and self.slimproto:getServerIp() or data.serverIp

		if self.stream then
			-- disconnect any existing stream
			self.stream:disconnect()
		end

		-- reset stream state
		-- XXXX flags
		self.header = data.header
		self.autostart = data.autostart
		self.threshold = data.threshold * 1024

		self.sentResume = false
		self.sentDecoderFullEvent = true
		self.sentDecoderUnderrunEvent = false
		self.sentOutputUnderrunEvent = false
		self.sentAudioUnderrunEvent = false

		-- connect to server
		self.stream = Stream:connect(serverIp, data.serverPort)

		local wtask = Task("streambufW", self, _streamWrite)
		self.jnt:t_addWrite(self.stream, wtask, 30)

		self.rtask = Task("streambufR", self, _streamRead)
		self.jnt:t_addRead(self.stream, self.rtask, 0) -- XXXX timeout?

	elseif data.command == 'q' then
		-- quit
		-- XXXX check against ip3k
		Decode:stop()
		if self.stream then
			self.stream:disconnect()
		end

		self.tracksStarted = 0

	elseif data.command == 'f' then
		-- flush
		Decode:flush()
		if self.stream then
			self.stream:flush()
		end

	elseif data.command == 'p' then
		-- pause
		local interval_ms = data.replayGain

		Decode:pause(interval_ms)
		if interval_ms == 0 then
			self.slimproto:sendStatus('STMp')
		end

	elseif data.command == 'a' then
		-- skip ahead
		local interval_ms = data.replayGain

		Decode:skipAhead(interval_ms)

	elseif data.command == 'u' then
		-- unpause
		local interval_ms = data.replayGain

		Decode:resume(interval_ms)
		self.slimproto:sendStatus('STMr')

	elseif data.command == 't' then
		-- timestamp
		local server_ts = data.replayGain

		self.slimproto:sendStatus('STMt', server_ts)
	end

	return true
end



--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
