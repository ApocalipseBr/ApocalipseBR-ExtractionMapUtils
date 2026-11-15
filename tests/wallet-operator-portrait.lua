local root='ApocalipseBR-Wallet/common/media/lua/'
package.path=root..'shared/?.lua;'..root..'client/?.lua;'..package.path
local checks,now,loads=0,1000,0
local function check(ok,message) checks=checks+1; assert(ok,message) end
function getTimestampMs() return now end
local available={shots_00=true,shots_03=true,shots_12=true,single_00=true}
function getTexture(path)
    loads=loads+1
    local name=path:match('/([^/]+)%.png$')
    return available[name] and name or nil
end
local function window()
    return {drawRect=function() end,drawTextureScaled=function(self,tex) self.lastTexture=tex end}
end
local Portrait=require 'ApocWallet/OperatorPortrait'
local ui=window()
local function draw(prefix,state,talkingUntil,target)
    target=target or ui
    target.lastTexture=nil
    Portrait.draw(target,0,0,50,60,state or 'connected',talkingUntil or 0,{texturePrefix=prefix})
    return target.lastTexture
end
check(draw('shots_',nil,100000)=='shots_00','contact begins with first snapshot')
now=5999
check(draw('shots_',nil,100000)=='shots_00','speech holds snapshot for at least five seconds')
now=6000
check(draw('shots_',nil,100000)=='shots_03','speech advances to next available snapshot at hold boundary')
check(draw('shots_',nil,100000)=='shots_03','repeated render does not advance snapshot')
now=12000
check(draw('shots_')=='shots_03','silence retains current snapshot instead of resetting')
check(draw('shots_',nil,14000)=='shots_12','next reply advances after minimum hold')
now=60000
check(draw('shots_',nil,62000)=='shots_00','long render gap advances once and wraps available snapshots')
check(loads==16,'snapshot textures are cached across renders')
local other=window()
check(draw('shots_',nil,62000,other)=='shots_00','another radio window starts independently')
now=65000
check(draw('shots_',nil,67000)=='shots_03','first window keeps its own cadence')
check(draw('single_',nil,67000)=='single_00','operator switch starts with new operator snapshot')
now=90000
check(draw('single_',nil,92000)=='single_00','single-photo operator stays visible')
check(draw('missing_',nil,92000)==nil,'missing photo set renders without an error')
check(draw('shots_','tuning')==nil and not ui.walletOperatorSnapshot,'disconnected state clears portrait progression')
check(draw('shots_',nil,92000)=='shots_00','reconnection starts a fresh snapshot hold')
print('Passed '..checks..' operator portrait snapshot checks.')
