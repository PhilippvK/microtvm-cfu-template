#ifndef CFU_WCA_H
#define CFU_WCA_H

#include <stdint.h>

asm(".set regnum_x0  ,  0");
asm(".set regnum_x1  ,  1");
asm(".set regnum_x2  ,  2");
asm(".set regnum_x3  ,  3");
asm(".set regnum_x4  ,  4");
asm(".set regnum_x5  ,  5");
asm(".set regnum_x6  ,  6");
asm(".set regnum_x7  ,  7");
asm(".set regnum_x8  ,  8");
asm(".set regnum_x9  ,  9");
asm(".set regnum_x10 , 10");
asm(".set regnum_x11 , 11");
asm(".set regnum_x12 , 12");
asm(".set regnum_x13 , 13");
asm(".set regnum_x14 , 14");
asm(".set regnum_x15 , 15");
asm(".set regnum_x16 , 16");
asm(".set regnum_x17 , 17");
asm(".set regnum_x18 , 18");
asm(".set regnum_x19 , 19");
asm(".set regnum_x20 , 20");
asm(".set regnum_x21 , 21");
asm(".set regnum_x22 , 22");
asm(".set regnum_x23 , 23");
asm(".set regnum_x24 , 24");
asm(".set regnum_x25 , 25");
asm(".set regnum_x26 , 26");
asm(".set regnum_x27 , 27");
asm(".set regnum_x28 , 28");
asm(".set regnum_x29 , 29");
asm(".set regnum_x30 , 30");
asm(".set regnum_x31 , 31");

asm(".set regnum_zero,  0");
asm(".set regnum_ra  ,  1");
asm(".set regnum_sp  ,  2");
asm(".set regnum_gp  ,  3");
asm(".set regnum_tp  ,  4");
asm(".set regnum_t0  ,  5");
asm(".set regnum_t1  ,  6");
asm(".set regnum_t2  ,  7");
asm(".set regnum_s0  ,  8");
asm(".set regnum_s1  ,  9");
asm(".set regnum_a0  , 10");
asm(".set regnum_a1  , 11");
asm(".set regnum_a2  , 12");
asm(".set regnum_a3  , 13");
asm(".set regnum_a4  , 14");
asm(".set regnum_a5  , 15");
asm(".set regnum_a6  , 16");
asm(".set regnum_a7  , 17");
asm(".set regnum_s2  , 18");
asm(".set regnum_s3  , 19");
asm(".set regnum_s4  , 20");
asm(".set regnum_s5  , 21");
asm(".set regnum_s6  , 22");
asm(".set regnum_s7  , 23");
asm(".set regnum_s8  , 24");
asm(".set regnum_s9  , 25");
asm(".set regnum_s10 , 26");
asm(".set regnum_s11 , 27");
asm(".set regnum_t3  , 28");
asm(".set regnum_t4  , 29");
asm(".set regnum_t5  , 30");
asm(".set regnum_t6  , 31");

asm(".set CUSTOM0  , 0x0B");
asm(".set CUSTOM1  , 0x2B");

#ifdef ISSUE_582_WORKAROUND
#define CUSTOM_INSTRUCTION_NOP "nop\n"
#else
#define CUSTOM_INSTRUCTION_NOP
#endif

