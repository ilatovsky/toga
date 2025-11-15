-- UNCOMMENT TO add midigrid plugin
--local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/mg_128" or grid

local togagrid = {
  device = nil, -- needed by cheat codes 2
  cols = 16,
  rows = 8,
  old_buffer = nil,
  new_buffer = nil,
  dirty = nil, -- dirty flag array for tracking changes
  dest = {},
  cleanup_done = false,
  old_grid = nil,
  old_osc_in = nil,
  old_cleanup = nil,
  key = nil, -- key event callback
  last_refresh_time = 0, -- for throttling
  refresh_interval = 0.01667, -- 30Hz refresh rate (33ms)
  batch_sync_interval = 0.25, -- Sync one batch every 250ms
  sync_batch_row = 1, -- Current row being synced (1-8)
  batch_size = 1, -- Number of rows per batch
  sync_clock_id = nil -- Background sync coroutine ID
}

function togagrid:connect()
    if _ENV.togagrid then return _ENV.togagrid end
    togagrid:init()
    _ENV.togagrid = togagrid
    return togagrid
end

function create_buffer(width,height)
  local new_buffer = {}

  for r = 1,width do
    new_buffer[r] = {}
    for c = 1,height do
      new_buffer[r][c] = 0
    end
  end

  return new_buffer
end

function create_dirty_flags(width,height)
  local dirty = {}

  for r = 1,width do
    dirty[r] = {}
    for c = 1,height do
      dirty[r][c] = false
    end
  end

  return dirty
end

function togagrid:init()
  -- UNCOMMENT to add default touchosc client
  --table.insert(self.dest, {"192.168.0.123",8002})

  self.device = self
  self.old_buffer = create_buffer(self.cols, self.rows)
  self.new_buffer = create_buffer(self.cols, self.rows)
  self.dirty = create_dirty_flags(self.cols, self.rows)
  self:hook_osc_in()
  self:hook_cleanup()
  self:start_background_sync()
  self:refresh(true)
  
  self.old_grid = grid.connect()
  if self.old_grid then
    self.old_grid.key = function(x, y, z)
      if togagrid.key then
        togagrid.key(x, y, z)
      else
        --print("grid.key is not defined!")
      end
    end
  end
  
  self:send_connected(nil, true)
end

function togagrid:start_background_sync()
  -- Stop existing sync if running
  if self.sync_clock_id then
    clock.cancel(self.sync_clock_id)
  end
  
  -- Start background sync coroutine
  self.sync_clock_id = clock.run(function()
    while not self.cleanup_done do
      clock.sleep(self.batch_sync_interval)
      
      -- Only sync if we have destinations
      if #self.dest > 0 then
        self:sync_batch()
      end
    end
  end)
  print("togagrid: started background sync (row-based batching)")
end

function togagrid:sync_batch()
  -- Calculate which rows to sync in this batch
  local batch_rows = {}
  for i = 1, self.batch_size do
    local row = self.sync_batch_row + i - 1
    if row <= self.rows then
      table.insert(batch_rows, row)
    end
  end
  
  -- Sync the batch rows
  for _, batch_row in ipairs(batch_rows) do
    for c = 1, self.cols do
      self:update_led(c, batch_row)
    end
  end
  
  -- Move to next batch, wrap around after last row
  self.sync_batch_row = self.sync_batch_row + self.batch_size
  if self.sync_batch_row > self.rows then
    self.sync_batch_row = 1
  end
end

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

-- @static
function togagrid.osc_in(path, args, from)
  local consumed = false
  if not togagrid.cleanup_done then
    local x, y, z, i
    --print("togagrid_osc_in", dump(path), dump(args), dump(from))
    if string.starts(path, "/toga_connection") then
      print("togagrid connect!")
      local added = false
      for d, dest in pairs(togagrid.dest) do
        if dest[1] == from[1] and dest[2] == from[2] then
          added = true
        end
      end
      if not added then
        print("togagrid: add new toga client", from[1]..":"..from[2])
        table.insert(togagrid.dest, from)
        togagrid:refresh(true, from)
      end
      -- echo back anyway to update connection button value
      togagrid:send_connected(from, true)
      -- do not consume the event so togaarc can also add the new touchosc client.
    elseif string.starts(path, "/togagrid/") then
      i = tonumber(string.sub(path,11))
      x = ((i-1) % 16) + 1
      y = (i-1) // 16 + 1
      z = args[1] // 1
      --print("togagrid_osc_in togagrid", i, x, y, z)
      if togagrid.key then
        togagrid.key(x, y, z)
      end
      -- Removed immediate LED update on button release - let next refresh handle it
      consumed = true
    end
  end
  
  if not consumed then
    -- invoking original osc.event callback
    togagrid.old_osc_in(path, args, from)
  end
