-- Health check system for Himalaya email plugin
-- Detects and diagnoses common issues

local M = {}

-- Dependencies
local notify = require('neotex.util.notifications')

-- Health check functions
M.checks = {}

-- Check UIDVALIDITY files
function M.checks.uidvalidity()
  local config = require('neotex.plugins.tools.himalaya.core.config')
  local account = config.get_account()
  local maildir = vim.fn.expand(account.maildir_path)
  
  local issues = {}
  local checked = 0
  
  -- Find all UIDVALIDITY files
  local handle = io.popen('find ' .. vim.fn.shellescape(maildir) .. ' -name ".uidvalidity" 2>/dev/null')
  if handle then
    local files = handle:read('*a')
    handle:close()
    
    for file in files:gmatch('[^\n]+') do
      checked = checked + 1
      
      -- Check file content
      local content_handle = io.open(file, 'r')
      if content_handle then
        local content = content_handle:read('*a')
        content_handle:close()
        
        -- Check for invalid formats
        if content:match('^%d+$') and #content < 5 then
          -- Single digit - our old format
          table.insert(issues, {
            file = file,
            issue = 'Contains timestamp instead of mbsync format',
            fix = 'Empty the file'
          })
        elseif content ~= '' and not content:match('^%d+\n%d+') then
          -- Non-empty but not mbsync format
          table.insert(issues, {
            file = file,
            issue = 'Invalid format',
            fix = 'Empty the file'
          })
        end
      end
    end
  end
  
  return {
    ok = #issues == 0,
    checked = checked,
    issues = issues,
    fix = #issues > 0 and ':HimalayaFixMaildir' or nil
  }
end

-- Check OAuth tokens
function M.checks.oauth()
  local oauth = require('neotex.plugins.tools.himalaya.sync.oauth')
  local config = require('neotex.plugins.tools.himalaya.core.config')
  local account = config.get_account()
  
  local status = oauth.get_status(account.name or 'gmail')
  
  local issues = {}
  
  if not status.has_token then
    table.insert(issues, 'No OAuth token found')
  end
  
  if not status.environment_loaded then
    table.insert(issues, 'OAuth environment variables not loaded')
  end
  
  return {
    ok = #issues == 0,
    status = status,
    issues = issues,
    fix = #issues > 0 and ':HimalayaSetupOAuth or run "himalaya account configure" in terminal' or nil
  }
end

-- Check maildir structure
function M.checks.maildir()
  local config = require('neotex.plugins.tools.himalaya.core.config')
  local account = config.get_account()
  local maildir = vim.fn.expand(account.maildir_path)
  
  local issues = {}
  
  -- Check trailing slash
  if not account.maildir_path:match('/$') then
    table.insert(issues, 'Maildir path missing trailing slash (required for Maildir++ format)')
  end
  
  -- Check base directories
  local required_dirs = {'cur', 'new', 'tmp'}
  for _, dir in ipairs(required_dirs) do
    if vim.fn.isdirectory(maildir .. dir) == 0 then
      table.insert(issues, 'Missing ' .. dir .. ' directory in INBOX')
    end
  end
  
  -- Check folder structure
  for imap_name, local_name in pairs(account.folder_map or {}) do
    if local_name ~= 'INBOX' then
      local folder_path = maildir .. '.' .. local_name
      if vim.fn.isdirectory(folder_path) == 1 then
        -- Check subdirectories
        for _, dir in ipairs(required_dirs) do
          if vim.fn.isdirectory(folder_path .. '/' .. dir) == 0 then
            table.insert(issues, 'Missing ' .. dir .. ' in folder ' .. local_name)
          end
        end
      end
    end
  end
  
  return {
    ok = #issues == 0,
    maildir = maildir,
    issues = issues,
    fix = #issues > 0 and 'Check trailing slash in config and run :HimalayaSetupMaildir' or nil
  }
end

-- Check for stuck sync processes
function M.checks.sync_processes()
  local issues = {}
  local processes = {}
  
  -- Check for mbsync processes
  local handle = io.popen('ps aux | grep "[m]bsync" 2>/dev/null')
  if handle then
    local output = handle:read('*a')
    handle:close()
    
    for line in output:gmatch('[^\n]+') do
      local pid = line:match('^%S+%s+(%d+)')
      if pid then
        table.insert(processes, {pid = pid, cmd = line})
      end
    end
  end
  
  -- Check lock files
  local lock = require('neotex.plugins.tools.himalaya.sync.lock')
  local active_locks = lock.get_active_locks()
  
  if #processes > 1 then
    table.insert(issues, 'Multiple mbsync processes detected')
  end
  
  if #active_locks > 0 and #processes == 0 then
    table.insert(issues, 'Stale lock files detected')
  end
  
  return {
    ok = #issues == 0,
    processes = processes,
    locks = active_locks,
    issues = issues,
    fix = #issues > 0 and ':HimalayaCleanup' or nil
  }
end

-- Check binaries
function M.checks.binaries()
  local config = require('neotex.plugins.tools.himalaya.core.config')
  local issues = {}
  
  for name, path in pairs(config.config.binaries) do
    if vim.fn.executable(path) == 0 then
      table.insert(issues, name .. ' not found at: ' .. path)
    end
  end
  
  return {
    ok = #issues == 0,
    issues = issues,
    fix = #issues > 0 and 'Install missing binaries or update config paths' or nil
  }
