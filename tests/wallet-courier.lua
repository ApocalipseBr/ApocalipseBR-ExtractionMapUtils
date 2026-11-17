local root='ApocalipseBR-Wallet/common/media/lua/'
-- Match the deployed Kahlua globals. Standard Lua's next() concealed a startup failure.
next=nil
package.path=root..'shared/?.lua;'..root..'server/?.lua;'..package.path
local checks,time,saves,packets,world,loaded,created=0,100000,0,{}, {},true,0
local randomBounds={}
local function check(v,m) checks=checks+1; assert(v,m) end
function isClient() return false end
function getTimestampMs() return time end
function ZombRand(lo,hi) randomBounds[#randomBounds+1]={lo,hi}; return lo+10000 end
local persisted={}
local failSave,storeAvailable=false,true
package.loaded['ApocWallet/EntityStore']={data=function() return persisted end,ready=function() return storeAvailable end,
 modData=function(kind,id) persisted.itemData=persisted.itemData or {}; persisted.itemData[kind..id]=persisted.itemData[kind..id] or {}; return persisted.itemData[kind..id] end,
 persist=function() if failSave then error('PERSISTENCE_WRITE_FAILED') end; saves=saves+1 end,
 run=function(_,fn,onError) local ok,err=pcall(fn); if not ok then if onError then onError(err) else error(err) end end end}
ModData={getOrCreate=function() return persisted end}
ApocBrApiBridge={}
local recipients={}
function sendServerCommand(player,module,command,args)
    assert(type(player)=='table','courier packets must target individual nearby clients or the owner')
    packets[#packets+1]={module,command,args}
    recipients[#recipients+1]=player
end
local function list(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
local nearby={getX=function() return 10 end,getY=function() return 20 end,getUsername=function() return 'spectator' end}
local farX={getX=function() return 1000 end,getY=function() return 20 end,getUsername=function() return 'far-x' end}
local farY={getX=function() return 10 end,getY=function() return 1000 end,getUsername=function() return 'far-y' end}
local online={nearby,farX,farY}
function getOnlinePlayers() return list(online) end
local square={getX=function() return 10 end,getY=function() return 20 end,getZ=function() return 0 end}
function square:getWorldObjects() return list(world) end
local failCreate=false
local failAt
function instanceItem(fullType)
    if failCreate or failAt and created>=failAt then return nil end
    created=created+1
    local item={type=fullType,md={}}
    function item:getID() return created end
    function item:getModData() return self.md end
    function item:getWorldItem() return self.world end
    return item
end
function square:AddWorldInventoryItem(item)
    local object={getItem=function() return item end}
    item.world=object; world[#world+1]=object; return item
end
local cell={}
function cell:getGridSquare(x,y,z)
    if not loaded then return nil end
    if x==10 and y==20 then return square end
    return {isSolid=function() return false end,isBlockedTo=function() return false end,
        isDoorBlockedTo=function() return false end,isWindowTo=function() return false end}
end
function square:isSolid() return false end
function square:isBlockedTo() return false end
function square:isDoorBlockedTo() return false end
function square:isWindowTo() return false end
function getCell() return cell end
local loads=0
ApocBRLobbyStreaming={keepCellLoaded=function() loads=loads+1 end}
ScriptManager={instance={getItem=function(_,id) return id~='Bad.Item' end}}
local C=require 'ApocWallet/CourierService'
local destination={x=10,y=20,z=0}
local goods={{type='Base.Axe',count=2}}
local id=C.delivery('alice','receipt1',destination,goods)
check(id and saves>0,'durable job before dispatch')
check(persisted.jobs[id].due-time>=30000 and persisted.jobs[id].due-time<=90000,'ETA bounds')
check(randomBounds[1][1]==30000 and randomBounds[1][2]==90001,'dropoff ETA range unchanged')
destination.x=99; goods[1].count=99
check(persisted.jobs[id].x==10 and persisted.jobs[id].items[1].count==2,'snapshots immutable to caller')
check(C.delivery('alice','receipt1',{x=10,y=20,z=0},{{type='Base.Axe',count=2}})==id,'receipt replay idempotent')
check(C.delivery('alice','receipt2',{x=10,y=20,z=0},{{type='Base.Hammer',count=1}})==id,'multiple purchases one drone')
check(not C.delivery('alice','bad',{x=1.5,y=1,z=0},{{type='Base.Axe',count=1}}),'reject fractional square')
time=persisted.jobs[id].due-8000
loaded=false; C.update()
check(loads==1 and #world==0,'offline unloaded square requested without early cargo')
loaded=true; time=time+250; C.update()
check(#persisted.jobs[id].path>1 and #world==0,'approach starts before cargo')
check(#packets==1 and packets[1][2]=='CourierFlight' and recipients[1]==nearby,'one approach event targets only nearby X/Y recipients')
time=persisted.jobs[id].due; failCreate=true; C.update()
check(#world==0 and persisted.jobs[id].state=='waiting','failed creation retained for retry')
failCreate=false; failAt=1; time=time+250; C.update()
check(#world==1 and persisted.jobs[id].placed==1 and persisted.jobs[id].state=='waiting','partial delivery progress saved')
-- Simulate recovery where a tagged object reached the square before progress saved.
persisted.jobs[id].placed=0
failAt=nil; time=time+250; C.update()
check(#world==3 and persisted.jobs[id].state=='departing','offline ground delivery on saved square')
local deliveryManifest
for _,p in ipairs(packets) do if p[2]=='CourierTransmission' then deliveryManifest=p[3] end end
check(deliveryManifest and #deliveryManifest.lines==2,'batched dropoff has separate cargo entries')
check(deliveryManifest.lines[1].code==ApocWallet.MarketProtocol.code('Base.Axe') and deliveryManifest.lines[1].count==2,'dropoff codes and quantities derived server-side')
check(not deliveryManifest.lines[1].blob and not deliveryManifest.lines[1].type,'cosmetic manifest has no item blobs or type payload')
local flightCount=0
for i,p in ipairs(packets) do
    if p[2]=='CourierFlight' then flightCount=flightCount+1 end
    check(recipients[i]==nearby,'distant players receive neither flight nor manifest')
end
check(flightCount==1,'handoff uses the original visual schedule without a second flight packet')
time=time+250; C.update(); check(#world==3,'no repeat on next tick')
-- Simulated Lua reload keeps durable receipts and progress, no online player.
package.loaded['ApocWallet/CourierService']=nil
ApocWallet.CourierService=nil
C=require 'ApocWallet/CourierService'; C.update()
check(#world==3,'restart retains placement progress')
check(packets[#packets][2]=='CourierFlight','restart resumes a persisted active flight with one nearby event')
time=time+10000; C.update(); check(persisted.jobs[id]==nil and persisted.finished[id],'departure completed and active job retired')
local removed=0
local inv={getOutermostContainer=function(self) return self end}
function inv:DoRemoveItem(item) removed=removed+1; item.container=nil end
function sendRemoveItemFromContainer() end
local player={getUsername=function() return 'alice' end,isDead=function() return false end,
    getCurrentSquare=function() return square end,getInventory=function() return inv end,isEquipped=function() return false end}
local function inventoryItem(id,fullType)
    local item={container=inv}
    function item:getContainer() return self.container end
    function item:getID() return id end
    function item:getFullType() return fullType or 'Base.Axe' end
    return item
end
ApocBrApiBridge={encodeItem=function(item) return 'native-save-'..item:getID() end}
ApocBRModEntities={character=function() return {status='OK',characterId='12345678-1234-4234-8234-123456789abc',
    steamId='76561198000000001',sourceServerId=2} end}
local pickup=C.pickup(player,'post1',{inventoryItem(1)})
check(pickup and removed==1,'pickup immediately removes inventory item')
check(randomBounds[#randomBounds][1]==10000 and randomBounds[#randomBounds][2]==30001,'pickup ETA is 10 to 30 seconds inclusive')
check(persisted.escrow['pickup:12345678-1234-4234-8234-123456789abc:post1'].state=='held','pickup exact item blob in persistent custody')
local pickup2=C.pickup(player,'post2',{inventoryItem(2)})
check(pickup2==pickup and removed==2,'pickup batch uses single drone')
check(C.pickup(player,'post1',{inventoryItem(1)})==pickup and removed==2,'pickup replay cannot remove twice')
check(C.pickup(player,'post3',{inventoryItem(3,'Base.Hammer')})==pickup and removed==3,'different cargo types share pickup flight')
local before=#world
time=persisted.jobs[pickup].due; C.update()
check(#world==before,'pickup animation never creates cargo')
local pickupManifest,flight
for _,p in ipairs(packets) do
    if p[2]=='CourierTransmission' and p[3].id==pickup then pickupManifest=p[3] end
    if p[2]=='CourierFlight' and p[3].id==pickup then flight=p[3] end
end
check(pickupManifest and #pickupManifest.lines==2 and pickupManifest.lines[1].count==2,'pickup manifest combines accepted batches without replay duplicates')
check(flight.hover==3000 and flight.approach==8000 and flight.depart==8000,'pickup waits one extra second and traverses farther in the same time')
local transmissions=0
for _,p in ipairs(packets) do if p[2]=='CourierTransmission' then transmissions=transmissions+1 end end
time=time+250; C.update()
local afterTransmissions=0
for _,p in ipairs(packets) do if p[2]=='CourierTransmission' then afterTransmissions=afterTransmissions+1 end end
check(afterTransmissions==transmissions,'updates do not replay cargo announcements')
-- Purchase API succeeds after disconnect and moving the original player.
ApocBRModEntities={character=function() return {status='OK',characterId='12345678-1234-4234-8234-123456789abc',
    steamId='76561198000000001',sourceServerId=2} end}
local callbacks,requests={},{}
ApocBrApiBridge.CHARACTER_DEBIT='DEBIT'
ApocBrApiBridge.isEnabled=function() return true end
ApocBrApiBridge.request=function(endpoint,params,callback)
    local key='request'..tostring(#requests+1); requests[#requests+1]=params; callbacks[key]=callback; return key
end
local P=require 'ApocWallet/PurchaseService'
time=time+1000
local orderId=P.buy(player,'buy1',{amount=10,reason='market.purchase',items={{type='Base.Axe',count=1}}})
check(orderId and #requests==1,'purchase calls API')
check(#world==before,'no delivery before debit success')
player.getCurrentSquare=function() return nil end
callbacks.request1({requestId='request1',ok=true,idempotencyKey=orderId,transactionId='tx1',balance=90})
time=time+1000; P.update()
local order=persisted.purchases[orderId]
check(order.state=='fulfilled' and persisted.jobs[order.jobId].x==10,'callback after disconnect retains purchase square')
local jobCount=0; for _ in pairs(persisted.jobs) do jobCount=jobCount+1 end
callbacks.request1({requestId='request1',ok=true,idempotencyKey=orderId,transactionId='tx1'})
P.update()
local afterCount=0; for _ in pairs(persisted.jobs) do afterCount=afterCount+1 end
check(jobCount==afterCount,'duplicate callback cannot queue second delivery')
player.getCurrentSquare=function() return square end
time=time+1000
local failed=P.buy(player,'buy2',{amount=10,reason='market.purchase',items={{type='Base.Axe',count=1}}})
callbacks.request2({requestId='request2',ok=false,status=402,error='HTTP_402'})
check(persisted.purchases[failed].state=='failed' and not persisted.purchases[failed].jobId,'rejected debit creates no delivery')
-- Lost response and Lua reload replay the exact debit body/key.
time=time+1000
local retry=P.buy(player,'buy3',{amount=10,reason='market.purchase',items={{type='Base.Axe',count=1}}})
local firstBody=requests[3]
check(firstBody:find('idempotencyKey',1,true),'stable key sent to backend')
package.loaded['ApocWallet/PurchaseService']=nil
ApocWallet.PurchaseService=nil
P=require 'ApocWallet/PurchaseService'
time=time+71000; P.update()
check(requests[4]==firstBody,'restart replays identical debit body after uncertain result')
callbacks.request3({requestId='request3',ok=true,idempotencyKey=retry,transactionId='tx3'})
check(persisted.purchases[retry].state=='pending','stale attempt cannot finish a newer attempt')
callbacks.request4({requestId='request4',ok=true,idempotencyKey=retry,transactionId='tx3'})
time=time+1000; P.update()
check(persisted.purchases[retry].state=='fulfilled','matching replay receipt schedules delivery')
online={}
persisted.jobs={}
local unattended=C.delivery('alice','unattended',{x=10,y=20,z=0},{{type='Base.Axe',count=1}})
local groundBefore,packetsBefore=#world,#packets
time=persisted.jobs[unattended].due
C.update()
check(#world==groundBefore+1 and persisted.jobs[unattended].state=='departing','server fulfills delivery with no connected clients')
check(#packets==packetsBefore,'an empty relevance area generates no courier network packets')
-- Restart recovery runs on the server even when clients send no commands.
persisted.jobs={}
local recoveryItem=inventoryItem(99)
function inv:getItemById(id) if id==99 then return recoveryItem end end
persisted.escrow.restart={owner='alice',characterId='12345678-1234-4234-8234-123456789abc',
    state='removing',items={{itemId=99,blob='native-save-99',type='Base.Axe'}}}
package.loaded['ApocWallet/CourierService']=nil
ApocWallet.CourierService=nil
C=require 'ApocWallet/CourierService'
time=time+5000; C.update()
check(persisted.escrow.restart.state=='removing','offline pickup recovery waits for its owner')
online={player}
local identityReady=false
ApocBRModEntities.character=function()
    return {status=identityReady and 'OK' or 'IDENTITY_PENDING',characterId='12345678-1234-4234-8234-123456789abc'}
end
time=time+5000; C.update()
check(persisted.escrow.restart.state=='removing','server recovery waits for authoritative identity')
identityReady=true
local beforeRecovery=removed
time=time+5000; C.update()
check(persisted.escrow.restart.state=='held' and removed==beforeRecovery+1,'server recovers interrupted escrow without a client sync')
local onlineScans=0
function getOnlinePlayers() onlineScans=onlineScans+1; return list(online) end
time=time+5000; C.update()
check(onlineScans==0 and removed==beforeRecovery+1,'completed recovery does not keep scanning online players')
local handlers={}
function isServer() return true end
Events={OnClientCommand={Add=function() error('courier must not register a client polling handler') end},
    OnTick={Add=function(fn) handlers.tick=fn end},OnTickEvenPaused={Add=function(fn) handlers.paused=fn end}}
require 'ApocWallet/CourierController'
check(handlers.tick and handlers.paused and C.sync==nil,'controller keeps autonomous fulfillment and removes sync command routing')
print('Passed '..checks..' wallet courier persistence, batching, pickup, offline streaming and purchase checks.')
