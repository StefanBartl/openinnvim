// MsgPack.cs - msgpack encoder for requests and a complete, bounded decoder for whatever comes back.
//
// The decoder must be able to step over EVERY msgpack type: Neovim delivers broadcast notifications
// (vim.rpcnotify(0, ...)) on the launcher's channel too, and a table, float or buffer handle the
// decoder cannot skip would hide the reply behind it. "Not all bytes here yet" and "this can never
// become a valid message" are different answers; only the first one is worth waiting for.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace OpenInNvim
{
    public enum DecodeStatus
    {
        Ok = 0,
        Incomplete = 1,
        Malformed = 2
    }

    /// <summary>An ext / fixext value (Neovim sends buffer, window and tabpage handles this way).</summary>
    public sealed class MsgPackExt
    {
        public int Type;
        public byte[] Data;
    }

    public sealed class DecodeResult
    {
        public DecodeStatus Status;
        public object Value;
        /// <summary>Offset of the first byte after the value; only meaningful when Status is Ok.</summary>
        public int Next;
    }

    public static class MsgPack
    {
        /// <summary>Deeper nesting is refused: a hostile peer must not be able to overflow the stack.</summary>
        public const int MaxDepth = 32;

        /// <summary>No single connection may deliver more than this; lengths beyond it can never complete.</summary>
        public const int MaxBytes = 1 << 20;

        // ------------------------------------------------------------------------------------------
        // Encoder: nil, bool, integers (full range), strings, arrays. That is all a request needs.
        // ------------------------------------------------------------------------------------------

        public static byte[] Encode(object value)
        {
            MemoryStream o = new MemoryStream(256);
            Write(o, value);
            return o.ToArray();
        }

        public static void Write(MemoryStream o, object value)
        {
            if (value == null) { o.WriteByte(0xc0); return; }
            string s = value as string;
            if (s != null) { WriteString(o, s); return; }
            object[] arr = value as object[];
            if (arr != null)
            {
                WriteArrayHeader(o, arr.Length);
                for (int i = 0; i < arr.Length; i++) { Write(o, arr[i]); }
                return;
            }
            if (value is bool) { o.WriteByte((bool)value ? (byte)0xc3 : (byte)0xc2); return; }
            if (value is int) { WriteInt(o, (int)value); return; }
            if (value is long) { WriteInt(o, (long)value); return; }
            if (value is ulong)
            {
                ulong u = (ulong)value;
                if (u <= long.MaxValue) { WriteInt(o, (long)u); return; }
                o.WriteByte(0xcf);
                WriteBigEndian(o, u, 8);
                return;
            }
            throw new ArgumentException("msgpack: cannot encode " + value.GetType().FullName);
        }

        public static void WriteArrayHeader(MemoryStream o, int count)
        {
            if (count < 16) { o.WriteByte((byte)(0x90 + count)); }
            else if (count <= 0xffff) { o.WriteByte(0xdc); WriteBigEndian(o, (ulong)count, 2); }
            else { o.WriteByte(0xdd); WriteBigEndian(o, (ulong)count, 4); }
        }

        public static void WriteString(MemoryStream o, string s)
        {
            byte[] b = Encoding.UTF8.GetBytes(s);
            int n = b.Length;
            if (n < 32) { o.WriteByte((byte)(0xa0 + n)); }
            else if (n <= 0xff) { o.WriteByte(0xd9); o.WriteByte((byte)n); }
            else if (n <= 0xffff) { o.WriteByte(0xda); WriteBigEndian(o, (ulong)n, 2); }
            else { o.WriteByte(0xdb); WriteBigEndian(o, (ulong)n, 4); }
            o.Write(b, 0, n);
        }

        public static void WriteInt(MemoryStream o, long v)
        {
            if (v >= 0)
            {
                if (v <= 0x7f) { o.WriteByte((byte)v); }
                else if (v <= 0xff) { o.WriteByte(0xcc); o.WriteByte((byte)v); }
                else if (v <= 0xffff) { o.WriteByte(0xcd); WriteBigEndian(o, (ulong)v, 2); }
                else if (v <= 0xffffffffL) { o.WriteByte(0xce); WriteBigEndian(o, (ulong)v, 4); }
                else { o.WriteByte(0xcf); WriteBigEndian(o, (ulong)v, 8); }
                return;
            }
            if (v >= -32) { o.WriteByte((byte)(0x100 + v)); }
            else if (v >= sbyte.MinValue) { o.WriteByte(0xd0); o.WriteByte((byte)(sbyte)v); }
            else if (v >= short.MinValue) { o.WriteByte(0xd1); WriteBigEndian(o, (ulong)(ushort)(short)v, 2); }
            else if (v >= int.MinValue) { o.WriteByte(0xd2); WriteBigEndian(o, (ulong)(uint)(int)v, 4); }
            else { o.WriteByte(0xd3); WriteBigEndian(o, (ulong)v, 8); }
        }

        private static void WriteBigEndian(MemoryStream o, ulong v, int bytes)
        {
            for (int shift = (bytes - 1) * 8; shift >= 0; shift -= 8) { o.WriteByte((byte)(v >> shift)); }
        }

        // ------------------------------------------------------------------------------------------
        // Decoder
        // ------------------------------------------------------------------------------------------

        /// <summary>
        /// Decode one value starting at <paramref name="offset"/>; bytes from <paramref name="end"/> on do not
        /// exist yet. Integers come back as long (ulong above long.MaxValue), floats as double, arrays as
        /// object[], maps as Dictionary&lt;string, object&gt; (keys stringified), bin as byte[], ext as MsgPackExt.
        /// </summary>
        public static DecodeResult Decode(byte[] data, int offset, int end)
        {
            DecodeResult r = new DecodeResult();
            int pos = offset;
            object value;
            r.Status = TryDecode(data, ref pos, end, 0, out value);
            if (r.Status == DecodeStatus.Ok) { r.Value = value; r.Next = pos; }
            return r;
        }

        public static DecodeResult Decode(byte[] data)
        {
            return Decode(data, 0, data.Length);
        }

        internal static DecodeStatus TryDecode(byte[] b, ref int pos, int end, int depth, out object value)
        {
            value = null;
            if (depth > MaxDepth) { return DecodeStatus.Malformed; }
            if (pos >= end) { return DecodeStatus.Incomplete; }
            int t = b[pos++];

            if (t <= 0x7f) { value = (long)t; return DecodeStatus.Ok; }
            if (t >= 0xe0) { value = (long)(t - 256); return DecodeStatus.Ok; }
            if (t >= 0xa0 && t <= 0xbf) { return ReadString(b, ref pos, end, t & 0x1f, out value); }
            if (t >= 0x90 && t <= 0x9f) { return ReadArray(b, ref pos, end, t & 0x0f, depth, out value); }
            if (t >= 0x80 && t <= 0x8f) { return ReadMap(b, ref pos, end, t & 0x0f, depth, out value); }

            long n;
            switch (t)
            {
                case 0xc0: return DecodeStatus.Ok;
                case 0xc2: value = false; return DecodeStatus.Ok;
                case 0xc3: value = true; return DecodeStatus.Ok;

                case 0xc4: return ReadLength(b, ref pos, end, 1, out n) ? ReadBin(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;
                case 0xc5: return ReadLength(b, ref pos, end, 2, out n) ? ReadBin(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;
                case 0xc6: return ReadLength(b, ref pos, end, 4, out n) ? ReadBin(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;

                case 0xc7: return ReadLength(b, ref pos, end, 1, out n) ? ReadExt(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;
                case 0xc8: return ReadLength(b, ref pos, end, 2, out n) ? ReadExt(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;
                case 0xc9: return ReadLength(b, ref pos, end, 4, out n) ? ReadExt(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;

                case 0xca:
                    {
                        if (end - pos < 4) { return DecodeStatus.Incomplete; }
                        byte[] f = new byte[4];
                        f[0] = b[pos + 3]; f[1] = b[pos + 2]; f[2] = b[pos + 1]; f[3] = b[pos];
                        pos += 4;
                        value = (double)BitConverter.ToSingle(f, 0);
                        return DecodeStatus.Ok;
                    }
                case 0xcb:
                    {
                        if (end - pos < 8) { return DecodeStatus.Incomplete; }
                        value = BitConverter.Int64BitsToDouble((long)ReadBigEndian(b, pos, 8));
                        pos += 8;
                        return DecodeStatus.Ok;
                    }

                case 0xcc: if (!ReadLength(b, ref pos, end, 1, out n)) { return DecodeStatus.Incomplete; } value = n; return DecodeStatus.Ok;
                case 0xcd: if (!ReadLength(b, ref pos, end, 2, out n)) { return DecodeStatus.Incomplete; } value = n; return DecodeStatus.Ok;
                case 0xce: if (!ReadLength(b, ref pos, end, 4, out n)) { return DecodeStatus.Incomplete; } value = n; return DecodeStatus.Ok;
                case 0xcf:
                    {
                        if (end - pos < 8) { return DecodeStatus.Incomplete; }
                        ulong u = ReadBigEndian(b, pos, 8);
                        pos += 8;
                        if (u <= long.MaxValue) { value = (long)u; } else { value = u; }
                        return DecodeStatus.Ok;
                    }

                case 0xd0: if (end - pos < 1) { return DecodeStatus.Incomplete; } value = (long)(sbyte)b[pos]; pos += 1; return DecodeStatus.Ok;
                case 0xd1: if (end - pos < 2) { return DecodeStatus.Incomplete; } value = (long)(short)ReadBigEndian(b, pos, 2); pos += 2; return DecodeStatus.Ok;
                case 0xd2: if (end - pos < 4) { return DecodeStatus.Incomplete; } value = (long)(int)ReadBigEndian(b, pos, 4); pos += 4; return DecodeStatus.Ok;
                case 0xd3: if (end - pos < 8) { return DecodeStatus.Incomplete; } value = (long)ReadBigEndian(b, pos, 8); pos += 8; return DecodeStatus.Ok;

                case 0xd4: return ReadExt(b, ref pos, end, 1, out value);
                case 0xd5: return ReadExt(b, ref pos, end, 2, out value);
                case 0xd6: return ReadExt(b, ref pos, end, 4, out value);
                case 0xd7: return ReadExt(b, ref pos, end, 8, out value);
                case 0xd8: return ReadExt(b, ref pos, end, 16, out value);

                case 0xd9: return ReadLength(b, ref pos, end, 1, out n) ? ReadString(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;
                case 0xda: return ReadLength(b, ref pos, end, 2, out n) ? ReadString(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;
                case 0xdb: return ReadLength(b, ref pos, end, 4, out n) ? ReadString(b, ref pos, end, n, out value) : DecodeStatus.Incomplete;

                case 0xdc: return ReadLength(b, ref pos, end, 2, out n) ? ReadArray(b, ref pos, end, n, depth, out value) : DecodeStatus.Incomplete;
                case 0xdd: return ReadLength(b, ref pos, end, 4, out n) ? ReadArray(b, ref pos, end, n, depth, out value) : DecodeStatus.Incomplete;

                case 0xde: return ReadLength(b, ref pos, end, 2, out n) ? ReadMap(b, ref pos, end, n, depth, out value) : DecodeStatus.Incomplete;
                case 0xdf: return ReadLength(b, ref pos, end, 4, out n) ? ReadMap(b, ref pos, end, n, depth, out value) : DecodeStatus.Incomplete;
            }
            // 0xc1 is the one byte msgpack never uses.
            return DecodeStatus.Malformed;
        }

        private static ulong ReadBigEndian(byte[] b, int pos, int bytes)
        {
            ulong v = 0;
            for (int i = 0; i < bytes; i++) { v = (v << 8) | b[pos + i]; }
            return v;
        }

        private static bool ReadLength(byte[] b, ref int pos, int end, int bytes, out long n)
        {
            n = 0;
            if (end - pos < bytes) { return false; }
            n = (long)ReadBigEndian(b, pos, bytes);
            pos += bytes;
            return true;
        }

        // The length checks below come BEFORE any allocation: a 4 GB length prefix costs nothing.

        private static DecodeStatus ReadString(byte[] b, ref int pos, int end, long n, out object value)
        {
            value = null;
            if (n > MaxBytes) { return DecodeStatus.Malformed; }
            if (n > end - pos) { return DecodeStatus.Incomplete; }
            value = Encoding.UTF8.GetString(b, pos, (int)n);
            pos += (int)n;
            return DecodeStatus.Ok;
        }

        private static DecodeStatus ReadBin(byte[] b, ref int pos, int end, long n, out object value)
        {
            value = null;
            if (n > MaxBytes) { return DecodeStatus.Malformed; }
            if (n > end - pos) { return DecodeStatus.Incomplete; }
            byte[] data = new byte[(int)n];
            Buffer.BlockCopy(b, pos, data, 0, (int)n);
            pos += (int)n;
            value = data;
            return DecodeStatus.Ok;
        }

        private static DecodeStatus ReadExt(byte[] b, ref int pos, int end, long n, out object value)
        {
            value = null;
            if (n > MaxBytes) { return DecodeStatus.Malformed; }
            if (n + 1 > end - pos) { return DecodeStatus.Incomplete; }
            MsgPackExt ext = new MsgPackExt();
            ext.Type = (sbyte)b[pos];
            ext.Data = new byte[(int)n];
            Buffer.BlockCopy(b, pos + 1, ext.Data, 0, (int)n);
            pos += (int)n + 1;
            value = ext;
            return DecodeStatus.Ok;
        }

        private static DecodeStatus ReadArray(byte[] b, ref int pos, int end, long n, int depth, out object value)
        {
            value = null;
            if (n > MaxBytes) { return DecodeStatus.Malformed; }
            // Every element takes at least one byte, so fewer bytes than elements cannot be complete.
            if (n > end - pos) { return DecodeStatus.Incomplete; }
            // The list grows with the elements that really arrive. Allocating n slots up front would let
            // 32 nested headers that each claim a million entries cost 250 MB before the first mismatch.
            List<object> items = new List<object>(n < 64 ? (int)n : 64);
            for (long i = 0; i < n; i++)
            {
                object item;
                DecodeStatus st = TryDecode(b, ref pos, end, depth + 1, out item);
                if (st != DecodeStatus.Ok) { return st; }
                items.Add(item);
            }
            value = items.ToArray();
            return DecodeStatus.Ok;
        }

        private static DecodeStatus ReadMap(byte[] b, ref int pos, int end, long n, int depth, out object value)
        {
            value = null;
            if (n > MaxBytes / 2) { return DecodeStatus.Malformed; }
            if (n * 2 > end - pos) { return DecodeStatus.Incomplete; }
            Dictionary<string, object> map = new Dictionary<string, object>(n < 64 ? (int)n : 64, StringComparer.Ordinal);
            for (long i = 0; i < n; i++)
            {
                object k, v;
                DecodeStatus st = TryDecode(b, ref pos, end, depth + 1, out k);
                if (st != DecodeStatus.Ok) { return st; }
                st = TryDecode(b, ref pos, end, depth + 1, out v);
                if (st != DecodeStatus.Ok) { return st; }
                // Keys of any type are legal msgpack; the launcher only ever looks up string keys.
                string key = k as string;
                if (key == null) { key = (k == null) ? "" : Convert.ToString(k, CultureInfo.InvariantCulture); }
                map[key] = v;
            }
            value = map;
            return DecodeStatus.Ok;
        }
    }
}
