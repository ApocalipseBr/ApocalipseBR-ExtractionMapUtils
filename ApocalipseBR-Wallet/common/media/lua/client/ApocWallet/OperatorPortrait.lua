require 'ApocWallet/Protocol'
if ApocWallet.OperatorPortrait then return ApocWallet.OperatorPortrait end
local Portrait={frames={}}
local SNAPSHOT_HOLD_MS=5000
ApocWallet.OperatorPortrait=Portrait
function Portrait.load(prefix)
    if Portrait.frames[prefix] then return Portrait.frames[prefix] end
    local frames={}
    for i=0,15 do
        local texture=getTexture(string.format('media/textures/ApocWallet/operator/%s%02d.png',prefix,i))
        if texture then frames[#frames+1]=texture end
    end
    Portrait.frames[prefix]=frames
    return frames
end
function Portrait.draw(ui,x,y,w,h,state,talkingUntil,operator)
    local prefix=operator and operator.texturePrefix or 'control_'
    local frames=Portrait.load(prefix)
    local t=getTimestampMs()
    ui:drawRect(x,y,w,h,1,0.02,0.04,0.03)
    if state=='connected' then
        local snapshot=ui.walletOperatorSnapshot
        if not snapshot or snapshot.prefix~=prefix then
            snapshot={prefix=prefix,index=1,nextChangeAt=t+SNAPSHOT_HOLD_MS}
            ui.walletOperatorSnapshot=snapshot
        elseif #frames>1 and t>=snapshot.nextChangeAt and t<(talkingUntil or 0) then
            snapshot.index=snapshot.index%#frames+1
            snapshot.nextChangeAt=t+SNAPSHOT_HOLD_MS
        end
        local tex=frames[snapshot.index]
        if tex then ui:drawTextureScaled(tex,x,y,w,h,1,0.85,1,0.85) end
    else
        ui.walletOperatorSnapshot=nil
    end
    -- RadioTraders' scan-line treatment, bounded and deterministic.
    local scan=math.floor(t/35)%math.max(1,math.floor(h))
    ui:drawRect(x,y+scan,w,1,0.16,0.65,1,0.7)
    if state~='connected' then
        for i=1,8 do
            local row=(math.floor(t/60)+i*17)%math.max(1,math.floor(h))
            ui:drawRect(x,y+row,w,1,0.18,0.6,0.8,0.6)
        end
    end
end
return Portrait
