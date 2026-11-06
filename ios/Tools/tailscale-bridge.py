#!/usr/bin/env python3
"""Install on the iPhone over Tailscale: Xcode's wireless connection, bridged. After the design of
github.com/petejkim/xcode-tailscale-bridge. A free (personal team) signature installs only through Xcode or devicectl,
never from a download, so this is how a build reaches the phone when it isn't on the Mac's network.

How it works. The Mac's remotepairingd finds a paired iPhone by its Bonjour advert (`_remotepairing._tcp`) and connects
only through the real interface the advert arrived on. So, on the Mac's own Wi-Fi interface:

1. A stand-in advert: the phone's own identifier and authTag (captured once on the same network), pointing at this
   Mac's address and a local control port. Any pair the phone has published works; they don't expire.
2. A relay from that port to the phone's pairing port over Tailscale. The pairing handshake and the tunnel stay end to
   end between remotepairingd and the phone; the relay only copies bytes, and only for connections from this Mac.
3. The tunnel: after the handshake the phone offers a tunnel port (sequential, logged by remotepairingd as "Got tunnel
   endpoint"). The relay listens on a window of ports ahead and moves it on as the log reports each one.

Needs: the phone paired with this Mac once (by cable), Developer Mode on, "Connect via network" in Xcode's Devices
window, Tailscale on both, and the phone on some Wi-Fi (on cellular it closes these ports). macOS's firewall must let
the relay's ports in from this Mac.

Capture the advert once, with the phone on the Mac's network (the instance name is the identifier):
    dns-sd -B _remotepairing._tcp local.
    dns-sd -L <identifier> _remotepairing._tcp local.     # TXT: identifier=… authTag=… ver=… minVer=…

Run, then install:
    Tools/tailscale-bridge.py <phone's Tailscale IP> <identifier> <authTag> [ver] [minVer]
    xcrun devicectl list devices                            # the phone: "available (paired)" within ~15 s
    xcrun devicectl device install app --device <udid> <Tasks.app>

If the phone stays "unavailable", remotepairingd may be in a long retry delay from earlier failures: restarting it
(`kill $(pgrep -f remotepairingd.xpc)`, it runs as the user and relaunches) makes it connect within seconds.
"""
import asyncio
import ctypes
import re
import select
import socket
import sys
import threading
import time

PHONE_IP, IDENT, AUTH = sys.argv[1], sys.argv[2], sys.argv[3]
VER = sys.argv[4] if len(sys.argv) > 4 else "26"
MINVER = sys.argv[5] if len(sys.argv) > 5 else "8"
IFACE = "en0"
DEVICE_CONTROL = 49152
LOCAL_CONTROL = 42000
LOOKAHEAD = 20
PREDICATE = ('processImagePath BEGINSWITH "/Library/Apple/System/Library/PrivateFrameworks/RemotePairing.framework/" '
             'AND (eventMessage CONTAINS "Got tunnel endpoint" OR eventMessage CONTAINS "Sending tunnel establish request")')
ENDPOINT = re.compile(r"Got tunnel endpoint: '[^']*[.:](\d+)'")


def log(msg: str) -> None:
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def mac_ip() -> str:
    import subprocess
    return subprocess.run(["ipconfig", "getifaddr", IFACE], capture_output=True, text=True, check=True).stdout.strip()


MAC_IP = mac_ip()
LOCAL_IPS = {MAC_IP, "127.0.0.1"}

# MARK: The advert (dns_sd, on en0)

lib = ctypes.CDLL("/usr/lib/system/libsystem_dnssd.dylib")
RegReply = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int32, ctypes.c_char_p, ctypes.c_char_p,
                            ctypes.c_char_p, ctypes.c_void_p)
RecReply = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int32, ctypes.c_void_p)
_reg_cb = RegReply(lambda ref, flags, err, n, t, d, ctx: log(f"advert: err={err} name={n and n.decode()}"))
_rec_cb = RecReply(lambda ref, rec, flags, err, ctx: log(f"advert host record: err={err}"))


