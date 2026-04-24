return {
  -- Extend snacks.nvim (already provided by LazyVim) with opencode requirements
  {
    "folke/snacks.nvim",
    opts = {
      input = {}, -- enhances ask()
      picker = {
        actions = {
          opencode_send = function(...) return require("opencode").snacks_picker_send(...) end,
        },
        win = {
          input = {
            keys = {
              ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
            },
          },
        },
      },
    },
  },

  -- opencode.nvim
  {
    "nickjvandyke/opencode.nvim",
    dependencies = {
      {
        -- snacks.nvim integration is recommended but optional
        "folke/snacks.nvim",
        optional = true,
      },
    },
    config = function()
      ---@type opencode.Opts
      vim.g.opencode_opts = {
        contexts = {
          ["@buffer"] = function(context)
            local filename = vim.api.nvim_buf_get_name(context.buf)
            local ft = vim.api.nvim_get_option_value("filetype", { buf = context.buf })
            local header = filename ~= "" and vim.fn.fnamemodify(filename, ":~") or "buffer"
            local lines = vim.api.nvim_buf_get_lines(context.buf, 0, -1, false)
            return string.format("```%s\n-- %s\n%s\n```", ft, header, table.concat(lines, "\n"))
          end,
          ["@buffers"] = function(_context)
            local summaries = {}
            for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
              local name = vim.api.nvim_buf_get_name(buf.bufnr)
              if name ~= "" then
                local short = vim.fn.fnamemodify(name, ":~")
                local ft = vim.api.nvim_get_option_value("filetype", { buf = buf.bufnr })
                local line_count = vim.api.nvim_buf_line_count(buf.bufnr)
                table.insert(summaries, string.format("- %s  [%s, %d lines]", short, ft ~= "" and ft or "?", line_count))
              end
            end
            if #summaries == 0 then return nil end
            return "Open buffers:\n" .. table.concat(summaries, "\n")
          end,
          ["@visible"] = function(_context)
            local parts = {}
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              local buf = vim.api.nvim_win_get_buf(win)
              local name = vim.api.nvim_buf_get_name(buf)
              if name ~= "" then
                local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
                local short = vim.fn.fnamemodify(name, ":~")
                local from = vim.fn.line("w0", win)
                local to = vim.fn.line("w$", win)
                local lines = vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
                table.insert(parts, string.format("```%s\n-- %s:L%d-L%d\n%s\n```", ft, short, from, to, table.concat(lines, "\n")))
              end
            end
            if #parts == 0 then return nil end
            return table.concat(parts, "\n\n")
          end,
          ["@this"] = function(context)
            local filename = vim.api.nvim_buf_get_name(context.buf)
            local ft = vim.api.nvim_get_option_value("filetype", { buf = context.buf })
            local header = filename ~= "" and vim.fn.fnamemodify(filename, ":~") or "buffer"

            local lines, from_line, to_line
            if context.range then
              from_line = context.range.from[1]
              to_line = context.range.to[1]
              lines = vim.api.nvim_buf_get_lines(context.buf, from_line - 1, to_line, false)
              header = header .. string.format(":L%d-L%d", from_line, to_line)
            else
              from_line = context.cursor[1]
              to_line = from_line
              lines = vim.api.nvim_buf_get_lines(context.buf, from_line - 1, to_line, false)
              header = header .. string.format(":L%d", from_line)
            end

            return string.format("```%s\n-- %s\n%s\n```", ft, header, table.concat(lines, "\n"))
          end,
        },
        prompts = {
          -- Fast prompts: single-shot, no tool calls, respond directly in chat.
          -- Only explain and diagnostics remain fast; all others load a skill and edit files.
          explain = {
            submit = true,
            prompt = [[You are a senior technical analyst. Analyze the following code and produce:
1. Summary: one-paragraph overview of what this code does and why
2. Findings: numbered, specific observations about logic, patterns, data flow, and dependencies
3. Recommendations: suggested improvements if any
4. Open Questions: anything unclear without more context

Back claims with evidence. Distinguish facts from assumptions.

Explain @this and its context

Do NOT call any tools or load any skills. Respond directly.]],
          },
          document = {
            submit = true,
            prompt = [[Load the documenter skill. Then add documentation to @this.

Rules:
- Add doc comments (/// for Rust, /** */ for TypeScript) to all public items
- Explain *what* and *why*, not *how* (the code shows how)
- Document parameters, return values, error conditions, and panics
- Keep comments concise and consistent with the surrounding code
- Do not invent behavior -- only document what the code actually does

Apply the doc comments directly to the source file.]],
          },
          optimize = {
            submit = true,
            prompt = [[Load the programmer skill. Then optimize @this for performance and readability.

Consider:
- Unnecessary heap allocations
- Unnecessary clones -- prefer borrowing
- Algorithmic complexity
- Iterator chains vs manual loops
- Cache-friendly data access patterns

Rules:
- Explain the performance issue before proposing a fix
- Preserve correctness -- do not sacrifice safety for speed
- No unwrap() or expect() in production code
- Use Result<T, E> / Option<T> for error handling

Apply the optimizations directly to the source file.]],
          },
          diagnostics = {
            submit = true,
            prompt = [[You are a senior technical analyst. Analyze the following diagnostics and explain:
1. What each diagnostic means in plain language
2. Why it occurs -- trace the root cause
3. Severity: is it a bug, a warning to address, or noise?
4. How to fix it -- describe the minimal change needed

Back claims with evidence. Be specific about file paths and line numbers.

Explain @diagnostics

Do NOT call any tools or load any skills. Respond directly.]],
          },
          -- Full prompts: tool-aware, load a skill, and apply changes directly to source files.
          -- Require a write-capable agent (build or local) to edit files.
          -- Skill mapping: document→documenter, optimize/implement→programmer, review/diff→reviewer, test→tester, fix→debugger.
          review = {
            submit = true,
            prompt = [[Load the reviewer skill. Then review @this for correctness, security, and readability.

Report findings grouped by severity: Critical, Important, Suggestions.
Be specific — reference exact lines when possible.]],
          },
          implement = {
            submit = true,
            prompt = [[Load the programmer skill. Then implement @this.

Follow conventions already in the codebase. Handle errors and edge cases explicitly.
Implement in small, logical steps.]],
          },
          test = {
            submit = true,
            prompt = [[Load the tester skill. Then write tests for @this.

Cover happy path, edge cases, and error paths.
Run existing tests first to understand current state.]],
          },
          fix = {
            submit = true,
            prompt = [[Load the debugger skill. Then fix @diagnostics.

Identify the root cause before changing code. Make the smallest change that fixes the issue.
Verify the fix does not break existing tests.]],
          },
          diff = {
            submit = true,
            prompt = [[Load the reviewer skill. Then review the following git diff for correctness and readability: @diff

Report findings grouped by severity: Critical, Important, Suggestions.
Focus on changed lines, but consider surrounding context. Flag missing tests for new functionality.]],
          },
        },
      }

      -- Required for buffer reload when opencode edits files on disk
      vim.o.autoread = true

      -- Ask opencode with @this context (cursor position or visual selection).
      vim.keymap.set({ "n", "x" }, "<leader>oa", function()
        require("opencode").ask("@this: ", { submit = true })
      end, { desc = "Ask opencode" })
      -- Open action selector (prompts, commands, server controls).
      vim.keymap.set({ "n", "x" }, "<leader>os", function()
        require("opencode").select()
      end, { desc = "Select opencode action" })
      -- Toggle opencode panel
      vim.keymap.set({ "n", "t" }, "<leader>ot", function() require("opencode").toggle() end, { desc = "Toggle opencode" })

      -- Operator: send motion range to opencode (supports dot-repeat)
      vim.keymap.set({ "n", "x" }, "go", function() return require("opencode").operator("@this ") end, { desc = "Add range to opencode", expr = true })
      vim.keymap.set("n", "goo", function() return require("opencode").operator("@this ") .. "_" end, { desc = "Add line to opencode", expr = true })

      -- Scroll opencode session
      vim.keymap.set("n", "<S-C-u>", function() require("opencode").command("session.half.page.up") end, { desc = "Scroll opencode up" })
      vim.keymap.set("n", "<S-C-d>", function() require("opencode").command("session.half.page.down") end, { desc = "Scroll opencode down" })
    end,
  },

  -- Extend lualine (already provided by LazyVim) with opencode status in lualine_z
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_z, {
        require("opencode").statusline,
      })
      return opts
    end,
  },
}
