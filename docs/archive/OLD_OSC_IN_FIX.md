# 🔧 Fixed old_osc_in Nil Value Error

## ❌ **Problem:**
```
lua: /home/we/dust/code/toga/lib/oscgard.lua:178: attempt to call a nil value (field 'old_osc_in')
```

The code was trying to call `oscgard.old_osc_in` when it might be nil, and there was inconsistent usage between static and instance variables.

## ✅ **Solution Applied:**

### **1. Added Nil Check Before Calling:**
```lua
-- Before (causing error):
oscgard.old_osc_in(path, args, from)

-- After (safe):
if oscgard.old_osc_in then
  oscgard.old_osc_in(path, args, from)
end
```

### **2. Fixed Static vs Instance Variable Consistency:**
```lua
-- hook_osc_in function - now consistently uses static variable:
oscgard.old_osc_in = osc.event  -- Static storage
if oscgard.old_osc_in ~= nil    -- Static check

-- hook_cleanup function - also fixed for consistency:
oscgard.old_cleanup = grid.cleanup  -- Static storage  
if oscgard.old_cleanup ~= nil       -- Static check
```

## 🎯 **Root Cause:**
The issue was a mix of:
1. **Missing nil check** - Code tried to call a function that might not exist
2. **Inconsistent variable usage** - Mixed static (`oscgard.old_osc_in`) and instance (`self.old_osc_in`) patterns

## 🔄 **How It Works Now:**

### **OSC Event Chain:**
1. TouchOSC sends message → `oscgard.osc_in()` handles it
2. If oscgard doesn't consume the message, safely call original handler
3. `oscgard.old_osc_in` only called if it exists (not nil)

### **Clean Initialization:**
```lua
-- When hooking OSC events:
oscgard.old_osc_in = osc.event    -- Store original safely
osc.event = oscgard.osc_in        -- Replace with oscgard handler

-- When calling original:
if oscgard.old_osc_in then        -- Check it exists
  oscgard.old_osc_in(...)         -- Call safely
end
```

## 🚀 **Result:**
- ✅ No more nil value errors when using TouchOSC
- ✅ Proper OSC event chaining with other scripts
- ✅ Consistent static variable usage throughout
- ✅ Safe fallback behavior when no original handler exists

**Your TouchOSC integration should now work without any OSC handler errors! 🎯✨**