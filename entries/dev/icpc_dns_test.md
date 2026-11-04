---
title: Lab network check for MaratonaLinux / NutellaBoot hosts
date: Tue Nov 03 2026
tag: dev
slug: icpc_dns_test
excerpt: A single bash script to diagnose DNS, NTP and reachability problems on ICPC lab machines before contest day.
---
# Lab network check for MaratonaLinux / NutellaBoot hosts

Want to know if a lab machine can actually reach the MaratonaLinux / NutellaBoot servers before contest day? This script checks DNS, NTP, HTTPS and (optionally) download speed and DNS behaviour under load, then tells you what's broken in a short verdict.

**[Download icpc_dns_test.sh](./files/icpc_dns_test.sh)**

## Requirements

* An Ubuntu 24.04 live USB, booted on the **same** lab machine and network port you want to test.
* `python3` (already on the Ubuntu live image). No root needed.

## Quick start

This downloads the script and runs the base test: the DNS, NTP and HTTPS checks, then a 20 s saturation test with 4 streams.

```bash
curl -fsSL https://things.idlechara.net/icpc_dns_test.sh -o icpc_dns_test.sh && bash icpc_dns_test.sh -s 20 -p 4
```

If the machine has no `curl`, use `wget -qO icpc_dns_test.sh https://things.idlechara.net/icpc_dns_test.sh && bash icpc_dns_test.sh -s 20 -p 4`.

The saturation test needs something to download. The script tries Cloudflare, OVH and Hetzner in that order, pulling 1 MB from each, and uses the first that returns data (Cloudflare sometimes answers 403). If all three fail, it skips the test and asks you to pass a reachable URL with `-u`.

## Usage

```bash
bash icpc_dns_test.sh                    # one round
bash icpc_dns_test.sh -r 3 -i 300        # 3 rounds, 5 min apart (catches DNS that "disappears")
bash icpc_dns_test.sh -u <squash-url> -m 50   # + download speed test (first 50 MB)
bash icpc_dns_test.sh -s 20 -p 4         # + saturation test: 4 parallel downloads for 20 s
```

You can override the DNS servers it tests with environment variables:

```bash
LAB_DNS="10.0.0.1 10.0.0.2" PUB_DNS="1.1.1.1 8.8.8.8" bash icpc_dns_test.sh
```

## What it checks

For each host (the `ntp.br` servers plus the `naquadah.com.br` contest infrastructure):

* **System resolver** (`getent`, which goes through resolv.conf / systemd-resolved).
* **Lab DNS servers** (taken from DHCP / resolvectl) and **public DNS**, queried directly over UDP/53.
* **Service by name and by IP**: an NTP query for time servers, an HTTPS (falling back to HTTP) `HEAD` for web hosts.
* Notes when DNS returns an unexpected IP, the clock is off by more than 5 s, or TLS verification fails.

It also checks for a captive portal, and with `-s` it measures DNS latency and packet loss while the uplink is full. That tells you whether `aria2 errorCode=19` failures come from DNS breaking down under load.

> The saturation test briefly fills the lab uplink. Don't run it during a contest.

## Output

Each round prints the full details, then a **SUMMARY** table and a **VERDICT** section that says where the problem is (local resolver config, university DNS, blocked UDP/53, firewall, etc.). At the end it prints an `/etc/hosts` block you can paste in as a workaround if DNS is the culprit.

Everything is also written to a log in `$HOME` (`lab-net-check-<host>-<timestamp>.log`). On a live USB, copy it to a pendrive or just take a photo of the SUMMARY and VERDICT.
