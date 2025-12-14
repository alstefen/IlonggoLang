%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int yylineno;
extern int yylex();
extern FILE* yyin;
extern char* yytext;
void yyerror(const char *s);

// Symbol table and code generation structures
#define MAX_SYMBOLS 512
#define MAX_TEMP_REGS 32
#define MAX_STRINGS 256

typedef enum { type_int, type_float, type_char } VarType;

typedef struct {
    char name[32];
    VarType type;
    int addr;
    int line;
} Symbol;

typedef struct {
    char label[32];
    char content[256];
    int id;
} StringLiteral;

typedef enum {
    FMT_R_TYPE,
    FMT_I_TYPE,
    FMT_R_SPECIAL
} InstructionFormat;

typedef struct {
    const char *name;
    InstructionFormat format;
    unsigned int opcode;
    unsigned int funct;
} InstructionDef;

// Global variables
static Symbol symbol_table[MAX_SYMBOLS];
static int symbol_count = 0;
static StringLiteral string_table[MAX_STRINGS];
static int string_count = 0;
static char temp_regs[MAX_TEMP_REGS][16];
static int temp_count = 0;
static FILE *output_file = NULL;
static int has_errors = 0;

// Instruction table
static const InstructionDef instruction_table[] = {
    {"DADDIU",  FMT_I_TYPE,     0b011001, 0},
    {"DADDU",   FMT_R_TYPE,     0b000000, 0b101101},
    {"DSUBU",   FMT_R_TYPE,     0b000000, 0b101111},
    {"DMULTU",  FMT_R_SPECIAL,  0b000000, 0b011001},
    {"DDIVU",   FMT_R_SPECIAL,  0b000000, 0b011011},
    {"LD",      FMT_I_TYPE,     0b110111, 0},
    {"SD",      FMT_I_TYPE,     0b111111, 0},
    {"MFLO",    FMT_R_TYPE,     0b000000, 0b010010},
    {"ORI",     FMT_I_TYPE,     0b001101, 0},
    {"SYSCALL", FMT_R_TYPE,     0b000000, 0b001100},
    {"LUI",     FMT_I_TYPE,     0b001111, 0},
    {NULL, 0, 0, 0}
};

// Function prototypes
int add_symbol(const char *name, VarType type);
int lookup_symbol(const char *name);
const char* add_string_literal(const char *str);
const char* allocate_temp();
void reset_temps();
void generate_load(const char *reg, const char *var);
void generate_load_immediate(const char *reg, int value);
void generate_store(const char *reg, const char *var);
void generate_binary_op(const char *result, const char *left, const char *right, char op);
void generate_print_string(const char *label);
void generate_print_integer(const char *reg);
void generate_machine_code(const char *instr, int rd, int rs, int rt, int imm, const char *info);
unsigned int encode_r_type(unsigned int opcode, int rs, int rt, int rd, int shamt, unsigned int funct);
unsigned int encode_i_type(unsigned int opcode, int rs, int rt, int imm);
const InstructionDef* find_instruction(const char *instr);
void machine_code_to_binary(unsigned int machine, char *binary);

%}

%union {
    int ival;
    float fval;
    char cval;
    char sval[256];
}

%token PROGRAM START FINISH VAR PRINT
%token INT_TYPE FLOAT_TYPE CHAR_TYPE
%token <ival> INTEGER
%token <fval> FLOAT
%token <cval> CHAR
%token <sval> IDENTIFIER STRING
%token PLUS MINUS MULTIPLY DIVIDE ASSIGN
%token LPAREN RPAREN LBRACE RBRACE COMMA PERIOD

%type <sval> expression term factor print_argument
%type <ival> type

%left PLUS MINUS
%left MULTIPLY DIVIDE

%%

program:
    PROGRAM IDENTIFIER PERIOD
    {
        printf("\n=== Compiling program: %s ===\n", $2);
        output_file = fopen("output_asm.txt", "w");
        if (!output_file) {
            fprintf(stderr, "Error: Cannot create output file\n");
            YYABORT;
        }
        fprintf(output_file, "=== Assembly Code for Program: %s ===\n\n", $2);
    }
    var_section main_section
    {
        if (has_errors) {
            printf("✗ Compilation failed with errors\n");
            if (output_file) {
                fclose(output_file);
                output_file = NULL;
            }
            YYABORT;
        }

        printf("✓ Program syntax is correct!\n");
//        printf("✓ Assembly code generated in output_asm.txt\n\n");

        // Print summary
        fprintf(output_file, "\n=== Summary ===\n");
        fprintf(output_file, "Total variables declared: %d\n", symbol_count);
        fprintf(output_file, "Total string literals: %d\n", string_count);

        if (output_file) {
            fclose(output_file);
            output_file = NULL;
        }
    }
    ;

