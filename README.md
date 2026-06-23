# docker-xng

[![Discord](https://img.shields.io/discord/734090820684349521)](https://discord.gg/sTf9uYF)

> [!CAUTION]
> This is a test container and is NOT ready for production.

Docker container for running [xng](https://github.com/airframesio/xng), the
next-generation multi-mode SDR decoder for ACARS, VDL2, HFDL, satcom, AIS, and
more. The container builds `xng` from upstream source and runs it as a
configurable "station" managed by S6.

Builds and runs on `amd64`, `arm64`.

## Required hardware

A host on a supported architecture and one or more USB SDR dongles (RTL-SDR,
Airspy, SDRPlay, etc.) connected to suitable antennas. The runtime image is
built on the `soapy-full` base image, so all the common SoapySDR hardware
modules are available.

## How it works

`xng` runs as a _station_: one process that drives one or more decode
_sessions_ (each session is one SDR tuned to one mode on a set of channels)
with a shared set of outputs. This container generates the station config from
environment variables at startup, then runs `xng station`.

For the common single-SDR case you only set a handful of variables. Multiple
SDRs are supported via indexed variables (see
[Multiple sessions](#multiple-sessions)). For anything more elaborate you can
mount your own native config (see [Custom config file](#custom-config-file)).

## Up and running

### Single SDR (ACARS)

```yaml
services:
  xng:
    image: ghcr.io/sdr-enthusiasts/docker-xng:latest
    container_name: xng
    restart: always
    ports:
      - 8080:8080 # live web dashboard
    environment:
      - TZ=America/Denver
      - XNG_STATION_ID=XX-KSEA-1
      - XNG_MODE=acars
      - XNG_SERIAL=00000978
      - XNG_CENTER=131.1375M
      - XNG_SAMPLE_RATE=2400000
      - XNG_CHANNELS=131.550;131.725;130.025
    tmpfs:
      - /run:exec,size=64M
      - /var/log
    device_cgroup_rules:
      - "c 189:* rwm"
    volumes:
      - /dev/bus/usb:/dev/bus/usb:ro
```

### Two SDRs (ACARS + VDL2)

```yaml
services:
  xng:
    image: ghcr.io/sdr-enthusiasts/docker-xng:latest
    container_name: xng
    restart: always
    ports:
      - 8080:8080
    environment:
      - TZ=America/Denver
      - XNG_STATION_ID=XX-KSEA-1
      # session 1 — ACARS
      - XNG_MODE=acars
      - XNG_SERIAL=00001234
      - XNG_CENTER=131.1375M
      - XNG_SAMPLE_RATE=2400000
      - XNG_CHANNELS=131.550;131.725;130.025
      # session 2 — VDL2
      - XNG_MODE_2=vdl2
      - XNG_SERIAL_2=00000978
      - XNG_CENTER_2=136.4125M
      - XNG_SAMPLE_RATE_2=2400000
      - XNG_CHANNELS_2=136.725;136.700;136.650;136.100
    tmpfs:
      - /run:exec,size=64M
      - /var/log
    device_cgroup_rules:
      - "c 189:* rwm"
    volumes:
      - /dev/bus/usb:/dev/bus/usb:ro
```

## Configuration

Configuration is split into three groups:

- **Station** — identifies the whole station. `XNG_STATION_ID` is required.
- **Session** — describes one SDR/mode/channel set. Repeatable (indexed).
- **Outputs** — shared by all sessions (dashboard, feeds, files, etc.).

### Station

| Variable         | Description                                               | Required | Default |
| ---------------- | --------------------------------------------------------- | -------- | ------- |
| `TZ`             | Your timezone                                             | No       | `UTC`   |
| `XNG_STATION_ID` | Station identity (e.g. `XX-KSEA-1`). Need not be unique.  | Yes      | _none_  |
| `XNG_CONFIG`     | Path to a mounted native config; bypasses all generation. | No       | Blank   |
| `XNG_VERBOSE`    | Log verbosity: `1` (info), `2` (debug), `3` (trace).      | No       | Blank   |

`XNG_STATION_ID` has no default on purpose: the container fails fast at
startup if it is unset.

### Session

These describe **session 1**. Add more sessions by appending `_2`, `_3`, ...
to the variable names (see [Multiple sessions](#multiple-sessions)).

| Variable           | Description                                                               | Required | Default  |
| ------------------ | ------------------------------------------------------------------------- | -------- | -------- |
| `XNG_MODE`         | Decode mode (see [Modes](#modes)).                                        | Yes      | `acars`  |
| `XNG_DRIVER`       | SoapySDR driver name (`rtlsdr`, `airspy`, `sdrplay`, ...).                | No       | `rtlsdr` |
| `XNG_SERIAL`       | SDR device serial that selects a specific dongle.                         | No       | Blank    |
| `XNG_BIASTEE`      | Set `true` to enable the antenna bias tee.                                | No       | `false`  |
| `XNG_SDR`          | Full SoapySDR arg string; overrides the three vars above when set.        | No       | Blank    |
| `XNG_GAIN`         | Tuner gain in dB. Hardware AGC when blank.                                | No       | Blank    |
| `XNG_SAMPLE_RATE`  | Capture sample rate in Hz (e.g. `2400000`).                               | No       | Blank    |
| `XNG_CENTER`       | Capture center frequency (e.g. `131.1375M`).                              | No       | Blank    |
| `XNG_CHANNELS`     | Channel frequencies. See [Frequencies](#frequencies).                     | No       | Blank    |
| `XNG_RECEIVER_POS` | Receiver location as `lat,lon` (enables ADS-B surface positions).         | No       | Blank    |
| `XNG_DEMOD_EFFORT` | `max` (thorough) or `live` (real-time budget; matters on Pi-class hosts). | No       | Blank    |

For many modes `xng` can derive `CENTER`, `SAMPLE_RATE`, and `CHANNELS` from
the mode's built-in plan when they are left blank.

The SDR selector is built from `XNG_DRIVER` + `XNG_SERIAL` + `XNG_BIASTEE`,
e.g. `XNG_DRIVER=rtlsdr XNG_SERIAL=00000978 XNG_BIASTEE=true` becomes
`driver=rtlsdr,serial=00000978,bias=1`. If you need full control (extra
SoapySDR keys, alternate backends), set `XNG_SDR` to the complete arg string
and it is used verbatim.

### Outputs

Outputs are **global** — one set per station, no index suffix.

| Variable             | Description                                                        | Required | Default        |
| -------------------- | ------------------------------------------------------------------ | -------- | -------------- |
| `XNG_HTTP`           | Live web dashboard listen address.                                 | No       | `0.0.0.0:8080` |
| `XNG_METRICS`        | Prometheus metrics listen address (e.g. `0.0.0.0:9090`).           | No       | Blank          |
| `XNG_JSONL`          | Append normalized messages to this JSONL file path.                | No       | Blank          |
| `XNG_JSON`           | Set `true` to render console output as raw JSON.                   | No       | `false`        |
| `XNG_UDP`            | acarsdec-JSON UDP target(s). See [Feeding](#feeding-acars_router). | No       | Blank          |
| `XNG_FEED_AIRFRAMES` | Set `true` to feed Airframes (requires a valid station id).        | No       | `false`        |
| `XNG_MQTT`           | MQTT broker URL: `mqtt://[user:pass@]host[:port]`.                 | No       | Blank          |
| `XNG_MQTT_TOPIC`     | MQTT topic prefix; messages publish to `<prefix>/<mode>`.          | No       | `xng`          |
| `XNG_SBS`            | Serve SBS-1/BaseStation output (Mode S/ADS-B) on this address.     | No       | Blank          |
| `XNG_BEAST`          | Serve Beast binary frames (Mode S) on this address.                | No       | Blank          |
| `XNG_NMEA_TCP`       | Serve raw NMEA AIVDM (AIS) over TCP on this address.               | No       | Blank          |
| `XNG_NMEA_UDP`       | Push raw NMEA AIVDM (AIS) as UDP datagrams to this target.         | No       | Blank          |
| `XNG_DECODE_THREADS` | Decode worker threads. Auto (all cores) when blank.                | No       | Blank          |

## Modes

`XNG_MODE` accepts one of: `acars`, `vdl2`, `hfdl`, `aero`, `aero-c`, `std-c`,
`ais`, `adsb`, `iridium`, `uat`, `sarsat`, `dsc`, `navtex`, `sonde`, `ads-l`,
`atcs`.

## Frequencies

`XNG_CHANNELS` (and `XNG_CENTER`) accept several forms:

- A bare number below `10000` is treated as **MHz**: `131.550`, `1090`.
- A bare number of `10000` or more is treated as **Hz**: `136725000`.
- Explicit suffixes are accepted: `131.55M`, `131.55MHz`, `136975k`.

`XNG_CHANNELS` may be separated by semicolons, commas, or spaces, so the
sdr-enthusiasts `FREQUENCIES` style pastes in directly:

```text
XNG_CHANNELS=131.85;131.825;131.725;131.65;131.55
```

## Multiple sessions

To decode several modes/SDRs in one container, define additional sessions by
appending a numeric suffix to the **session** variables. Session 1 uses the
unsuffixed names; sessions 2 and up use `_2`, `_3`, and so on.

- Sessions must be numbered **consecutively from 1**. A gap (e.g. `_2` and
  `_4` with no `_3`) fails at startup so a typo cannot silently drop a decoder.
- Each session requires its own `XNG_MODE_n` and an SDR selector
  (`XNG_SERIAL_n` / `XNG_DRIVER_n`, or `XNG_SDR_n`).
- Outputs are not indexed; they belong to the station as a whole.

```text
# session 1
XNG_MODE=acars
XNG_SERIAL=00001234
# session 2
XNG_MODE_2=vdl2
XNG_SERIAL_2=00000978
# session 3
XNG_MODE_3=adsb
XNG_SERIAL_3=00005678
XNG_CENTER_3=1090M
XNG_SAMPLE_RATE_3=2000000
XNG_CHANNELS_3=1090
```

## Custom config file

When the indexed variables are not expressive enough, write a native `xng`
station config and point `XNG_CONFIG` at it. When `XNG_CONFIG` is set, the
container uses that file verbatim and skips all environment-based generation.

```yaml
services:
  xng:
    image: ghcr.io/sdr-enthusiasts/docker-xng:latest
    environment:
      - XNG_STATION_ID=XX-KSEA-1
      - XNG_CONFIG=/etc/xng/station.toml
    volumes:
      - ./station.toml:/etc/xng/station.toml:ro
      - /dev/bus/usb:/dev/bus/usb:ro
    device_cgroup_rules:
      - "c 189:* rwm"
```

See the upstream
[station config example](https://github.com/airframesio/xng/blob/master/contrib/station.example.toml)
for the full schema.

## Feeding acars_router

`xng` can forward decoded messages to
[acars_router](https://github.com/sdr-enthusiasts/acars_router) as
acarsdec-compatible JSON over UDP. Set `XNG_UDP` to the router's ACARS input:

```yaml
environment:
  - XNG_UDP=acars_router:5550
```

This sends one acarsdec-flat-JSON datagram per message to `host:5550/UDP`,
which is exactly what acars_router ingests on its ACARS port.

Note: this feed carries **ACARS messages only** — `xng` emits non-ACARS modes
(VDL2, HFDL, etc.) on its other outputs (dashboard, MQTT, JSONL, Airframes),
not on the acarsdec-JSON UDP sink. Feeding the full multi-mode message stream
to acars_router is planned for a later revision.

## Web dashboard

When `XNG_HTTP` is set (default `0.0.0.0:8080`) the container serves a live web
dashboard — a map of decoded aircraft/vessels plus a message stream. Publish
the port (`8080:8080`) and browse to `http://<host>:8080/`.
