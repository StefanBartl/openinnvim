// Rpc.cs - msgpack-rpc client: one connection, several requests, pipe or TCP, a deadline on every wait.

using System;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;

namespace OpenInNvim
{
    public enum ReplyStatus
    {
        /// <summary>The reply arrived without an error; Result holds the value.</summary>
        Ok = 0,
        /// <summary>The instance answered with an error; ErrorText holds it (text only, never evaluated).</summary>
        Error = 1,
        /// <summary>No complete reply yet (parser), or none within the time limit (client).</summary>
        TimedOut = 2,
        /// <summary>The peer closed the connection.</summary>
        Closed = 3,
        /// <summary>The bytes are not msgpack-rpc; waiting longer cannot fix that.</summary>
        Malformed = 4,
        /// <summary>More than MsgPack.MaxBytes arrived on this connection.</summary>
        TooBig = 5,
        /// <summary>The request could not be written.</summary>
        NotSent = 6
    }

    public sealed class RpcReply
    {
        public ReplyStatus Status;
        public object Result;
        public string ErrorText;

        internal static RpcReply Of(ReplyStatus status)
        {
            RpcReply r = new RpcReply();
            r.Status = status;
            return r;
        }
    }

    /// <summary>
    /// Receive buffer and message parser. Linear: "start" is the offset of the first byte that is not
    /// part of an already handled message, and nothing before it is ever decoded again.
    /// </summary>
    public sealed class RpcParser
    {
        private byte[] buffer = new byte[ChannelRead.ChunkSize * 2];
        private int start;
        private int end;
        private long total;

        public long TotalReceived { get { return total; } }

        /// <summary>Make room for one chunk and return where it goes.</summary>
        internal byte[] Reserve(out int offset)
        {
            if (buffer.Length - end < ChannelRead.ChunkSize)
            {
                int used = end - start;
                if (start > 0 && buffer.Length - used >= ChannelRead.ChunkSize)
                {
                    Buffer.BlockCopy(buffer, start, buffer, 0, used);
                }
                else
                {
                    byte[] bigger = new byte[Math.Max(buffer.Length * 2, used + ChannelRead.ChunkSize)];
                    Buffer.BlockCopy(buffer, start, bigger, 0, used);
                    buffer = bigger;
                }
                start = 0;
                end = used;
            }
            offset = end;
            return buffer;
        }

        internal void Commit(int count)
        {
            end += count;
            total += count;
        }

        /// <summary>Append received bytes (the unit tests feed the parser this way).</summary>
        public void Feed(byte[] data)
        {
            int done = 0;
            while (done < data.Length)
            {
                int offset;
                byte[] target = Reserve(out offset);
                int n = Math.Min(ChannelRead.ChunkSize, data.Length - done);
                Buffer.BlockCopy(data, done, target, offset, n);
                Commit(n);
                done += n;
            }
        }

        /// <summary>
        /// Look for the reply to <paramref name="msgid"/> among the complete messages received so far.
        /// Notifications, requests and replies to other ids are stepped over. Status TimedOut means
        /// "need more bytes" (or the deadline passed while parsing).
        /// </summary>
        public RpcReply Next(long msgid, long deadlineMs)
        {
            while (start < end)
            {
                // Checked per message: a peer streaming thousands of tiny messages must not stretch the wait.
                if (Clock.Ms >= deadlineMs) { return RpcReply.Of(ReplyStatus.TimedOut); }
                int pos = start;
                object msg;
                DecodeStatus st = MsgPack.TryDecode(buffer, ref pos, end, 0, out msg);
                if (st == DecodeStatus.Incomplete) { break; }
                if (st == DecodeStatus.Malformed) { return RpcReply.Of(ReplyStatus.Malformed); }
                start = pos;

                object[] arr = msg as object[];
                if (arr == null || arr.Length < 3 || !(arr[0] is long)) { return RpcReply.Of(ReplyStatus.Malformed); }
                long type = (long)arr[0];
                if (type == 1 && arr.Length == 4)
                {
                    if (!(arr[1] is long) || (long)arr[1] != msgid) { continue; }
                    RpcReply reply = new RpcReply();
                    if (arr[2] == null)
                    {
                        reply.Status = ReplyStatus.Ok;
                        reply.Result = arr[3];
                    }
                    else
                    {
                        reply.Status = ReplyStatus.Error;
                        reply.ErrorText = ErrorToText(arr[2]);
                    }
                    return reply;
                }
                if ((type == 0 && arr.Length == 4) || (type == 2 && arr.Length == 3)) { continue; }
                return RpcReply.Of(ReplyStatus.Malformed);
            }
            if (total > MsgPack.MaxBytes) { return RpcReply.Of(ReplyStatus.TooBig); }
            return RpcReply.Of(ReplyStatus.TimedOut);
        }

        public RpcReply Next(long msgid)
        {
            return Next(msgid, long.MaxValue);
        }

        // Neovim's error object is [type, "message"].
        private static string ErrorToText(object error)
        {
            object[] parts = error as object[];
            if (parts != null && parts.Length >= 2 && parts[1] is string) { return (string)parts[1]; }
            string text = error as string;
            if (text != null) { return text; }
            return Convert.ToString(error, CultureInfo.InvariantCulture);
        }
    }

    public sealed class RpcClient : IDisposable
    {
        private readonly IChannel channel;
        private readonly RpcParser parser = new RpcParser();
        private long nextId = 1;

        /// <summary>Time allowed for writing one request (a healthy pipe takes microseconds).</summary>
        public const int WriteTimeoutMs = 2000;

        public RpcClient(IChannel channel)
        {
            this.channel = channel;
        }

