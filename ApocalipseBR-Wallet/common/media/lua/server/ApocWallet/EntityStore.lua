if not isServer() then return end
require 'ApocWallet/Protocol'
local Entities=require 'ApocBR/Entities'
if ApocWallet.EntityStore then return ApocWallet.EntityStore end
local S={queue={},keys={},nextAttempt=0,status='loading',committed={},dirty={},marketVersions={}}
ApocWallet.EntityStore=S
local collections={jobs=true,receipts=true,finished=true,escrow=true,purchases=true,itemData=true,
    ['market.listings']=true,['market.requests']=true,['market.transactions']=true,['market.credits']=true,['market.actions']=true}
local function log(status) if S.lastLog~=status then S.lastLog=status; print('[ApocWallet/Entities] '..status) end end
function S.data() if not S.root then error('PERSISTENCE_NOT_READY') end; return S.root end
function S.ready() return S.status=='ready' and not S.initializing end
function S.sharedMarket() return S.shared==true end
local function bucket(collection)
    if collection=='$' then return S.root end
    if collection=='market.$' then S.root.market=S.root.market or {}; return S.root.market end
    if not collections[collection] then error('UNKNOWN_WALLET_COLLECTION') end
    local name=collection:match('^market%.(.+)$')
    local parent=S.root
    if name then parent.market=parent.market or {}; parent=parent.market else name=collection end
    parent[name]=parent[name] or {}; return parent[name]
end
local function address(collection,key) return collection..'\0'..tostring(key) end
local function encoded(collection,value)
    -- Scheduling and HTTP handles are session state, not business data.
    if type(value)=='table' and (collection=='purchases' or collection=='market.credits') then
        local copy={}
        for k,v in pairs(value) do if k~='requestId' and k~='nextAttempt' and k~='attempts' then copy[k]=v end end
        value=copy
    end
    return Entities.encode({value=value})
end
function S.touch(collection,key)
    if key==nil then error('WALLET_MUTATION_KEY_REQUIRED') end
    key=tostring(key); bucket(collection)
    S.dirty[address(collection,key)]={collection=collection,key=key}
end
function S.modData(kind,id)
    local key=kind..':'..id; local data=bucket('itemData')
    data[key]=data[key] or {kind=kind,objectId=id,values={}}
    S.touch('itemData',key)
    return data[key].values
end
local function restore()
    for id,op in pairs(S.dirty) do
        local payload=S.committed[id]
        if payload then bucket(op.collection)[op.key]=Entities.decode(payload).value
        else bucket(op.collection)[op.key]=nil end
    end
    S.dirty={}
end
local function complete(task,ok,reason)
    S.keys[task.key]=nil; S.active=nil
    if not ok then
        restore()
        if reason=='MARKET_CONFLICT' and S.root.market then
            local market=S.root.market
            market.collecting=nil; market.expiredListings=nil; market.pendingActions=nil
        end
        if task.onError then pcall(task.onError,reason) else log('OPERATION_FAILED '..tostring(reason)) end
    end
    for key in pairs(task.marketAliases or {}) do
        local market=S.root.market
        if market.openListings then market.openListings[key]=nil end
        if market.expiredListings then market.expiredListings[key]=nil end
        bucket('market.listings')[key]=nil
        S.committed[address('market.listings',key)]=nil
        S.marketVersions[key]=nil
    end
end
local function rejectQueued(reason)
    for _,task in ipairs(S.queue) do if task.onError then pcall(task.onError,reason) end end
    S.queue={}; S.keys={}
end
local function resume(task)
    local ok,reason=coroutine.resume(task.thread)
    if not ok then S.status='blocked'; complete(task,false,reason); rejectQueued(reason)
    elseif coroutine.status(task.thread)=='dead' then complete(task,true) end
