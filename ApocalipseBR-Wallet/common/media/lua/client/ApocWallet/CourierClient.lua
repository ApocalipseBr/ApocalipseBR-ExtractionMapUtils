if isServer() then return end
local Renderer=require 'ApocWallet/DroneRenderer'
local Route=require 'ApocWallet/CourierRoute'
if ApocWallet.CourierClient then return ApocWallet.CourierClient end
local Client={flights={},latestByPlayer={},transmissions={},heard={}}
ApocWallet.CourierClient=Client
local function transmissionPosition(message)
    local f=Client.flights[message.id]
    if f then
        local t=getTimestampMs()+f.offset
        local progress=t<f.due and (t-f.due+f.approach)/f.approach or
            t<f.due+f.hover and 1 or 1-(t-f.due-f.hover)/f.depart
        local x,y=Route.sample(f.path,progress)
        if x then message.x,message.y=x,y end
    end
    return message.x,message.y,message.z+0.6
end
function Client.updateTransmissions()
    local t=getTimestampMs()
    for id,message in pairs(Client.transmissions) do
        if t>=message.nextLine then
            local line=message.lines[message.index]
            if not line then Client.transmissions[id]=nil
            else
                message.index=message.index+1; message.nextLine=t+3000
                local key=message.kind=='pickup' and 'UI_ApocWallet_CourierPickupCargoFmt' or 'UI_ApocWallet_CourierDropoffCargoFmt'
                local text=getText(key,line.code,line.count)
                message.text=TextDrawObject.new()
                message.text:ReadString(UIFont.Small,getText('UI_ApocWallet_CourierDrone')..': '..text,48)
                local x,y,z=transmissionPosition(message)
                -- Local positional audio only; no world sound/zombie attraction.
                local emitter=getWorld():getFreeEmitter(x,y,z)
                emitter:playSound('ApocWallet_Squelch')
                if ApocWallet.MarketClient then
                    for _,s in pairs(ApocWallet.MarketClient.sessions) do
                        if s.player:getUsername()==message.owner then
                            s.dialogue:record('drone',text)
                            pcall(function() s.radio:AddDeviceText(text,0.9,1,0.5,nil,nil,0) end)
                        end
                    end
                end
            end
        end
    end
end
local function renderTransmissions()
    for _,message in pairs(Client.transmissions) do
        if message.text then
            local x,y,z=transmissionPosition(message)
            for i=0,getNumActivePlayers()-1 do
                local player=getSpecificPlayer(i)
                if player and player:getZ()==message.z and math.abs(player:getX()-x)+math.abs(player:getY()-y)<40 then
                    local zoom=getCore():getZoom(i)
                    local sx=(IsoUtils.XToScreen(x,y,z,0)-IsoCamera.getOffX(i))/zoom+IsoCamera.getScreenLeft(i)
                    local sy=(IsoUtils.YToScreen(x,y,z,0)-IsoCamera.getOffY(i))/zoom+IsoCamera.getScreenTop(i)-24
                    message.text:Draw(sx,sy,true)
                end
            end
        end
    end
end
function Client.latestFor(player)
    return player and Client.latestByPlayer[player:getOnlineID()]
end
function Client.receive(command,args)
    if type(args)~='table' then return end
    if command=='CourierFlight' and type(args.id)=='string' and type(args.path)=='table' then
        args.offset=args.serverNow-getTimestampMs()
        Client.flights[args.id]=args
    elseif command=='CourierTransmission' and type(args.id)=='string' and type(args.lines)=='table' and not Client.heard[args.id] then
        Client.heard[args.id]=true
        args.index=1; args.nextLine=getTimestampMs()
        Client.transmissions[args.id]=args
    elseif command=='CourierETA' and type(args.id)=='string' and type(args.seconds)=='number' and type(args.onlineId)=='number' then
        local key=args.kind=='pickup' and 'UI_ApocWallet_CourierPickupFmt' or 'UI_ApocWallet_CourierDeliveryFmt'
        local message=getText(key,math.ceil(args.seconds))
        Client.latestByPlayer[args.onlineId]=message
        if ApocWallet.MarketClient then ApocWallet.MarketClient.courierETA(args) end
        if ApocWallet.RadioUIController then
            for _,win in pairs(ApocWallet.RadioUIController.windows) do
                if not win.closed and win.player:getOnlineID()==args.onlineId then win:setCourierMessage(message) end
            end
        end
    end
end
Events.OnServerCommand.Add(function(module,command,args)
    if module=='ApocWallet' then Client.receive(command,args) end
end)
Events.OnDisconnect.Add(function()
    Client.flights={}; Client.latestByPlayer={}
    Client.transmissions={}; Client.heard={}
end)
function Client.render()
    local clock=getTimestampMs()
    for id,f in pairs(Client.flights) do
        local t=clock+f.offset
        local start=f.due-f.approach
        local finish=f.due+f.hover+f.depart
        if t>=finish then Client.flights[id]=nil
        elseif t>=start then
            local progress,height
            if t<f.due then
                progress=(t-start)/f.approach
                height=f.vertical and 1.8-1.2*progress or 0.6
            elseif t<f.due+f.hover then progress=1; height=0.6
            else
                progress=1-(t-f.due-f.hover)/f.depart
                height=f.vertical and 0.6+1.2*(1-progress) or 0.6
            end
            local x,y,yaw=Route.sample(f.path,progress)
            if t>=f.due+f.hover then yaw=(yaw+180)%360 end
            if x then Renderer.draw(x,y,f.z,height,yaw,t/1000) end
        end
    end
    renderTransmissions()
end
Events.OnPostRender.Add(function()
    local ok,error=pcall(Client.render)
    if not ok and Client.lastError~=tostring(error) then
        Client.lastError=tostring(error); print('[ApocWallet] courier render: '..Client.lastError)
    end
end)
Events.OnTick.Add(function()
    Client.updateTransmissions()
end)
return Client
