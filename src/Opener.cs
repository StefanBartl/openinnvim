// Opener.cs - handing the target to one instance, and what its answer means.

using System;

namespace OpenInNvim
{
    public enum OpenOutcome
    {
        /// <summary>The instance confirmed: the file or folder is on screen there.</summary>
        Opened = 0,
        /// <summary>The request was written and no answer came in time. The instance HAS it; see Open.</summary>
        Delivered = 1,
        /// <summary>The instance answered with an error: nothing was opened there, try the next one.</summary>
        Refused = 2,
        /// <summary>The request could not be written: this instance never saw it.</summary>
        NotWritten = 3,
        /// <summary>The instance closed the connection without answering: it is gone, so is the request.</summary>
        Lost = 4
    }

    public static class Opener
    {
        /// <summary>How long the launcher waits (hidden, idle) for the instance to confirm.</summary>
        public const int ReplyTimeoutMs = 15000;

        // Lua run inside the instance by nvim_exec_lua(Lua, { kind, path, folder_mode }).
        //
        // The path arrives as a PARAMETER and never becomes Ex command text: ":drop"/":edit" expand
        // "$NAME" and treat "[...]" as a wildcard even after fnameescape(), which opened a different
        // file. bufadd() takes the name verbatim; the only Ex commands below carry a buffer NUMBER.
        //
        // Where it goes: a window that already shows the buffer (any tabpage) wins. Otherwise the
        // current window if its buffer may be replaced there (not floating, an ordinary buffer, no
        // 'winfixbuf'), else the first such window of the tabpage, else a new split. A window whose
        // buffer has unsaved changes that ":buffer" would have to abandon gets a split as well:
        // ":buffer" would fail with E37 or, with 'confirm', stop the editor at a dialog.
        //
        // A folder (no :Filetree, or FOLDER_OPENS_IN = edit): Neovim expands "$NAME" in a directory
        // name before changing to it, in ":cd", chdir() and nvim_set_current_dir() alike, and offers no
        // escape for a "$" in the middle of a name. A folder "a$USERNAME" would fail or, worse, become
        // another folder. So the variables the name mentions are hidden while the folder is opened
        // (the directory view, netrw for one, changes directory once more by itself).
        //
        // What counts as a refusal: only a failure BEFORE the instance has taken the target. An
        // autocommand that fails after the buffer is on screen, or a directory view that fails after the
        // working directory was changed, is not one: reporting it as an error would send the same
        // target to the next instance too.
        public const string Lua = @"local kind, path, folder_mode = ...
local api, fn = vim.api, vim.fn

if kind == 'dir' and folder_mode == 'filetree' and fn.exists(':Filetree') == 2 then
  vim.cmd({ cmd = 'Filetree', args = { 'open', path } })
  return 'filetree'
end

local function floating(win)
  return api.nvim_win_get_config(win).relative ~= ''
end

local function plain(win)
  if floating(win) then return false end
  if vim.bo[api.nvim_win_get_buf(win)].buftype ~= '' then return false end
  if fn.exists('+winfixbuf') == 1 and vim.wo[win].winfixbuf then return false end
  return true
end

local function replaceable(win)
  local b = api.nvim_win_get_buf(win)
  if not vim.bo[b].modified then return true end
  local bh = vim.bo[b].bufhidden
  if bh == 'hide' or (bh == '' and vim.o.hidden) then return true end
  return #fn.win_findbuf(b) > 1
end

-- Makes the window current that takes the target; true when the target needs a new split.
local function choose()
  local wins = api.nvim_tabpage_list_wins(0)
  local win = api.nvim_get_current_win()
  if not plain(win) then
    win = nil
    for _, w in ipairs(wins) do
      if plain(w) then win = w break end
    end
  end
  if win then
    api.nvim_set_current_win(win)
    return not replaceable(win)
  end
  if floating(api.nvim_get_current_win()) then
    for _, w in ipairs(wins) do
      if not floating(w) then api.nvim_set_current_win(w) break end
    end
  end
  return true
end

if kind == 'dir' then
  local hidden = {}
  for name in path:gmatch('%$([%w_]+)') do
    if vim.env[name] ~= nil then
      hidden[name] = vim.env[name]
      vim.env[name] = nil
    end
  end
  local changed, why = pcall(api.nvim_set_current_dir, path)
  if changed then
    pcall(function()
      if choose() then vim.cmd('silent split .') else vim.cmd('silent edit .') end
    end)
  end
  for name, value in pairs(hidden) do vim.env[name] = value end
  if not changed then error(why, 0) end
  return 'edit'
end

local buf = fn.bufadd(path)
vim.bo[buf].buflisted = true
local ok, err = pcall(function()
  local shown = fn.win_findbuf(buf)
  if #shown > 0 then
    local target = shown[1]
    local tab = api.nvim_get_current_tabpage()
    for _, w in ipairs(shown) do
      if api.nvim_win_get_tabpage(w) == tab then target = w break end
    end
    api.nvim_set_current_win(target)
  elseif choose() then
    vim.cmd('silent sbuffer ' .. buf)
  else
    vim.cmd('silent buffer ' .. buf)
  end
end)
if api.nvim_win_get_buf(0) ~= buf then
  error(ok and 'the buffer is not shown' or err, 0)
end
return 'file'
";