#define opcode_R(opcode, func3, func7, rs1, rs2)   \
({                                                 \
    register unsigned long result;                 \
    asm volatile(                                  \
     ".word ((" #opcode ") |                       \
     (regnum_%[result] << 7) |                     \
     (regnum_%[arg1] << 15) |                      \
     (regnum_%[arg2] << 20) |                      \
     ((" #func3 ") << 12) |                        \
     ((" #func7 ") << 25));\n"                    \
     CUSTOM_INSTRUCTION_NOP                        \
     : [result] "=r" (result)                      \
     : [arg1] "r" (rs1), [arg2] "r" (rs2)          \
    );                                             \
    result;                                        \
})

// generic name for each custom instruction - via hardware
#define cfu_op_hw(funct3, funct7, rs1, rs2) \
  opcode_R(CUSTOM0, funct3, funct7, (rs1), (rs2))
#define cfu_op0_hw(funct7, rs1, rs2) cfu_op_hw(0, funct7, rs1, rs2)
#define cfu_op1_hw(funct7, rs1, rs2) cfu_op_hw(1, funct7, rs1, rs2)
#define cfu_op2_hw(funct7, rs1, rs2) cfu_op_hw(2, funct7, rs1, rs2)
#define cfu_op3_hw(funct7, rs1, rs2) cfu_op_hw(3, funct7, rs1, rs2)
#define cfu_op4_hw(funct7, rs1, rs2) cfu_op_hw(4, funct7, rs1, rs2)
#define cfu_op5_hw(funct7, rs1, rs2) cfu_op_hw(5, funct7, rs1, rs2)
#define cfu_op6_hw(funct7, rs1, rs2) cfu_op_hw(6, funct7, rs1, rs2)
#define cfu_op7_hw(funct7, rs1, rs2) cfu_op_hw(7, funct7, rs1, rs2)

// generic name for each custom instruction - via software
#define cfu_op_sw(funct3, funct7, rs1, rs2) \
  software_cfu(funct3, funct7, rs1, rs2)
#define cfu_op0_sw(funct7, rs1, rs2) cfu_op_sw(0, funct7, rs1, rs2)
#define cfu_op1_sw(funct7, rs1, rs2) cfu_op_sw(1, funct7, rs1, rs2)
#define cfu_op2_sw(funct7, rs1, rs2) cfu_op_sw(2, funct7, rs1, rs2)
#define cfu_op3_sw(funct7, rs1, rs2) cfu_op_sw(3, funct7, rs1, rs2)
#define cfu_op4_sw(funct7, rs1, rs2) cfu_op_sw(4, funct7, rs1, rs2)
#define cfu_op5_sw(funct7, rs1, rs2) cfu_op_sw(5, funct7, rs1, rs2)
#define cfu_op6_sw(funct7, rs1, rs2) cfu_op_sw(6, funct7, rs1, rs2)
#define cfu_op7_sw(funct7, rs1, rs2) cfu_op_sw(7, funct7, rs1, rs2)

// generic name for each custom instruction - switchable
#define cfu_op0(funct7, rs1, rs2) cfu_op(0, funct7, rs1, rs2)
#define cfu_op1(funct7, rs1, rs2) cfu_op(1, funct7, rs1, rs2)
#define cfu_op2(funct7, rs1, rs2) cfu_op(2, funct7, rs1, rs2)
#define cfu_op3(funct7, rs1, rs2) cfu_op(3, funct7, rs1, rs2)
#define cfu_op4(funct7, rs1, rs2) cfu_op(4, funct7, rs1, rs2)
#define cfu_op5(funct7, rs1, rs2) cfu_op(5, funct7, rs1, rs2)
#define cfu_op6(funct7, rs1, rs2) cfu_op(6, funct7, rs1, rs2)
#define cfu_op7(funct7, rs1, rs2) cfu_op(7, funct7, rs1, rs2)

// =============== Switch HW vs SW

#ifdef CFU_SOFTWARE_DEFINED
#define cfu_op(funct3, funct7, rs1, rs2) cfu_op_sw(funct3, funct7, rs1, rs2)
#else
#define cfu_op(funct3, funct7, rs1, rs2) cfu_op_hw(funct3, funct7, rs1, rs2)
#endif

#define MODE_CPU      1
#define MODE_EMUL     2
#define MODE_CFU      3

#define CFU_OPCODE_PUSH_WEIGHTS        0b0000000
#define CFU_OPCODE_PUSH_WEIGHTS_4B     0b0001000
#define CFU_OPCODE_SET_CODEBOOK_2B     0b0100000
#define CFU_OPCODE_SET_CODEBOOK_4B     0b0101000
#define CFU_OPCODE_SET_CODEBOOK_16B_LO 0b0111000
#define CFU_OPCODE_SET_CODEBOOK_16B_HI 0b0110000
#define CFU_OPCODE_ALU_MAC             0b1000000
#define CFU_OPCODE_ALU_RST             0b1001000

#ifndef MODE
#define MODE MODE_CFU
#endif

#if MODE == MODE_EMUL
typedef struct {
    uint32_t word0;
    uint32_t word1;
} weights_t;

typedef struct {
    int8_t x[4];
} codebook_t;

static weights_t current_weights = {.word0 = 0, .word1 = 0};
static codebook_t current_codebook = {.x = {0, 0, 0, 0}};

static int32_t acc = 0;
#endif  // MODE

#if MODE == MODE_EMUL
static void __attribute__((always_inline)) inline push_weights(uint32_t word0, uint32_t word1) {
    current_weights.word0 = word0;
    current_weights.word1 = word1;
}
#elif MODE == MODE_CFU
static int32_t __attribute__((always_inline)) inline push_weights(uint32_t word0, uint32_t word1) {
#ifdef SEAL5
    return __builtin_riscv_xcfu_cfu0_push_weights_4b(word0, word1);
#else
    cfu_op0_hw(CFU_OPCODE_PUSH_WEIGHTS_4B, word0, word1);
#endif  // SEAL5
}
#endif  // MODE

#define push_weights_16b push_weights
#define push_weights_4b push_weights
#define push_weights_2b push_weights

static int32_t __attribute__((always_inline)) inline alu_mac(uint32_t word0, uint32_t word1) {
#if MODE == MODE_EMUL
    acc += current_weights.word0 * word0;
    acc += current_weights.word1 * word1;
    return acc;
#elif MODE == MODE_CFU
#ifdef SEAL5
    int32_t acc = __builtin_riscv_xcfu_cfu0_alu_mac(word0, word1);
#else
    int32_t acc = cfu_op0_hw(CFU_OPCODE_ALU_MAC, word0, word1);
#endif  // SEAL5
    return acc;
#endif  // MODE
    // TODO: if non-zero?
}

void set_codebook_2(int8_t* data_ptr) {
#if MODE == MODE_EMUL
#elif MODE == MODE_CFU
    uint16_t codebook_lo = *((int16_t*)data_ptr);
#ifdef SEAL5
    int32_t acc = __builtin_riscv_xcfu_cfu0_set_codebook_2b(codebook_lo);
#else
    cfu_op0_hw(CFU_OPCODE_SET_CODEBOOK_2B, codebook_lo, 0);
#endif  // SEAL5
#endif  // MODE
}

void set_codebook_4(int8_t* data_ptr) {
#if MODE == MODE_EMUL
#elif MODE == MODE_CFU
    uint32_t codebook_lo = *((int32_t*)data_ptr);
#ifdef SEAL5
    int32_t acc = __builtin_riscv_xcfu_cfu0_set_codebook_4b(codebook_lo);
#else
    cfu_op0_hw(CFU_OPCODE_SET_CODEBOOK_4B, codebook_lo, 0);
#endif  // SEAL5
#endif  // MODE
}

void set_codebook_16(int8_t* data_ptr) {
#if MODE == MODE_EMUL
#elif MODE == MODE_CFU
    uint32_t codebook_lo = *((int32_t*)data_ptr);
    uint32_t codebook_hi = *(((int32_t*)data_ptr) + 1);
#ifdef SEAL5
    int32_t acc = __builtin_riscv_xcfu_cfu0_set_codebook_16b(codebook_lo, codebook_hi);
#else
    cfu_op0_hw(CFU_OPCODE_SET_CODEBOOK_4B, codebook_lo, codebook_hi);
#endif  // SEAL5
#endif  // MODE
}

static void __attribute__((always_inline)) inline alu_rst() {
#if MODE == MODE_EMUL
    acc = 0;
#elif MODE == MODE_CFU
#ifdef SEAL5
    __builtin_riscv_xcfu_cfu0_alu_rst();
#else
    cfu_op0_hw(CFU_OPCODE_ALU_RST, 0, 0);
#endif  // SEAL5
#endif  // MODE
}

static int32_t __attribute__((always_inline)) inline get_acc() {
#if MODE == MODE_EMUL
    return acc;
#elif MODE == MODE_CFU
#ifdef SEAL5
    return __builtin_riscv_xcfu_cfu0_alu_mac(0, 0);
#else
    return cfu_op0_hw(CFU_OPCODE_ALU_MAC, 0, 0);  // TODO: opcode for load?
#endif  // SEAL5
#endif  // MODE
}

#endif  // CFU_WCA_H
