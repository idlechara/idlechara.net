#!/usr/bin/env bash
# lab-net-check.sh — DNS / reachability check for MaratonaLinux / NutellaBoot hosts.
# Run from an Ubuntu 24.04 live USB on the SAME lab machine/port. No root needed.
# With sudo it also probes for DHCP servers (DHCPDISCOVER, never takes an address) and IP conflicts (ARP).
#
#   bash lab-net-check.sh                 # one round
#   bash lab-net-check.sh -r 3 -i 300     # 3 rounds, 5 min apart (catches DNS that "disappears")
#   sudo bash lab-net-check.sh            # + root-only DHCP server discovery / duplicate-IP check
#   bash lab-net-check.sh -u <squash-url> -m 50   # + download speed test (first 50 MB)
#   bash lab-net-check.sh -s 20 -p 4      # + saturation test: 4 parallel downloads for 20 s,
#                                         #   measuring DNS latency/loss idle vs. loaded
#                                         #   (uses -u URL if given, else the first working built-in mirror)
#
# Env overrides: LAB_DNS="10.0.0.1 10.0.0.2"  PUB_DNS="1.1.1.1 8.8.8.8"
# Needs python3 (present on Ubuntu live) for direct DNS/NTP/HTTPS probes.

set -u
export LC_ALL=C

ROUNDS=1; INTERVAL=300; DL_URL=""; DL_MB=50; SAT=0; STREAMS=4
# saturation sources, tried in order until one actually delivers data
SAT_URLS_DEFAULT=(
  "https://speed.cloudflare.com/__down?bytes=100000000"
  "https://proof.ovh.net/files/100Mb.dat"
  "https://ash-speed.hetzner.com/100MB.bin"
)
while getopts "r:i:u:m:s:p:h" o; do
  case $o in
    r) ROUNDS=$OPTARG ;; i) INTERVAL=$OPTARG ;; u) DL_URL=$OPTARG ;; m) DL_MB=$OPTARG ;;
    s) SAT=$OPTARG ;; p) STREAMS=$OPTARG ;;
    *) sed -n '2,16p' "$0"; exit 0 ;;
  esac
done

# name  expected_ip  kind(ntp|web)
HOSTS=(
  "a.ntp.br 200.160.0.8 ntp"
  "b.ntp.br 200.189.40.8 ntp"
  "c.ntp.br 200.192.232.8 ntp"
  "a.st1.ntp.br 200.160.7.186 ntp"
  "b.st1.ntp.br 201.49.148.135 ntp"
  "c.st1.ntp.br 200.186.125.195 ntp"
  "d.st1.ntp.br 200.20.186.76 ntp"
  "gps.ntp.br 200.160.7.193 ntp"
  "files.mdp.naquadah.com.br 177.70.23.147 web"
  "nutellaboot.mdp.naquadah.com.br 179.127.15.205 web"
  "animeitor.naquadah.com.br 177.70.23.144 web"
  "global.naquadah.com.br 177.70.23.143 web"
  "moj.naquadah.com.br 177.70.23.195 web"
)

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
LOGHOME=$HOME; [ -n "${SUDO_USER:-}" ] && LOGHOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
LOG="${LOG:-${LOGHOME:-$HOME}/lab-net-check-$(hostname)-$(date +%Y%m%d-%H%M%S).log}"
exec > >(tee -a "$LOG") 2>&1

command -v python3 >/dev/null || { echo "ERROR: python3 not found (use an Ubuntu live image)"; exit 1; }

# ---------------------------------------------------------------- python probes
cat > "$TMP/probe.py" <<'PY'
import sys, socket, ssl, struct, random, time, http.client, urllib.request

RC = {1:'FORMERR',2:'SERVFAIL',3:'NXDOMAIN',4:'NOTIMP',5:'REFUSED'}

def _skip(d, i):
    while True:
        l = d[i]
        if l == 0: return i + 1
        if l & 0xC0 == 0xC0: return i + 2
        i += l + 1

def dns(server, name, timeout=2.0, tries=2):
    qid = random.randint(0, 0xFFFF)
    q = struct.pack('>HHHHHH', qid, 0x0100, 1, 0, 0, 0)
    for lab in name.rstrip('.').split('.'):
        b = lab.encode(); q += bytes([len(b)]) + b
    q += b'\x00' + struct.pack('>HH', 1, 1)
    try:
        fam, _, _, _, addr = socket.getaddrinfo(server, 53, type=socket.SOCK_DGRAM)[0]
    except OSError as e:
        return f"ERR bad-server:{e}"
    for _ in range(tries):
        s = socket.socket(fam, socket.SOCK_DGRAM); s.settimeout(timeout)
        t0 = time.monotonic()
        try:
            s.sendto(q, addr)
            while True:
                d, _ = s.recvfrom(4096)
                if len(d) >= 12 and struct.unpack('>H', d[:2])[0] == qid: break
        except socket.timeout:
            continue
        except OSError as e:
            return f"ERR {e.strerror or e}"
        finally:
            s.close()
        ms = int((time.monotonic() - t0) * 1000)
        _, fl, qd, an, _, _ = struct.unpack('>HHHHHH', d[:12])
        if fl & 0x000F: return f"ERR {RC.get(fl & 0xF, 'RCODE'+str(fl & 0xF))} {ms}ms"
        if fl & 0x0200: return f"ERR truncated {ms}ms"
        i = 12
        for _ in range(qd): i = _skip(d, i) + 4
        ips = []
        for _ in range(an):
            i = _skip(d, i)
            t, _, _, rl = struct.unpack('>HHIH', d[i:i+10]); i += 10
            if t == 1 and rl == 4: ips.append(socket.inet_ntoa(d[i:i+4]))
            i += rl
        if not ips: return f"ERR NODATA {ms}ms"
        return f"OK {','.join(sorted(set(ips)))} {ms}ms"
    return "ERR timeout"

