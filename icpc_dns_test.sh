#!/usr/bin/env bash
# lab-net-check.sh — DNS / reachability check for MaratonaLinux / NutellaBoot hosts.
# Run from an Ubuntu 24.04 live USB on the SAME lab machine/port. No root needed.
#
#   bash lab-net-check.sh                 # one round
#   bash lab-net-check.sh -r 3 -i 300     # 3 rounds, 5 min apart (catches DNS that "disappears")
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
    *) sed -n '2,14p' "$0"; exit 0 ;;
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
LOG="${LOG:-$HOME/lab-net-check-$(hostname)-$(date +%Y%m%d-%H%M%S).log}"
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

f = {'sat': sat, 'dns': dns, 'ntp': ntp, 'web': web, 'portal': portal, 'dl': dl}[sys.argv[1]]
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
env | grep -E '^(https?_proxy|HTTPS?_PROXY)=' && echo "  ^ proxy env set (urllib/aria2 may use it)"
LABDNS=$(lab_dns_servers); PUBDNS=${PUB_DNS:-"1.1.1.1 8.8.8.8"}
echo "--- lab DNS under test: ${LABDNS:-<none found>}   public: $PUBDNS"
echo "--- captive portal: $(probe portal)"

# ---------------------------------------------------------------- rounds
prev=""
for ((round=1; round<=ROUNDS; round++)); do
  echo; echo "================ round $round/$ROUNDS  $(date +%T)"
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
      if(lf>0 && po>0)   print "* Lab DNS fails but public DNS works -> university DNS problem; workaround: /etc/hosts or public DNS.";
      if(so==0 && po==0 && lo==0 && io>0) print "* ALL DNS fails but IPs reachable -> DNS (udp/53) blocked; workaround: /etc/hosts below.";
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

echo; echo "---- /etc/hosts workaround (only if VERDICT says DNS is the problem):"
for e in "${HOSTS[@]}"; do read -r h ip _ <<<"$e"; printf '%-16s %s\n' "$ip" "$h"; done
echo; echo "Full log: $LOG  (live USB: copy it to a pendrive or photograph SUMMARY+VERDICT)"