# 🔍 Debugging TouchOSC Bitwise Extraction Issue

## ❌ **Problem:**
`new_brightness` is always returning `0.5` instead of the correct extracted LED brightness values from the packed words.

## 🛠 **Debugging Changes Applied:**

### **1. Fixed Bitwise Operations:**
The original mathematical bitwise functions were too simplified and causing incorrect results. Replaced with proper bit-by-bit implementations:

```lua
-- Before (simplified but incorrect):
local function bit_and(a, b)
    return (a + b - bit_or(a, b)) / 2
end

-- After (proper bit-by-bit calculation):
local function bit_and(a, b)
    local result = 0
    local power = 1
    while a > 0 and b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit == 1 and b_bit == 1 then
            result = result + power
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        power = power * 2
    end
    return result
end
```

### **2. Added Debug Output:**
Temporarily enabled debug printing in `extract_led_from_word` to show:
- Input word value
- LED offset within word  
- Bit shift calculation
- Mask value (should be 15 for 4-bit LEDs)
- Shifted value after right shift
- Final extracted result

### **3. Debug Output Format:**
```lua
print("extract_led: word=" .. word .. " offset=" .. led_offset .. " shift=" .. bit_shift .. " mask=" .. mask .. " shifted=" .. shifted_value .. " result=" .. result)
```

## 🔍 **What To Look For:**

When you run the script, you should see output like:
```
extract_led: word=2851 offset=0 shift=0 mask=15 shifted=2851 result=3
extract_led: word=2851 offset=1 shift=4 mask=15 shifted=178 result=2
extract_led: word=2851 offset=2 shift=8 mask=15 shifted=11 result=11
```

### **Expected Values:**
- **mask**: Should always be `15` (0x0F for 4-bit values)
- **shift**: Should be `0, 4, 8, 12, 16, 20, 24, 28` for LEDs 0-7 in word
- **result**: Should be `0-15` (hex `0-F`) representing LED brightness

## 🎯 **Troubleshooting:**

### **If mask is wrong:**
- Issue with `bit_lshift(1, BITS_PER_LED) - 1` calculation
- Should produce `15` for 4-bit LEDs

### **If shifted value is wrong:**  
- Issue with `bit_rshift(word, bit_shift)` function
- Check if right shift is working correctly

### **If result is always same:**
- Issue with `bit_and(shifted_value, mask)` function
- The AND operation isn't isolating the 4-bit value correctly

## 🧮 **Manual Test:**
Try this manually in TouchOSC console:
```lua
-- Test with known values
local test_word = 2851  -- Binary: 101100100011 
local test_result = extract_led_from_word(test_word, 0)
print("Manual test result: " .. test_result)  -- Should be 3 (hex char from position 0)
```

## 💡 **Quick Fix Test:**
If the bitwise functions are still wrong, you can temporarily try a simpler approach:
```lua
function extract_led_from_word_simple(word, led_offset)
    -- Convert back to hex string and extract character (for testing)
    local hex_string = string.format("%X", word)
    -- This is just for debugging - not the final solution
    return tonumber(string.sub(hex_string, led_offset + 1, led_offset + 1), 16) or 0
end
```

The debug output will help identify exactly where in the bitwise extraction chain the issue is occurring! 🔍✨