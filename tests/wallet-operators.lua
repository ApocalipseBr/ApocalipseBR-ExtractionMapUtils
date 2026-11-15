local root='ApocalipseBR-Wallet/common/media/lua/'
package.path=root..'shared/?.lua;'..root..'server/?.lua;C:/Users/ricar/Zomboid/Workshop/apocbr/Contents/mods/ApocalisebrPack/42.14/media/lua/server/?.lua;'..package.path
local checks,time,randomIndex,rolls=0,100000,0,0
local function check(value,message) checks=checks+1; assert(value,message) end
function isClient() return false end
function isServer() return true end
function getTimestampMs() return time end
function ZombRand(limit) rolls=rolls+1; return randomIndex%limit end
local callbacks,startups={},{}
Events={OnServerStarted={Add=function(fn) startups[#startups+1]=fn end},
    OnTickEvenPaused={Add=function(fn) callbacks[#callbacks+1]=fn end}}
local function tick() for _,fn in ipairs(callbacks) do fn() end end
local requests,responses,documents={},{},{}
local sequence=0
ApocBRModEntities={
    define=function(name,mapping)
        check(name=='ApocWallet.OperatorGossip' and mapping.table=='wallet_operator_gossip','gossip uses the mapped entity facade')
        check(mapping.fields.operator_key.id and mapping.fields.pools.type=='text','keyed scalar mapping matches the database')
    end,
    submit=function(name,operation,keys,values,revision)
        sequence=sequence+1
        check(operation=='find' and next(values)==nil,'startup issues keyed reads without writes')
        requests[#requests+1]={id=tostring(sequence),key=keys.operator_key}
        return {accepted=true,id=tostring(sequence)}
    end,
    decode=function(text) return assert(documents[text],'malformed JSON') end,
    poll=function() local result=responses; responses={}; return result end,
}
local Operators=require 'ApocWallet/OperatorRules'
local Gossip=require 'ApocWallet/GossipController'
local P=require 'ApocWallet/MarketProtocol'
local context={characterId='character-one',sourceServerId=2}
local first=Operators.contact(context,{connection=1})
check(first.key=='iron_echo' and first.name=='IRON ECHO' and first.gender=='female','sorted random pool selects IRON ECHO')
local before=rolls
randomIndex=1; time=time+599999
check(Operators.contact(context,{connection=2})==first and rolls==before,'reconnect uses character contact and refreshes inactivity')
time=time+599999
check(Operators.current(context.characterId)==first,'renewed assignment survives another interval')
time=time+1
check(not Operators.current(context.characterId),'assignment expires at exactly ten minutes of inactivity')
local second=Operators.contact(context,{connection=3})
check(second.key=='sparks' and second.gender=='male' and rolls==before+1,'expired assignment rolls again')
Operators.register({key='secret',name='SECRET',gender='female',texturePrefix='secret_',randomEligible=false})
Operators.registerRule('lower',1,function() return 'sparks' end)
Operators.registerRule('higher',10,function(c) if c.characterId=='special' then return 'secret' end end)
check(Operators.roll({characterId='special'}).key=='secret','highest priority server rule may choose a non-random operator')
check(Operators.roll({characterId='ordinary'}).key=='sparks','unmatched rules continue in priority order')
Operators.rules={}
for index=0,1 do randomIndex=index; check(Operators.roll({}).key~='secret','non-random operator excluded from fallback') end
check(not pcall(Operators.register,{key='sparks',name='duplicate',gender='male',texturePrefix='control_'}),'duplicate operator rejected')
Operators.definitions.secret=nil
check(P.pageReference('market',3)=='MER-003' and P.pageReference('inventory',12)=='MOC-012' and P.pageReference('expired',1)=='EXP-001','navigation references encode mode and page')

Gossip.start()
check(#requests==2,'server startup loads one record per operator')
for _=1,30 do tick() end
check(#requests==2,'in-flight startup reads are coalesced')
documents.good={greeting={'Aqui {operator}. Consulte {page}.'},posted={'Confirmado {item} x{count}, {page}.'},
    page_market={'Mensagem sem a referência obrigatória'},page_expired={'Token desconhecido {secret} {page}'}}
for _,request in ipairs(requests) do
    responses[#responses+1]=request.key=='sparks' and {id=request.id,status='OK',values={operator_key='sparks',enabled=true,pools='good'},revision='1'}
        or {id=request.id,status='UNAVAILABLE'}
end
tick()
local sparks=Operators.definitions.sparks
local text=Gossip.line(sparks,'greeting',{page='MER-001'})
check(text=='Aqui SPARKS. Consulte MER-001.','server renders database gossip and operator identity')
check(Gossip.line(sparks,'posted',{item='CARGA-00042',count=2,page='MOC-001'}):find('CARGA%-00042 x2, MOC%-001'),'item and page placeholders survive formatting')
check(not Gossip.cache.sparks.page_market and not Gossip.cache.sparks.page_expired,'missing references and unknown template tokens rejected per category')
check(not Gossip.validate({page_inventory={[1]='{page}',[3]='{page}'}}).page_inventory,'sparse gossip arrays cannot select a missing line')
check(Gossip.line(sparks,'page_market',{page='MER-003'}):find('MER%-003'),'invalid category uses operator fallback')
check(Gossip.line(Operators.definitions.iron_echo,'greeting',{page='MER-001'}):find('IRON ECHO',1,true),'database failure uses matching female operator fallback')
time=time+29999; tick(); check(#requests==2,'failure retry is paced')
time=time+1; tick(); check(#requests==3 and requests[3].key=='iron_echo','only failed operator is retried')
responses[1]={id=requests[3].id,status='NOT_FOUND'}; tick()
check(Gossip.loaded.iron_echo,'missing operator content settles on fallback')
for _=1,100 do time=time+30000; tick() end
check(#requests==3,'loaded cache performs no further SQL reads or writes')
check(next(Operators.contacts)==nil,'expired character contacts are released from memory')
for key,operator in pairs(Operators.definitions) do
    local fallback=require 'ApocWallet/OperatorFallbacks'
    local validated=Gossip.validate(fallback[key])
    for category in pairs(Gossip.requirements) do
        check(validated[category]~=nil,'valid fallback for '..key..'/'..category)
        local line=Gossip.line(operator,category,{page='EXP-002',item='CARGA-00001',count=1,seconds=20})
        check(line and not line:find('[{}]'),'rendered fallback for '..key..'/'..category)
    end
end
Operators.contact({characterId='before-restart'}, {})
package.loaded['ApocWallet/Operators']=nil; ApocWallet.Operators=nil
local restarted=require 'ApocWallet/Operators'
check(next(restarted.contacts)==nil and restarted.definitions.sparks~=nil,'fresh server runtime recreates definitions with an empty contact cache')
print('Passed '..checks..' operator lifecycle, rule, cache, template and fallback checks.')
