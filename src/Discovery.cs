// Discovery.cs - which Neovim gets the file: candidates, their order, and the usability probe.

using System;
using System.Collections.Generic;
using System.Globalization;

namespace OpenInNvim
{
    public sealed class Candidate
    {
        /// <summary>Full pipe name or host:port. For a default-pipe instance: the pipe that was verified.</summary>
        public string Address;
        public bool IsTcp;
        public string Host;
        public int Port;
        /// <summary>Process id (0 for TCP: nobody can tell who listens on a port).</summary>
        public int Pid;
        /// <summary>Process creation time (FILETIME ticks); the order key.</summary>
        public long Created;
        /// <summary>
        /// For a default-pipe instance: the indexes n of its nvim.&lt;pid&gt;.&lt;n&gt; pipes, ascending. The lowest
        /// one is used; a higher one is only tried when a lower one is not served by that process.
        /// </summary>
        public List<int> Indexes;
        /// <summary>"default", "stable" or "server" (for the log).</summary>
        public string Source;
    }

    /// <summary>An open, trusted connection to an instance that passed the usability probe.</summary>
    public sealed class Session : IDisposable
    {
        public RpcClient Rpc;
        public Candidate Candidate;
        /// <summary>The mode nvim_get_mode reported ("n", "i", "c", ...).</summary>
        public string Mode;

        public void Dispose()
        {
            if (Rpc != null) { Rpc.Dispose(); Rpc = null; }
        }
    }

    public sealed class DiscoveryResult
    {
        public List<Candidate> Candidates = new List<Candidate>();
        /// <summary>NVIM_SERVER when it is a pipe name nobody serves yet: a new instance may listen there.</summary>
        public string ListenPipe;
    }

    public static class Discovery
    {
        /// <summary>
        /// Limits. Connecting to an existing local pipe and nvim_get_mode (a "fast" API call, answered even
        /// at a hit-enter prompt) take about a millisecond each; whoever needs 300 ms is hung.
        /// </summary>
        public const int ConnectTimeoutMs = 300;
        public const int ProbeTimeoutMs = 300;

