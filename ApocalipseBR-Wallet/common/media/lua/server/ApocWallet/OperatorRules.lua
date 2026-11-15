if isClient() then return end
local Operators=require 'ApocWallet/Operators'

-- Register future server rules here or from another server script.
-- Operators.registerRule('secret-contact',100,function(context)
--     if serverOwnedCondition(context.characterId) then return 'operator_key' end
-- end)
-- The highest priority matching rule wins when a new contact is rolled.
-- Without a matching rule, roll() uses the random-eligible operator pool.
return Operators