var_section:
    VAR LBRACE
    {
        fprintf(output_file, ".data\n");
    }
    variable_declarations RBRACE
    {
        // Add string literals to data section
        if (string_count > 0) {
            fprintf(output_file, "\n# String literals\n");
            for (int i = 0; i < string_count; i++) {
                fprintf(output_file, "%s: .asciiz \"%s\"\n",
                    string_table[i].label, string_table[i].content);
            }
        }
        fprintf(output_file, "\n.code\n\n");
    }
    ;

variable_declarations:
    /* empty */
    | variable_declarations variable_declaration
    ;

variable_declaration:
    type variable_list PERIOD
    ;

variable_list:
    IDENTIFIER
    {
        if (!add_symbol($1, $<ival>0)) {
            has_errors = 1;
            YYABORT;
        }
        int idx = lookup_symbol($1);
        fprintf(output_file, "%s: .dword 0    # Address: 0x%08X\n",
                $1, symbol_table[idx].addr);
    }
    | variable_list COMMA IDENTIFIER
    {
        if (!add_symbol($3, $<ival>0)) {
            has_errors = 1;
            YYABORT;
        }
        int idx = lookup_symbol($3);
        fprintf(output_file, "%s: .dword 0    # Address: 0x%08X\n",
                $3, symbol_table[idx].addr);
    }
    ;

type:
    INT_TYPE    { $$ = type_int; }
    | FLOAT_TYPE  { $$ = type_float; }
    | CHAR_TYPE   { $$ = type_char; }
    ;

main_section:
    START
    {
        fprintf(output_file, "# Main section\n");
    }
    statements FINISH
    ;

statements:
    /* empty */
    | statements statement
    ;

statement:
    IDENTIFIER ASSIGN expression PERIOD
    {
        // Check if variable is declared
        if (lookup_symbol($1) < 0) {
            fprintf(stderr, "Error at line %d: Undeclared variable '%s'\n", yylineno, $1);
            has_errors = 1;
            YYABORT;
        }

        fprintf(output_file, "\n# Assignment: %s = expression\n", $1);
        fprintf(output_file, "# ----------------------------------------\n");

        // Store result to variable
        generate_store($3, $1);

        fprintf(output_file, "# ----------------------------------------\n\n");
        reset_temps();
    }
    | PRINT LPAREN print_argument RPAREN PERIOD
    {
        fprintf(output_file, "\n# Print statement: ipakita()\n");
        fprintf(output_file, "# ----------------------------------------\n");

        // Check if it's a string literal (starts with str_)
        if (strncmp($3, "str_", 4) == 0) {
            generate_print_string($3);
        } else {
            // It's a register containing an integer
            generate_print_integer($3);
        }

        fprintf(output_file, "# ----------------------------------------\n\n");
        reset_temps();
    }
    ;

print_argument:
    STRING
    {
        // Add string to string table and return its label
        const char *label = add_string_literal($1);
        strcpy($$, label);
    }
    | expression
    {
        strcpy($$, $1);
    }
    ;

expression:
    term
    {
        strcpy($$, $1);
    }
    | expression PLUS term
    {
        const char *result = allocate_temp();
        strcpy($$, result);
        generate_binary_op($$, $1, $3, '+');
    }
    | expression MINUS term
    {
        const char *result = allocate_temp();
        strcpy($$, result);
        generate_binary_op($$, $1, $3, '-');
    }
    ;

term:
    factor
    {
        strcpy($$, $1);
    }
    | term MULTIPLY factor
    {
        const char *result = allocate_temp();
        strcpy($$, result);
        generate_binary_op($$, $1, $3, '*');
    }
    | term DIVIDE factor
    {
        const char *result = allocate_temp();
        strcpy($$, result);
        generate_binary_op($$, $1, $3, '/');
    }
    ;

