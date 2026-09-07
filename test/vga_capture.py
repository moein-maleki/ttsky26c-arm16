"""Reference renderer and frame comparison for the arm16 VGA output (spec 3.4).

Pixel geometry of vga_renderer.v: digits in x 64..576 (four cells of 128: three 32-pixel columns and a
32-pixel gap), y 160..320 (five rows of 32). Colour code col[5:0] = {R1, R0, G1, G0, B1, B0}; pins
uo[7:0] = {HSYNC, B0, G0, R0, VSYNC, B1, G1, R1}."""

SEGMENTS = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71]
WIDTH, HEIGHT = 640, 480
H_TOTAL, V_TOTAL = 800, 525
H_SYNC_START, H_SYNC_END = 656, 752
V_SYNC_START, V_SYNC_END = 490, 492


def segment_lit(value, x, y):
    if not (64 <= x < 576 and 160 <= y < 320):
        return False
    hx, vy = x - 64, y - 160
    digit, gx, gy = hx >> 7, (hx >> 5) & 3, vy >> 5
    nibble = (value >> (12 - 4 * digit)) & 0xF
    seg = SEGMENTS[nibble]
    if gy == 0:
        return gx == 1 and bool(seg & 0x01)
    if gy == 1:
        return (gx == 0 and bool(seg & 0x20)) or (gx == 2 and bool(seg & 0x02))
    if gy == 2:
        return gx == 1 and bool(seg & 0x40)
    if gy == 3:
        return (gx == 0 and bool(seg & 0x10)) or (gx == 2 and bool(seg & 0x04))
    if gy == 4:
        return gx == 1 and bool(seg & 0x08)
    return False


def reference_pixel(value, fg, bg, x, y):
    return fg if segment_lit(value, x, y) else bg


def reference_frame(value, fg, bg, rows=range(HEIGHT)):
    return {y: [reference_pixel(value, fg, bg, x, y) for x in range(WIDTH)] for y in rows}


def colour_from_pins(uo):
    """6-bit colour code from the eight output pins."""
    r1, g1, b1 = uo & 1, (uo >> 1) & 1, (uo >> 2) & 1
    r0, g0, b0 = (uo >> 4) & 1, (uo >> 5) & 1, (uo >> 6) & 1
    return (r1 << 5) | (r0 << 4) | (g1 << 3) | (g0 << 2) | (b1 << 1) | b0


def write_ppm(path, frame, rows):
    """Write the captured rows as a small PPM image (scaled colours) for a human to look at."""
    with open(path, "w") as f:
        f.write("P3\n%d %d\n255\n" % (WIDTH, len(rows)))
        for y in rows:
            line = []
            for c in frame[y]:
                r, g, b = (c >> 4) & 3, (c >> 2) & 3, c & 3
                line.append("%d %d %d" % (r * 85, g * 85, b * 85))
            f.write(" ".join(line) + "\n")


class VideoTimingError(AssertionError):
    """The pin observer found an invalid sync level, bus state, or incomplete sample."""


class VisibleProgressError(AssertionError):
    """The displayed count did not reach its required nonzero value."""


def decode_segment_pixels(packed, fg=0x3F, bg=0):
    """Decode 28 observed segment centres, six colour bits each, into four hex digits."""
    value = 0
    for digit in range(4):
        mask = 0
        for segment in range(7):
            colour = (packed >> (6 * (7 * digit + segment))) & 0x3F
            if colour == fg:
                mask |= 1 << segment
            elif colour != bg:
                raise VideoTimingError('unexpected segment colour 0x%02X at digit %d segment %d' %
                                       (colour, digit, segment))
        if mask not in SEGMENTS:
            raise VideoTimingError('invalid segment mask 0x%02X at digit %d' % (mask, digit))
        value = (value << 4) | SEGMENTS.index(mask)
    return value


def check_pin_monitor(dut):
    errors = int(dut.video_errors.value)
    if errors:
        raise VideoTimingError('pin observer error mask 0x%X at sample %d' %
                               (errors, int(dut.video_first_error_sample.value)))


async def capture_monitor_frame(dut, frame, timeout_ns=120_000_000):
    """Wait for one compiled pin capture. There is no Python callback on each pixel clock."""
    from cocotb.triggers import Edge, Timer, with_timeout
    from cocotb.utils import get_sim_time
    deadline = get_sim_time('ns') + timeout_ns
    while True:
        check_pin_monitor(dut)
        sequence = int(dut.video_capture_sequence.value)
        observed_frame = int(dut.video_capture_frame.value)
        if sequence and observed_frame >= frame:
            if observed_frame != frame:
                raise VideoTimingError('missed frame %d; last capture was %d' % (frame, observed_frame))
            value = decode_segment_pixels(int(dut.video_captured_pixels.value))
            dut._log.info('PIN CAPTURE frame=%d value=%04X samples=%d', frame, value,
                          int(dut.video_sample_count.value))
            return value
        remaining = deadline - get_sim_time('ns')
        if remaining <= 0:
            raise VideoTimingError('no pin capture for frame %d before timeout' % frame)
        await with_timeout(Edge(dut.video_capture_sequence), remaining, 'ns')
        await Timer(1, unit='ns')


def require_visible_count(got, expected):
    if got != expected or expected <= 0:
        raise VisibleProgressError('visible ROM count: got %04X, expected nonzero %04X' %
                                   (got, expected))