end
function S.run(key,operation,onError)
    if S.keys[key] then return false end
    if not S.ready() and onError then onError('PERSISTENCE_NOT_READY'); return false end
    if S.status=='blocked' then return false end
    if #S.queue>=128 then if onError then onError('PERSISTENCE_BUSY') end; return false end
    local task={key=key,thread=coroutine.create(operation),onError=onError}
    S.keys[key]=task; S.queue[#S.queue+1]=task
    return true
end
local function save(task)
    task.retryAt=getTimestampMs()+5000; task.inflight=true
    local ok,reason=pcall(function()
        S.repository:mutate(task.revision,task.mutationId,task.operations,function(result)
            task.inflight=false
            if result.status=='OK' then task.ack=result.revision; task.marketVersions=result.marketVersions
            elseif result.status=='MARKET_CONFLICT' then task.marketConflict=true
            elseif result.status~='BUSY' and result.status~='UNAVAILABLE' and result.status~='OUTCOME_UNKNOWN' then
                task.failure='PERSISTENCE_'..tostring(result.status)
            end
            -- Unknown commits replay the identical token/body/revision. SQL
            -- recognizes its last committed mutation without a document read.
        end)
    end)
    if not ok then task.inflight=false; task.failure='PERSISTENCE_'..tostring(reason) end
end
function S.persist(...)
    local task=S.active
    if not task or coroutine.running()~=task.thread then error('PERSISTENCE_TRANSACTION_REQUIRED') end
    local args={...}
    if #args%2~=0 then error('INVALID_WALLET_MUTATION_PATHS') end
    for i=1,#args,2 do S.touch(args[i],args[i+1]) end
    local operations={}
    for id,path in pairs(S.dirty) do
        local value=bucket(path.collection)[path.key]
        local payload=value~=nil and encoded(path.collection,value) or nil
        if payload~=S.committed[id] then
            operations[#operations+1]={collection=path.collection,key=path.key,payload=payload,deleted=value==nil or nil}
            if S.shared and path.collection=='market.listings' then
                operations[#operations].marketExpected=S.marketVersions[path.key] or ''
                if task.marketBuy==path.key then operations[#operations].marketBuy=true end
            end
        else S.dirty[id]=nil end
    end
    if #operations==0 then return end
    if #operations>(S.initializing and 100000 or 256) then error('WALLET_MUTATION_LIMIT') end
    task.operations=operations; task.revision=S.revision; task.mutationId=Entities.newMutationId()
    save(task); coroutine.yield()
end
function S.beforeMarketBuy(key)
    S.active.marketBuy=key
end
local function marketRead(document)
    local task=S.active
    task.reading=true
    local ok=pcall(function()
        Entities.document(document):load(function(result) task.readResult=result end)
    end)
    if not ok then task.readResult={status='UNAVAILABLE'} end
    coroutine.yield()
    local result=task.readResult
    task.readResult=nil; task.reading=false
    return result
end
function S.marketCatalog(mode,steamId,page,query)
    local result=marketRead('ApocWallet.MarketCatalog.v1.'..mode..':'..steamId..':'..string.format('%.0f',page)..':'..query)
    if result.status=='OK' then return result end
end
function S.marketListing(key)
    if not key:match('^%d+$') and not key:match('^market%-%x+$') or #key>39 then return nil,'ITEM' end
    local result=marketRead('ApocWallet.MarketListing.'..key)
    if result.status~='OK' then return nil,result.status=='NOT_FOUND' and 'ITEM' or 'WAIT' end
    local value=Entities.decode(result.payload).value
    value.id=key
    local collection='market.listings'
    bucket(collection)[key]=value
    S.committed[address(collection,key)]=encoded(collection,value)
    S.marketVersions[key]=result.checksum
    if key:sub(1,7)=='market-' then
        local task=S.active
        task.marketAliases=task.marketAliases or {}
        task.marketAliases[key]=true
    end
    return value,nil,result.foreign==true,result.now
end
local function importLegacy(root)
    S.root=root
    for key,value in pairs(root) do
        if key=='market' then
            for name,rows in pairs(value) do
                if collections['market.'..name] then for id in pairs(rows) do S.touch('market.'..name,id) end
                elseif name=='seq' then S.touch('market.$',name) end
            end
        elseif collections[key] then for id in pairs(value) do S.touch(key,id) end
        elseif key~='pendingPurchases' then S.touch('$',key) end
    end
end
local function bootstrap()
    if S.loading or S.status=='blocked' or getTimestampMs()<S.nextAttempt then return end
    S.nextAttempt=getTimestampMs()+5000; S.loading=true
    local function fail(result) S.loading=false; log('LOAD_'..tostring(result.status)) end
    local ok,reason=pcall(function()
        S.repository=S.repository or Entities.document('ApocWallet.Couriers.v2')
        S.repository:load(function(result)
            local handled,reason=pcall(function()
            if result.status=='OK' then
                S.shared=result.sharedMarket==true
                local decoded,error=pcall(function()
                    S.root={}; S.committed={}; S.dirty={}
                    for _,row in ipairs(result.records) do
                        bucket(row.collection)[row.key]=Entities.decode(row.payload).value
                        S.committed[address(row.collection,row.key)]=encoded(row.collection,bucket(row.collection)[row.key])
                        if row.checksum then S.marketVersions[row.key]=row.checksum end
                    end
                end)
                if not decoded then fail({status=error}); return end
                S.revision=result.revision
            elseif result.status=='NOT_FOUND' then
                S.shared=result.sharedMarket==true
                S.root={}; S.committed={}; S.dirty={}; S.revision='0'
                local legacy=ModData and ModData.get and ModData.get('ApocWallet.Couriers.v1')
                if legacy then importLegacy(Entities.decode(Entities.encode(legacy))) end
                local count=0; for _ in pairs(S.dirty) do count=count+1 end
                if count>100000 then S.status='blocked'; fail({status='LEGACY_IMPORT_TOO_LARGE'}); return end
            else fail(result); return end
            S.loading=false; S.status='ready'; log('READY')
            if result.status=='NOT_FOUND' then
                local task={key='initialize',thread=coroutine.create(function()
                    local hasDirty=false; for _ in pairs(S.dirty) do hasDirty=true; break end
                    if hasDirty then S.persist() else
                        local task=S.active; task.operations={}; task.revision='0'; task.mutationId=Entities.newMutationId()
                        save(task); coroutine.yield()
                    end
                    S.initializing=false
                end)}
                S.initializing=true; S.keys[task.key]=task; S.active=task; resume(task)
            end
            end)
            if not handled then S.status='blocked'; fail({status=reason}) end
        end)
    end)
    if not ok then fail({status=reason}) end
end
function S.update()
    if S.status=='blocked' then return end
    if S.status~='ready' then bootstrap(); return end
    for _=1,4 do
        local task=S.active
        if not task then
            task=table.remove(S.queue,1); if not task then return end
            S.active=task; resume(task)
        elseif task.failure then
            S.status='blocked'; log(task.failure); complete(task,false,task.failure)
            rejectQueued(task.failure); return
        elseif task.marketConflict then
            complete(task,false,'MARKET_CONFLICT')
        elseif task.ack then
            S.revision=task.ack
            local stale=false
            for _,op in ipairs(task.operations) do
                local id=address(op.collection,op.key)
                S.committed[id]=op.payload; S.dirty[id]=nil
                if S.shared and op.collection=='market.listings' then
                    S.marketVersions[op.key]=task.marketVersions and task.marketVersions[op.key]
                    if not S.marketVersions[op.key] then stale=true end
                end
            end
            task.operations=nil; task.ack=nil; task.inflight=false; task.marketVersions=nil
            if stale then complete(task,false,'MARKET_CONFLICT') else resume(task) end
        elseif task.reading then
            if task.readResult then resume(task) else return end
        elseif task.operations then
            if not task.inflight and getTimestampMs()>=(task.retryAt or 0) then save(task) end
            return
        else return end
    end
end
Events.OnServerStarted.Add(bootstrap)
Events.OnTickEvenPaused.Add(S.update)
return S
