# Generates to-double.csv, the oracle for decimal -> double conversion.
#
# Run once from this directory with `python3 -I make-to-double.py`; the output
# is checked in, so the tests do not need Python. Python's float() of a
# decimal string is correctly rounded (round-half-even) for input of any
# length, and float.hex() records the result exactly.
#
# Columns: `input` is a decimal string; `scale` is NA or a vector scale to
# apply with decimal(input, scale = scale), which pads the stored string with
# zeros (scales above 4932 used to overflow R_strtod's long double); `hex` is
# the expected double as a C99 hex float, or Inf / -Inf.
import csv
import decimal
import random
import struct
import sys
from decimal import Decimal as D

random.seed(20261113)
decimal.getcontext().prec = 3000
rows = []


def add(s, scale="NA"):
    f = float(s)
    if f == float("inf"):
        h = "Inf"
    elif f == float("-inf"):
        h = "-Inf"
    else:
        h = f.hex()
    rows.append((s, str(scale), h))


def digits(n):
    return str(random.randint(1, 9)) + "".join(
        random.choice("0123456789") for _ in range(n - 1)
    )


def as_double(bits):
    return struct.unpack("<d", struct.pack("<Q", bits))[0]


def sign():
    return random.choice(["", "-"])


# Short and medium values over the whole exponent range.
for nd in [1, 2, 3, 5, 8, 12, 15, 16, 17, 18, 19, 20, 22, 25, 30, 40]:
    for _ in range(90):
        e = random.choice([
            0, -nd, -(nd // 2), random.randint(-30, 30),
            random.randint(-340, 310), -324 - nd + random.randint(-3, 3),
            308 - nd + random.randint(-2, 2),
        ])
        add(sign() + digits(nd) + "E" + str(e))

# Shortest round-trip forms of random doubles, normal and subnormal.
for _ in range(400):
    add(repr(as_double(random.getrandbits(63) & 0x7FEFFFFFFFFFFFFF)))
for _ in range(150):
    add(repr(as_double(random.randint(1, (1 << 52) - 1))))


def halfway(f_bits):
    lo = D(as_double(f_bits))
    hi = D(as_double(f_bits + 1))
    return (lo + hi) / 2


def neighbours(mid, extra):
    t = mid.as_tuple()
    eps = D(1).scaleb(mid.adjusted() - len(t.digits) - extra)
    return [mid, mid + eps, mid - eps]


# Exact halfway points between adjacent doubles and their nearest neighbours
# 1 to 30 digits beyond the halfway point's last digit. Binary exponents near
# zero keep these to roughly 50 to 110 significant digits.
for _ in range(450):
    e = random.randint(1023 - 60, 1023 + 60)
    bits = (e << 52) | random.getrandbits(52)
    if bits & 0xFFFFFFFFFFFFF == 0xFFFFFFFFFFFFF:
        continue
    for v in neighbours(halfway(bits), random.randint(1, 30)):
        add(sign() + str(v))

# Halfway points rounded to 17 to 25 significant digits: near-ties that a
# double-rounding conversion gets wrong.
for _ in range(500):
    bits = random.getrandbits(63) & 0x7FEFFFFFFFFFFFFE
    mid = halfway(bits)
    nd = random.randint(17, 25)
    with decimal.localcontext() as ctx:
        ctx.prec = nd
        ctx.rounding = random.choice(
            [decimal.ROUND_HALF_EVEN, decimal.ROUND_DOWN, decimal.ROUND_UP]
        )
        v = +mid
    add(str(v))

# A few deep halfway points: subnormal and large-exponent ties need hundreds
# of digits.
for bits in [1, 2, 3, (1 << 52) - 2, (1 << 52) - 1, 0x7FEFFFFFFFFFFFFE,
             0x7FE0000000000000, 0x0010000000000000]:
    for v in neighbours(halfway(bits), 5):
        add(str(v))

# Edges: the smallest subnormal, the underflow threshold, DBL_MIN, DBL_MAX
# and the overflow threshold.
for s in [
    "4.9406564584124654E-324", "2.4703282292062327E-324",
    "2.4703282292062328E-324", "2.47032822920623272088284396434110686182E-324",
    "1E-324", "1E-325", "1E-400", "1E-999999",
    "2.2250738585072014E-308", "2.2250738585072011E-308",
    "2.2250738585072012E-308",
    "1.7976931348623157E+308", "1.7976931348623158E+308",
    "1.7976931348623159E+308", "1.797693134862315807E+308",
    "1.797693134862315708145274237317043567981E+308",
    "-1.7976931348623158E+308", "1E+309", "-1E+309", "1E+999999",
    "9007199254740991", "9007199254740992", "9007199254740993",
    "9007199254740993.0000000000000000000000000000000000000001",
    "9007199254740995", "1E+23", "8.589973e+9", "83E25", "19745E303",
    "44658E-118", "237281754796605.859375", "0", "-0", "0E-50", "-0E+50",
]:
    add(s)

# Values with more than 4932 significant or stored digits.
add("1" + "0" * 5000)
add("0." + "0" * 5000 + "1")
add("1" + "0" * 5000 + "E-5000")
add("9" * 6000 + "E-5990")
add("1." + "0" * 6000 + "1")
add(str(halfway(0x3FF0000000000000)) + "0" * 5000)
add(str(halfway(0x3FF0000000000000)) + "0" * 5000 + "1")

# Short values padded to a scale beyond long double range.
for scale in [4931, 4932, 4933, 5000, 6000]:
    for s in ["1", "2.5", "-2.5", "0", "-0", "0.1", "1E+23", "83E25",
              "1.7976931348623158E+308", "4.9E-324"]:
        add(s, scale)

with open("to-double.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["input", "scale", "hex"])
    w.writerows(rows)
sys.stderr.write("%d rows\n" % len(rows))
