

-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------



-- stuff we use
local assert, getmetatable, ipairs, pairs, pcall, setmetatable, tonumber, tostring, type = assert, getmetatable, ipairs, pairs, pcall, setmetatable, tonumber, tostring, type

local oo                     = require("loop.simple")

local io                     = require("io")
local os                     = require("os")
local string                 = require("string")
local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")

local Applet                 = require("jive.Applet")
local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local Button                 = require("jive.ui.Button")
local Group                  = require("jive.ui.Group")
local Keyboard               = require("jive.ui.Keyboard")
local Tile                   = require("jive.ui.Tile")
local RadioButton            = require("jive.ui.RadioButton")
local RadioGroup             = require("jive.ui.RadioGroup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Surface                = require("jive.ui.Surface")
local Task                   = require("jive.ui.Task")
local Textarea               = require("jive.ui.Textarea")
local Textinput              = require("jive.ui.Textinput")
local Window                 = require("jive.ui.Window")
local Popup                  = require("jive.ui.Popup")

local Networking             = require("jive.net.Networking")

local log                    = require("jive.utils.log").logger("applets.setup")

local jnt                    = jnt

local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE


-- configuration
local CONNECT_TIMEOUT = 30
local wirelessTitleStyle = 'setuptitle'

module(..., Framework.constants)
oo.class(_M, Applet)


function init(self)
	self.wifiInterface  = Networking:wirelessInterface()
	self.wiredInterface = Networking:wiredInterface()
	self.t_ctrl = Networking(jnt, self.wifiInterface)
end


function setupRegionShow(self, setupNext)
	local wlan = self.t_ctrl

	local window = Window("regionWindow", self:string("NETWORK_REGION"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local region = wlan:getRegion()

	local menu = SimpleMenu("buttonmenu")

	for name in wlan:getRegionNames() do
		local item = {
			text = self:string("NETWORK_REGION_" .. name),
			style = 'buttonitem',
			sound = "WINDOWSHOW",
			callback = function()
					   if region ~= name then
						   wlan:setRegion(name)
					   end
					   setupNext()
				   end
		}

		menu:addItem(item)
		if region == name then
			log:warn("setSelectedItem=", menu:numItems())
			menu:setSelectedItem(item)
		end
		log:warn("region=", region, " name=", name)
	end


	--window:addWidget(Textarea("help", self:string("NETWORK_REGION_HELP")))
	local helpButton = Button( Label( 'helpTouchButton', self:string("NETWORK_CONNECTION_HELP")), function() self:helpWindow('NETWORK_REGION', 'NETWORK_REGION_HELP') end )
	window:addWidget(helpButton)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

function settingsRegionShow(self)
	local wlan = self.t_ctrl

	local window = Window("window", self:string("NETWORK_REGION"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local region = wlan:getRegion()

	local menu = SimpleMenu("menu")
	menu:setComparator(SimpleMenu.itemComparatorAlpha)

	local group = RadioGroup()
	for name in wlan:getRegionNames() do
		log:warn("region=", region, " name=", name)
		menu:addItem({
				     text = self:string("NETWORK_REGION_" .. name),
				     icon = RadioButton("radio", group,
							function() wlan:setRegion(name) end,
							region == name
						)
			     })
	end

	window:addWidget(Textarea("help", self:string("NETWORK_REGION_HELP")))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function _setCurrentSSID(self, ssid)
	if self.currentSSID == ssid then
		return
	end

	if self.currentSSID and self.scanResults[self.currentSSID] then
		local item = self.scanResults[self.currentSSID].item
		item.style = nil
		self.scanMenu:updatedItem(item)
	end

	self.currentSSID = ssid

	if self.currentSSID then
		local item = self.scanResults[self.currentSSID].item
		item.style = "checked"
		self.scanMenu:updatedItem(item)
	end
end


function _addNetwork(self, ssid)
	local item = {
		text = ssid,
		icon = Icon("icon"),
		sound = "WINDOWSHOW",
		callback = function()
				   openNetwork(self, ssid)
			   end,
		weight = 1
	}
		      
	self.scanResults[ssid] = {
		item = item,            -- menu item
		-- flags = nil,         -- beacon flags
		-- bssid = nil,         -- bssid if know from scan
		-- id = nil             -- wpa_ctrl id if configured
	}

	self.scanMenu:addItem(item)
end


function setupScanShow(self, setupNext)

	local window = Popup("popupIcon")
	window:setAllowScreensaver(false)

        window:addWidget(Icon("iconConnecting"))
        window:addWidget(Label("text", self:string("NETWORK_FINDING_NETWORKS")))

	local status = Label("text2", self:string("NETWORK_FOUND_NETWORKS", 0))
	window:addWidget(status)

	-- wait for network scan (in task)
	self.t_ctrl:scan(setupNext)

        window:addTimer(1000, function()
			local results = self.t_ctrl:scanResults()
			local numNetworks = 0
			for k, v in pairs(results) do
				numNetworks = numNetworks + 1
			end
			if numNetworks >= 1 then
				status:setValue(self:string("NETWORK_FOUND_NETWORKS", tostring(numNetworks) ) )
			end
		end)

	-- or timeout after 10 seconds if no networks are found
	window:addTimer(10000, function() setupNext() end)

	self:tieAndShowWindow(window)
	return window

end


function setupNetworksShow(self, setupNext)
	self.setupNext = setupNext

	local window = _networksShow(self, self:string("NETWORK_WIRELESS_NETWORKS"), self:string("NETWORK_SETUP_HELP"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	return window
end


function setupConnectionHelp(self)
	local window = Window("window", self:string("NETWORK_CONNECTION_HELP"), 'setuptitle')
	window:setAllowScreensaver(false)

	local textarea = Textarea("textarea", "this is just a placeholder for a bunch of text that we may put in to describe the vagaries of network connections, including terms such as 'cat5', 'SSID', and 'distributed denial of service attack'. It could be this window presents menu options or the like, but for starters I'm just throwing a textarea in here. Press the back button in the upper left to go back.")
	window:addWidget(textarea)
	self:tieAndShowWindow(window)

	return window
end


function setupConnectWiredInterface(self, setupNext)
	log:warn('bringing ', self.wiredInterface, ' up')
	self.wiredInterface:t_ifUp()
end


function setupConnectionType(self, setupNextWireless, setupNextWired)
	log:warn('setupConnectionType')

	local window = Window("window", self:string("NETWORK_CONNECTION_TYPE"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local connectionMenu = SimpleMenu("buttonmenu")

	connectionMenu:addItem({
					style = 'buttonitem',
				      text = (self:string("NETWORK_CONNECTION_TYPE_WIRELESS")),
				      sound = "WINDOWSHOW",
				      callback = function()
							 setupNextWireless()
						 end,
				      weight = 1
			      })
	
	connectionMenu:addItem({
					style = 'buttonitem',
				      text = (self:string("NETWORK_CONNECTION_TYPE_WIRED")),
				      sound = "WINDOWSHOW",
				      callback = function()
							 setupNextWired()
						 end,
				      weight = 2
			      })
	
	local helpButton     = Button( Label( 'helpTouchButton', self:string("NETWORK_CONNECTION_HELP")), function() self:setupConnectionHelp() end )
	window:addWidget(helpButton)
	window:addWidget(connectionMenu)

	self:tieAndShowWindow(window)
	return window

end


function settingsNetworksShow(self)
	self.setupNext = nil

	return setupScanShow(self,
			     function()
				     _networksShow(self, self:string("NETWORK"), self:string("NETWORK_SETTINGS_HELP"))
			     end)
end


function _networksShow(self, title, help)
	local window = Window("window", title, wirelessTitleStyle)
	window:setAllowScreensaver(false)

	-- window to return to on completion of network settings
	self.topWindow = window

	self.scanMenu = SimpleMenu("menu")
	self.scanMenu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	self.scanMenu:addItem({
				      text = self:string("NETWORK_ENTER_ANOTHER_NETWORK"),
				      sound = "WINDOWSHOW",
				      callback = function()
							 enterSSID(self)
						 end,
				      weight = 2
			      })
	
	
	self.scanResults = {}

	-- load known networks (in network thread)
	Task("networkList", self, t_listNetworks):addTask()

	-- process existing scan results
	self:_scanComplete(self.t_ctrl:scanResults())

	-- schedule network scan 
	self.scanMenu:addTimer(5000,
			       function()
				       self:scan()
			       end)

	local help = Textarea("help", help)
	window:addWidget(help)
	window:addWidget(self.scanMenu)

	self:tieAndShowWindow(window)
	return window
end


-- load known networks from wpa supplicant into scan menu
function t_listNetworks(self)
	local networkResults = self.t_ctrl:request("LIST_NETWORKS")
	log:warn("list results ", networkResults)

	for id, ssid, flags in string.gmatch(networkResults, "([%d]+)\t([^\t]*)\t[^\t]*\t([^\t]*)\n") do
		if not string.match(ssid, "logitech[%-%+%*]squeezebox[%-%+%*](%x+)") then

			if not self.scanResults[ssid] then
				_addNetwork(self, ssid)
			end
			self.scanResults[ssid].id = id

			if string.match(flags, "%[CURRENT%]") then
				self:_setCurrentSSID(ssid)
				self.scanMenu:setSelectedItem(self.scanResults[ssid].item)
			end
		end
	end
end


function scan(self)
	self.t_ctrl:scan(function(scanTable)
				 _scanComplete(self, scanTable)
			 end)
end


function _scanComplete(self, scanTable)
	local now = Framework:getTicks()

	local associated = nil
	for ssid, entry in pairs(scanTable) do
		      -- hide squeezebox ad-hoc networks
		      if not string.match(ssid, "logitech[%-%+%*]squeezebox[%-%+%*](%x+)") then

			      if not self.scanResults[ssid] then
				      _addNetwork(self, ssid)
			      end

			      -- always update the bssid and flags
			      self.scanResults[ssid].bssid = entry.bssid
			      self.scanResults[ssid].flags = entry.flags

			      if entry.associated then
				      associated = ssid
			      end

			      local item = self.scanResults[ssid].item

			      --assert(type(entry.quality) == "number", "Eh? quality is " .. tostring(entry.quality) .. " for " .. ssid)
			      item.icon:setStyle("wirelessLevel" .. entry.quality)
			      self.scanMenu:updatedItem(item)
		      end
	end

	-- remove old networks
	for ssid, entry in pairs(self.scanResults) do
		if not scanTable[ssid] then
			self.scanMenu:removeItem(entry.item)
			self.scanResults[ssid] = nil
		end
	end

	-- update current ssid 
	self:_setCurrentSSID(associated)
end


function _hideToTop(self, dontSetupNext)
	if Framework.windowStack[1] == self.topWindow then
		return
	end

	while #Framework.windowStack > 2 and Framework.windowStack[2] ~= self.topWindow do
		log:warn("hiding=", Framework.windowStack[2], " topWindow=", self.topWindow)
		Framework.windowStack[2]:hide(Window.transitionPushLeft)
	end

	Framework.windowStack[1]:hide(Window.transitionPushLeft)

	-- we have successfully setup the network, so hide any open network
	-- settings windows before advancing during setup.
	if dontSetupNext ~= true and type(self.setupNext) == "function" then
		self.setupNext()
		return
	end
end


function openNetwork(self, ssid)
	if ssid == self.currentSSID then
		-- current network, show status
		if type(self.setupNext) == "function" then
			return self.setupNext()
		else
			return networkStatusShow(self)
		end

	elseif self.scanResults[ssid] and
		self.scanResults[ssid].id ~= nil then
		-- known network, give options
		return connectOrDelete(self, ssid)

	else
		-- unknown network, enter password
		self.ssid = ssid
		return enterPassword(self)
	end
end


function enterSSID(self)
	local window = Window("window", self:string("NETWORK_NETWORK_NAME"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local textinput = Textinput("textinput", "",
				    function(widget, value)
					    if #value == 0 then
						    return false
					    end

					    self.ssid = value

					    widget:playSound("WINDOWSHOW")
					    enterPassword(self)

					    return true
				    end
			    )

	local helpButton = Button( Label( 'helpTouchButton', self:string("NETWORK_CONNECTION_HELP")), function() self:helpWindow('NETWORK_NETWORK_NAME', 'NETWORK_NETWORK_NAME_HELP') end )

	window:addWidget(textinput)
	window:addWidget(helpButton)
	window:addWidget(Keyboard("keyboard", 'qwerty'))
	window:focusWidget(textinput)

	self:tieAndShowWindow(window)
	return window
end


function enterPassword(self)
	assert(self.ssid, "No SSID selected")

	if self.scanResults[self.ssid] == nil then
		return chooseEncryption(self)
	end
	local flags = self.scanResults[self.ssid].flags

	log:warn("ssid is: ", self.ssid, " flags are: ", flags)

	if flags == "" then
		self.encryption = "none"
		return createAndConnect(self)

	elseif string.find(flags, "WPA2%-PSK") then
		log:warn("**** WPA2")
		self.encryption = "wpa2"
		return enterPSK(self)

	elseif string.find(flags, "WPA%-PSK") then
		log:warn("**** WPA")
		self.encryption = "wpa"
		return enterPSK(self)

	elseif string.find(flags, "WEP") then
		log:warn("**** WEP")
		return chooseWEPLength(self)

	elseif string.find(flags, "WPA%-EAP") or string.find(flags, "WPA2%-EAP") then
		local window = Window("window", self:string("NETWORK_CONNECTION_PROBLEM"))
		window:setAllowScreensaver(false)

		local menu = SimpleMenu("menu",
					{
						{
							text = self:string("NETWORK_GO_BACK"),
							sound = "WINDOWHIDE",
							callback = function()
									   window:hide()
								   end
						},
					})

		local help = Textarea("help", self:string("NETWORK_UNSUPPORTED_TYPES_HELP"))
--"WPA-EAP and WPA2-EAP are not supported encryption types.")

		window:addWidget(help)
		window:addWidget(menu)

		self:tieAndShowWindow(window)		
		return window

	else
		return chooseEncryption(self)

	end
end


function chooseEncryption(self)
	local window = Window("window", self:string("NETWORK_WIRELESS_ENCRYPTION"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("NETWORK_NO_ENCRYPTION"),
						sound = "WINDOWSHOW",
						callback = function()
								   self.encryption = "none"
								   createAndConnect(self)
							   end
					},
					{
						text = self:string("NETWORK_WEP_64"),
						sound = "WINDOWSHOW",
						callback = function()
								   self.encryption = "wep40"
								   enterWEPKey(self)
							   end
					},
					{
						text = self:string("NETWORK_WEP_128"),
						sound = "WINDOWSHOW",
						callback = function()
								   self.encryption = "wep104"
								   enterWEPKey(self)
							   end
					},
					{
						text = self:string("NETWORK_WPA"),
						sound = "WINDOWSHOW",
						callback = function()
								   self.encryption = "wpa"
								   enterPSK(self)
							   end
					},
					{
						text = self:string("NETWORK_WPA2"),
						sound = "WINDOWSHOW",
						callback = function()
								   self.encryption = "wpa2"
								   enterPSK(self)
							   end
					},
				})

	local helpButton     = Button( Label( 'helpTouchButton', self:string("NETWORK_CONNECTION_HELP")), function() self:helpWindow('NETWORK_WIRELESS_ENCRYPTION', 'NETWORK_WIRELESS_ENCRYPTION_HELP') end )
	window:addWidget(helpButton)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function helpWindow(self, title, token)
	local window = Window("window", self:string(title), wirelessTitleStyle)
	window:setAllowScreensaver(false)
	window:addWidget(Textarea("textarea", self:string(token)))

	self:tieAndShowWindow(window)
	return window
end


function chooseWEPLength(self)
	local window = Window("window", self:string("NETWORK_WIRELESS_ENCRYPTION"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("NETWORK_WEP_64"),
						sound = "WINDOWSHOW",
						callback = function()
								   self.encryption = "wep40"
								   enterWEPKey(self)
							   end
					},
					{
						text = self:string("NETWORK_WEP_128"),
						sound = "WINDOWSHOW",
						callback = function()
								   self.encryption = "wep104"
								   enterWEPKey(self)
							   end
					},
				})

	local help = Textarea("help", self:string("NETWORK_WIRELESS_ENCRYPTION_HELP"))
	window:addWidget(help)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function enterWEPKey(self)
	local window = Window("window", self:string("NETWORK_WIRELESS_KEY"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local v
	-- set the initial value
	if self.encryption == "wep40" then
		v = Textinput.textValue("0000000000", 10, 10)
	else
		v = Textinput.textValue("00000000000000000000000000", 26, 26)
	end

	local textinput = Textinput("textinput", v,
				    function(widget, value)
					    self.key = value:getValue()

					    widget:playSound("WINDOWSHOW")
					    createAndConnect(self)

					    return true
				    end
			    )

	local keyboard = Keyboard('keyboard', 'hex')
	local helpButton     = Button( Label( 'helpTouchButton', self:string("NETWORK_CONNECTION_HELP")), function() self:helpWindow('NETWORK_WIRELESS_KEY', 'NETWORK_WIRELESS_KEY_HELP') end )

	window:addWidget(textinput)
	window:addWidget(helpButton)
	window:addWidget(keyboard)
	window:focusWidget(textinput)

	self:tieAndShowWindow(window)
	return window
end


function enterPSK(self)
	local window = Window("window", self:string("NETWORK_WIRELESS_PASSWORD"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local v = Textinput.textValue(self.psk, 8, 63)
	local textinput = Textinput("textinput", v,
				    function(widget, value)
					    self.psk = tostring(value)

					    widget:playSound("WINDOWSHOW")
					    createAndConnect(self)

					    return true
				    end,
				    self:string("ALLOWEDCHARS_WPA")
			    )
	local helpButton     = Button( Label( 'helpTouchButton', self:string("NETWORK_CONNECTION_HELP")), function() self:helpWindow('NETWORK_WIRELESS_PASSWORD', 'NETWORK_WIRELESS_PASSWORD_HELP') end )

	window:addWidget(helpButton)
	window:addWidget(textinput)
	window:addWidget(Keyboard('keyboard', 'qwerty'))
	window:focusWidget(textinput)



	self:tieAndShowWindow(window)
	return window
end


function t_addNetwork(self)
	assert(self.t_ctrl, "No WPA supplicant")

	local option = {
		encryption = self.encryption,
		psk = self.psk,
		key = self.key
	}

	log:warn('ADDING NETWORK: ', self.ssid)
	local id = self.t_ctrl:t_addNetwork(self.ssid, option)
	log:warn('returned id: ', id)

	self.addNetwork = true
	self.scanResults[self.ssid].id = id
end


function _connectTimer(self)
	Task("networkConnect", self,
	     function()
		     log:warn("connectTimeout=", self.connectTimeout, " dhcpTimeout=", self.dhcpTimeout)

		     local status = self.t_ctrl:t_wpaStatus()

		     log:warn("wpa_state=", status.wpa_state)
		     log:warn("ip_address=", status.ip_address)

		     if not (status.wpa_state == "COMPLETED" and status.ip_address) then
			     -- not connected yet

			     self.connectTimeout = self.connectTimeout + 1
			     if self.connectTimeout ~= CONNECT_TIMEOUT then
				     return
			     end

			     -- connection timed out
			     self:connectFailed("timeout")
			     return
		     end
			    
		     if string.match(status.ip_address, "^169.254.") then
			     -- auto ip
			     self.dhcpTimeout = self.dhcpTimeout + 1
			     if self.dhcpTimeout ~= CONNECT_TIMEOUT then
				     return
			     end

			     -- dhcp timed out
			     self:failedDHCP()
		     else
			     -- dhcp completed
			     self:connectOK()
		     end
	     end):addTask()
	
end


function t_selectNetwork(self, ssid)
	local request

	self.t_ctrl:t_disconnectNetwork(self.wifiInterface)

	if self.createNetwork == ssid then
		-- remove the network config
		self:t_removeNetwork(ssid)
	end

	if self.scanResults[ssid] == nil then
		-- ensure the network state exists
		_addNetwork(self, ssid)
	end

	log:warn("SSID=", self.ssid, " SR=", self.scanResults)
	local id = self.scanResults[ssid].id
	log:warn("t_selectNetwork ssid=", ssid, " id=", id)

	if id == nil then
		-- create the network config
		self:t_addNetwork()
	end

	self.t_ctrl:t_selectNetwork(ssid)	
end


function createAndConnect(self)
	log:warn("createAndConnect ", self.ssid)

	self.createNetwork = self.ssid
	connect(self)
end


function connect(self, keepConfig)
	local request

	self.connectTimeout = 0
	self.dhcpTimeout = 0

	if not keepConfig then
		self:_setCurrentSSID(nil)

		-- Select/add the network in a background task
		log:warn("SSID=", self.ssid)
		Task("networkSelect", self, t_selectNetwork):addTask(self.ssid)
	end

	-- Progress window
	local window = Popup("popupIcon")

	local icon  = Icon("iconConnecting")
	icon:addTimer(1000, function()
				    self:_connectTimer()
			    end)
	window:addWidget(icon)

	window:addWidget(Label("text", self:string("NETWORK_CONNECTING_TO", self.ssid)))

	self:tieAndShowWindow(window)
	return window
end


function t_connectFailed(self)
	local request

	-- Stop trying to connect to the network
	self.t_ctrl:t_disconnectNetwork(self)

	log:warn("addNetwork=", self.addNetwork)
	if self.addNetwork then
		-- Remove failed network
		self:t_removeNetwork(self.ssid)
		self.addNetwork = nil
	end
end


function connectFailed(self, reason)
	log:warn("connection failed")

	-- Stop trying to connect to the network, if this network is
	-- being added this will also remove the network configuration
	Task("networkFailed", self, t_connectFailed):addTask()

	-- Message based on failure type
	local helpText = self:string("NETWORK_CONNECTION_PROBLEM_HELP")

	if reason == "psk" then
		helpText = tostring(helpText) .. " " .. tostring(self:string("NETWORK_PROBLEM_PASSWORD_INCORRECT"))
	end


	-- popup failure
	local window = Window("window", self:string("NETWORK_CONNECTION_PROBLEM"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("NETWORK_TRY_AGAIN"),
						sound = "WINDOWHIDE",
						callback = function()
								   connect(self)
								   window:hide(Window.transitionNone)
							   end
					},
					{
						text = self:string("NETWORK_TRY_DIFFERENT"),
						sound = "WINDOWSHOW",
						callback = function()
								   _hideToTop(self, true)
							   end
					},
					{
						text = self:string("NETWORK_GO_BACK"),
						sound = "WINDOWHIDE",
						callback = function()
								   window:hide()
							   end
					},
				})


	local help = Textarea("help", helpText)

	window:addWidget(help)
	window:addWidget(menu)

	self:tieWindow(window)
	window:show()

	return window
end


function connectOK(self)
	if self.ssid == nil then
		-- make sure we are still trying to connect
		return
	end

	log:warn("connection OK ", self.ssid)

	self:_setCurrentSSID(self.ssid)

	-- forget connection state
	self.ssid = nil
	self.encryption = nil
	self.psk = nil
	self.key = nil

	-- send notification we're on a new network
	jnt:notify("networkConnected")

	-- popup confirmation
	local window = Popup("popupIcon")
	window:addWidget(Icon("iconConnected"))

	local text = Label("text", self:string("NETWORK_CONNECTED_TO", self.currentSSID))
	window:addWidget(text)

	window:addTimer(2000,
			function(event)
				_hideToTop(self)
			end)

	window:addListener(EVENT_KEY_PRESS,
			   function(event)
				   _hideToTop(self)
				   return EVENT_CONSUME
			   end)


	self:tieWindow(window)
	window:show()
	return window
end


function _parseip(str)
	local ip = 0
	for w in string.gmatch(str, "%d+") do
		ip = ip << 8
		ip = ip | tonumber(w)
	end
	return ip
end


function _ipstring(ip)
	local str = {}
	for i = 4,1,-1 do
		str[i] = string.format("%d", ip & 0xFF)
		ip = ip >> 8
	end
	str = table.concat(str, ".")
	return str
end


function _validip(str)
	local ip = _parseip(str)
	if ip == 0x00000000 or ip == 0xFFFFFFFF then
		return false
	else
		return true
	end
end


function _subnet(self)
	local ip = _parseip(self.ipAddress or "0.0.0.0")

	if ((ip & 0xC0000000) == 0xC0000000) then
		return "255.255.255.0"
	elseif ((ip & 0x80000000) == 0x80000000) then
		return "255.255.0.0"
	elseif ((ip & 0x80000000) == 0) then
		return "255.0.0.0"
	else
		return "0.0.0.0";
	end
end


function _gateway(self)
	local ip = _parseip(self.ipAddress or "0.0.0.0")
	local subnet = _parseip(self.ipSubnet or "255.255.255.0")

	return _ipstring(ip & subnet | 1)
end


function _sigusr1(process)
	local pid

	local pattern = "%s*(%d+).*" .. process

	log:warn("pattern is ", pattern)

	local cmd = io.popen("/bin/ps")
	for line in cmd:lines() do
		pid = string.match(line, pattern)
		if pid then break end
	end
	cmd:close()

	if pid then
		log:warn("kill -usr1 ", pid)
		os.execute("kill -usr1 " .. pid)
	else
		log:error("cannot sigusr1 ", process)
	end
end


function failedDHCP(self)
	log:warn("self.encryption=", self.encryption)

	if self.encryption and string.match(self.encryption, "^wep.*") then
		-- use different error screen for WEP, the failure may
		-- be due to a bad WEP passkey, not DHCP.
		return failedDHCPandWEP(self)
	else
		return failedDHCPandWPA(self)
	end
end


function failedDHCPandWPA(self)
	local window = Window("window", self:string("NETWORK_ADDRESS_PROBLEM"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("NETWORK_TRY_AGAIN"),
						sound = "WINDOWHIDE",
						callback = function()
								   -- poke udhcpto try again
								   _sigusr1("udhcpc")
								   connect(self, true)
								   window:hide(Window.transitionNone)
							   end
					},
					{
						text = self:string("ZEROCONF_ADDRESS"),
						sound = "WINDOWSHOW",
						callback = function()
								   -- already have a self assigned address, we're done
								   connectOK(self)
							   end
					},
					{
						text = self:string("STATIC_ADDRESS"),
						sound = "WINDOWSHOW",
						callback = function()
								   enterIP(self)
							   end
					},
				})


	local help = Textarea("help", self:string("NETWORK_ADDRESS_HELP"))

	window:addWidget(help)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function failedDHCPandWEP(self)
	local window = Window("window", self:string("NETWORK_CONNECTION_PROBLEM"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("NETWORK_TRY_AGAIN"),
						sound = "WINDOWHIDE",
						callback = function()
								   -- poke udhcpto try again
								   _sigusr1("udhcpc")
								   connect(self, true)
								   window:hide(Window.transitionNone)
							   end
					},



					{
						text = self:string("NETWORK_EDIT_WIRELESS_KEY"),
						sound = "WINDOWHIDE",
						callback = function()
								   window:hide()
							   end
					},



					{
						text = self:string("ZEROCONF_ADDRESS"),
						sound = "WINDOWSHOW",
						callback = function()
								   -- already have a self assigned address, we're done
								   connectOK(self)
							   end
					},
					{
						text = self:string("STATIC_ADDRESS"),
						sound = "WINDOWSHOW",
						callback = function()
								   enterIP(self)
							   end
					},
				})


	local help = Textarea("help", self:string("NETWORK_ADDRESS_HELP_WEP"))

	window:addWidget(help)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function enterIP(self)
	local v = Textinput.ipAddressValue(self.ipAddress or "0.0.0.0")

	local window = Window("window", self:string("NETWORK_IP_ADDRESS"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	window:addWidget(Textarea("help", self:string("NETWORK_IP_ADDRESS_HELP")))
	window:addWidget(Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()
					   if not _validip(value) then
						   return false
					   end

					   self.ipAddress = value
					   self.ipSubnet = _subnet(self)

					   widget:playSound("WINDOWSHOW")
					   self:enterSubnet()
					   return true
				   end))

	self:tieAndShowWindow(window)
	return window
end


function enterSubnet(self)
	local v = Textinput.ipAddressValue(self.ipSubnet)

	local window = Window("window", self:string("NETWORK_SUBNET"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	window:addWidget(Textarea("help", self:string("NETWORK_SUBNET_HELP")))
	window:addWidget(Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   self.ipSubnet = value
					   self.ipGateway = _gateway(self)

					   widget:playSound("WINDOWSHOW")
					   self:enterGateway()
					   return true
				   end))

	self:tieAndShowWindow(window)
	return window
end


function enterGateway(self)
	local v = Textinput.ipAddressValue(self.ipGateway)

	local window = Window("window", self:string("NETWORK_GATEWAY"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	window:addWidget(Textarea("help", self:string("NETWORK_GATEWAY_HELP")))
	window:addWidget(Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   if not _validip(value) then
						   return false
					   end

					   self.ipGateway = value
					   self.ipDNS = self.ipGateway

					   widget:playSound("WINDOWSHOW")
					   self:enterDNS()
					   return true
				   end))

	self:tieAndShowWindow(window)
	return window
end


function enterDNS(self)
	local v = Textinput.ipAddressValue(self.ipDNS)

	local window = Window("window", self:string("NETWORK_DNS"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	window:addWidget(Textarea("help", self:string("NETWORK_DNS_HELP")))
	window:addWidget(Textinput("textinput", v,
				   function(widget, value)
					   value = value:getValue()

					   if not _validip(value) then
						   return false
					   end

					   self.ipDNS = value

					   widget:playSound("WINDOWSHOW")
					   self:setStaticIP()
					   return true
				   end))

	self:tieAndShowWindow(window)
	return window
end


function setStaticIP(self)
	log:warn("setStaticIP addr=", self.ipAddress, " subnet=", self.ipSubnet, " gw=", self.ipGateway, " dns=", self.ipDNS)

	Task("networkStatic", self,
	     function()
		     self.t_ctrl:t_setStaticIP(self.ssid, self.ipAddress, self.ipSubnet, self.ipGateway, self.ipDNS)
		     connectOK(self)
	     end):addTask()
end


function t_removeNetwork(self, ssid)
	self.t_ctrl:t_removeNetwork(ssid)

	if self.scanResults[ssid] then
		-- remove from menu
		local item = self.scanResults[ssid].item
		self.scanMenu:removeItem(item)

		-- clear entry
		self.scanResults[ssid] = nil
	end
end


function removeNetwork(self, ssid)
	-- forget the network
	Task("networkRemove", self, t_removeNetwork):addTask(ssid)

	-- popup confirmation
	local window = Popup("popupIcon")
	window:addWidget(Icon("iconConnected"))

	local text = Label("text", self:string("NETWORK_FORGOTTEN_NETWORK", ssid))
	window:addWidget(text)

	self:tieWindow(window)
	window:showBriefly(2000, function() _hideToTop(self) end)

	return window
end


function connectOrDelete(self, ssid)
	local window = Window("window", ssid, wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("NETWORK_CONNECT_TO_NETWORK"), nil,
						sound = "WINDOWSHOW",
						callback = function()
								   self.ssid = ssid
								   connect(self)
							   end
					},
					{
						text = self:string("NETWORK_FORGET_NETWORK"), nil,
						sound = "WINDOWSHOW",
						callback = function()
								   deleteConfirm(self, ssid)
							   end
					},
				})

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function deleteConfirm(self, ssid)
	local window = Window("window", self:string("NETWORK_FORGET_NETWORK"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("NETWORK_FORGET_CANCEL"), nil,
						sound = "WINDOWHIDE",
						callback = function()
								   window:hide()
							   end
					},
					{
						text = self:string("NETWORK_FORGET_CONFIRM", ssid), nil,
						sound = "WINDOWSHOW",
						callback = function()
								   removeNetwork(self, ssid)
							   end
					},
				})

	window:addWidget(Textarea("help", self:string("NETWORK_FORGET_HELP", ssid)))
	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


local stateTxt = {
	[ "DISCONNECTED" ] = "NETWORK_STATE_DISCONNECTED",
	[ "INACTIVE" ] = "NETWORK_STATE_DISCONNECTED",
	[ "SCANNING" ] = "NETWORK_STATE_SCANNING",
	[ "ASSOCIATING" ] = "NETWORK_STATE_CONNECTING",
	[ "ASSOCIATED" ] = "NETWORK_STATE_CONNECTING",
	[ "4WAY_HANDSHAKE" ] = "NETWORK_STATE_HANDSHAKE",
	[ "GROUP_HANDSHAKE" ] = "NETWORK_STATE_HANDSHAKE",
	[ "COMPLETED" ] = "NETWORK_STATE_CONNECTED",
}


function t_networkStatusTimer(self, values)
	local status = self.t_ctrl:t_wpaStatus()

	local snr = self.t_ctrl:getSNR()
	local bitrate = self.t_ctrl:getTxBitRate()

	local wpa_state = stateTxt[status.wpa_state] or "NETWORK_STATE_UNKNOWN"

	local encryption = status.key_mgmt
	-- white lie :)
	if string.match(status.pairwise_cipher, "WEP") then
		encryption = "WEP"
	end

	-- update the ui
	values[1]:setValue(self:string(wpa_state))
	values[2]:setValue(tostring(status.ssid))
	values[3]:setValue(tostring(status.bssid))
	values[4]:setValue(tostring(encryption))
	values[5]:setValue(tostring(status.ip_address))
	values[6]:setValue(tostring(snr))
	values[7]:setValue(tostring(bitrate))
end


function networkStatusTimer(self, values)
	Task("networkStatus", self,
	     function()
		     self:t_networkStatusTimer(values)
	     end):addTask()
end


function networkStatusShow(self)
	local window = Window("window", self:string("NETWORK_STATUS"), wirelessTitleStyle)
	window:setAllowScreensaver(false)

	local values = {}
	for i=1,7 do
		values[i] = Label("value", "")
	end

	-- FIXME format this nicely
	local menu = SimpleMenu("menu",
				{
				   { text = self:string("NETWORK_STATE"), icon = values[1] },
				   { text = self:string("NETWORK_SSID"), icon = values[2] },
				   { text = self:string("NETWORK_BSSID"), icon = values[3] },
				   { text = self:string("NETWORK_ENCRYPTION"), icon = values[4] },
				   { text = self:string("NETWORK_IP_ADDRESS"), icon = values[5] },
				   { text = self:string("NETWORK_SNR"), icon = values[6] },
				   { text = self:string("NETWORK_BITRATE"), icon = values[7] },

				   {
					   text = self:string("NETWORK_FORGET_NETWORK"), nil,
					   sound = "WINDOWSHOW",
					   callback = function()
							      deleteConfirm(self, self.currentSSID)
						      end
				   },
				})
	window:addWidget(menu)

	self:networkStatusTimer(values)
	window:addTimer(1000, function()
				      self:networkStatusTimer(values)
			      end)

	self:tieAndShowWindow(window)
	return window
end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]