def ntp(host, timeout=3.0):
    try:
        fam, _, _, _, addr = socket.getaddrinfo(host, 123, socket.AF_INET, socket.SOCK_DGRAM)[0]
    except OSError as e:
        return f"ERR resolve:{e.strerror or e}"
    s = socket.socket(fam, socket.SOCK_DGRAM); s.settimeout(timeout)
    try:
        t1 = time.time(); s.sendto(b'\x23' + 47 * b'\0', addr)
        d, _ = s.recvfrom(512); t4 = time.time()
    except socket.timeout:
        return "ERR timeout(udp/123 blocked?)"
    except OSError as e:
        return f"ERR {e.strerror or e}"
    finally:
        s.close()
    if len(d) < 48: return "ERR short-reply"
    if d[1] == 0: return "ERR kiss-of-death"
    ts = lambda o: (lambda a, b: a - 2208988800 + b / 2**32)(*struct.unpack('>II', d[o:o+8]))
    t2, t3 = ts(32), ts(40)
    off = ((t2 - t1) + (t3 - t4)) / 2; rtt = (t4 - t1) - (t3 - t2)
    return f"OK off={off:+.3f}s rtt={rtt*1000:.0f}ms"

def _http(host, ip, port, tls, timeout):
    t0 = time.monotonic()
    try:
        sock = socket.create_connection((ip or host, port), timeout=timeout)
    except socket.timeout:
        return "ERR tcp-timeout"
    except socket.gaierror as e:
        return f"ERR resolve:{e.strerror}"
    except OSError as e:
        return f"ERR tcp-{(e.strerror or str(e)).replace(' ', '-')}"
    try:
        if tls:
            try:
                sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
            except ssl.SSLCertVerificationError as e:
                return f"ERR tls-verify:{e.verify_message.replace(' ', '-')}"
            except (ssl.SSLError, OSError) as e:
                return f"ERR tls:{type(e).__name__}"
        sock.sendall(f"HEAD / HTTP/1.1\r\nHost: {host}\r\nUser-Agent: lab-net-check\r\n"
                     f"Connection: close\r\n\r\n".encode())
        line = sock.recv(256).split(b'\r\n')[0].decode(errors='replace').split()
        ms = int((time.monotonic() - t0) * 1000)
        if len(line) >= 2 and line[0].startswith('HTTP/'):
            return f"OK http{'s' if tls else ''}={line[1]} {ms}ms"
        return "ERR no-http-reply"
    except socket.timeout:
        return "ERR read-timeout"
    except OSError as e:
        return f"ERR {(e.strerror or str(e)).replace(' ', '-')}"
    finally:
        sock.close()

def web(host, ip=None, timeout=6.0):
    r = _http(host, ip, 443, True, timeout)
    if r.startswith('OK'): return r
    r80 = _http(host, ip, 80, False, timeout)
    if r80.startswith('OK'): return f"{r80} (443:{r[4:]})"
    return f"ERR 443:{r[4:]} 80:{r80[4:]}"

def portal():
    try:
        c = http.client.HTTPConnection('connectivitycheck.gstatic.com', 80, timeout=6)
        c.request('GET', '/generate_204'); r = c.getresponse()
        if r.status == 204: return "OK no-captive-portal"
        return f"WARN got-{r.status} loc={r.getheader('Location')} (captive portal / proxy?)"
    except Exception as e:
        return f"ERR {type(e).__name__}:{e}"

def dl(url, mb):
    lim = int(mb) * 1048576
    req = urllib.request.Request(url, headers={'User-Agent': 'lab-net-check',
                                               'Range': f'bytes=0-{lim-1}'})
    t0 = time.monotonic(); n = 0
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            while n < lim:
                c = r.read(1 << 16)
                if not c: break
                n += len(c)
    except Exception as e:
        return f"ERR {type(e).__name__}:{e} after {n/1048576:.1f}MB"
    dt = time.monotonic() - t0; mbs = n / 1048576 / dt
    return f"OK {n/1048576:.1f}MB in {dt:.1f}s = {mbs:.2f} MB/s ({mbs*8.39:.0f} Mbit/s)"

