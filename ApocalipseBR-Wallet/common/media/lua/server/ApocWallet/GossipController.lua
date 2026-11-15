if isClient() then return end
local Operators=require 'ApocWallet/OperatorRules'
local Fallbacks=require 'ApocWallet/OperatorFallbacks'
require 'ApocWallet/Protocol'
if ApocWallet.GossipController then return ApocWallet.GossipController end

local Gossip={cache={},loading={},loaded={},retryAt={},started=false}
ApocWallet.GossipController=Gossip
local requirements={
    greeting={'operator','page'},page_market={'page'},page_inventory={'page'},page_expired={'page'},
    posted={'item','count','page'},reserved={'item','count','page'},bought={'item','count','page'},
    reposted={'item','page'},recovered={'item','page'},error_item={'item','page'},
    error_sold={'item','page'},error_funds={'item','page'},error_refused={'page'},
    error_radio={},error_signal={},error_wait={},error_storage={},eta_pickup={'seconds'},eta_delivery={'seconds'},
}
local placeholders={operator=true,page=true,item=true,count=true,seconds=true}
Gossip.requirements=requirements

local function validTemplate(text,required)
    if type(text)~='string' or #text<1 or #text>1024 or text:find('[%c]') then return false end
    local valid=true
    local remainder=text:gsub('{([%w_]+)}',function(key)
        if not placeholders[key] then valid=false end
        return ''
    end)
    if not valid or remainder:find('[{}]') then return false end
    for _,key in ipairs(required) do if not text:find('{'..key..'}',1,true) then return false end end
    return true
end

-- Invalid categories fall back independently, preserving valid operator content.
function Gossip.validate(pools)
    if type(pools)~='table' then return nil end
    local result={}
    for category,required in pairs(requirements) do
        local lines=pools[category]
        if type(lines)=='table' and #lines>0 and #lines<=32 then
            local valid,count=true,0
            for key,text in pairs(lines) do
                count=count+1
                if type(key)~='number' or key%1~=0 or key<1 or key>#lines or not validTemplate(text,required) then valid=false end
            end
            if valid and count==#lines then result[category]=lines end
        end
    end
    return result
end

function Gossip.line(operator,category,values)
    local pools=Gossip.cache[operator.key] or {}
    local fallback=Fallbacks[operator.key] or Fallbacks.sparks
    local lines=pools[category] or fallback[category]
    if not lines then return nil end
    local text=lines[ZombRand(#lines)+1]
    values=values or {}
    return (text:gsub('{([%w_]+)}',function(key)
        if key=='operator' then return operator.name end
        return tostring(values[key] or '')
    end))
end

local repository,entities
local function loadOperator(key)
    Gossip.loading[key]=true
    Gossip.retryAt[key]=getTimestampMs()+30000
    local ok,reason=pcall(function()
        entities=entities or require 'ApocBR/Entities'
        repository=repository or entities.define('ApocWallet.OperatorGossip',{
            table='wallet_operator_gossip',fields={operator_key={type='string',id=true},
                enabled={type='boolean'},pools={type='text'}},
        })
        repository:find({operator_key=key},function(result)
            Gossip.loading[key]=nil
            if result.status=='OK' then
                local row=result.entity
                local decoded,pools=pcall(entities.decode,row:get('pools'))
                if decoded then
                    Gossip.cache[key]=row:get('enabled') and Gossip.validate(pools) or {}
                    Gossip.loaded[key]=true
                    print('[ApocWallet/Gossip] loaded '..key)
                else print('[ApocWallet/Gossip] invalid content '..key) end
            elseif result.status=='NOT_FOUND' then
                Gossip.loaded[key]=true
                print('[ApocWallet/Gossip] fallback for missing operator '..key)
            else print('[ApocWallet/Gossip] load '..key..': '..tostring(result.status)) end
        end)
    end)
    if not ok then
        Gossip.loading[key]=nil
        print('[ApocWallet/Gossip] load '..key..': '..tostring(reason))
    end
end

function Gossip.update()
    Operators.cleanup()
    if not Gossip.started then return end
    local now=getTimestampMs()
    for key in pairs(Operators.definitions) do
        if not Gossip.loaded[key] and not Gossip.loading[key] and now>=(Gossip.retryAt[key] or 0) then loadOperator(key) end
    end
end

function Gossip.start()
    Gossip.started=true
    Gossip.update()
end

Events.OnServerStarted.Add(Gossip.start)
Events.OnTickEvenPaused.Add(Gossip.update)
return Gossip