factor:
    INTEGER
    {
        const char *reg = allocate_temp();
        strcpy($$, reg);
        generate_load_immediate(reg, $1);
    }
    | FLOAT
    {
        const char *reg = allocate_temp();
        strcpy($$, reg);
        generate_load_immediate(reg, (int)$1);
    }
    | CHAR
    {
        const char *reg = allocate_temp();
        strcpy($$, reg);
        generate_load_immediate(reg, (int)(unsigned char)$1);
    }
    | IDENTIFIER
    {
        if (lookup_symbol($1) < 0) {
            fprintf(stderr, "Error at line %d: Undeclared variable '%s'\n", yylineno, $1);
            has_errors = 1;
            YYABORT;
        }
        const char *reg = allocate_temp();
        strcpy($$, reg);
        generate_load(reg, $1);
    }
    | LPAREN expression RPAREN
    {
        strcpy($$, $2);
    }
    | MINUS INTEGER
    {
        const char *reg = allocate_temp();
        strcpy($$, reg);
        generate_load_immediate(reg, -$2);
    }
    | MINUS FLOAT
    {
        const char *reg = allocate_temp();
        strcpy($$, reg);
        generate_load_immediate(reg, (int)(-$2));
    }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Error at line %d: %s\n", yylineno, s);
    has_errors = 1;
}

// Symbol table functions
int add_symbol(const char *name, VarType type) {
    if (lookup_symbol(name) >= 0) {
        fprintf(stderr, "Error at line %d: Variable '%s' already declared\n", yylineno, name);
        return 0;
    }

    if (symbol_count >= MAX_SYMBOLS) {
        fprintf(stderr, "Error: Symbol table full\n");
        return 0;
    }

    strcpy(symbol_table[symbol_count].name, name);
    symbol_table[symbol_count].type = type;
    symbol_table[symbol_count].addr = symbol_count * 8;
    symbol_table[symbol_count].line = yylineno;
    symbol_count++;
    return 1;
}

int lookup_symbol(const char *name) {
    for (int i = 0; i < symbol_count; i++) {
        if (strcmp(symbol_table[i].name, name) == 0)
            return i;
    }
    return -1;
}

const char* add_string_literal(const char *str) {
    if (string_count >= MAX_STRINGS) {
        fprintf(stderr, "Error: String table full\n");
        return NULL;
    }

    snprintf(string_table[string_count].label, 32, "str_%d", string_count);
    strncpy(string_table[string_count].content, str, 255);
    string_table[string_count].id = string_count;

    return string_table[string_count++].label;
}

const char* allocate_temp() {
    if (temp_count >= MAX_TEMP_REGS)
        return NULL;
    snprintf(temp_regs[temp_count], 16, "R%d", temp_count + 1);
    return temp_regs[temp_count++];
}

void reset_temps() {
    temp_count = 0;
}

// Code generation functions
const InstructionDef* find_instruction(const char *instr) {
    for (int i = 0; instruction_table[i].name != NULL; i++) {
        if (strcmp(instruction_table[i].name, instr) == 0) {
            return &instruction_table[i];
        }
    }
    return NULL;
}

unsigned int encode_r_type(unsigned int opcode, int rs, int rt, int rd, int shamt, unsigned int funct) {
    return (opcode << 26) | (rs << 21) | (rt << 16) | (rd << 11) | (shamt << 6) | funct;
}

unsigned int encode_i_type(unsigned int opcode, int rs, int rt, int imm) {
    return (opcode << 26) | (rs << 21) | (rt << 16) | (imm & 0xFFFF);
}

void machine_code_to_binary(unsigned int machine, char *binary) {
    for (int i = 31; i >= 0; i--) {
        binary[31 - i] = (machine & (1u << i)) ? '1' : '0';
    }
    binary[32] = '\0';
}

void generate_machine_code(const char *instr, int rd, int rs, int rt, int imm, const char *info) {
    const InstructionDef *def = find_instruction(instr);
    if (!def) return;

    unsigned int machine = 0;
    switch (def->format) {
        case FMT_R_TYPE:
            machine = encode_r_type(def->opcode, rs, rt, rd, 0, def->funct);
            break;
        case FMT_R_SPECIAL:
            machine = encode_r_type(def->opcode, rs, rt, 0, 0, def->funct);
            break;
        case FMT_I_TYPE:
            machine = encode_i_type(def->opcode, rs, rt, imm);
            break;
    }

    char binary[33];
    machine_code_to_binary(machine, binary);
    fprintf(output_file, "   >> %s  0x%08X  %s\n", binary, machine, info);
}

void generate_load(const char *reg, const char *var) {
    int idx = lookup_symbol(var);
    if (idx < 0) return;

    int reg_num = atoi(reg + 1);
    int offset = symbol_table[idx].addr;
    char info[128];

    snprintf(info, sizeof(info), "[ Load %s to %s ]", var, reg);
    fprintf(output_file, "   LD %s, %s(R0)\n", reg, var);
    generate_machine_code("LD", 0, 0, reg_num, offset, info);
}

void generate_load_immediate(const char *reg, int value) {
    int reg_num = atoi(reg + 1);
    char info[128];

    snprintf(info, sizeof(info), "[ Load immediate %d to %s ]", value, reg);
    fprintf(output_file, "   DADDIU %s, R0, #%d\n", reg, value);
    generate_machine_code("DADDIU", 0, 0, reg_num, value, info);
}

