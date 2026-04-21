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
          explain = {
            submit = true,
            prompt = [[You are a senior technical analyst. Analyze the following code and produce:
1. Summary: one-paragraph overview of what this code does and why
2. Findings: numbered, specific observations about logic, patterns, data flow, and dependencies
3. Recommendations: suggested improvements if any
4. Open Questions: anything unclear without more context

Back claims with evidence. Distinguish facts from assumptions.

Explain @this and its context

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
          review = {
            submit = true,
            prompt = [[You are a meticulous code reviewer. Review the following code and report findings grouped by severity:

## Critical (must fix)
Logic errors, security issues, data loss risks.

## Important (should fix)
Performance bottlenecks, poor error handling, missing edge cases.

## Suggestions (nice to have)
Style, naming, minor improvements, optional refactors.

Rules:
- Be specific: reference exact lines when possible
- Explain *why* something is a problem
- Flag missing tests for new functionality

Rust-specific checks:
- Flag any unwrap() or expect() in production code (not tests)
- Flag unsafe blocks missing a safety comment
- Check for unnecessary clones, unused results
- Verify error handling uses Result<T, E> / Option<T>, not panics

Review @this for correctness and readability

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
          document = {
            submit = true,
            prompt = [[You are a documentation specialist. Add clear, accurate documentation to the following code.

Rules:
- Add doc comments (/// for Rust) to all public items
- Explain *what* and *why*, not *how* (the code shows how)
- Document parameters, return values, error conditions, and panics
- Keep comments concise and consistent with the surrounding code
- Do not invent behavior -- only document what the code actually does
- If something is unclear, mark it as "needs confirmation"

Add comments documenting @this

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
          implement = {
            submit = true,
            prompt = [[You are a senior software engineer. Implement the following.

Workflow:
1. Understand the requirement and existing code context
2. Plan the approach if non-trivial
3. Implement in small, logical steps
4. Include error handling and edge cases

Rules:
- Follow conventions already in the codebase
- Handle errors explicitly -- no unwrap() or expect() in production code
- Use Result<T, E> / Option<T> and the ? operator for error propagation
- Prefer ownership and borrowing over cloning
- Favor immutability by default
- Keep functions small and composable
- Do not add dependencies without clear reason

Implement @this

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
          optimize = {
            submit = true,
            prompt = [[You are a senior software engineer focused on performance. Optimize the following code.

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
- Prefer slices over owned collections where possible

Optimize @this for performance and readability

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
          test = {
            submit = true,
            prompt = [[You are a quality-focused test engineer. Write tests for the following code.

Structure tests as:
1. Happy path: core expected behavior under normal conditions
2. Edge cases: boundary values, empty inputs, max/min
3. Error paths: invalid inputs, failures, error conditions

Principles:
- Arrange / Act / Assert structure
- One logical concern per test
- Test names describe *behavior*, not implementation
- Tests must be deterministic and isolated

Rust-specific:
- Use #[cfg(test)] modules for unit tests
- Integration tests go under tests/
- Target 90% coverage with cargo tarpaulin
- Exclude UI and CUDA functions with #[cfg(not(tarpaulin_include))]

Add tests for @this

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
          fix = {
            submit = true,
            prompt = [[You are a senior software engineer. Fix the following diagnostics with minimal, targeted changes.

Rules:
- Identify the root cause before changing code
- Make the smallest change that fixes the issue
- Do not refactor unrelated code
- Handle errors with Result<T, E> / Option<T> and the ? operator
- No unwrap() or expect() in production code
- Preserve existing tests; add a new test if the fix covers an untested path

Fix @diagnostics

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
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

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
          diff = {
            submit = true,
            prompt = [[You are a meticulous code reviewer. Review the following git diff and report findings grouped by severity:

## Critical (must fix)
Logic errors, security issues, regressions.

## Important (should fix)
Performance issues, poor error handling, missing edge cases.

## Suggestions (nice to have)
Style, naming, minor improvements.

Rules:
- Focus on changed lines, but consider surrounding context
- Explain *why* something is a problem
- Flag missing tests for new functionality

Rust-specific checks:
- Flag any unwrap() or expect() in production code
- Flag unsafe blocks missing a safety comment
- Check for unnecessary clones, unused results

Review the following git diff for correctness and readability: @diff

Do NOT call any tools or load any skills. Respond directly.

/no_think]],
          },
        },
      }

      -- Required for buffer reload when opencode edits files on disk
      vim.o.autoread = true

      -- Ask opencode with @this context (cursor position or visual selection)
      vim.keymap.set({ "n", "x" }, "<leader>oa", function() require("opencode").ask("@this: ", { submit = true }) end, { desc = "Ask opencode" })
      -- Open action selector (prompts, commands, server controls)
      vim.keymap.set({ "n", "x" }, "<leader>os", function() require("opencode").select() end, { desc = "Select opencode action" })
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