def sat(url, streams, secs, servers, name, maxmb='800', idle='5'):
    """Saturate the link with N parallel downloads; probe DNS before and during load."""
    import threading, statistics
    streams, secs, idle, lim = int(streams), float(secs), float(idle), int(maxmb) * 1048576
    servers = [x for x in servers.split(',') if x]
    res = {(p, x): [] for p in ('idle', 'load') for x in servers}
    phase = ['idle']; stop_all = threading.Event(); stop_load = threading.Event()
    total = [0]; lock = threading.Lock(); errs = []
    def prober():
        while not stop_all.is_set():
            for x in servers:
                ph = phase[0]; t0 = time.monotonic()
                r = dns(x, name, timeout=1.0, tries=1)
                res[(ph, x)].append((time.monotonic() - t0) * 1000 if r.startswith('OK') else None)
            time.sleep(0.25)
    def loader():
        while not stop_load.is_set():
            try:
                req = urllib.request.Request(url, headers={'User-Agent': 'lab-net-check'})
                with urllib.request.urlopen(req, timeout=10) as r:
                    while not stop_load.is_set():
                        c = r.read(1 << 16)
                        if not c: break
                        with lock:
                            total[0] += len(c)
                            if total[0] >= lim: stop_load.set()
            except Exception as e:
                errs.append(f"{type(e).__name__}:{e}"); time.sleep(0.5)
    pt = threading.Thread(target=prober, daemon=True); pt.start()
    time.sleep(idle)
    phase[0] = 'load'; t0 = time.monotonic()
    ls = [threading.Thread(target=loader, daemon=True) for _ in range(streams)]
    for t in ls: t.start()
    while time.monotonic() - t0 < secs and not stop_load.is_set(): time.sleep(0.2)
    stop_load.set(); dt = time.monotonic() - t0
    stop_all.set(); pt.join(3)
    out = []
    mb = total[0] / 1048576; mbit = total[0] * 8 / 1e6 / dt
    out.append(f"throughput  {mbit:.1f} Mbit/s aggregate ({streams} streams, {dt:.1f}s, {mb:.0f} MB)")
    if total[0] == 0:
        out.append(f"ERR load generator failed: {errs[0] if errs else 'no data'}  (try -u <url>)")
    def st(L):
        ok = sorted(v for v in L if v is not None)
        if not L: return None, None, None
        loss = 100 * (len(L) - len(ok)) / len(L)
        if not ok: return None, None, loss
        return statistics.median(ok), ok[max(0, -(-95 * len(ok) // 100) - 1)], loss  # nearest-rank p95
    bad, slow = [], []
    for x in servers:
        i50, i95, il = st(res[('idle', x)]); l50, l95, ll = st(res[('load', x)])
        f = lambda v, u: 'n/a' if v is None else f"{v:.0f}{u}"
        deg = (ll is not None and il is not None and ll - il >= 10) or \
              (l95 is not None and i95 is not None and l95 > max(200, 5 * i95))
        bloat = not deg and l95 is not None and i95 is not None and l95 > max(100, 10 * i95)
        if deg and (il or 0) < 50: bad.append(x)
        if bloat: slow.append(x)
        tag = 'DEAD' if (il or 0) >= 50 else 'DEGRADED' if deg else 'LATENCY^' if bloat else 'ok'
        out.append(f"dns {x:<15} idle p50={f(i50,'ms')} p95={f(i95,'ms')} loss={f(il,'%')}  |  "
                   f"load p50={f(l50,'ms')} p95={f(l95,'ms')} loss={f(ll,'%')}  {tag}")
    dead = [x for x in servers if (st(res[('idle', x)])[2] or 0) >= 50]
    if dead:
        out.append(f"VERDICT: DNS already failing while idle ({', '.join(dead)}) -> fix DNS first; "
                   "saturation result is inconclusive for those servers.")
    if total[0] and bad:
        out.append("VERDICT: DNS degrades when the link is saturated -> aria2 errorCode=19 under load is plausible. "
                   "Cap aria2 (fewer -x/-s connections, --max-overall-download-limit) or use a local mirror.")
    elif total[0] and slow:
        out.append("VERDICT: latency rises under load (bufferbloat) but no DNS loss -> unlikely to cause "
                   "errorCode=19 alone; aria2 with many connections makes it worse.")
    elif total[0] and len(dead) < len(servers):
        out.append("VERDICT: DNS holds up under load -> saturation is not the cause.")
    return "\n".join(out)

def _psock(iface, proto):  # raw L2 socket bound to iface + its MAC
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(proto)); s.bind((iface, proto))
    return s, s.getsockname()[4][:6]

def _ipsum(h):
    s = sum(struct.unpack('!10H', h)); s = (s >> 16) + (s & 0xFFFF); s += s >> 16
    return (~s) & 0xFFFF

def dhcpdisc(iface, secs='4'):
    """root: broadcast one DHCPDISCOVER (real MAC, new xid) and list every DHCP server that answers.
    Never sends REQUEST, so no address is taken and the current lease is untouched."""
    secs = float(secs); s, mac = _psock(iface, 0x0800); xid = random.getrandbits(32)
    prl = bytes([1, 3, 6, 15, 26, 42, 51, 54, 58, 59, 66, 67, 119])
    bootp = struct.pack('!BBBBIHHIIII', 1, 1, 6, 0, xid, 0, 0x8000, 0, 0, 0, 0) + mac + b'\0' * 202
    bootp += b'\x63\x82\x53\x63' + b'\x35\x01\x01' + b'\x37' + bytes([len(prl)]) + prl + b'\xff'
    bootp += b'\0' * max(0, 300 - len(bootp))
    udp = struct.pack('!HHHH', 68, 67, 8 + len(bootp), 0) + bootp
    iph = struct.pack('!BBHHHBBH4s4s', 0x45, 0x10, 20 + len(udp), 0, 0, 64, 17, 0,
                      b'\0\0\0\0', b'\xff\xff\xff\xff')
    iph = iph[:10] + struct.pack('!H', _ipsum(iph)) + iph[12:]
    frame = b'\xff' * 6 + mac + b'\x08\x00' + iph + udp
    ips = lambda v: ','.join(socket.inet_ntoa(v[i:i+4]) for i in range(0, len(v) - 3, 4))
    t0 = time.monotonic(); s.send(frame); end = t0 + secs
    offers, others = [], {}
    while True:
        left = end - time.monotonic()
        if left <= 0: break
        s.settimeout(left)
        try: d, a = s.recvfrom(65535)
        except socket.timeout: break
        if a[2] == 4: continue                                   # our own outgoing frame
        ip = d[14:]
        if len(ip) < 28 or ip[9] != 17: continue
        u = ip[(ip[0] & 15) * 4:]
        if struct.unpack('!HH', u[:4]) != (67, 68): continue
        b = u[8:]
        if len(b) < 240 or b[0] != 2 or b[236:240] != b'\x63\x82\x53\x63': continue
        o, op = 240, {}
        while o < len(b) - 1 and b[o] != 255:
            if b[o] == 0: o += 1; continue
            op[b[o]] = b[o+2:o+2+b[o+1]]; o += 2 + b[o+1]
        srv = socket.inet_ntoa(op[54]) if 54 in op and len(op[54]) == 4 else socket.inet_ntoa(ip[12:16])
        if struct.unpack('!I', b[4:8])[0] != xid:
            others[srv] = others.get(srv, 0) + 1; continue
        kind = {2: 'OFFER', 5: 'ACK', 6: 'NAK'}.get(op.get(53, b'\0')[0], 'REPLY')
        f = [f"server={srv}", f"yiaddr={socket.inet_ntoa(b[16:20])}",
             f"from_mac={d[6:12].hex(':')}", f"from_ip={socket.inet_ntoa(ip[12:16])}",
             f"ms={int((time.monotonic() - t0) * 1000)}"]
        if 51 in op: f.append(f"lease={struct.unpack('!I', op[51])[0]}")
        if 1 in op: f.append(f"mask={socket.inet_ntoa(op[1])}")
        if 3 in op: f.append(f"router={ips(op[3])}")
        if 6 in op: f.append(f"dns={ips(op[6])}")
        if 42 in op: f.append(f"ntp={ips(op[42])}")
        if 15 in op: f.append(f"domain={op[15].decode(errors='replace').strip(chr(0))}")
        if 26 in op: f.append(f"mtu={struct.unpack('!H', op[26])[0]}")
        offers.append(f"{kind} " + ' '.join(f))
    s.close()
    out = offers or ["NONE no DHCP server answered"]
    out += [f"SEEN server={k} replies-to-other-clients={v}" for k, v in others.items()]
    srvs = sorted({x.split('server=')[1].split()[0] for x in offers} | set(others))
    out.append(f"SUMMARY offers={len(offers)} servers={','.join(srvs) or '-'}")
    return '\n'.join(out)

def arpcheck(iface, targets, secs='2'):
    """root: ARP probe (sender 0.0.0.0, like duplicate-address detection) and list every MAC that answers."""
    s, mac = _psock(iface, 0x0806); targets = [t for t in targets.split(',') if t]
    seen = {t: set() for t in targets}; end = time.monotonic() + float(secs); sent = 0
    while time.monotonic() < end:
        if sent < 3:
            for t in targets:
                s.send(b'\xff' * 6 + mac + b'\x08\x06' + struct.pack('!HHBBH', 1, 0x0800, 6, 4, 1)
                       + mac + b'\0' * 4 + b'\0' * 6 + socket.inet_aton(t))
            sent += 1
        s.settimeout(0.2)
        try: d, a = s.recvfrom(2048)
        except socket.timeout: continue
        if a[2] == 4 or len(d) < 42 or d[20:22] != b'\x00\x02': continue
        sm, si = d[22:28], socket.inet_ntoa(d[28:32])
        if si in seen and sm != mac: seen[si].add(sm.hex(':'))
    s.close()
    return '\n'.join(f"ARP {t} macs={','.join(sorted(m)) or '-'}" for t, m in seen.items())

f = {'sat': sat, 'dns': dns, 'ntp': ntp, 'web': web, 'portal': portal, 'dl': dl,
     'dhcpdisc': dhcpdisc, 'arpcheck': arpcheck}[sys.argv[1]]
try:
    print(f(*sys.argv[2:]))
except Exception as e:
    print(f"ERR {type(e).__name__}:{e}")
PY
probe() { python3 "$TMP/probe.py" "$@"; }

# ---------------------------------------------------------------- helpers
ms_now() { date +%s%3N; }
sys_resolve() {   # system resolver path (nsswitch -> resolved / hosts / mdns)
  local t0 out; t0=$(ms_now)
  out=$(timeout 10 getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, -)
  if [ -n "$out" ]; then echo "OK $out $(( $(ms_now) - t0 ))ms"; else echo "ERR not-resolved $(( $(ms_now) - t0 ))ms"; fi
}
lab_dns_servers() {
  if [ -n "${LAB_DNS:-}" ]; then echo "$LAB_DNS"; return; fi
  local s=""
  if command -v resolvectl >/dev/null; then
    s=$(resolvectl dns 2>/dev/null | sed -E 's/^[^:]*\)?:[[:space:]]*//; s/^Global:[[:space:]]*//' \
        | tr ' ' '\n' | grep -E '^[0-9a-fA-F.:]+$' | grep -vE '^fe80|^127\.' | sort -u | paste -sd' ' -)
  fi
  [ -z "$s" ] && s=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | grep -vE '^127\.|^fe80' | paste -sd' ' -)
  echo "$s"
}
dhcp_norm() {   # stdin: "key<TAB>value" from any DHCP client -> canonical "key<TAB>value"
  awk -F'\t' '
    BEGIN{ split("ip_address:addr address:addr fixed_address:addr subnet_mask:mask netmask:mask " \
                 "routers:gw router:gw domain_name_servers:dns dns:dns domain_name:domain domainname:domain " \
                 "domain_search:search domain_search_list:search ntp_servers:ntp ntp:ntp " \
                 "dhcp_lease_time:lease lifetime:lease expiry:expiry expire:expiry_txt " \
                 "dhcp_renewal_time:t1 t1:t1 dhcp_rebinding_time:t2 t2:t2 " \
                 "dhcp_server_identifier:server server_address:server interface_mtu:mtu mtu:mtu " \
                 "host_name:hostname hostname:hostname next_server:bootsrv filename:bootfile", M, " ")
           for(i in M){split(M[i],kv,":"); C[kv[1]]=kv[2]} }
    { k=tolower($1); gsub(/-/,"_",k); v=$2; gsub(/[";]/,"",v); gsub(/,/," ",v)
      gsub(/^ +| +$/,"",v); if((k in C) && v!="") print C[k] "\t" v }'
}
default_dev() { ip -4 route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}'; }
lease_left() {  # $1=dev -> seconds left on the DHCP address (kernel countdown), "forever", or empty
  ip -4 -o addr show dev "$1" 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="valid_lft"){print $(i+1); exit}}' | sed 's/sec$//'
}
dhcp_info() {   # what the DHCP server actually handed out (read-only, no root needed)
  local dev f idx shown=0 kv="$TMP/dhcp.kv"
  dev=$(default_dev)
  echo "--- DHCP lease (iface: ${dev:-<no default route>})"
  : > "$kv"
  [ -z "$dev" ] && return
  printf 'iface\t%s\n' "$dev" >> "$kv"
  if ip -4 route show default dev "$dev" 2>/dev/null | grep -q 'proto dhcp'; then
    printf 'isdhcp\tyes\n' >> "$kv"
  else
    printf 'isdhcp\tno\n' >> "$kv"
    echo "  WARN default route is not 'proto dhcp' -> static config or DHCP not in use"
  fi
  printf 'cidr\t%s\n' "$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{print $4; exit}')" >> "$kv"
  ip -4 addr show dev "$dev" 2>/dev/null | grep -E 'inet |valid_lft' | sed -E 's/^ +/  /'
  # NetworkManager (Ubuntu desktop / live USB)
  if command -v nmcli >/dev/null; then
    f=$(nmcli -t -f DHCP4 device show "$dev" 2>/dev/null | sed -E 's/^DHCP4\.OPTION\[[0-9]+\]://; s/\\:/:/g' \
        | grep -vE '^requested_' | sort)
    if [ -n "$f" ]; then
      echo "  [NetworkManager]"; sed 's/^/    /' <<<"$f"; shown=1
      sed 's/ = /\t/' <<<"$f" | dhcp_norm >> "$kv"
    fi
  fi
  # systemd-networkd (Ubuntu server)
  idx=$(cat "/sys/class/net/$dev/ifindex" 2>/dev/null)
  if [ "$shown" = 0 ] && [ -n "$idx" ] && [ -r "/run/systemd/netif/leases/$idx" ]; then
    f=$(grep -vE '^#' "/run/systemd/netif/leases/$idx")
    echo "  [systemd-networkd]"; sed 's/^/    /' <<<"$f"; shown=1
    sed 's/=/\t/' <<<"$f" | dhcp_norm >> "$kv"
  fi
  # NM internal lease file / dhclient lease file (last lease block)
  if [ "$shown" = 0 ]; then
    for f in /var/lib/NetworkManager/*"$dev"*.lease /var/lib/dhcp/dhclient*"$dev"*.leases /var/lib/dhcp/dhclient.leases; do
      [ -r "$f" ] || continue
      echo "  [$f]"
      f=$(awk '/^lease/{b=""} {b=b $0 "\n"} END{printf "%s", b}' "$f" | grep -vE '^\s*$|^lease|^}')
      sed 's/^/    /' <<<"$f"; shown=1
      if grep -q '=' <<<"$f"; then sed -E 's/^ *//; s/=/\t/' <<<"$f"     # NM internal: KEY=VALUE
      else sed -E 's/^ *(option )?//; s/ /\t/' <<<"$f"; fi | dhcp_norm >> "$kv"   # dhclient
      break
    done
  fi
  [ "$shown" = 0 ] && echo "  (no readable lease info: no nmcli/networkd lease/dhclient file found)"
  # DHCP trouble in the system log this boot (readable without root for users in group adm, e.g. Ubuntu live)
  if command -v journalctl >/dev/null; then
    f=$(journalctl -b --no-pager -o short-iso 2>/dev/null | grep -iE 'dhcp' \
        | grep -iE 'timed? ?out|fail|expire|nak|lost|could not acquire' | tail -n 5)
    if [ -n "$f" ]; then
      echo "  DHCP problems in system log (last 5 this boot):"; sed 's/^/    /' <<<"$f"
      printf 'logfail\t%s\n' "$(journalctl -b --no-pager 2>/dev/null | grep -iE 'dhcp' \
        | grep -ciE 'timed? ?out|fail|expire|nak|lost|could not acquire')" >> "$kv"
      printf 'loglast\t%s\n' "$(tail -n1 <<<"$f" | cut -c1-19)" >> "$kv"
    fi
  fi
  echo "  gateway neighbor: $(ip -4 neigh show dev "$dev" 2>/dev/null \
        | grep -F "$(ip -4 route show default dev "$dev" | awk '{print $3; exit}') " | head -1)"
}
human_secs() {  # 5400 -> "1 hour 30 minutes"
  local s=$1 d h m out=""
  d=$((s/86400)); h=$((s%86400/3600)); m=$((s%3600/60))
  ((d)) && out+="$d day$( ((d>1)) && echo s) "
  ((h)) && out+="$h hour$( ((h>1)) && echo s) "
  ((m)) && out+="$m minute$( ((m>1)) && echo s) "
  [ -z "$out" ] && out="$s seconds "
  echo "${out% }"
}
is_private() { [[ $1 =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.) ]]; }
dhcp_explain() {  # $1 = last SUMMARY table ; readable summary of the DHCP lease + findings
  local kv="$TMP/dhcp.kv" k v x left labok labn any=0 where
  declare -A D=()
  [ -r "$kv" ] && while IFS=$'\t' read -r k v; do [ -z "${D[$k]:-}" ] && D[$k]=$v; done < "$kv"
  echo; echo "================ NETWORK SETTINGS (DHCP)"
  if [ -z "${D[iface]:-}" ]; then
    echo "  No default route: this machine has no path to the internet (cable / port / Wi-Fi)."
    return
  fi
  row() { printf '  %-22s %s\n' "$1" "$2"; }
  row "Interface" "${D[iface]}"
  row "Configured by" "$([ "${D[isdhcp]:-}" = yes ] && echo DHCP || echo 'manual (not DHCP)')"
  row "IP address" "${D[addr]:-${D[cidr]%/*}}"
  if [ -n "${D[mask]:-}" ]; then row "Subnet mask" "${D[mask]}"
  elif [[ ${D[cidr]:-} == */* ]]; then row "Subnet mask" "/${D[cidr]#*/}"; fi
  row "DHCP server" "${D[server]:-unknown}"
  row "Gateway" "${D[gw]:-none}"
  if [ -n "${D[dns]:-}" ]; then
    where=""; for x in ${D[dns]}; do is_private "$x" && where+="$x (local) " || where+="$x (public) "; done
    row "DNS servers" "${where% }"
  else
    row "DNS servers" "none"
  fi
  [ -n "${D[domain]:-}" ] && row "Domain" "${D[domain]}"
  [ -n "${D[search]:-}" ] && row "Search domains" "${D[search]}"
  row "NTP servers" "${D[ntp]:-none}"
  # --- lease timing: kernel countdown first, then client-reported expiry
  local L t1 t2 el now state=""
  now=$(date +%s); left=$(lease_left "${D[iface]}")
  if ! [[ $left =~ ^[0-9]+$ ]]; then
    [ "$left" = forever ] && [ -z "${D[lease]:-}" ] || left=""   # keep "forever" only if no lease info
    if [ -z "$left" ] && [[ ${D[expiry]:-} =~ ^[0-9]+$ ]]; then left=$(( D[expiry] - now ))
    elif [ -z "$left" ] && [ -n "${D[expiry_txt]:-}" ]; then
      x=$(date -u -d "${D[expiry_txt]#[0-9] }" +%s 2>/dev/null) && left=$(( x - now ))
    fi
  fi
  L=${D[lease]:-}
  if [[ $L =~ ^[0-9]+$ ]] && ((L > 0)) && ((L < 4294967295)); then
    row "Lease duration" "$(human_secs "$L")"
    t1=${D[t1]:-$((L / 2))}; t2=${D[t2]:-$((L * 7 / 8))}
    if [[ $left =~ ^-?[0-9]+$ ]]; then
      el=$((L - left))
      if ((left <= 0)); then state=expired
      elif ((el < t1 + 60)); then state=ok;      row "Next renewal" "in $(human_secs $(( t1 - el > 0 ? t1 - el : 0 )))"
      elif ((el < t2)); then state=overdue;      row "Next renewal" "OVERDUE by $(human_secs $((el - t1)))"
      else state=rebinding;                      row "Next renewal" "OVERDUE by $(human_secs $((el - t1))) (rebinding)"
      fi
      ((left > 0)) && row "Lease expires" "in $(human_secs "$left") ($(date -d "@$((now + left))" +%T))"
      ((left <= 0)) && row "Lease expires" "EXPIRED $(human_secs $((-left))) ago"
    fi
  elif [[ $L =~ ^[0-9]+$ ]] && ((L >= 4294967295)) || [ "$left" = forever ]; then
    row "Lease duration" "infinite"
  elif [[ $left =~ ^[0-9]+$ ]]; then
    row "Lease expires" "in $(human_secs "$left") ($(date -d "@$((now + left))" +%T))"
  fi
  if [ -n "${D[r_done]:-}" ]; then
    if [ "${D[r_servers]:--}" != - ]; then row "DHCP servers found" "${D[r_servers]//,/ }"
    else row "DHCP servers found" "none answered"; fi
    [ -n "${D[r_offer_yiaddr]:-}" ] && row "Current offer" \
      "${D[r_offer_yiaddr]} from ${D[r_offer_server]}, DNS ${D[r_offer_dns]:-none}, lease $( [[ ${D[r_offer_lease]:-} =~ ^[0-9]+$ ]] && human_secs "${D[r_offer_lease]}" || echo '?'), ${D[r_offer_ms]}ms"
  fi
  [ -n "$LEASE_TRACE" ] && row "Lease per round" "${LEASE_TRACE% }"
  ((RENEWS)) && row "Renewals seen" "$RENEWS during the test"
  [ -n "${D[mtu]:-}" ] && row "MTU" "${D[mtu]}"
  [ -n "${D[hostname]:-}" ] && row "Hostname (from DHCP)" "${D[hostname]}"
  [ -n "${D[bootsrv]:-}${D[bootfile]:-}" ] && row "Network boot" "${D[bootsrv]:-?} ${D[bootfile]:-}"

  echo; echo "  Findings:"
  say() { echo "  - $*"; any=1; }
  [ "${D[isdhcp]:-}" = no ] && say "Network settings were set manually, not received from DHCP."
  [ -z "${D[dns]:-}" ] && say "DHCP did not provide DNS servers; names will not resolve unless set manually."
  x=${D[lease]:-${D[r_offer_lease]:-}}
  [[ $x =~ ^[0-9]+$ ]] && ((x > 0 && x < 3600)) && \
    say "RECOMMENDATION: lease time is $(human_secs "$x"); ask the network admins to raise it to at least 1 hour," \
        "so the address cannot expire or change while MaratonaLinux is downloading/installing."
  case $state in
    overdue)   say "Lease renewal is overdue: the DHCP server did not answer the renewal request." \
                   "The address is lost in $(human_secs "$left") unless a DHCP server answers." ;;
    rebinding) say "AT RISK: renewal failed, machine is now asking any DHCP server (rebinding)." \
                   "The address is lost in $(human_secs "$left")." ;;
    expired)   say "Lease has EXPIRED: the machine has lost (or is about to lose) its address." ;;
  esac
  [[ ${D[logfail]:-} =~ ^[0-9]+$ ]] && ((D[logfail] > 0)) && \
    say "System log shows ${D[logfail]} DHCP error(s) this boot (last at ${D[loglast]:-?})."
  if [ -n "${D[r_done]:-}" ]; then
    [ "${D[r_offers]:-0}" -eq 0 ] && \
      say "No DHCP server answered a discovery request. Machines that boot or reconnect now will get no address;" \
          "this one keeps its address only until the lease expires."
    [[ ${D[r_servers]:-} == *,* ]] && \
      say "More than one DHCP server answered (${D[r_servers]//,/ }). A second/rogue server can give some" \
          "machines a wrong gateway or DNS."
    [ -n "${D[r_offer_dns]:-}" ] && [ -n "${D[dns]:-}" ] && [ "${D[r_offer_dns]//,/ }" != "${D[dns]}" ] && \
      say "DHCP now hands out DNS ${D[r_offer_dns]//,/ }, but this machine is using ${D[dns]} (settings changed since the lease was obtained)."
    [ -n "${D[r_offer_yiaddr]:-}" ] && [ "${D[r_offer_yiaddr]}" != "${D[addr]:-${D[cidr]%/*}}" ] && \
      say "DHCP would now give this machine a different IP (${D[r_offer_yiaddr]}) than the one it has."
    [ -n "${D[r_dupmacs]:-}" ] && [ "${D[r_dupmacs]}" != - ] && \
      say "IP CONFLICT: another device (${D[r_dupmacs]}) is using this machine's IP. Causes random disconnections."
    [[ ${D[r_gwmacs]:-} == *,* ]] && \
      say "Several devices answer for the gateway IP (${D[r_gwmacs]}): redundant routers or ARP spoofing."
    [ "${D[r_gwmacs]:-}" = - ] && say "The gateway did not answer ARP."
  fi
  [[ ${D[mtu]:-} =~ ^[0-9]+$ ]] && ((D[mtu] < 1500)) && \
    say "MTU below 1500 (${D[mtu]}); large transfers may stall if the path is misconfigured."
  if [ -n "$1" ] && [ -n "${D[dns]:-}" ]; then
    labn=$(grep -c . <<<"$1"); labok=$(awk '$3=="ok"' <<<"$1" | wc -l)
    if [ "$labok" -eq 0 ]; then say "The DNS servers given by DHCP failed all $labn lookups in the test above."
    elif [ "$labok" -lt "$labn" ]; then say "The DNS servers given by DHCP answered only $labok of $labn lookups."
    fi
  fi
  ((any)) || echo "  - None. DHCP settings look normal."
  [ -z "${D[r_done]:-}" ] && echo "  (not run as root: DHCP server discovery and IP-conflict check skipped)"
}
root_checks() {  # extra probes that need raw sockets; results go to $TMP/dhcp.kv as r_*
  local dev ip gw r kv="$TMP/dhcp.kv"
  dev=$(default_dev); [ -z "$dev" ] && return
  ip=$(ip -4 -o addr show dev "$dev" | awk '{split($4,a,"/"); print a[1]; exit}')
  gw=$(ip -4 route show default dev "$dev" | awk '{print $3; exit}')
  echo "--- [root] DHCP discovery on $dev (4 s; DISCOVER only, no address is taken)"
  r=$(probe dhcpdisc "$dev" 4); sed 's/^/  /' <<<"$r"
  {
    printf 'r_done\t1\n'
    awk '/^SUMMARY/{for(i=2;i<=NF;i++){split($i,a,"="); print "r_" a[1] "\t" a[2]}}' <<<"$r"
    awk '/^OFFER/{for(i=2;i<=NF;i++){split($i,a,"="); print "r_offer_" a[1] "\t" a[2]}; exit}' <<<"$r"
  } >> "$kv"
  echo "--- [root] ARP check: who answers for this IP ($ip) and the gateway ($gw)"
  r=$(probe arpcheck "$dev" "$ip,$gw"); sed 's/^/  /' <<<"$r"
  printf 'r_dupmacs\t%s\n' "$(awk -v t="$ip" '$2==t{sub("macs=","",$3); print $3}' <<<"$r")" >> "$kv"
  [ -n "$gw" ] && printf 'r_gwmacs\t%s\n' "$(awk -v t="$gw" '$2==t{sub("macs=","",$3); print $3}' <<<"$r")" >> "$kv"
}
mark() { case "$1" in OK*) echo ok ;; WARN*) echo warn ;; *) echo FAIL ;; esac; }

