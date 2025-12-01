# 🔧 Fixed old_osc_in Nil Value Error

## ❌ **Problem:**
```
lua: /home/we/dust/code/toga/lib/togagrid.lua:178: attempt to call a nil value (field 'old_osc_in')
```

The code was trying to call `togagrid.old_osc_in` when it might be nil, and there was inconsistent usage between static and instance variables.

## ✅ **Solution Applied:**

### **1. Added Nil Check Before Calling:**
```lua
-- Before (causing error):
togagrid.old_osc_in(path, args, from)

-- After (safe):
if togagrid.old_osc_in then
  togagrid.old_osc_in(path, args, from)
end
```

### **2. Fixed Static vs Instance Variable Consistency:**
```lua
-- hook_osc_in function - now consistently uses static variable:
togagrid.old_osc_in = osc.event  -- Static storage
if togagrid.old_osc_in ~= nil    -- Static check

-- hook_cleanup function - also fixed for consistency:
togagrid.old_cleanup = grid.cleanup  -- Static storage  
if togagrid.old_cleanup ~= nil       -- Static check
```

## 🎯 **Root Cause:**
The issue was a mix of:
1. **Missing nil check** - Code tried to call a function that might not exist
2. **Inconsistent variable usage** - Mixed static (`togagrid.old_osc_in`) and instance (`self.old_osc_in`) patterns

## 🔄 **How It Works Now:**

### **OSC Event Chain:**
1. TouchOSC sends message → `togagrid.osc_in()` handles it
2. If toga doesn't consume the message, safely call original handler
3. `togagrid.old_osc_in` only called if it exists (not nil)

### **Clean Initialization:**
```lua
-- When hooking OSC events:
togagrid.old_osc_in = osc.event    -- Store original safely
osc.event = togagrid.osc_in        -- Replace with toga handler

-- When calling original:
if togagrid.old_osc_in then        -- Check it exists
  togagrid.old_osc_in(...)         -- Call safely
end
```

## 🚀 **Result:**
- ✅ No more nil value errors when using TouchOSC
- ✅ Proper OSC event chaining with other scripts
- ✅ Consistent static variable usage throughout
- ✅ Safe fallback behavior when no original handler exists

**Your TouchOSC integration should now work without any OSC handler errors! 🎯✨**