void generate_store(const char *reg, const char *var) {
    int idx = lookup_symbol(var);
    if (idx < 0) return;

    int reg_num = atoi(reg + 1);
    int offset = symbol_table[idx].addr;
    char info[128];

    snprintf(info, sizeof(info), "[ Store %s to %s ]", reg, var);
    fprintf(output_file, "   SD %s, %s(R0)\n", reg, var);
    generate_machine_code("SD", 0, 0, reg_num, offset, info);
}

void generate_binary_op(const char *result, const char *left, const char *right, char op) {
    int res_num = atoi(result + 1);
    int left_num = atoi(left + 1);
    int right_num = atoi(right + 1);
    char info[128];

    switch (op) {
        case '+':
            snprintf(info, sizeof(info), "[ %s + %s -> %s ]", left, right, result);
            fprintf(output_file, "   DADDU %s, %s, %s\n", result, left, right);
            generate_machine_code("DADDU", res_num, left_num, right_num, 0, info);
            break;
        case '-':
            snprintf(info, sizeof(info), "[ %s - %s -> %s ]", left, right, result);
            fprintf(output_file, "   DSUBU %s, %s, %s\n", result, left, right);
            generate_machine_code("DSUBU", res_num, left_num, right_num, 0, info);
            break;
        case '*':
            snprintf(info, sizeof(info), "[ %s * %s ]", left, right);
            fprintf(output_file, "   DMULTU %s, %s\n", left, right);
            generate_machine_code("DMULTU", 0, left_num, right_num, 0, info);
            fprintf(output_file, "   MFLO %s\n", result);
            fprintf(output_file, "   >> [INFO] MFLO result stored in %s\n", result);
            break;
        case '/':
            snprintf(info, sizeof(info), "[ %s / %s ]", left, right);
            fprintf(output_file, "   DDIVU %s, %s\n", left, right);
            generate_machine_code("DDIVU", 0, left_num, right_num, 0, info);
            fprintf(output_file, "   MFLO %s\n", result);
            fprintf(output_file, "   >> [INFO] MFLO result stored in %s\n", result);
            break;
    }
}

void generate_print_string(const char *label) {
    char info[128];

    // Load address of string into R4 (syscall argument register)
    // In MIPS64, we use LUI + ORI to load full address
    // For simplicity, we'll use a pseudo-instruction LA (load address)
    fprintf(output_file, "   # Load string address\n");
    fprintf(output_file, "   LA R4, %s\n", label);
    fprintf(output_file, "   >> [INFO] Load address of %s into R4\n", label);

    // Set syscall code for print_string (4)
    snprintf(info, sizeof(info), "[ Set syscall code 4 (print_string) ]");
    fprintf(output_file, "   DADDIU R2, R0, #4\n");
    generate_machine_code("DADDIU", 0, 0, 2, 4, info);

    // Execute syscall
    snprintf(info, sizeof(info), "[ Execute syscall (print string) ]");
    fprintf(output_file, "   SYSCALL\n");
    generate_machine_code("SYSCALL", 0, 0, 0, 0, info);
}

void generate_print_integer(const char *reg) {
    int reg_num = atoi(reg + 1);
    char info[128];

    // Move value to R4 (syscall argument register)
    if (reg_num != 4) {
        snprintf(info, sizeof(info), "[ Move %s to R4 for syscall ]", reg);
        fprintf(output_file, "   DADDU R4, R0, %s\n", reg);
        generate_machine_code("DADDU", 4, 0, reg_num, 0, info);
    }

    // Set syscall code for print_int (1)
    snprintf(info, sizeof(info), "[ Set syscall code 1 (print_int) ]");
    fprintf(output_file, "   DADDIU R2, R0, #1\n");
    generate_machine_code("DADDIU", 0, 0, 2, 1, info);

    // Execute syscall
    snprintf(info, sizeof(info), "[ Execute syscall (print integer) ]");
    fprintf(output_file, "   SYSCALL\n");
    generate_machine_code("SYSCALL", 0, 0, 0, 0, info);
}

int main(int argc, char *argv[]) {
    if (argc <= 1) {
        fprintf(stderr, "Usage: %s source_file\n", argv[0]);
        return 1;
    }

    FILE *input = fopen(argv[1], "r");
    if (!input) {
        fprintf(stderr, "Cannot open file: %s\n", argv[1]);
        return 1;
    }

    yyin = input;
    int result = yyparse();
    fclose(input);

    return result;
}
