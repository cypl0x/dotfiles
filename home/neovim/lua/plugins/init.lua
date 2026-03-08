local ok_which, which_key = pcall(require, "which-key")
if ok_which then
  which_key.setup({
    preset = "modern",
    delay = 300,
  })

  which_key.add({
    {"<leader>w", group = "window"},
    {"<leader>b", group = "buffer"},
    {"<leader>p", group = "project"},
    {"<leader>t", group = "toggle"},
    {"<leader>o", group = "open"},
    {"<leader>g", group = "git"},
    {"<leader>c", group = "code"},
  })
end

local ok_telescope, telescope = pcall(require, "telescope")
if ok_telescope then
  local actions = require("telescope.actions")

  telescope.setup({
    defaults = {
      mappings = {
        i = {
          ["<C-j>"] = actions.move_selection_next,
          ["<C-k>"] = actions.move_selection_previous,
        },
      },
      layout_config = {
        horizontal = {
          preview_width = 0.56,
        },
      },
      sorting_strategy = "ascending",
      prompt_prefix = " > ",
    },
  })

  pcall(telescope.load_extension, "fzf")
end

local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>pf", builtin.find_files, {desc = "Find files", silent = true})
vim.keymap.set("n", "<leader>pg", builtin.live_grep, {desc = "Live grep", silent = true})
vim.keymap.set("n", "<leader>pb", builtin.buffers, {desc = "Project buffers", silent = true})
vim.keymap.set("n", "<leader>pp", builtin.oldfiles, {desc = "Recent files", silent = true})
vim.keymap.set("n", "<leader>bb", builtin.buffers, {desc = "Switch buffer", silent = true})

local ok_project, project = pcall(require, "project_nvim")
if ok_project then
  project.setup({
    detection_methods = {"lsp", "pattern"},
    patterns = {".git", "flake.nix", "package.json", "Cargo.toml", "go.mod"},
    silent_chdir = true,
  })
  if ok_telescope then
    pcall(telescope.load_extension, "projects")
  end
  vim.keymap.set("n", "<leader>ps", "<cmd>Telescope projects<CR>", {desc = "Switch project", silent = true})
end

local ok_gitsigns, gitsigns = pcall(require, "gitsigns")
if ok_gitsigns then
  gitsigns.setup({
    signs = {
      add = {text = "+"},
      change = {text = "~"},
      delete = {text = "_"},
      topdelete = {text = "^"},
      changedelete = {text = "~"},
      untracked = {text = "+"},
    },
  })

  vim.keymap.set("n", "]h", gitsigns.next_hunk, {desc = "Next hunk", silent = true})
  vim.keymap.set("n", "[h", gitsigns.prev_hunk, {desc = "Prev hunk", silent = true})
  vim.keymap.set("n", "<leader>gs", gitsigns.stage_hunk, {desc = "Stage hunk", silent = true})
  vim.keymap.set("n", "<leader>gr", gitsigns.reset_hunk, {desc = "Reset hunk", silent = true})
  vim.keymap.set("n", "<leader>gp", gitsigns.preview_hunk, {desc = "Preview hunk", silent = true})
end

local ok_treesitter, treesitter = pcall(require, "nvim-treesitter.configs")
if ok_treesitter then
  treesitter.setup({
    highlight = {enable = true},
    indent = {enable = true},
    ensure_installed = {},
  })
end

local ok_lualine, lualine = pcall(require, "lualine")
if ok_lualine then
  local lualine_theme = require("core.theme").lualine
  lualine.setup({
    options = {
      theme = lualine_theme,
      globalstatus = true,
      section_separators = "",
      component_separators = "|",
    },
  })
end

local ok_cmp, cmp = pcall(require, "cmp")
if ok_cmp then
  local luasnip = require("luasnip")
  require("luasnip.loaders.from_vscode").lazy_load()

  cmp.setup({
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
    mapping = cmp.mapping.preset.insert({
      ["<C-j>"] = cmp.mapping.select_next_item(),
      ["<C-k>"] = cmp.mapping.select_prev_item(),
      ["<C-b>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      ["<CR>"] = cmp.mapping.confirm({select = false}),
      ["<Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        else
          fallback()
        end
      end, {"i", "s"}),
      ["<S-Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, {"i", "s"}),
    }),
    sources = cmp.config.sources({
      {name = "nvim_lsp"},
      {name = "luasnip"},
      {name = "path"},
      {name = "buffer"},
    }),
  })

  cmp.setup.cmdline({"/", "?"}, {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {{name = "buffer"}},
  })

  cmp.setup.cmdline(":", {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
      {name = "path"},
    }, {
      {name = "cmdline"},
    }),
  })
end

local ok_autopairs, autopairs = pcall(require, "nvim-autopairs")
if ok_autopairs then
  autopairs.setup({})
end

local ok_comment, comment = pcall(require, "Comment")
if ok_comment then
  comment.setup({})
end

if vim.lsp and vim.lsp.config and vim.lsp.enable then
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  local ok_cmp_lsp, cmp_lsp = pcall(require, "cmp_nvim_lsp")
  if ok_cmp_lsp then
    capabilities = cmp_lsp.default_capabilities(capabilities)
  end

  local on_attach = function(_, bufnr)
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, {buffer = bufnr, silent = true, desc = desc})
    end

    map("n", "gd", vim.lsp.buf.definition, "Go to definition")
    map("n", "gr", vim.lsp.buf.references, "References")
    map("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
    map("n", "gi", vim.lsp.buf.implementation, "Implementation")
    map("n", "K", vim.lsp.buf.hover, "Hover")
    map("n", "<leader>cr", vim.lsp.buf.rename, "Rename symbol")
    map({"n", "v"}, "<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("n", "<leader>cf", function()
      vim.lsp.buf.format({async = true})
    end, "Format buffer")
  end

  local function setup_if(server, bin, extra)
    if vim.fn.executable(bin) == 1 then
      local cfg = {
        capabilities = capabilities,
        on_attach = on_attach,
      }
      if extra then
        cfg = vim.tbl_deep_extend("force", cfg, extra)
      end
      vim.lsp.config(server, cfg)
      vim.lsp.enable(server)
    end
  end

  setup_if("bashls", "bash-language-server")
  setup_if("nil_ls", "nil")
  setup_if("rust_analyzer", "rust-analyzer")
  setup_if("marksman", "marksman")
  setup_if("lua_ls", "lua-language-server", {
    settings = {
      Lua = {
        diagnostics = {
          globals = {"vim"},
        },
      },
    },
  })

  local has_ts_ls = #vim.api.nvim_get_runtime_file("lsp/ts_ls.lua", false) > 0
  if has_ts_ls then
    setup_if("ts_ls", "typescript-language-server")
  else
    setup_if("tsserver", "typescript-language-server")
  end
end