        /// <summary>
        /// The ordered candidate list. Nothing is written to any instance here: default pipes are checked
        /// through their process only; the stable pipe and a pipe NVIM_SERVER are connected to once, just
        /// to learn (and verify) which process serves them.
        /// </summary>
        public static DiscoveryResult Find(Config cfg, Hooks hooks)
        {
            DiscoveryResult result = new DiscoveryResult();
            List<Candidate> list = result.Candidates;

            List<string> names = Pipes.List();
            Dictionary<int, Candidate> byPid = new Dictionary<int, Candidate>();
            for (int i = 0; i < names.Count; i++)
            {
                int pid, index;
                if (!Pipes.TryParseDefault(names[i], out pid, out index)) { continue; }
                if (hooks.OnlyPids != null && Array.IndexOf(hooks.OnlyPids, pid) < 0) { continue; }
                Candidate known;
                if (byPid.TryGetValue(pid, out known))
                {
                    known.Indexes.Add(index);
                    continue;
                }
                long created;
                string reason = Trust.CheckProcess(pid, out created);
                if (reason != null)
                {
                    Log.Line("skip " + names[i] + ": " + reason);
                    // Remembered (without a place in the list) so its other pipes are not checked again.
                    known = new Candidate();
                    known.Indexes = new List<int>();
                    byPid[pid] = known;
                    continue;
                }
                known = new Candidate();
                known.Pid = pid;
                known.Created = created;
                known.Source = "default";
                known.Indexes = new List<int>();
                known.Indexes.Add(index);
                byPid[pid] = known;
                list.Add(known);
            }
            for (int i = 0; i < list.Count; i++)
            {
                list[i].Indexes.Sort();
                list[i].Address = DefaultPipe(list[i].Pid, list[i].Indexes[0]);
            }

            bool oldestFirst = cfg.InstancePick == "oldest";
            list.Sort(delegate(Candidate a, Candidate b)
            {
                int c = a.Created.CompareTo(b.Created);
                if (c == 0) { c = a.Pid.CompareTo(b.Pid); }
                return oldestFirst ? c : -c;
            });

            int front = 0;
            string server = cfg.NvimServer == null ? "" : cfg.NvimServer.Trim();
            string serverPipe = null;
            if (server.Length > 0)
            {
                string host;
                int port;
                if (Pipes.IsPipeAddress(server)) { serverPipe = server; }
                else if (TcpChannel.TryParseAddress(server, out host, out port))
                {
                    // In ONLY_PIDS mode nothing but the listed processes may be contacted, and a port has no PID.
                    if (hooks.OnlyPids != null && !hooks.AllowTcp)
                    {
                        Log.Line("NVIM_SERVER " + server + " not used: OPEN_IN_NVIM_ONLY_PIDS is set (OPEN_IN_NVIM_ALLOW_TCP=1 allows it)");
                    }
                    else
                    {
                        Candidate tcp = new Candidate();
                        tcp.Address = server;
                        tcp.IsTcp = true;
                        tcp.Host = host;
                        tcp.Port = port;
                        tcp.Source = "server";
                        list.Insert(front++, tcp);
                    }
                }
                else if (server.IndexOfAny(new char[] { '\\', '/', ':' }) < 0) { serverPipe = Pipes.Prefix + server; }
                else { Log.Line("NVIM_SERVER '" + server + "' is neither a pipe name nor host:port; ignored"); }
            }

            if (serverPipe != null)
            {
                bool missing;
                Promote(list, serverPipe, "server", hooks, ref front, out missing);
                if (missing) { result.ListenPipe = serverPipe; }
            }

            if (cfg.PreferStablePipe && !string.IsNullOrEmpty(hooks.UserName))
            {
                string stable = Pipes.Prefix + "nvim-" + hooks.UserName;
                if (serverPipe == null || !string.Equals(stable, serverPipe, StringComparison.OrdinalIgnoreCase))
                {
                    bool missing;
                    Promote(list, stable, "stable", hooks, ref front, out missing);
                }
            }

            if (Log.Enabled)
            {
                for (int i = 0; i < list.Count; i++)
                {
                    Log.Line("candidate " + (i + 1).ToString(CultureInfo.InvariantCulture) + ": " + list[i].Address
                        + " pid=" + list[i].Pid.ToString(CultureInfo.InvariantCulture) + " (" + list[i].Source + ")");
                }
            }
            return result;
        }

        private static string DefaultPipe(int pid, int index)
        {
            return Pipes.Prefix + "nvim." + pid.ToString(CultureInfo.InvariantCulture) + "." + index.ToString(CultureInfo.InvariantCulture);
        }

        /// <summary>
        /// A named pipe (stable name or NVIM_SERVER) is never used because it exists: its server process is
        /// resolved and verified. If that process is already in the list it simply moves to the front; if
        /// it has no default pipe (started with --listen), the named pipe becomes its address.
        /// </summary>
        private static void Promote(List<Candidate> list, string pipe, string source, Hooks hooks, ref int front, out bool missing)
        {
            PipeConnectResult res = Pipes.ConnectTrusted(pipe, 0, hooks.OnlyPids, ConnectTimeoutMs);
            missing = res.NotFound;
            if (res.Channel == null)
            {
                if (!res.NotFound) { Log.Line("skip " + pipe + ": " + res.Reason); }
                return;
            }
            // Only the identity was needed. The instance is contacted later, in its turn, like any other.
            res.Channel.Dispose();

            for (int i = 0; i < list.Count; i++)
            {
                if (!list[i].IsTcp && list[i].Pid == res.ServerPid)
                {
                    if (i >= front)
                    {
                        Candidate moved = list[i];
                        list.RemoveAt(i);
                        list.Insert(front++, moved);
                        Log.Line(pipe + " is served by pid " + res.ServerPid.ToString(CultureInfo.InvariantCulture) + ": that instance goes first");
                    }
                    return;
                }
            }
            Candidate c = new Candidate();
            c.Address = pipe;
            c.Pid = res.ServerPid;
            c.Created = res.ServerCreated;
            c.Source = source;
            list.Insert(front++, c);
        }

