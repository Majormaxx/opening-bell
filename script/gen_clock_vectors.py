"""Generate NYSEClock test vectors from Python's zoneinfo, independent of the Solidity code.

Usage: python3 -I script/gen_clock_vectors.py > test/vectors/nyse_clock.json

The holiday table here must match the one NYSEClockTest seeds on-chain.
"""

import json
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")
HOLIDAYS = {date(2026, 11, 26), date(2026, 12, 25), date(2027, 1, 1)}
EARLY = {date(2026, 11, 27), date(2026, 12, 24)}
START = datetime(2026, 11, 1, tzinfo=timezone.utc)
END = datetime(2027, 3, 31, tzinfo=timezone.utc)


def session(d):
    if d.weekday() >= 5 or d in HOLIDAYS:
        return None
    o = datetime(d.year, d.month, d.day, 9, 30, tzinfo=ET)
    c = datetime(d.year, d.month, d.day, 13 if d in EARLY else 16, 0, tzinfo=ET)
    return int(o.timestamp()), int(c.timestamp())


def days_around(t):
    d = datetime.fromtimestamp(t, ET).date()
    return [d + timedelta(i) for i in range(0, 11)]


def is_open(t):
    s = session(datetime.fromtimestamp(t, ET).date())
    return bool(s) and s[0] <= t < s[1]


def next_open(t):
    return min(s[0] for d in days_around(t) if (s := session(d)) and s[0] > t)


def next_close(t):
    return min(s[1] for d in days_around(t) if (s := session(d)) and s[1] >= t)


def main():
    ts = set()
    t = int(START.timestamp())
    while t < int(END.timestamp()):
        ts.add(t)
        t += 1800
    d = START.date()
    while d <= END.date():
        if s := session(d):
            for edge in s:
                ts.update({edge - 1, edge, edge + 1})
        d += timedelta(1)
    # DST end Nov 1 2026 06:00 UTC and DST start Mar 14 2027 07:00 UTC.
    for edge in (1793512800, 1805007600):
        ts.update({edge - 1, edge, edge + 1})
    ts = sorted(ts)
    out = {
        "ts": ts,
        "isOpen": [is_open(x) for x in ts],
        "nextOpen": [next_open(x) for x in ts],
        "nextClose": [next_close(x) for x in ts],
    }
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