def advertise() -> None:
    idx = socket.if_nametoindex(IFACE)
    host = f"tsrelay-{socket.gethostname().split('.')[0].lower()}-{LOCAL_CONTROL}.local."
    conn, rec, svc = ctypes.c_void_p(), ctypes.c_void_p(), ctypes.c_void_p()
    assert lib.DNSServiceCreateConnection(ctypes.byref(conn)) == 0
    err = lib.DNSServiceRegisterRecord(conn, ctypes.byref(rec), ctypes.c_uint32(0x20), ctypes.c_uint32(idx), host.encode(),
                                       ctypes.c_uint16(1), ctypes.c_uint16(1), ctypes.c_uint16(4), socket.inet_aton(MAC_IP),
                                       ctypes.c_uint32(120), _rec_cb, None)
    assert err == 0, f"RegisterRecord {err}"
    items = [f"identifier={IDENT}", f"authTag={AUTH}", f"ver={VER}", f"minVer={MINVER}", "flags=0"]
    txt = b"".join(bytes([len(s)]) + s.encode() for s in items)
    err = lib.DNSServiceRegister(ctypes.byref(svc), ctypes.c_uint32(0), ctypes.c_uint32(idx), IDENT.encode(),
                                 b"_remotepairing._tcp", b"local.", host.encode(), ctypes.c_uint16(socket.htons(LOCAL_CONTROL)),
                                 ctypes.c_uint16(len(txt)), txt, _reg_cb, None)
    assert err == 0, f"Register {err}"
    log(f"advertising {IDENT} on {IFACE} (index {idx}) at {host} {MAC_IP}:{LOCAL_CONTROL}")
    fds = {lib.DNSServiceRefSockFD(conn): conn, lib.DNSServiceRefSockFD(svc): svc}

    def run() -> None:
        while True:
            ready, _, _ = select.select(list(fds), [], [], 5)
            for fd in ready:
                lib.DNSServiceProcessResult(fds[fd])

    threading.Thread(target=run, daemon=True).start()


# MARK: The relay


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, counter: list) -> None:
    try:
        while data := await reader.read(65536):
            counter[0] += len(data)
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def relay(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, local: int, target: int) -> None:
    peer = writer.get_extra_info("peername")[0]
    if peer not in LOCAL_IPS:
        log(f"refused {peer} on {local}")
        writer.close()
        return
    try:
        r2, w2 = await asyncio.wait_for(asyncio.open_connection(PHONE_IP, target), 10)
    except Exception as e:
        log(f"{local} -> phone:{target} failed: {e!r}")
        writer.close()
        return
    log(f"{local} -> phone:{target} open")
    up, down = [0], [0]
    await asyncio.gather(pipe(reader, w2, up), pipe(r2, writer, down))
    log(f"{local} -> phone:{target} closed (sent {up[0]} B, got {down[0]} B)")


servers: dict[int, asyncio.base_events.Server] = {}


async def listen(local: int, target: int) -> None:
    if local in servers:
        return
    try:
        servers[local] = await asyncio.start_server(lambda r, w: relay(r, w, local, target), host=MAC_IP, port=local)
    except OSError as e:
        log(f"can't listen on {local}: {e.strerror}")


async def window(start: int) -> None:
    """Tunnel ports from `start`, LOOKAHEAD ahead; ports below it are closed."""
    for p in [p for p in servers if p != LOCAL_CONTROL and p < start]:
        servers.pop(p).close()
    for p in range(start, start + LOOKAHEAD + 1):
        await listen(p, p)


async def follow_log() -> None:
    # `log stream` buffers unless it writes to a terminal: run it under script(1).
    proc = await asyncio.create_subprocess_exec("/usr/bin/script", "-q", "/dev/null", "/usr/bin/log", "stream", "--style",
                                                "compact", "--predicate", PREDICATE, stdout=asyncio.subprocess.PIPE)
    assert proc.stdout
    while line := await proc.stdout.readline():
        text = line.decode(errors="replace")
        if "Sending tunnel establish request" in text:
            log("remotepairingd: tunnel establish request")
        if m := ENDPOINT.search(text):
            port = int(m.group(1))
            log(f"remotepairingd: tunnel endpoint port {port}")
            await window(port)


def last_tunnel_port() -> int | None:
    """The last tunnel port remotepairingd logged in the past day: the phone's next one comes after it."""
    import subprocess
    out = subprocess.run(["/usr/bin/log", "show", "--last", "24h", "--style", "compact", "--predicate", PREDICATE],
                         capture_output=True, text=True).stdout
    ports = [int(m.group(1)) for m in ENDPOINT.finditer(out)]
    return ports[-1] if ports else None


async def main() -> None:
    log(f"bridge: phone {PHONE_IP}, this Mac {MAC_IP}")
    await listen(LOCAL_CONTROL, DEVICE_CONTROL)
    # The ports after the last one logged; after a restart the phone's start over near 49152, which the log then gives.
    last = last_tunnel_port()
    await window(last + 1 if last else 49153)
    log(f"listening on {MAC_IP}: {sorted(servers)}")
    advertise()
    await follow_log()


asyncio.run(main())