        /// <summary>
        /// Connect to a candidate, verify the server, and ask whether it can take a file right now.
        /// Null (and the reason) when it cannot. Nothing that changes the instance is sent.
        /// </summary>
        public static Session Connect(Candidate c, Hooks hooks, out string why)
        {
            IChannel channel = null;
            if (c.IsTcp)
            {
                channel = TcpChannel.Connect(c.Host, c.Port, ConnectTimeoutMs);
                if (channel == null) { why = "no TCP connection within " + ConnectTimeoutMs.ToString(CultureInfo.InvariantCulture) + " ms"; return null; }
            }
            else if (c.Indexes != null)
            {
                why = "no pipe";
                for (int i = 0; i < c.Indexes.Count && channel == null; i++)
                {
                    string pipe = DefaultPipe(c.Pid, c.Indexes[i]);
                    PipeConnectResult res = Pipes.ConnectTrusted(pipe, c.Pid, hooks.OnlyPids, ConnectTimeoutMs);
                    if (res.Channel != null) { channel = res.Channel; c.Address = pipe; }
                    else
                    {
                        why = res.Reason;
                        if (i + 1 < c.Indexes.Count) { Log.Line("skip " + pipe + ": " + res.Reason); }
                    }
                }
                if (channel == null) { return null; }
            }
            else
            {
                PipeConnectResult res = Pipes.ConnectTrusted(c.Address, 0, hooks.OnlyPids, ConnectTimeoutMs);
                if (res.Channel == null) { why = res.Reason; return null; }
                // The name could have changed hands since it was resolved; the process must still be the same.
                if (res.ServerPid != c.Pid)
                {
                    res.Channel.Dispose();
                    why = "now served by another process";
                    return null;
                }
                channel = res.Channel;
            }

            RpcClient rpc = new RpcClient(channel);
            string mode;
            why = Probe(rpc, out mode);
            if (why != null)
            {
                rpc.Dispose();
                return null;
            }
            Session s = new Session();
            s.Rpc = rpc;
            s.Candidate = c;
            s.Mode = mode;
            return s;
        }

        /// <summary>
        /// Usable = not waiting at a prompt, and somebody is looking at it. nvim_get_mode first: it is the
        /// one call a blocked instance still answers, so a hit-enter prompt costs a millisecond instead of
        /// a timeout. The UI count separates an editor (TUI core, GUI) from --headless helpers, -l scripts
        /// and a plugin's "--embed --headless" child.
        /// </summary>
        private static string Probe(RpcClient rpc, out string mode)
        {
            mode = "";
            RpcReply r = rpc.Call("nvim_get_mode", new object[0], ProbeTimeoutMs);
            if (r.Status != ReplyStatus.Ok) { return "no answer to nvim_get_mode (" + r.Status.ToString() + ")"; }
            Dictionary<string, object> map = r.Result as Dictionary<string, object>;
            object blocking, modeValue;
            if (map == null || !map.TryGetValue("blocking", out blocking) || !(blocking is bool)) { return "unexpected nvim_get_mode reply"; }
            if (map.TryGetValue("mode", out modeValue) && modeValue is string) { mode = (string)modeValue; }
            if ((bool)blocking) { return "blocked, waiting for input (mode " + mode + ")"; }

            r = rpc.Call("nvim_eval", new object[] { "len(nvim_list_uis())" }, ProbeTimeoutMs);
            if (r.Status != ReplyStatus.Ok) { return "no answer to the UI question (" + r.Status.ToString() + ")"; }
            if (!(r.Result is long) || (long)r.Result < 1) { return "no UI attached (headless helper)"; }
            return null;
        }
    }
}
