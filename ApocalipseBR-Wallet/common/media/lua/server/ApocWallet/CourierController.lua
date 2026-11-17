if not isServer() then return end
local Courier=require 'ApocWallet/CourierService'
local Purchase=require 'ApocWallet/PurchaseService'
local Store=require 'ApocWallet/EntityStore'
if ApocWallet.courierControllerInstalled then return end
ApocWallet.courierControllerInstalled=true
local function update()
    Store.run('courier-update',Courier.update)
    Store.run('purchase-update',Purchase.update)
end
Events.OnTick.Add(update)
-- Empty dedicated servers can pause normal world ticks. Wall-clock fulfillment
-- and loading requests must continue while the simulation is paused.
Events.OnTickEvenPaused.Add(update)