check_host() {  # $1=idx $2=name $3=expected $4=kind ; writes $TMP/sum.$1 and $TMP/det.$1
  local i=$1 h=$2 exp=$3 kind=$4 r s labok=0 labn=0 pubok=0 pubn=0 note="" ips byname byip
  {
    echo "== $h  (expected $exp, $kind)"
    r=$(sys_resolve "$h"); echo "  system      $r"; s=$(mark "$r")
    ips=$(awk '$1=="OK"{print $2}' <<<"$r")
    [ -n "$ips" ] && ! grep -qw "$exp" <<<"${ips//,/ }" && note+="sys->$ips "
    for d in $LABDNS; do
      r=$(probe dns "$d" "$h"); printf '  lab %-15s %s\n' "$d" "$r"; labn=$((labn+1))
      [[ $r == OK* ]] && labok=$((labok+1))
      ips=$(awk '$1=="OK"{print $2}' <<<"$r")
      [ -n "$ips" ] && ! grep -qw "$exp" <<<"${ips//,/ }" && note+="lab->$ips "
    done
    for d in $PUBDNS; do
      r=$(probe dns "$d" "$h"); printf '  pub %-15s %s\n' "$d" "$r"; pubn=$((pubn+1))
      [[ $r == OK* ]] && pubok=$((pubok+1))
    done
    if [ "$kind" = ntp ]; then
      byname=$(probe ntp "$h"); byip=$(probe ntp "$exp")
    else
      byname=$(probe web "$h"); byip=$(probe web "$h" "$exp")
    fi
    echo "  svc-by-name $byname"; echo "  svc-by-ip   $byip"
    off=$(grep -oE 'off=[-+][0-9.]+' <<<"$byip$byname" | head -1 | cut -d= -f2)
    if [ -n "$off" ] && awk -v o="$off" 'BEGIN{exit !(o>5||o<-5)}'; then note+="CLOCK${off}s "; fi
    [[ $byip == *tls-verify* || $byname == *tls-verify* ]] && note+="TLS-VERIFY "
  } > "$TMP/det.$i"
  local lab pub
  if [ "$labn" -eq 0 ]; then lab="-"; elif [ "$labok" -eq "$labn" ]; then lab=ok; elif [ "$labok" -eq 0 ]; then lab=FAIL; else lab="$labok/$labn"; fi
  if [ "$pubok" -eq "$pubn" ]; then pub=ok; elif [ "$pubok" -eq 0 ]; then pub=FAIL; else pub="$pubok/$pubn"; fi
  printf '%-32s %-5s %-5s %-5s %-6s %-6s %s\n' "$h" "$s" "$lab" "$pub" "$(mark "$byname")" "$(mark "$byip")" "$note" > "$TMP/sum.$i"
}

