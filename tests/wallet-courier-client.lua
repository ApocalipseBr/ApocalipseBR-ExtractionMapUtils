local root='ApocalipseBR-Wallet/common/media/lua/'
package.path=root..'shared/?.lua;'..root..'client/?.lua;'..package.path
local checks,time,draws=0,1000,{}
local function check(v,m) checks=checks+1; assert(v,m) end
local function event()
    local callbacks={}
    return {Add=function(fn) callbacks[#callbacks+1]=fn end,
        fire=function(...) for _,fn in ipairs(callbacks) do fn(...) end end}
end
Events={OnServerCommand=event(),OnPostRender=event(),OnTick=event(),OnDisconnect=event()}
function isServer() return false end
function getTimestampMs() return time end
function getText(key,...) local text=key; for _,arg in ipairs({...}) do text=text..':'..arg end; return text end
require 'ApocWallet/Protocol'
package.loaded['ApocWallet/DroneRenderer']={draw=function(...) draws[#draws+1]={...} end}
local C=require 'ApocWallet/CourierClient'
C.receive('CourierFlight',{id='1',kind='delivery',path={{x=0,y=0},{x=12,y=0}},z=2,
    due=100000,serverNow=92000,approach=8000,hover=2000,depart=8000})
C.render()
check(draws[1][1]==0 and draws[1][3]==2,'client/server clocks aligned at approach start')
time=5000; C.render(); check(draws[2][1]==6,'approaches destination smoothly')
time=9000; C.render(); check(draws[3][1]==12,'arrives at server handoff time')
time=11000; C.render(); check(draws[4][1]==12,'hover then departure')
time=15000; C.render(); check(draws[5][1]==6,'flies away along route')
time=19000; C.render(); check(C.flights['1']==nil and #draws==5,'render removed after departure')
C.receive('CourierETA',{id='1',kind='delivery',seconds=42,onlineId=7})
check(C.latestFor({getOnlineID=function() return 7 end}):find('42',1,true),'radio arrival message')
check(not C.latestFor({getOnlineID=function() return 8 end}),'ETA belongs to the targeted local player')
local Route=require 'ApocWallet/CourierRoute'
local cell={}
function cell:getGridSquare(x,y)
    return {isSolid=function() return false end,isBlockedTo=function(_,next) return false end,
        isDoorBlockedTo=function() return false end,isWindowTo=function() return false end}
end
local path=Route.plan(cell,5,5,0)
check(#path==25 and path[#path].x==5.5,'bounded grid path reaches saved destination')
local openSquare=cell.getGridSquare
function cell:getGridSquare(x,y)
    if math.abs(x-5)+math.abs(y-5)>12 then return nil end
    return openSquare(self,x,y)
end
local shorter,shortVertical=Route.plan(cell,5,5,0)
check(#shorter==13 and not shortVertical,'limited loaded area preserves shorter horizontal route')
function cell:getGridSquare(x,y)
    return {isSolid=function() return false end,isBlockedTo=function() return true end,
        isDoorBlockedTo=function() return false end,isWindowTo=function() return false end}
end
local enclosed,vertical=Route.plan(cell,5,5,0)
check(vertical and enclosed[1].x==enclosed[2].x,'enclosed square uses vertical visual instead of crossing walls')
local speech,audio,records,captions={}, {}, {}, {}
UIFont={Small=1}
TextDrawObject={new=function() return {ReadString=function(_,_,text) speech[#speech+1]=text end,
    Draw=function(_,x,y) captions[#captions+1]={x,y} end} end}
function getWorld() return {getFreeEmitter=function(_,x,y,z)
    audio[#audio+1]={x,y,z}; return {playSound=function() end}
end} end
ApocWallet.MarketClient={sessions={{player={getUsername=function() return 'alice' end},
    dialogue={record=function(_,speaker,text) records[#records+1]={speaker,text} end},radio={AddDeviceText=function() end}}}}
local transmission={id='cargo',kind='pickup',owner='alice',x=10,y=20,z=0,
    lines={{code='CARGA-00001',count=2},{code='CARGA-00002',count=1}}}
C.receive('CourierTransmission',transmission)
C.updateTransmissions()
check(#speech==1 and #records==1 and records[1][1]=='drone','first cargo line reaches world bubble and owner chat')
check(audio[1][1]==10 and audio[1][2]==20,'squelch originates at drone position')
time=time+2999; C.updateTransmissions(); check(#speech==1,'first pickup message stays visible for three seconds')
time=time+1; C.updateTransmissions(); check(#speech==2,'separate cargo lines three seconds apart')
C.receive('CourierTransmission',transmission); C.updateTransmissions()
check(#speech==2,'duplicate cosmetic packet cannot repeat manifest')
time=time+2999; C.updateTransmissions(); check(C.transmissions.cargo and C.transmissions.cargo.text,'last pickup message stays visible for three seconds')
time=time+1; C.updateTransmissions(); check(not C.transmissions.cargo,'finished transmission cleaned up after last message')
C.receive('CourierTransmission',{id='drop',kind='delivery',owner='alice',x=1,y=2,z=0,lines={{code='CARGA-00003',count=3}}})
C.updateTransmissions()
check(speech[3]:find('DropoffCargoFmt',1,true),'delivery has its own cargo transmission')
function getNumActivePlayers() return 1 end
function getSpecificPlayer() return {getZ=function() return 0 end,getX=function() return 1 end,getY=function() return 2 end} end
function getCore() return {getZoom=function() return 2 end} end
IsoUtils={XToScreen=function(x) return x*10 end,YToScreen=function(_,y) return y*10 end}
IsoCamera={getOffX=function() return 0 end,getOffY=function() return 0 end,
    getScreenLeft=function() return 100 end,getScreenTop=function() return 200 end}
C.render()
check(captions[1][1]==105 and captions[1][2]==186,'world caption projection respects player viewport and zoom')
time=time+2999; C.updateTransmissions()
check(C.transmissions.drop and C.transmissions.drop.text,'single dropoff message stays visible for three seconds')
time=time+1; C.updateTransmissions()
check(not C.transmissions.drop,'single dropoff message clears after three seconds')
local requests=0
function sendClientCommand() requests=requests+1 end
for i=1,100 do time=time+15000; Events.OnTick.fire() end
check(requests==0,'idle and active clients never poll courier state')
Events.OnDisconnect.fire()
check(next(C.flights)==nil and next(C.transmissions)==nil,'disconnect clears local courier presentation')
print('Passed '..checks..' courier client timing, approach/departure, ETA and path checks.')
