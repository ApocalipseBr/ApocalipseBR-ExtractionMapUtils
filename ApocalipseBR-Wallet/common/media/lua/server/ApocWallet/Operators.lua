if isClient() then return end
require 'ApocWallet/Protocol'
if ApocWallet.Operators then return ApocWallet.Operators end

local Operators={definitions={},rules={},contacts={},IDLE_MS=10*60*1000,nextCleanup=0}
ApocWallet.Operators=Operators

function Operators.register(definition)
    assert(type(definition.key)=='string' and #definition.key<=64 and definition.key:match('^[a-z][a-z0-9_]*$'),'Invalid operator key')
    assert(not Operators.definitions[definition.key],'Duplicate operator key')
    assert(type(definition.name)=='string' and #definition.name>0,'Operator name required')
    assert(type(definition.gender)=='string','Operator gender required')
    assert(type(definition.texturePrefix)=='string' and definition.texturePrefix:match('^[%w_]+$'),'Invalid portrait prefix')
    local operator={key=definition.key,name=definition.name,gender=definition.gender,
        texturePrefix=definition.texturePrefix,randomEligible=definition.randomEligible==true}
    Operators.definitions[operator.key]=operator
    return operator
end

-- Selectors receive server-derived character identity and the current player.
-- Return an operator key to claim the contact, or nil to try the next rule.
function Operators.registerRule(key,priority,select)
    assert(type(key)=='string' and type(priority)=='number' and type(select)=='function','Invalid operator rule')
    for _,rule in ipairs(Operators.rules) do assert(rule.key~=key,'Duplicate operator rule') end
    Operators.rules[#Operators.rules+1]={key=key,priority=priority,select=select}
    table.sort(Operators.rules,function(a,b)
        if a.priority==b.priority then return a.key<b.key end
        return a.priority>b.priority
    end)
end

function Operators.roll(context)
    for _,rule in ipairs(Operators.rules) do
        local ok,key=pcall(rule.select,context)
        if ok and Operators.definitions[key] then return Operators.definitions[key] end
        if not ok then print('[ApocWallet/Operators] rule failed: '..rule.key) end
    end
    local eligible={}
    for key,operator in pairs(Operators.definitions) do
        if operator.randomEligible then eligible[#eligible+1]=key end
    end
    table.sort(eligible)
    assert(#eligible>0,'No eligible market operators')
    return Operators.definitions[eligible[ZombRand(#eligible)+1]]
end

function Operators.contact(context,player)
    local now=getTimestampMs()
    local contact=Operators.contacts[context.characterId]
    if not contact or now>=contact.expires then
        local operator=Operators.roll({characterId=context.characterId,sourceServerId=context.sourceServerId,player=player})
        contact={operatorKey=operator.key,expires=now+Operators.IDLE_MS}
        Operators.contacts[context.characterId]=contact
    end
    contact.expires=now+Operators.IDLE_MS
    return Operators.definitions[contact.operatorKey]
end

function Operators.current(characterId)
    local contact=Operators.contacts[characterId]
    if contact and getTimestampMs()<contact.expires then return Operators.definitions[contact.operatorKey] end
end

function Operators.presentation(operator)
    return {key=operator.key,name=operator.name,gender=operator.gender,texturePrefix=operator.texturePrefix}
end

function Operators.cleanup()
    local now=getTimestampMs()
    if now<Operators.nextCleanup then return end
    Operators.nextCleanup=now+30000
    for key,contact in pairs(Operators.contacts) do
        if now>=contact.expires then Operators.contacts[key]=nil end
    end
end

Operators.register({key='sparks',name='SPARKS',gender='male',texturePrefix='control_',randomEligible=true})
Operators.register({key='iron_echo',name='IRON ECHO',gender='female',texturePrefix='ironcontrol_',randomEligible=true})
return Operators