        /// <summary>
        /// Send the open request and wait for the answer.
        ///
        /// Once the request has been written the target is never routed elsewhere unless the instance
        /// itself says "error" (or is gone). A slow open (a big file, LSP start, a swap-file dialog) is not
        /// a refusal: giving up and trying the next instance opened the file twice, and closing the
        /// connection early would drop the queued request. So the launcher simply waits.
        /// </summary>
        public static OpenOutcome Open(Session session, Target target, Config cfg, int replyTimeoutMs, out string detail)
        {
            RpcClient rpc = session.Rpc;

            // Leave Insert, Visual, Command-line, Terminal or operator-pending mode the way a person
            // would, BEFORE the buffer changes: nvim_input is handled on arrival and typed input is read
            // ahead of queued requests, so the Lua below already runs in Normal mode. Without it the
            // editor would stay in Insert mode in the new file, or keep a half-typed command line open.
            if (session.Mode != "n" && session.Mode != "nt")
            {
                rpc.Send("nvim_input", new object[] { "<C-\\><C-N>" });
            }

            string kind = target.Kind == TargetKind.Folder ? "dir" : "file";
            long id = rpc.Send("nvim_exec_lua", new object[] { Lua, new object[] { kind, target.Path, cfg.FolderOpensIn } });
            if (id == 0)
            {
                detail = "the request could not be written";
                return OpenOutcome.NotWritten;
            }
            if (cfg.FocusTerminal) { Focus.Raise(session.Candidate.Pid); }
            Log.Line("request written to " + session.Candidate.Address + ", waiting for the answer");
            Log.Flush();

            RpcReply reply = rpc.Wait(id, replyTimeoutMs);
            switch (reply.Status)
            {
                case ReplyStatus.Ok:
                    detail = reply.Result as string;
                    if (detail == null) { detail = "ok"; }
                    return OpenOutcome.Opened;
                case ReplyStatus.Error:
                    detail = FirstLine(reply.ErrorText);
                    return OpenOutcome.Refused;
                case ReplyStatus.Closed:
                    detail = "the instance closed the connection";
                    return OpenOutcome.Lost;
                default:
                    detail = "no answer yet (" + reply.Status.ToString() + "); the instance has the request";
                    return OpenOutcome.Delivered;
            }
        }

        private static string FirstLine(string text)
        {
            if (text == null) { return ""; }
            int nl = text.IndexOf('\n');
            return nl < 0 ? text : text.Substring(0, nl).TrimEnd('\r');
        }
    }
}