# ---------------------------------------------------------------- header
echo "################ lab-net-check  $(date -Is)  host=$(hostname)"
echo "log: $LOG"
echo "--- interfaces";  ip -br a 2>/dev/null
echo "--- routes";      ip r 2>/dev/null; ip -6 r show default 2>/dev/null
echo "--- /etc/resolv.conf ($(readlink -f /etc/resolv.conf))"; grep -vE '^\s*(#|$)' /etc/resolv.conf 2>/dev/null
command -v resolvectl >/dev/null && { echo "--- resolvectl dns"; resolvectl dns 2>/dev/null; }
dhcp_info
if [ "$(id -u)" -eq 0 ]; then root_checks
else echo "--- (run with sudo for DHCP server discovery and duplicate-IP check)"; fi
env | grep -E '^(https?_proxy|HTTPS?_PROXY)=' && echo "  ^ proxy env set (urllib/aria2 may use it)"
LABDNS=$(lab_dns_servers); PUBDNS=${PUB_DNS:-"1.1.1.1 8.8.8.8"}
echo "--- lab DNS under test: ${LABDNS:-<none found>}   public: $PUBDNS"
echo "--- captive portal: $(probe portal)"

# ---------------------------------------------------------------- rounds
prev=""; PREV_LEFT=""; LEASE_TRACE=""; RENEWS=0
for ((round=1; round<=ROUNDS; round++)); do
  echo; echo "================ round $round/$ROUNDS  $(date +%T)"
  if ((round > 1)); then
    now_dns=$(lab_dns_servers)
    if [ "$now_dns" != "$LABDNS" ]; then
      echo ">>> lab DNS servers changed: '${LABDNS}' -> '${now_dns}' (DHCP renewal / lease lost?)"
      dhcp_info; LABDNS=$now_dns
    fi
  fi
  l=$(lease_left "$(default_dev)")
  if [[ $l =~ ^[0-9]+$ ]]; then
    msg="DHCP lease: $(human_secs "$l") left"
    if [[ $PREV_LEFT =~ ^[0-9]+$ ]] && ((l > PREV_LEFT)); then msg+=" (renewed since last round)"; RENEWS=$((RENEWS+1)); fi
    echo "$msg"; LEASE_TRACE+="$(human_secs "$l" | sed -E 's/ (hour|minute|second|day)s?/\1/g; s/hour/h/g; s/minute/m/g; s/second/s/g; s/day/d/g; s/ //g') "
  fi
  PREV_LEFT=$l
  idx=0; pids=()
  for e in "${HOSTS[@]}"; do
    read -r h ip k <<<"$e"; check_host "$idx" "$h" "$ip" "$k" & pids+=($!); idx=$((idx+1))
  done
  wait "${pids[@]}"
  for ((j=0; j<idx; j++)); do cat "$TMP/det.$j"; done
  echo; echo "---- SUMMARY round $round  ($(date +%T))"
  printf '%-32s %-5s %-5s %-5s %-6s %-6s %s\n' HOST SYS LAB PUB BYNAME BYIP NOTE
  cur=$(for ((j=0; j<idx; j++)); do cat "$TMP/sum.$j"; done)
  echo "$cur"
  [ -n "$prev" ] && [ "$cur" != "$prev" ] && echo ">>> CHANGED since previous round <<<"
  prev=$cur

  # verdict (one line per finding)
  echo "---- VERDICT"
  awk -v nolab="$([ -z "$LABDNS" ] && echo 1)" '
    {n++; if($2=="ok")so++; if($3=="ok")lo++; if($3=="FAIL")lf++; if($4=="ok")po++;
     if($6=="ok")io++; if($5=="FAIL"&&$6=="ok")nf++; if($7!="")nt++}
    END{
      if(nolab) print "* No lab DNS server detected: DHCP gave none, or resolv.conf has only a local stub.";
      if(so==n && io==n) print "* All good: names resolve and every service answers.";
      if(so<n && lo>0)   print "* System resolver fails where lab DNS answers -> local resolver config (resolv.conf/resolved).";
      if(lf>0 && po>0)   print "* Lab DNS fails but public DNS works -> university DNS problem; workaround: NB_HOSTS in nutellaboot.conf (below) or public DNS.";
      if(so==0 && po==0 && lo==0 && io>0) print "* ALL DNS fails but IPs reachable -> DNS (udp/53) blocked; workaround: NB_HOSTS in nutellaboot.conf (below).";
      if(io==0)          print "* Nothing reachable by IP -> firewall / no route / proxy or captive portal required.";
      if(nf>0)           print "* " nf " host(s) unreachable by name but OK by IP -> name resolution is the problem.";
      if(nt>0)           print "* See NOTE column: IP mismatch (DNS hijack/portal or outdated list), CLOCK skew, or TLS-VERIFY failure.";
    }' <<<"$cur"

  if ((round < ROUNDS)); then echo "(next round in ${INTERVAL}s — leave the machine on)"; sleep "$INTERVAL"; fi
