
--[[
=head1 NAME

applets.SlimBrowser.SlimBrowserMeta - SlimBrowser meta-info

=head1 DESCRIPTION

See L<applets.SlimBrowser.SlimBrowserApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local utilLog       = require("jive.utils.log")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end


function registerApplet(self)
	
	-- SlimBrowser uses its an extra log category
	utilLog.logger("applet.SlimBrowser.data")

	self:registerService('goHome')
	self:registerService('showTrackOne')
	self:registerService('showPlaylist')
	self:registerService('setPresetCurrentTrack')
	self:registerService('squeezeNetworkRequest')

	self:registerService('browserJsonRequest')
	self:registerService('browserActionRequest')
	self:registerService('browserCancel')
	self:registerService('getAudioVolumeManager')

	appletManager:loadApplet("SlimBrowser")

end


--[[

=head1 LICENSE

Copyright 2007 Logitech. All Rights Reserved.

This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.

=cut
--]]

