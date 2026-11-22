local root='ApocalipseBR-Wallet/common/media/lua/'
package.path=root..'shared/?.lua;'..root..'client/?.lua;'..package.path
local checks,time,packets,said,heard,sounds,stops=0,100000,{},{},{},{},{}
local function check(v,m) checks=checks+1; assert(v,m) end
local function event() return {Add=function() end} end
Events={OnServerCommand=event(),OnTick=event(),OnDisconnect=event()}
function isServer() return false end
function isClient() return true end
function getTimestampMs() return time end
function instanceof(o,k) return o and (o.kind==k or k=='InventoryItem' and o.item) end
function getText(key,...)
    local out=key
    for _,a in ipairs({...}) do out=out..' '..tostring(a) end
    return out
end
UIFont={Small=1}
local measures=0
function getTextManager() return {MeasureStringX=function(_,_,text) measures=measures+1; return #text*6 end} end
local textures,texturePaths=0,{}
function getTexture(path) textures=textures+1; texturePaths[path]=true; return {path=path} end
function sendClientCommand(player,module,command,args) packets[#packets+1]={player=player,command=command,args=args} end
local inv={}; function inv:getOutermostContainer() return self end
local radio={item=true,getContainer=function() return inv end,getID=function() return 99 end}
function radio:AddDeviceText(text) heard[#heard+1]=text end
local emitter={playSound=function(_,name) sounds[#sounds+1]=name; return #sounds end,stopSound=function(_,id) stops[id]=true end}
local sq={getX=function() return 1200 end,getY=function() return 3400 end,getZ=function() return 0 end}
local player={getPlayerNum=function() return 0 end,getOnlineID=function() return 7 end,getCurrentSquare=function() return sq end,
    getInventory=function() return inv end,isDead=function() return false end,getEmitter=function() return emitter end}
function player:Say(text) said[#said+1]=text end
local win={player=player,radio=radio,playerIndex=0}
local Client=require 'ApocWallet/MarketClient'
local s=Client.open(win)
Client.tune(s)
check(s.state=='tuning' and #packets==1 and packets[1].command=='MarketTune','explicit tune begins channel request')
check(packets[1].args.radio.itemId==99,'native device locator sent')
check(sounds[1]=='ApocWallet_Static','ported static while tuning')
Client.receive({onlineId=8,token=s.pending.token,ok=true,kind='page',mode='market',page=1,pages=2,rows={}})
check(s.state=='tuning' and not s.deferred,'other local player packet ignored')
local iron={key='iron_echo',name='IRON ECHO',gender='female',texturePrefix='ironcontrol_'}
Client.receive({onlineId=7,token=s.pending.token,ok=true,kind='page',mode='market',page=1,pages=2,rows={},
    operator=iron,gossip='Aqui IRON ECHO. Boletim MER-001 autorizado.'})
Client.update()
check(s.state=='tuning' and #said==1 and said[1]:find('S012%-034%-N0'),'deterministic sector spoken while tuning')
time=time+1800; Client.update()
check(s.state=='connected' and stops[1],'tune waits for handshake and stops static')
time=time+1400; Client.update()
check(#heard==1 and heard[1]=='Aqui IRON ECHO. Boletim MER-001 autorizado.','server-selected text emitted verbatim through native radio')
check(s.operator==iron and s.dialogue.history[#s.dialogue.history].name=='IRON ECHO','operator identity accompanies transcript lines')
local dialogue=s.dialogue
local before=#dialogue.queue
Client.page(s,'market',2)
check(#dialogue.queue==before+1,'page request speaks only the player until a reply arrives')
check(dialogue.queue[#dialogue.queue].args[1]=='IRON ECHO' and dialogue.queue[#dialogue.queue].args[2]=='MER-002','player requests address operator and coded bulletin')
local firstToken=s.pending.token
Client.receive({onlineId=7,token=firstToken,ok=true,kind='page',mode='market',page=2,pages=2,rows={}})
check(#dialogue.queue==before+2,'operator acknowledges the successful page response')
time=time+400
Client.page(s,'market',1)
check(#dialogue.queue==before+2,'rapid page navigation does not add gossip')
Client.receive({onlineId=7,token=s.pending.token,ok=true,kind='page',mode='market',page=1,pages=2,rows={}})
local row={id='3',name='Axe',price=30,code='CARGA-01234',count=2,ids={1,2}}
Client.post(s,row,2,30)
local postToken=s.pending.token
check(packets[#packets].command=='MarketPost' and packets[#packets].args.price==30,'posting uses selected inventory IDs and seller terms')
local noticeCount=#s.dialogue.queue
Client.receive({onlineId=7,token=postToken,ok=false,error='STORAGE'})
check(s.pending and s.pending.token==postToken,'temporary recording failure preserves the original post intent')
check(#s.dialogue.queue==noticeCount+1,'temporary recording failure gets its own operator message')
Client.receive({onlineId=7,token=postToken,ok=false,error='STORAGE'})
check(#s.dialogue.queue==noticeCount+1,'repeated storage failures do not spam the channel')
local countPackets=#packets
time=time+10001; Client.update()
check(#packets==countPackets+1 and packets[#packets].args.token==postToken,'lost post acknowledgment reuses token')
Client.receive({onlineId=7,token=postToken,ok=true,kind='posted',code=row.code,count=2})
check(s.needsRefresh,'confirmed post schedules bulletin refresh')
time=time+350
Client.update()
Client.receive({onlineId=7,token=s.pending.token,ok=true,kind='page',mode='market',page=1,pages=1,rows={row}})
Client.buy(s,row,1)
local buyToken=s.pending.token
check(packets[#packets].command=='MarketBuy' and not packets[#packets].args.price,'buyer never sends a price')
Client.receive({onlineId=7,token=buyToken,ok=true,kind='reserved',transaction='tx1'})
check(s.transaction=='tx1','reserved purchase stays pending')
time=time+2501; Client.update()
check(s.pending.command=='MarketStatus','purchase result polled silently')
Client.receive({onlineId=7,token=s.pending.token,ok=true,kind='bought',jobId='courier1'})
check(not s.transaction and s.needsRefresh,'delivery acknowledgment only after authoritative completion')
local etaCount=#s.dialogue.queue
Client.courierETA({onlineId=7,id='courier1',kind='delivery',seconds=45})
Client.courierETA({onlineId=7,id='courier1',kind='delivery',seconds=30})
check(#s.dialogue.queue==etaCount+1,'ETA refresh does not repeatedly speak')
-- Attach the real market panel to mocked native widgets.
package.loaded['ISUI/ISScrollingListBox']=true; package.loaded['ISUI/ISContextMenu']=true; package.loaded['ISUI/ISButton']=true; package.loaded['ISUI/ISTextBox']=true
local function widget()
    local w={}
    for _,field in ipairs({'X','Y','Width','Height','Title','Tooltip','Enable'}) do w['set'..field]=function(self,v) self[field]=v end end
    function w:initialise() end; function w:instantiate() end
    return w
end
ISButton={new=function(_,x,y,w,h,title,target,onclick) local b=widget(); b.onclick=onclick; return b end}
ISScrollingListBox={new=function()
    local w=widget(); w.items={}; w.width=100; w.height=100; w.scroll=0
    function w:setWidth(v) self.width=v end
    function w:setHeight(v) self.height=v end
    function w:getHeight() return self.height end
    function w:getYScroll() return self.scroll end
    function w:setYScroll(v) self.scroll=v end
    function w:getScrollHeight() return #self.items*(self.itemheight or 16) end
    function w:clear() self.items={} end
    function w:addItem(text,item) self.items[#self.items+1]={text=text,item=item} end
    return w
end}
local modal
ISTextBox={new=function(_,x,y,w,h,text,default,target,callback)
    modal={entry={setOnlyNumbers=function() end,getText=function() return modal.value or '1' end},target=target,callback=callback,
        initialise=function() end,addToUIManager=function() end}; return modal
end}
win.fontHeight=14; win.L=require 'ApocWallet/UI/RadioLayout'; win.L=win.L.walkie
function win:R(r) return r[1],r[2],r[3],r[4] end
function win:getX() return 0 end; function win:getY() return 0 end
function win:addChild() end; function win:nextSkin() self.skinChanged=true end
function win:layout() end; function win:setBalanceState() end
win.refreshButton=widget(); win.skinButton=widget(); win.walletCloseButton=widget()
win.list={items={},width=450}
function win.list:clear() self.items={} end
function win.list:addItem(name,row) self.items[#self.items+1]={item=row} end
for _,method in ipairs({'drawText','drawTextCentre','drawRect','drawTextureScaled'}) do win[method]=function() end end
win.actions={refresh=function() end}
local menuOptions,menuPosition
local mouseX,mouseY=1250,740
function getMouseX() return mouseX end
function getMouseY() return mouseY end
ISContextMenu={get=function(index,x,y)
    menuPosition={playerIndex=index,x=x,y=y}
    menuOptions={}
    return {addOption=function(_,label,target,fn) menuOptions[#menuOptions+1]={label=label,target=target,fn=fn} end}
end}
local Panel=require 'ApocWallet/UI/MarketPanel'
Panel.attach(win)
check(win.marketPrev and win.marketNext and win.marketRefresh,'six physical keys have market controls')
s.pending=nil; s.needsRefresh=nil; s.rows={row}; s.mode='market'; row.name='Axe'; row.price=30
Panel.populate(win)
Panel.action(win)
modal.callback(win,{internal='OK',parent=modal})
check(s.pending and s.pending.command=='MarketBuy','main key quantity dialog submits purchase')
s.pending=nil
local beforeMeasure=measures
Panel.render(win); Panel.render(win)
check(measures==beforeMeasure,'market render performs no text measurement or network work')
check(textures==16,'ported operator frames cached once')
check(texturePaths['media/textures/ApocWallet/operator/ironcontrol_00.png'] and texturePaths['media/textures/ApocWallet/operator/ironcontrol_15.png'],'selected female portrait uses the full ironcontrol sequence')
check(win.marketOperatorDisplay=='IRON ECHO','operator name replaces generic display label')
local Portrait=require 'ApocWallet/OperatorPortrait'
Portrait.draw(win,0,0,50,60,'connected',0,{texturePrefix='control_'})
Portrait.draw(win,0,0,50,60,'connected',0,iron)
check(textures==32 and texturePaths['media/textures/ApocWallet/operator/control_00.png'],'portrait caches both operators independently')
s.pending=nil; s.transaction=nil; s.nextNavigation=0
Panel.menu(win)
check(#menuOptions==5,'menu offers market, inventory, expired stock, search and clear')
check(menuPosition.playerIndex==win.playerIndex and menuPosition.x==mouseX and menuPosition.y==mouseY,
    'menu opens at screen cursor instead of radio window corner')
menuOptions[4].fn()
modal.value='aXe'
modal.callback(win,{internal='OK',parent=modal})
check(s.pending.args.query=='aXe' and s.pending.args.page==1,'name search requests first filtered server page')
Client.receive({onlineId=7,token=s.pending.token,ok=true,kind='page',mode='expired',query='aXe',page=1,pages=2,rows={row}})
time=time+500; Client.page(s,'expired',2)
check(s.pending.args.query=='aXe','filter preserved across page navigation')
s.pending=nil; s.mode='expired'; s.rows={row}; Panel.populate(win)
mouseX,mouseY=1870,1030
Panel.action(win)
check(#menuOptions==2,'expired item offers recovery and repost')
check(menuPosition.playerIndex==win.playerIndex and menuPosition.x==mouseX and menuPosition.y==mouseY,
    'expired actions use current cursor position after mouse moves')
menuOptions[2].fn()
check(s.pending.command=='MarketRepost' and s.pending.args.listingId==row.id,'repost uses authoritative listing id')
local retryToken=s.pending.token
time=time+10001; Client.update()
check(s.pending.token==retryToken,'management retry keeps original token')
Client.receive({onlineId=7,token=retryToken,ok=true,kind='reposted'})
check(s.needsRefresh,'repost acknowledgment refreshes stock')
local refreshPackets=#packets
Client.update()
check(#packets==refreshPackets and s.needsRefresh,'fast repost acknowledgment waits before automatic refresh')
time=time+349; Client.update()
check(#packets==refreshPackets,'refresh stays deferred until navigation cooldown expires')
time=time+1; Client.update()
check(s.pending and s.pending.command=='MarketPage' and s.pending.args.mode=='expired'
    and s.pending.args.query=='aXe' and s.pending.args.page==1 and s.pending.args.silent,
    'automatic repost refresh preserves expired view, page and search silently')
local refreshToken=s.pending.token
local refreshArgs=s.pending.args
local refreshLines=#s.dialogue.queue
Client.receive({onlineId=7,token=refreshToken,ok=false,error='WAIT'})
check(s.pending and s.pending.token==refreshToken,'rate-limited automatic refresh remains pending')
check(#s.dialogue.queue==refreshLines,'automatic refresh backpressure adds no operator chatter')
refreshPackets=#packets
time=time+349; Client.update()
check(#packets==refreshPackets,'automatic refresh retry observes cooldown')
time=time+1; Client.update()
check(#packets==refreshPackets+1 and packets[#packets].args==refreshArgs,
    'automatic refresh retry reuses the same request and token')
Client.receive({onlineId=7,token=refreshToken,ok=true,kind='page',mode='expired',query='aXe',page=1,pages=1,rows={}})
check(not s.pending and #s.rows==0 and #win.list.items==0,'reposted item disappears from expired UI after refresh')
s.rows={row}; Panel.populate(win); Panel.action(win); menuOptions[1].fn()
check(s.pending.command=='MarketRecover','recovery option requests courier return')
check(s.dialogue.queue[#s.dialogue.queue].args[2]==row.code and s.dialogue.queue[#s.dialogue.queue].args[3]:find('EXP%-001'),'expired management transmits cargo and coded page')
Client.receive({onlineId=7,token=s.pending.token,ok=false,error='WAIT'})
check(not s.pending,'management WAIT does not automatically repeat a user action')
Client.manage(s,row,'MarketRecover')
Client.receive({onlineId=7,token=s.pending.token,ok=true,kind='recovered'})
time=time+350; Client.update()
check(s.pending and s.pending.command=='MarketPage','recovery still schedules automatic refresh')
Client.receive({onlineId=7,token=s.pending.token,ok=true,kind='page',mode='expired',query='aXe',page=1,pages=1,rows={}})
check(not s.pending and #s.rows==0,'recovered item disappears from expired list')
for i=1,30 do s.dialogue:record(i%2==0 and 'operator' or 'player','long message '..i..string.rep(' cargo',20)) end
check(#s.dialogue.history>12 and #win.marketChat.items>30,'transcript preserves all session exchanges and wraps long lines')
check(win.marketChat.scroll<0,'transcript follows latest messages')
win.marketChat.scroll=0
s.dialogue:record('drone','CARGA-12345')
check(win.marketChat.scroll==0,'reading older messages preserves scroll position')
local oldCount=#win.marketChat.items
Panel.layout(win)
check(#win.marketChat.items==oldCount,'layout rewrap keeps complete transcript')
Client.close(s)
check(not Client.sessions[0] and packets[#packets].command=='MarketHangup','closing releases dialogue and channel')
print('Passed '..checks..' market client handshake, coded dialogue, rate limiting, retry, portrait and UI checks.')
