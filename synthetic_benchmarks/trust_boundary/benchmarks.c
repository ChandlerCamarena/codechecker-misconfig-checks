/*
 * Synthetic benchmark suite — Appendix A, Table A.1
 *
 * Build with the trust_boundary.h header in the include path:
 *   clang -I../../include -fsyntax-only case01_padding_uninit_pass.c
 *
 * Run checker:
 *   clang-tidy -load SecurityMiscPlugin.so \
 *     -checks='-*,security-misc-padding-boundary-leak' \
 *     -p compile_commands.json \
 *     case*.c
 *
 * Expected outcomes match Table A.1 in the thesis appendix.
 */

#include "../../include/trust_boundary.h"
#include <stdint.h>
#include <string.h>

/* =========================================================================
 * Shared types used across cases
 * =========================================================================
 *
 * Msg1: uint8_t + uint64_t + uint32_t
 *   Typical ABI layout (x86-64 SysV):
 *     offset 0: tag  (1 byte)
 *     offset 1-7: PADDING (7 bytes — alignment before uint64_t)
 *     offset 8: x    (8 bytes)
 *     offset 16: n   (4 bytes)
 *     offset 20-23: PADDING (4 bytes tail — to make sizeof = 24)
 *   => HasPadding = true, ~11 bytes padding
 *
 * NoPad: two uint32_t fields
 *   offset 0: a (4 bytes)
 *   offset 4: b (4 bytes)
 *   sizeof = 8, no padding
 *   => HasPadding = false
 */
struct Msg1 { uint8_t tag; uint64_t x; uint32_t n; };
struct NoPad { uint32_t a; uint32_t b; };

/* =========================================================================
 * case01: padding present, no initialiser — WARNING expected (E3)
 * ========================================================================= */
TRUST_BOUNDARY void boundary_case01(struct Msg1 m);

void run_case01(void) {
    struct Msg1 m;          /* no initialiser */
    m.tag = 1;
    m.x   = 42;
    m.n   = 7;
    boundary_case01(m);     /* [WARN E3] field-wise only, padding uninit */
}

/* =========================================================================
 * case02: padding present, memset zero — NO WARNING expected
 * ========================================================================= */
TRUST_BOUNDARY void boundary_case02(struct Msg1 m);

void run_case02(void) {
    struct Msg1 m;
    memset(&m, 0, sizeof(m)); /* whole-object init: suppress */
    m.tag = 1;
    m.x   = 42;
    m.n   = 7;
    boundary_case02(m);       /* [NO WARN] whole-object init visible */
}

/* =========================================================================
 * case03: no padding in type — NO WARNING expected
 * ========================================================================= */
TRUST_BOUNDARY void boundary_case03(struct NoPad p);

void run_case03(void) {
    struct NoPad p;
    p.a = 10;
    p.b = 20;
    boundary_case03(p);   /* [NO WARN] HasPadding = false */
}

/* =========================================================================
 * case04: return-by-value, padding uninit — WARNING expected (E3)
 * ========================================================================= */
TRUST_BOUNDARY struct Msg1 boundary_case04(void);

struct Msg1 boundary_case04(void) {
    struct Msg1 m;      /* no initialiser */
    m.tag = 2;
    m.x   = 99;
    m.n   = 3;
    return m;           /* [WARN E3] return-by-value, padding uninit */
}

/* =========================================================================
 * case05: packed struct, no padding — NO WARNING expected
 * ========================================================================= */
struct __attribute__((packed)) PackedMsg { uint8_t tag; uint64_t x; uint32_t n; };
TRUST_BOUNDARY void boundary_case05(struct PackedMsg m);

void run_case05(void) {
    struct PackedMsg m;
    m.tag = 3;
    m.x   = 55;
    m.n   = 1;
    boundary_case05(m);   /* [NO WARN] packed, HasPadding = false */
}

/* =========================================================================
 * case06: field-wise init only — WARNING expected (E3)
 * Identical to case01 but named explicitly to match the benchmark matrix.
 * ========================================================================= */
TRUST_BOUNDARY void boundary_case06(struct Msg1 m);

void run_case06(void) {
    struct Msg1 m;
    m.tag = 1; m.x = 0; m.n = 0;  /* field-wise only */
    boundary_case06(m);            /* [WARN E3] */
}

/* =========================================================================
 * case07: designated init / full zero-init — NO WARNING expected
 * ========================================================================= */
TRUST_BOUNDARY void boundary_case07(struct Msg1 m);

void run_case07(void) {
    struct Msg1 m = {0};  /* whole-object zero init — padding zeroed */
    m.tag = 5;
    boundary_case07(m);   /* [NO WARN] */
}

/* =========================================================================
 * case08: nested struct with padding — WARNING expected (E3)
 * ========================================================================= */
struct Inner { uint8_t flag; uint32_t val; };   /* ~3 bytes padding between */
struct Outer { uint16_t id; struct Inner inner; uint8_t extra; };

TRUST_BOUNDARY void boundary_case08(struct Outer o);

void run_case08(void) {
    struct Outer o;
    o.id         = 1;
    o.inner.flag = 1;
    o.inner.val  = 100;
    o.extra      = 7;
    boundary_case08(o);   /* [WARN E3] nested padding in Outer */
}