end

function togagrid:hook_osc_in()
  if self.old_osc_in ~= nil then return end
  --print("togagrid: hook old osc_in")
  self.old_osc_in = osc.event
  osc.event = togagrid.osc_in
end

-- @static
function togagrid.cleanup()
  if togagrid.old_cleanup then
    togagrid.old_cleanup()
  end
  if not togagrid.cleanup_done then
    -- Stop background sync
    if togagrid.sync_clock_id then
      clock.cancel(togagrid.sync_clock_id)
      togagrid.sync_clock_id = nil
      print("togagrid: stopped background sync")
    end
    
    -- Clear all LEDs before disconnecting
    print("togagrid: clearing all LEDs on script shutdown")
    togagrid:all(0)
    togagrid:refresh(true) -- Force immediate refresh to clear all LEDs
    
    -- Send disconnected signal
    togagrid:send_connected(nil, false)
    togagrid.cleanup_done = true
  end
end

function togagrid:hook_cleanup()
  if self.old_cleanup ~= nil then return end
  --print("togagrid: hook old cleaup")
  self.old_cleanup = grid.cleanup
  grid.cleanup = togagrid.cleanup
end

function togagrid:rotation(val)
  if self.old_grid then
    self.old_grid:rotation(val)
  end
end

function togagrid:all(z)
  for r = 1,self.rows do
    for c = 1,self.cols do
      self.new_buffer[c][r] = z
      self.dirty[c][r] = true
    end
  end

  if self.old_grid then
    self.old_grid:all(z)
  end
end

function togagrid:led(x, y, z)
  if x > self.cols or y > self.rows then return end
  if self.new_buffer[x][y] ~= z then
    self.new_buffer[x][y] = z
    self.dirty[x][y] = true
  end
  
  if self.old_grid then
    self.old_grid:led(x, y, z)
  end
end

function togagrid:refresh(force_refresh, target_dest)
  -- Throttle refresh to 30Hz unless forced
  if not force_refresh then
    local now = util.time()
    if (now - self.last_refresh_time) < self.refresh_interval then
      return -- Skip this refresh, too soon
    end
    self.last_refresh_time = now
  end
  
  -- When force_refresh is true, send all cells
  -- When force_refresh is false, only send dirty cells
  for r = 1,self.rows do
    for c = 1,self.cols do
      local should_update = force_refresh or self.dirty[c][r]
      if should_update then
        self.old_buffer[c][r] = self.new_buffer[c][r]
        self:update_led(c, r, target_dest)
        if not force_refresh then
          self.dirty[c][r] = false
        end
      end
    end
  end
  
  -- Clear all dirty flags after a forced refresh
  if force_refresh then
    for r = 1,self.rows do
      for c = 1,self.cols do
        self.dirty[c][r] = false
      end
    end
  end
  
  if self.old_grid then
    self.old_grid:refresh()
  end
end

function togagrid:intensity(i)
  if self.old_grid then
    self.old_grid:intensity(i)
  end
end

function togagrid:update_led(c, r, target_dest)
  local z = self.new_buffer[c][r]
  local i = c + (r-1) * self.cols
  local addr = string.format("/togagrid/%d", i)
  --print("togagrid osc.send", addr, z)
  for d, dest in pairs(self.dest) do
    if target_dest and (target_dest[1] ~= dest[1] or target_dest[2] ~= dest[2]) then
      -- do nothing
    else
      osc.send(dest, addr, {z / 15.0})
    end
  end
end

function togagrid:send_connected(target_dest, connected)
  for d, dest in pairs(self.dest) do
    if target_dest and (target_dest[1] ~= dest[1] or target_dest[2] ~= dest[2]) then
      -- do nothing
    else
      osc.send(dest, "/toga_connection", {connected and 1.0 or 0.0})
    end
  end
end

return togagrid