end

-- Check folder mappings
function M.checks.folder_mappings()
  local config = require('neotex.plugins.tools.himalaya.core.config')
  local account = config.get_account()
  local maildir = vim.fn.expand(account.maildir_path)
  
  local issues = {}
  local mappings = {}
  
  -- Check consistency between folder_map and local_to_imap
  for imap, local_name in pairs(account.folder_map or {}) do
    mappings[imap] = local_name
    
    -- Check reverse mapping
    if account.local_to_imap and account.local_to_imap[local_name] ~= imap then
      table.insert(issues, 'Inconsistent mapping for ' .. imap)
    end
    
    -- Check if local folder exists
    if local_name ~= 'INBOX' then
      local folder_path = maildir .. '.' .. local_name
      if vim.fn.isdirectory(folder_path) == 0 then
        -- This is ok, folder will be created on sync
        mappings[imap] = mappings[imap] .. ' (not synced yet)'
      end
    end
  end
  
  return {
    ok = #issues == 0,
    mappings = mappings,
    issues = issues,
    fix = #issues > 0 and 'Check folder configuration in config' or nil
  }
end

-- Run all health checks
function M.check()
  local checks = {
    {name = 'Binaries', test = M.checks.binaries},
    {name = 'Maildir Structure', test = M.checks.maildir},
    {name = 'UIDVALIDITY Files', test = M.checks.uidvalidity},
    {name = 'OAuth Tokens', test = M.checks.oauth},
    {name = 'Folder Mappings', test = M.checks.folder_mappings},
    {name = 'Sync Processes', test = M.checks.sync_processes},
  }
  
  local report = {}
  local all_ok = true
  
  for _, check in ipairs(checks) do
    local result = check.test()
    result.name = check.name
    table.insert(report, result)
    
    if not result.ok then
      all_ok = false
    end
  end
  
  return {
    ok = all_ok,
    report = report
  }
end

-- Display health check results
function M.show_report(silent)
  local result = M.check()
  
  if not silent then
    notify.himalaya('🏥 Himalaya Health Check', notify.categories.USER_ACTION)
    notify.himalaya(string.rep('─', 40), notify.categories.STATUS)
  end
  
  for _, check in ipairs(result.report) do
    local icon = check.ok and '✅' or '❌'
    local status = check.ok and 'OK' or 'ISSUES'
    
    if not silent then
      notify.himalaya(string.format('%s %s: %s', icon, check.name, status), 
        check.ok and notify.categories.STATUS or notify.categories.WARNING)
    end
    
    if not check.ok and check.issues and not silent then
      for _, issue in ipairs(check.issues) do
        if type(issue) == 'table' then
          notify.himalaya('  - ' .. issue.issue .. ' (' .. issue.file .. ')', notify.categories.WARNING)
        else
          notify.himalaya('  - ' .. issue, notify.categories.WARNING)
        end
      end
      
      if check.fix then
        notify.himalaya('  💡 Fix: ' .. check.fix, notify.categories.STATUS)
      end
    end
  end
  
  if not silent then
    notify.himalaya(string.rep('─', 40), notify.categories.STATUS)
    
    if result.ok then
      notify.himalaya('🎉 All checks passed!', notify.categories.USER_ACTION)
    else
      notify.himalaya('⚠️  Some issues detected. Run suggested fixes.', notify.categories.WARNING)
    end
  end
  
  return result
end

-- Fix common issues automatically
function M.fix_common_issues()
  notify.himalaya('🔧 Attempting to fix common issues...', notify.categories.STATUS)
  
  local fixes_applied = {}
  
  -- Fix UIDVALIDITY files
  local uidvalidity_check = M.checks.uidvalidity()
  if not uidvalidity_check.ok then
    local wizard = require('neotex.plugins.tools.himalaya.setup.wizard')
    local config = require('neotex.plugins.tools.himalaya.core.config')
    local account = config.get_account()
    wizard.fix_uidvalidity_files(vim.fn.expand(account.maildir_path))
    table.insert(fixes_applied, 'Fixed UIDVALIDITY files')
  end
  
  -- Clean up stale locks
  local sync_check = M.checks.sync_processes()
  if not sync_check.ok and #sync_check.locks > 0 and #sync_check.processes == 0 then
    local lock = require('neotex.plugins.tools.himalaya.sync.lock')
    local cleaned = lock.cleanup_locks()
    if cleaned > 0 then
      table.insert(fixes_applied, 'Cleaned ' .. cleaned .. ' stale lock files')
    end
  end
  
  if #fixes_applied > 0 then
    notify.himalaya('✅ Applied fixes:', notify.categories.USER_ACTION)
    for _, fix in ipairs(fixes_applied) do
      notify.himalaya('  - ' .. fix, notify.categories.STATUS)
    end
  else
    notify.himalaya('No automatic fixes available', notify.categories.STATUS)
  end
  
  -- Show report again
  vim.defer_fn(function()
    M.show_report()
  end, 1000)
end

return M