return {
  "gleachkr/lectic",
  lazy = true,
  -- Use both markdown and lectic.markdown filetypes
  ft = { "markdown", "lectic.markdown" },
  build = "npm install", -- Install dependencies
  -- Don't modify the dir path - it's causing installation issues
  -- The plugin needs to be installed correctly first
  -- We'll let it install completely, then configure it
  init = function()
    -- Create the autocmd group early
    vim.api.nvim_create_augroup("Lectic", { clear = true })

    -- Keymappings are now defined in which-key.lua to centralize all mappings

    -- Add filetype detection for .lec files if not already defined
    vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
      group = "Lectic",
      pattern = "*.lec",
      callback = function()
        vim.bo.filetype = "lectic.markdown"
      end
    })
  end,
  config = function()
    -- Create a global function to submit current lectic section
    -- (to be used by which-key.lua)
    function _G.SubmitLecticSelection()
      -- Only run if we're in a lectic markdown buffer
      if vim.bo.filetype ~= "lectic.markdown" then
        vim.notify("This command only works in Lectic files (.lec)", vim.log.levels.WARN)
        return
      end

      -- Make sure the file is saved first
      if vim.bo.modified then
        vim.notify("Saving file before submitting to Lectic...", vim.log.levels.INFO)
        vim.cmd("write")
      end

      -- Get the visual selection using marks
      local selected_text = ""

      -- Check if visual marks exist in the buffer
      if vim.fn.getpos("'<")[2] > 0 and vim.fn.getpos("'>")[2] > 0 then
        -- Get start and end positions
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")

        -- Convert to 0-indexed for API calls
        local start_line = start_pos[2] - 1
        local start_col = start_pos[3] - 1
        local end_line = end_pos[2] - 1
        local end_col = end_pos[3]

        -- Get the lines in the selection
        local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line + 1, false)

        if #lines > 0 then
          -- Process the selection based on whether it spans multiple lines
          if #lines == 1 then
            -- Single line selection
            selected_text = string.sub(lines[1], start_col + 1, end_col)
          else
            -- Multi-line selection
            -- Adjust first and last line for partial selection
            lines[1] = string.sub(lines[1], start_col + 1)
            lines[#lines] = string.sub(lines[#lines], 1, end_col)
            selected_text = table.concat(lines, "\n")
          end
        end
      end

      -- Check if we have a selection
      if selected_text == "" then
        vim.notify("No text selected. Please select text in visual mode first.", vim.log.levels.WARN)
        return
      end

      -- Format the selected text
      local formatted_selection = "Text Selection:\n" .. selected_text .. "\n"

      -- Prompt for user message with a larger input box
      vim.ui.input({
        prompt = "Add a message or question: ",
        completion = "buffer",
        width = 80,      -- Make the input box wider
        height = 10,     -- Allow multiple lines of input
        multiline = true -- Support paragraph entry
      }, function(user_message)
        if not user_message or user_message == "" then
          vim.notify("Operation cancelled - no message provided", vim.log.levels.WARN)
          return
        end

        -- Format the user message
        local formatted_message = "User Message:\n" .. user_message

        -- Combine selection and message with only one blank line between them
        local combined_content = formatted_selection .. "\n" .. formatted_message

        -- Append to the end of the document
        local line_count = vim.api.nvim_buf_line_count(0)

        -- Check if the last line is empty, if not add exactly one newline
        local last_line = vim.api.nvim_buf_get_lines(0, line_count - 1, line_count, false)[1]
        local separator = (last_line and last_line ~= "") and "\n" or ""

        -- Add the content to the end of the buffer
        vim.api.nvim_buf_set_lines(0, line_count, line_count, false,
          vim.split(separator .. combined_content .. "\n", "\n"))

        -- Add a visual indicator that we're processing
        local ns_id = vim.api.nvim_create_namespace("lectic_processing")
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local extmark_id = vim.api.nvim_buf_set_extmark(0, ns_id, line - 1, 0, {
          virt_text = { { "Processing with Lectic AI...", "Comment" } },
          virt_text_pos = "eol",
        })

        -- Send the file to Lectic
        local ok, err = pcall(function()
          -- The plugin only has submit_lectic, not submit_current_section
          require("lectic.submit").submit_lectic()
        end)

        -- Clear the processing indicator
        vim.api.nvim_buf_del_extmark(0, ns_id, extmark_id)

        -- Handle errors
        if not ok then
          vim.notify("Error submitting to Lectic: " .. tostring(err), vim.log.levels.ERROR)
        else
          vim.notify("Selection and message submitted to Lectic", vim.log.levels.INFO)

          -- Move cursor to the end of the file
          local content_lines = vim.split(combined_content, "\n")
          vim.api.nvim_win_set_cursor(0, { line_count + #content_lines, 0 })
        end
      end)
    end

    -- Create a function to create a new Lectic file
    -- (to be used by which-key.lua)
    function _G.CreateNewLecticFile()
      -- Open a new buffer with .lec extension
      vim.cmd("enew")
      vim.cmd("setfiletype lectic.markdown")

      -- Create a welcome template
      local template = "---\n" ..
          "interlocutor:\n" ..
          "  # Required fields\n" ..
          "  name: Computer Scientist\n" ..
          "  prompt: You are an expert logician and computer scientist specializing in RL and agentic reasoning in AI.\n\n" ..
          "  # Optional model configuration\n" ..
          "  provider: anthropic           # Optional, default anthropic\n" ..
          "  # model: claude-3-7-sonnet    # Model selection\n" ..
          "  # temperature: 0.7            # Response variability (0-1)\n" ..
          "  # max_tokens: 1024            # Maximum response length\n\n" ..
          "  # Optional Context management\n" ..
          "  # memories: previous.txt        # Context from previous conversations.\n" ..
          "                                # Added to system prompt.\n" ..
          "                                # Can be string or file path\n\n" ..
          "  # # Tool integration\n" ..
          "  # tools:\n" ..
          "  #   # Command execution tool\n" ..
          "  #   exec: python3           # Command to execute\n" ..
          "  #   usage: Before running any code, show the code snippet to the user.\n" ..
          "  #   name: python            # Optional custom name\n" ..
          "---\n\n" ..
          "<!-- Instructions: Write your prompt below, then use <leader>mr to submit it,\n" ..
          "or select text and use <leader>ms to submit just that selection. -->\n\n"

      -- Insert the template
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(template, "\n"))

      -- Get the current working directory
      local cwd = vim.fn.getcwd()

      -- Use telescope to select the save location if available
      if pcall(require, "telescope") and pcall(require, "telescope.builtin") then
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values

        -- Create a default filename with date
        local default_filename = os.date("lectic-%Y-%m-%d.lec")

        -- Create picker for directory selection
        pickers.new({}, {
          prompt_title = "Select Directory to Save Lectic File",
          finder = finders.new_oneshot_job({ "find", cwd, "-type", "d", "-not", "-path", "*/\\.*" }, {}),
          sorter = conf.file_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)

              if selection then
                local dir = selection[1]

                -- Now prompt for filename within the selected directory
                vim.ui.input({
                  prompt = "Save as (in " .. dir .. "): ",
                  default = default_filename,
                  completion = "file"
                }, function(filename)
                  if filename and filename ~= "" then
                    -- Make sure it has .lec extension
                    if not filename:match("%.lec$") then
                      filename = filename .. ".lec"
                    end

                    -- Create the full path
                    local full_path = dir .. "/" .. filename

                    -- Try to save the file
                    local ok, err = pcall(function()
                      vim.cmd("write " .. vim.fn.fnameescape(full_path))
                    end)

                    -- Notify success or failure
                    if ok then
                      vim.notify("Lectic file created: " .. full_path, vim.log.levels.INFO)
                      -- Move cursor to position ready to write
                      vim.api.nvim_win_set_cursor(0, { 13, 0 })
                    else
                      vim.notify("Failed to save file: " .. err, vim.log.levels.ERROR)
                    end
                  end
                end)
              end
            end)
            return true
          end,
        }):find()
      else
        -- Fallback for when telescope is not available
        -- Save file with simple interface
        vim.ui.input({
          prompt = "Save Lectic file as (full path): ",
          default = cwd .. "/" .. os.date("lectic-%Y-%m-%d.lec"),
          completion = "file"
        }, function(filepath)
          if filepath and filepath ~= "" then
            -- Make sure it has .lec extension
            if not filepath:match("%.lec$") then
              filepath = filepath .. ".lec"
            end

            -- Try to save the file
            local ok, err = pcall(function()
              vim.cmd("write " .. vim.fn.fnameescape(filepath))
            end)

            -- Notify success or failure
            if ok then
              vim.notify("Lectic file created: " .. filepath, vim.log.levels.INFO)
              -- Move cursor to position ready to write
              vim.api.nvim_win_set_cursor(0, { 13, 0 })
            else
              vim.notify("Failed to save file: " .. err, vim.log.levels.ERROR)
            end
          end
        end)
      end
    end

    -- Register the command to use the plugin's submit function
    vim.api.nvim_create_user_command(
      'Lectic',
      function(opts)
        local start_line = opts.line1
        local end_line = opts.line2
        require("lectic.submit").submit_lectic(start_line, end_line)
      end,
      {
        range = "%",
        desc = "Process current buffer with Lectic AI (can be used with visual selections)",
        nargs = "?",
        complete = function()
          return { "gpt-4", "gpt-3.5-turbo" }
        end
      }
    )

    -- Configure any additional plugin settings
    vim.g.lectic_model = "gpt-4" -- Default model

    -- Create additional keymaps for Lectic files
    vim.api.nvim_create_autocmd("FileType", {
      group = "Lectic",
      pattern = "lectic.markdown",
      callback = function(ev)
        local bufnr = ev.buf

        -- Use the global manual folding settings from options.lua
        -- No need to set folding options specifically for lectic

        -- Also set standard markdown settings for this buffer
        vim.opt_local.conceallevel = 2     -- Enable concealing of syntax
        vim.opt_local.concealcursor = "nc" -- Conceal in normal and command mode

        -- Apply markdown-specific keymaps
        -- This is defined in keymaps.lua and adds bullet point handling, etc.
        _G.set_markdown_keymaps()

        -- Add lectic-specific indicator in the statusline
        vim.opt_local.statusline = "%<%f %h%m%r%=Model: " .. vim.g.lectic_model .. " | lectic.markdown %l,%c%V %P"
      end
    })
  end,
  -- Define dependencies if needed
  dependencies = {
    "nvim-lua/plenary.nvim",          -- Required by many plugins
    "nvim-treesitter/nvim-treesitter" -- For better folding support
  }
}
