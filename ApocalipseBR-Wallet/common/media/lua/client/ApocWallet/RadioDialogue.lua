require 'ApocWallet/Protocol'
if ApocWallet.RadioDialogue then return ApocWallet.RadioDialogue end
local D={}; D.__index=D
ApocWallet.RadioDialogue=D
function D.new(player,radio)
    return setmetatable({player=player,radio=radio,queue={},history={},nextLine=0,lastPage=-10000,talkingUntil=0,sounds={}},D)
end
function D:sound(name)
    local ok,id=pcall(function() return self.player:getEmitter():playSound('ApocWallet_'..name) end)
    if ok and id then
        self.sounds[#self.sounds+1]=id
        if name=='Static' then self.static=id end
        if #self.sounds>32 then table.remove(self.sounds,1) end
    end
end
function D:stopTuning()
    if self.static then pcall(function() self.player:getEmitter():stopSound(self.static) end); self.static=nil end
end
function D:enqueue(speaker,key,args)
    if #self.queue>=24 then return end
    self.queue[#self.queue+1]={speaker=speaker,key=key,args=args or {},name=speaker=='operator' and self.operatorName or nil}
end
function D:enqueueText(speaker,text,name)
    if type(text)~='string' or #text==0 or #self.queue>=24 then return end
    self.queue[#self.queue+1]={speaker=speaker,text=text,name=name}
end
function D:page(mode,page)
    local t=getTimestampMs()
    if t-self.lastPage<5000 then return end
    self.lastPage=t
    local P=require 'ApocWallet/MarketProtocol'
    self:enqueue('player','UI_ApocWallet_MarketPageTxFmt',{self.operatorName or 'Rede do Mercado',P.pageReference(mode,page)})
    return true
end
function D:update()
    local t=getTimestampMs()
    if t<self.nextLine or #self.queue==0 then return end
    self.nextLine=t+1400
    local line=table.remove(self.queue,1)
    local a=line.args or {}
    local text=line.text or getText(line.key,a[1],a[2],a[3],a[4])
    self:record(line.speaker,text,line.name)
    if line.speaker=='player' then self.player:Say(text)
    else
        self.talkingUntil=t+1600
        self:sound('Squelch')
        -- Native device speech; text remains in the radio log if the device
        -- cannot currently emit (for example, after the player moves away).
        pcall(function() self.radio:AddDeviceText(text,0.45,1,0.65,nil,nil,0) end)
    end
end
function D:record(speaker,text,name)
    self.history[#self.history+1]={speaker=speaker,text=text,name=name or (speaker=='operator' and self.operatorName or nil)}
    if self.onLine then self.onLine(self.history) end
end
function D:close()
    self.queue={}
    pcall(function()
        local emitter=self.player:getEmitter()
        for _,id in ipairs(self.sounds) do emitter:stopSound(id) end
    end)
    self.sounds={}
end
return D