        /// <summary>
        /// Connect to a Neovim pipe through the trust check. Null when the pipe is missing or its server
        /// is not a Neovim of this user and session.
        /// </summary>
        public static RpcClient OpenPipe(string fullName, int timeoutMs)
        {
            int pid, index;
            int expected = 0;
            if (Pipes.IsPipeAddress(fullName) && Pipes.TryParseDefault(fullName.Substring(Pipes.Prefix.Length), out pid, out index)) { expected = pid; }
            PipeConnectResult res = Pipes.ConnectTrusted(fullName, expected, null, timeoutMs);
            return res.Channel == null ? null : new RpcClient(res.Channel);
        }

        /// <summary>Write a request; returns its msgid, or 0 when it could not be written.</summary>
        public long Send(string method, object[] args)
        {
            long id = nextId++;
            MemoryStream o = new MemoryStream(256);
            o.WriteByte(0x94);
            o.WriteByte(0x00);
            MsgPack.WriteInt(o, id);
            MsgPack.WriteString(o, method);
            MsgPack.Write(o, args ?? new object[0]);
            return channel.Write(o.GetBuffer(), (int)o.Length, WriteTimeoutMs) ? id : 0;
        }

        /// <summary>Wait for the reply to a request that was sent with Send.</summary>
        public RpcReply Wait(long msgid, int timeoutMs)
        {
            long deadline = Clock.Ms + timeoutMs;
            for (;;)
            {
                RpcReply reply = parser.Next(msgid, deadline);
                if (reply.Status != ReplyStatus.TimedOut) { return reply; }
                long left = deadline - Clock.Ms;
                if (left <= 0) { return reply; }
                int offset;
                byte[] target = parser.Reserve(out offset);
                int n = channel.Read(target, offset, (int)left);
                if (n == ChannelRead.TimedOut) { return reply; }
                if (n == ChannelRead.Closed || n == ChannelRead.Failed) { return RpcReply.Of(ReplyStatus.Closed); }
                parser.Commit(n);
            }
        }

        public RpcReply Call(string method, object[] args, int timeoutMs)
        {
            long id = Send(method, args);
            if (id == 0) { return RpcReply.Of(ReplyStatus.NotSent); }
            return Wait(id, timeoutMs);
        }

        public void Dispose()
        {
            channel.Dispose();
        }
    }

    /// <summary>
    /// TCP transport for a NVIM_SERVER of the form host:port. There is no way to verify who listens on a
    /// port, so this only ever happens for an address the user wrote into the config.
    /// </summary>
    public sealed class TcpChannel : IChannel
    {
        private Socket socket;

        private TcpChannel(Socket s)
        {
            socket = s;
        }

        /// <summary>Split "host:port" ("[::1]:6666" for IPv6). False for anything else.</summary>
        public static bool TryParseAddress(string address, out string host, out int port)
        {
            host = null;
            port = 0;
            if (string.IsNullOrEmpty(address) || address.IndexOf('\\') >= 0 || address.IndexOf('/') >= 0) { return false; }
            int colon = address.LastIndexOf(':');
            if (colon < 1 || colon == address.Length - 1) { return false; }
            if (!int.TryParse(address.Substring(colon + 1), NumberStyles.None, CultureInfo.InvariantCulture, out port)) { return false; }
            if (port < 1 || port > 65535) { return false; }
            host = address.Substring(0, colon);
            if (host.Length > 2 && host[0] == '[' && host[host.Length - 1] == ']') { host = host.Substring(1, host.Length - 2); }
            return host.Length > 0;
        }

        /// <summary>Null when nobody answers within the limit (name resolution included).</summary>
        public static TcpChannel Connect(string host, int port, int timeoutMs)
        {
            Socket s = null;
            try
            {
                IPAddress ip;
                IAsyncResult pending;
                if (IPAddress.TryParse(host, out ip))
                {
                    s = new Socket(ip.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                    pending = s.BeginConnect(ip, port, null, null);
                }
                else
                {
                    // A name can resolve to IPv4 and IPv6; a dual-mode socket tries both.
                    if (Socket.OSSupportsIPv6)
                    {
                        s = new Socket(AddressFamily.InterNetworkV6, SocketType.Stream, ProtocolType.Tcp);
                        s.DualMode = true;
                    }
                    else
                    {
                        s = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                    }
                    pending = s.BeginConnect(host, port, null, null);
                }
                if (!pending.AsyncWaitHandle.WaitOne(timeoutMs) || !s.Connected)
                {
                    s.Close();
                    return null;
                }
                s.EndConnect(pending);
                s.NoDelay = true;
                return new TcpChannel(s);
            }
            catch (Exception)
            {
                if (s != null) { try { s.Close(); } catch (Exception) { } }
                return null;
            }
        }

        public int Read(byte[] buffer, int offset, int timeoutMs)
        {
            try
            {
                if (!socket.Poll(timeoutMs > 0 ? timeoutMs * 1000 : 0, SelectMode.SelectRead)) { return ChannelRead.TimedOut; }
                int n = socket.Receive(buffer, offset, ChannelRead.ChunkSize, SocketFlags.None);
                return n > 0 ? n : ChannelRead.Closed;
            }
            catch (Exception) { return ChannelRead.Failed; }
        }

        public bool Write(byte[] data, int count, int timeoutMs)
        {
            try
            {
                socket.SendTimeout = timeoutMs;
                int done = 0;
                while (done < count) { done += socket.Send(data, done, count - done, SocketFlags.None); }
                return true;
            }
            catch (Exception) { return false; }
        }

        public void Dispose()
        {
            try { socket.Close(); } catch (Exception) { }
        }
    }
}
