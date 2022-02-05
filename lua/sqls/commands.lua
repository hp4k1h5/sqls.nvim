local api = vim.api
local fn = vim.fn

local user_options = require('sqls')._user_options

local M = {}

---@alias lsp_handler fun(err?: table, result?: any, ctx: table, config: table)

---@param mods string
---@return lsp_handler
local function make_show_results_handler(mods)
    return function(err, result, _, _)
        if err then
            vim.notify('sqls: ' .. err.message, vim.log.levels.ERROR)
            return
        end
        if not result then
            return
        end
        local tempfile = fn.tempname() .. '.sqls_output'
        local bufnr = fn.bufnr(tempfile, true)
        api.nvim_buf_set_lines(bufnr, 0, 1, false, vim.split(result, '\n'))
        vim.cmd(('%s pedit %s'):format(mods or '', tempfile))
        api.nvim_buf_set_option(bufnr, 'filetype', 'sqls_output')
    end
end

---@param command string
---@param mods? string
---@param range_given? boolean
---@param show_vertical? '-show-vertical'
---@param line1? integer
---@param line2? integer
function M.exec(command, mods, range_given, show_vertical, line1, line2)
    local range
    if range_given then
        range = vim.lsp.util.make_given_range_params({line1, 0}, {line2, math.huge}).range
        range['end'].character = range['end'].character - 1
    end

    vim.lsp.buf_request(
        0,
        'workspace/executeCommand',
        {
            command = command,
            arguments = {vim.uri_from_bufnr(0), show_vertical},
            range = range,
        },
        make_show_results_handler(mods)
        )
end

---@alias operatorfunc fun(type: 'block'|'line'|'char')

---@param show_vertical? '-show-vertical'
---@return operatorfunc
local function make_query_mapping(show_vertical)
    return function(type)
        local range
        local _, lnum1, col1, _ = unpack(fn.getpos("'["))
        local _, lnum2, col2, _ = unpack(fn.getpos("']"))
        if type == 'block' then
            vim.notify('sqls does not support block-wise ranges!', vim.log.levels.ERROR)
            return
        elseif type == 'line' then
            range = vim.lsp.util.make_given_range_params({lnum1, 0}, {lnum2, math.huge}).range
            range['end'].character = range['end'].character - 1
        elseif type == 'char' then
            range = vim.lsp.util.make_given_range_params({lnum1, col1 - 1}, {lnum2, col2 - 1}).range
        end

        vim.lsp.buf_request(
            0,
            'workspace/executeCommand',
            {
                command = 'executeQuery',
                arguments = {vim.uri_from_bufnr(0), show_vertical},
                range = range,
            },
            make_show_results_handler('')
            )
    end
end

M.query = make_query_mapping()
M.query_vertical = make_query_mapping('-show-vertical')

---@alias switch_function fun(query: string)
---@alias prompt_function fun(switch_function: switch_function)
---@alias answer_formatter fun(answer: string): string
---@alias switcher fun(query: string)

---@param switch_function switch_function
---@param answer_formatter answer_formatter
---@return lsp_handler
local function make_choice_handler(switch_function, answer_formatter)
    return function(err, result, _, _)
        if err then
            vim.notify('sqls: ' .. err.message, vim.log.levels.ERROR)
            return
        end
        if not result then
            return
        end
        if result == '' then
            vim.notify('sqls: No choices available')
            return
        end
        local choices = vim.split(result, '\n')
        local function switch_callback(answer)
            if not answer then return end
            switch_function(answer_formatter(answer))
        end
        user_options.picker(switch_callback, choices)
    end
end

---@type lsp_handler
local function switch_handler(err, _, _, _)
    if err then
        vim.notify('sqls: ' .. err.message, vim.log.levels.ERROR)
    end
end

---@param command string
---@return switch_function
local function make_switch_function(command)
    return function(query)
        vim.lsp.buf_request(
            0,
            'workspace/executeCommand',
            {
                command = command,
                arguments = {query},
            },
            switch_handler
            )
    end
end

---@param command string
---@param answer_formatter answer_formatter
---@return prompt_function
local function make_prompt_function(command, answer_formatter)
    return function(switch_function)
        vim.lsp.buf_request(
            0,
            'workspace/executeCommand',
            {
                command = command,
            },
            make_choice_handler(switch_function, answer_formatter)
            )
    end
end

---@type answer_formatter
local function format_database_answer(answer) return answer end
---@type answer_formatter
local function format_connection_answer(answer) return vim.split(answer, ' ')[1] end

local database_switch_function = make_switch_function('switchDatabase')
local connection_switch_function = make_switch_function('switchConnections')
local database_prompt_function = make_prompt_function('showDatabases', format_database_answer)
local connection_prompt_function = make_prompt_function('showConnections', format_connection_answer)

---@param prompt_function prompt_function
---@param switch_function switch_function
---@return switcher
local function make_switcher(prompt_function, switch_function)
    return function(query)
        if not query then
            prompt_function(switch_function)
            return
        end
        switch_function(query)
    end
end

M.switch_database = make_switcher(database_prompt_function, database_switch_function)
M.switch_connection = make_switcher(connection_prompt_function, connection_switch_function)

return M