done

if [ -n "$DL_URL" ]; then
  echo; echo "---- download test (${DL_MB} MB): $DL_URL"
  echo "  $(probe dl "$DL_URL" "$DL_MB")"
fi

if [ "$SAT" -gt 0 ]; then
  if [ -n "$DL_URL" ]; then CANDS=("$DL_URL"); else CANDS=("${SAT_URLS_DEFAULT[@]}"); fi
  SAT_URL=""
  echo; echo "---- saturation source check (1 MB each)"
  for u in "${CANDS[@]}"; do
    r=$(probe dl "$u" 1); echo "  ${u%%\?*}: $r"
    case $r in OK\ 0.0MB*) ;; OK*) SAT_URL=$u; break ;; esac
  done
  SAT_DNS=$(echo $LABDNS ${PUBDNS%% *} | tr ' ' '\n' | awk 'NF && !seen[$0]++' | paste -sd, -)
  if [ -z "$SAT_URL" ]; then
    echo "  ERR no download source reachable -> saturation test skipped (pass a reachable URL with -u)"
  else
  echo; echo "---- SATURATION test (stops early at 800 MB): 5s idle, then $STREAMS streams x ${SAT}s from ${SAT_URL%%\?*}"
  echo "     (briefly fills the lab uplink — avoid running it during a contest)"
  probe sat "$SAT_URL" "$STREAMS" "$SAT" "$SAT_DNS" files.mdp.naquadah.com.br | sed 's/^/  /'
  fi
fi

echo; echo "---- DNS workaround (only if VERDICT says DNS is the problem):"
echo "     add these lines to nutellaboot.conf on the USB drive used to deploy MaratonaLinux:"
for e in "${HOSTS[@]}"; do read -r h ip _ <<<"$e"; printf 'set NB_HOSTS="%s %s"\n' "$h" "$ip"; done
dhcp_explain "$prev"

[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER": "$LOG" 2>/dev/null
echo; echo "Full log: $LOG  (live USB: copy it to a pendrive or photograph SUMMARY+VERDICT)"