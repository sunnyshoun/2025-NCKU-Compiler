
/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h"
    #define MAX_SYMBOLS 100
    #define MAX_SCOPES 10

    typedef struct {
        int index;
        char* name;
        int mut;
        char* type;
        int addr;
        int lineno;
        char* func_sig;
    } Symbol;

    typedef struct {
        Symbol symbols[MAX_SYMBOLS];
        int count;
    } SymbolTable;

    SymbolTable symbol_tables[MAX_SCOPES];
    int scopeLevel = 0;
    int addr = -1;

    extern int yylineno;
    extern int yylex();
    void yyerror (char const *s)
    {
        printf("error:%d: %s\n", yylineno+1, s);
    }
    extern FILE *yyin;

    /* Used to generate code */
    /* As printf; the usage: CODEGEN("%d - %s\n", 100, "Hello world"); */
    /* We do not enforce the use of this macro */
    #define CODEGEN(...) \
        do { \
            for (int i = 0; i < g_indent_cnt; i++) { \
                fprintf(fout, "\t"); \
            } \
            fprintf(fout, __VA_ARGS__); \
        } while (0)

    /* Symbol table function - you can add new functions if needed. */
    /* parameters and return type can be changed */
    static void print_ident(Symbol* sym);
    static void create_symbol();
    static void insert_symbol(char* name, char* type, int mut, char* func_sig);
    static Symbol* lookup_symbol(char* name, bool load);
    static void dump_symbol();
    static char ls_type(char* str);
    static void compare_operation(char* cmd, char* type);

    /* Global variables */
    bool g_has_error = false;
    FILE *fout = NULL;
    int g_indent_cnt = 0;
    int g_L_num = 0;
    int g_ifL_num = 0;
    int g_whileL_num = 0;
%}

%error-verbose

/* Use variable or self-defined structure to represent
 * nonterminal and token type
 *  - you can add new fields if needed.
 */
%union {
    int i_val;
    float f_val;
    char *s_val;
    /* ... */
}

/* Token without return */
%token LET MUT NEWLINE
%token INT FLOAT BOOL STR
%token TRUE FALSE
%token GEQ LEQ EQL NEQ LOR LAND
%token ADD_ASSIGN SUB_ASSIGN MUL_ASSIGN DIV_ASSIGN REM_ASSIGN
%token IF ELSE FOR WHILE LOOP
%token PRINT PRINTLN
%token FUNC RETURN BREAK
%token ARROW AS IN DOTDOT RSHIFT LSHIFT

/* Token with return, which need to sepcify type */
%token <i_val> INT_LIT
%token <f_val> FLOAT_LIT
%token <s_val> STRING_LIT
%token <s_val> ID

/* Nonterminal with return, which need to sepcify type */
%type <s_val> Type
%type <s_val> Expr
%type <s_val> Literal

%left LOR
%left LAND
%left GEQ LEQ EQL NEQ '>' '<'
%left '+' '-'
%left '*' '/' '%'
%right '!' AS
%right NEG
%nonassoc '(' ')'

/* Yacc will start at this nonterminal */
%start Program

/* Grammar section */
%%

Program
    : GlobalStatementList
;

GlobalStatementList 
    : GlobalStatementList GlobalStatement
    | GlobalStatement
;

GlobalStatement
    : FunctionDeclStmt
    | NEWLINE { ++yylineno; }
;

FunctionDeclStmt
    : FUNC ID { 
        create_symbol();
        printf("func: %s\n", $<s_val>2);
        insert_symbol($<s_val>2, "func", -1, "(V)V");
    } '(' ')' Block { dump_symbol(); }
;

Block
    : '{' { create_symbol(); } StatementList '}' { dump_symbol(); }
;

StatementList
    : StatementList Statement
    | Statement
;

Statement
    : PRINTLN {
        CODEGEN("getstatic java/lang/System/out Ljava/io/PrintStream;\n");
    } Expr {
        printf("PRINTLN %s\n", $<s_val>3);
        CODEGEN("invokevirtual java/io/PrintStream/println(%s)V\n", $<s_val>3);
    } ';'
    | PRINT {
        CODEGEN("getstatic java/lang/System/out Ljava/io/PrintStream;\n");
    } Expr {
        printf("PRINT %s\n", $<s_val>3);
        CODEGEN("invokevirtual java/io/PrintStream/println(%s)V\n", $<s_val>3);
    } ';'
    | VariableDecl ';' 
    | Assignment ';'
    | IfStatement
    | WHILE {
        CODEGEN("WHILEL%dIN:\n", g_whileL_num);
    } Expr {
        CODEGEN("ifeq WHILEL%dOUT\n", g_whileL_num++);
    } Block {
        CODEGEN("goto WHILEL%dIN\n", g_whileL_num-1);
        CODEGEN("WHILEL%dOUT:\n", --g_whileL_num);
    }
    | NEWLINE { ++yylineno; }
    | Block
;

IfStatement
    : IF Expr { CODEGEN("ifeq IFL%d\n", g_ifL_num++); } Block { CODEGEN("IFL%d:\n", --g_ifL_num); } ElsePart

ElsePart
    : ELSE Block
    |

VariableDecl
    : LET MUT ID ':' Type {
        char* default_val = (ls_type($<s_val>5) == 'f') ? "0.0" : "0";
        CODEGEN("ldc %s\n", default_val);
        insert_symbol($<s_val>3, $<s_val>5, 1, "-");
    }
    | LET ID ':' Type { insert_symbol($<s_val>2, $<s_val>4, 0, "-"); }
    | LET MUT ID ':' Type '=' Expr { insert_symbol($<s_val>3, $<s_val>5, 1, "-"); }
    | LET ID ':' Type '=' Expr { insert_symbol($<s_val>2, $<s_val>4, 0, "-"); }
    | LET MUT ID '=' Expr { insert_symbol($<s_val>3, $<s_val>5, 1, "-"); }
    | LET ID '=' Expr { insert_symbol($<s_val>2, $<s_val>4, 0, "-"); }
;

Assignment
    : ID { Symbol* sym = lookup_symbol($<s_val>1, true); } '=' Expr { 
        Symbol* sym = lookup_symbol($<s_val>1, false);
        if(sym){
            printf("ASSIGN\n");
            if(sym->mut == 0) {
                char error_msg[256];
                snprintf(error_msg, sizeof(error_msg), "cannot borrow immutable borrowed content `%s` as mutable", $<s_val>1);
                yyerror(error_msg);
                g_has_error = true;
            }
            CODEGEN("%cstore %d\n", ls_type(sym->type), sym->addr);
        }
    }
    | ID { Symbol* sym = lookup_symbol($<s_val>1, true); } ADD_ASSIGN Expr {
        printf("ADD_ASSIGN\n");
        Symbol* sym = lookup_symbol($<s_val>1, false);
        CODEGEN("%cadd\n", ls_type(sym->type));
        CODEGEN("%cstore %d\n", ls_type(sym->type), sym->addr);
    }
    | ID { Symbol* sym = lookup_symbol($<s_val>1, true); } SUB_ASSIGN Expr {
        printf("SUB_ASSIGN\n");
        Symbol* sym = lookup_symbol($<s_val>1, false);
        CODEGEN("%csub\n", ls_type(sym->type));
        CODEGEN("%cstore %d\n", ls_type(sym->type), sym->addr);
    }
    | ID { Symbol* sym = lookup_symbol($<s_val>1, true); } MUL_ASSIGN Expr {
        printf("MUL_ASSIGN\n");
        Symbol* sym = lookup_symbol($<s_val>1, false);
        CODEGEN("%cmul\n", ls_type(sym->type));
        CODEGEN("%cstore %d\n", ls_type(sym->type), sym->addr);
    }
    | ID { Symbol* sym = lookup_symbol($<s_val>1, true); } DIV_ASSIGN Expr {
        printf("DIV_ASSIGN\n");
        Symbol* sym = lookup_symbol($<s_val>1, false);
        CODEGEN("%cdiv\n", ls_type(sym->type));
        CODEGEN("%cstore %d\n", ls_type(sym->type), sym->addr);
    }
    | ID { Symbol* sym = lookup_symbol($<s_val>1, true); } REM_ASSIGN Expr {
        printf("REM_ASSIGN\n");
        Symbol* sym = lookup_symbol($<s_val>1, false);
        CODEGEN("%crem\n", ls_type(sym->type));
        CODEGEN("%cstore %d\n", ls_type(sym->type), sym->addr);
    }
;

Expr
    : Literal { $$ = $<s_val>1; }
    | ID {
        Symbol* sym = lookup_symbol($<s_val>1, true);
        print_ident(sym);
        $$ = sym ? sym->type : "undefined";
    }
    | ID {
        Symbol* sym = lookup_symbol($<s_val>1, true);
        print_ident(sym);
    } '[' Expr ']' { $$ = "[I"; }
    | '-' Expr %prec NEG { printf("NEG\n"); CODEGEN("%cneg\n", ls_type($<s_val>2)); $$ = $<s_val>2; }
    | '!' Expr { printf("NOT\n"); compare_operation("ifne", NULL); $$ = "Z"; }
    | Expr '+' Expr { printf("ADD\n"); CODEGEN("%cadd\n", ls_type($<s_val>1)); $$ = $<s_val>1; }
    | Expr '-' Expr { printf("SUB\n"); CODEGEN("%csub\n", ls_type($<s_val>1)); $$ = $<s_val>1; }
    | Expr '*' Expr { printf("MUL\n"); CODEGEN("%cmul\n", ls_type($<s_val>1)); $$ = $<s_val>1; }
    | Expr '/' Expr { printf("DIV\n"); CODEGEN("%cdiv\n", ls_type($<s_val>1)); $$ = $<s_val>1; }
    | Expr '%' Expr { printf("REM\n"); CODEGEN("%crem\n", ls_type($<s_val>1)); $$ = $<s_val>1; }
    | Expr '>' Expr { 
        if (strcmp($<s_val>1, $<s_val>3) != 0 || strcmp($<s_val>1, "undefined") == 0) {
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "invalid operation: GTR (mismatched types %s and %s)", $<s_val>1, $<s_val>3);
            yyerror(error_msg);
            g_has_error = true;
        }
        printf("GTR\n");
        compare_operation("gt", $<s_val>1);
        $$ = "Z"; 
    }
    | Expr '<' Expr {
        printf("LSS\n");
        compare_operation("lt", $<s_val>1);
        $$ = "Z";
    }
    | Expr GEQ Expr {
        printf("GEQ\n");
        compare_operation("ge", $<s_val>1);
        $$ = "Z";
    }
    | Expr LEQ Expr {
        printf("LEQ\n");
        compare_operation("le", $<s_val>1);
        $$ = "Z";
    }
    | Expr EQL Expr { printf("EQL\n");
        compare_operation("eq", $<s_val>1);
        $$ = "Z";
    }
    | Expr NEQ Expr { printf("NEQ\n");
        compare_operation("ne", $<s_val>1);
        $$ = "Z";
    }
    | Expr LOR Expr { printf("LOR\n"); CODEGEN("ior\n"); $$ = "Z"; }
    | Expr LAND Expr { printf("LAND\n"); CODEGEN("iand\n"); $$ = "Z"; }
    | Expr LSHIFT Expr { 
        if (strcmp($<s_val>1, "i32") != 0 || strcmp($<s_val>3, "i32") != 0) {
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "invalid operation: LSHIFT (mismatched types %s and %s)", $<s_val>1, $<s_val>3);
            yyerror(error_msg);
            g_has_error = true;
        }
        printf("LSHIFT\n"); 
        $$ = "I"; 
    }
    | Expr AS Type {
        printf("%c2%c\n", $<s_val>1[0], $<s_val>3[0]);
        CODEGEN("%c2%c\n", ls_type($<s_val>1), ls_type($<s_val>3));
        $$ = $<s_val>3;
    }
    | '"' Expr '"' { $$ = $<s_val>2; }
    | '(' Expr ')' { $$ = $<s_val>2; }
    | '[' ArrayLiteral ']' { $$ = "[I"; }
;

Literal
    : INT_LIT {
        printf("INT_LIT %d\n", $<i_val>1);
        CODEGEN("ldc %d\n", $<i_val>1);
        $$ = "I";
    }
    | FLOAT_LIT {
        printf("FLOAT_LIT %f\n", $<f_val>1);
        CODEGEN("ldc %f\n", $<f_val>1);
        $$ = "F";
    }
    | STRING_LIT {
        printf("STRING_LIT \"%s\"\n", $<s_val>1);
        CODEGEN("ldc \"%s\"\n", $<s_val>1);
        $$ = "Ljava/lang/String;";
    }
    | '"' '"' {
        printf("STRING_LIT \"\"\n");
        CODEGEN("ldc \"\"\n");
        $$ = "Ljava/lang/String;";
    }
    | TRUE {
        printf("bool TRUE\n");
        CODEGEN("ldc 1\n");
        $$ = "Z";
    }
    | FALSE {
        printf("bool FALSE\n");
        CODEGEN("ldc 0\n");
        $$ = "Z";
    }
;

ArrayLiteral
    : ArrayLiteral ',' Literal 
    | Literal
;

Type
    : INT { $$ = "I"; }
    | FLOAT { $$ = "F"; }
    | BOOL { $$ = "Z"; }
    | STR { $$ = "Ljava/lang/String;"; }
    | '&' Type { $$ = $<s_val>2; }
    | '[' Type ';' Literal ']' { $$ = "[I"; }
;

%%

/* C code section */
int main(int argc, char *argv[])
{
    if (argc == 2) {
        yyin = fopen(argv[1], "r");
    } else {
        yyin = stdin;
    }
    if (!yyin) {
        printf("file `%s` doesn't exists or cannot be opened\n", argv[1]);
        exit(1);
    }

    /* Codegen output init */
    char *bytecode_filename = "hw3.j";
    fout = fopen(bytecode_filename, "w");
    CODEGEN(".source hw3.j\n");
    CODEGEN(".class public Main\n");
    CODEGEN(".super java/lang/Object\n");
    CODEGEN(".method public static main([Ljava/lang/String;)V\n");
    CODEGEN(".limit stack 100\n");
    CODEGEN(".limit locals 100\n");
    
    
    /* Symbol table init */
    // Add your code

    yylineno = 0;
    yyparse();

    /* Symbol table dump */
    // Add your code

    CODEGEN("return\n");
    CODEGEN(".end method\n");

	printf("Total lines: %d\n", yylineno);
    fclose(fout);
    fclose(yyin);

    if (g_has_error) {
        remove(bytecode_filename);
    }
    yylex_destroy();
    return 0;
}

static void print_ident(Symbol* sym){
    if(!sym) return;
    printf("IDENT (name=%s, address=%d)\n", sym->name, sym->addr);
}

static void create_symbol() {
    symbol_tables[scopeLevel].count = 0;
    printf("> Create symbol table (scope level %d)\n", scopeLevel++);
}

static void insert_symbol(char* name, char* type, int mut, char* func_sig) {
    if (strcmp(type, "func") != 0) {
        CODEGEN("%cstore %d\n", ls_type(type), addr);
    }
    SymbolTable* table = &symbol_tables[scopeLevel - 1];
    Symbol* sym = &table->symbols[table->count];
    sym->index = table->count;
    sym->name = strdup(name);
    sym->mut = mut;
    sym->type = strdup(type ? type : "unknown");
    sym->addr = addr++;
    sym->lineno = yylineno+1;
    sym->func_sig = func_sig ? strdup(func_sig) : strdup("-");
    printf("> Insert `%s` (addr: %d) to scope level %d\n", name, sym->addr, scopeLevel - 1);
    table->count++;
}

static Symbol* lookup_symbol(char* name, bool load) {
    for (int i = scopeLevel - 1; i >= 0; i--) {
        SymbolTable* table = &symbol_tables[i];
        for (int j = 0; j < table->count; j++) {
            if (strcmp(table->symbols[j].name, name) == 0) {
                Symbol* sym = &table->symbols[j];
                if(load) CODEGEN("%cload %d\n", ls_type((sym->type)), sym->addr);
                return sym;
            }
        }
    }

    char error_msg[256];
    snprintf(error_msg, sizeof(error_msg), "undefined: %s", name);
    yyerror(error_msg);
    g_has_error = true;

    return NULL;
}

static void dump_symbol() {
    SymbolTable* table = &symbol_tables[--scopeLevel];
    printf("\n> Dump symbol table (scope level: %d)\n", scopeLevel);
    printf("%-10s%-10s%-10s%-10s%-10s%-10s%-10s\n",
           "Index", "Name", "Mut", "Type", "Addr", "Lineno", "Func_sig");

    for (int i = 0; i < table->count; i++) {
        Symbol* sym = &table->symbols[i];
        printf("%-10d%-10s%-10d%-10s%-10d%-10d%-10s\n",
               sym->index, sym->name, sym->mut, sym->type,
               sym->addr, sym->lineno, sym->func_sig);
        free(sym->name);
        free(sym->type);
        free(sym->func_sig);
    }
    table->count = 0;
}

static char ls_type(char* str){
    if(strcmp(str, "I") == 0){
        return 'i';
    }
    else if(strcmp(str, "F") == 0){
        return 'f';
    }
    else if(strcmp(str, "Z") == 0){
        return 'i';
    }
    return 'a';
}

static void compare_operation(char* cmd, char* type) {
    const char* cmd_type;
    if (type == NULL) {
        cmd_type = "";
    } 
    else {
        cmd_type = (strcmp(type, "I") == 0) ? "if_icmp" : "fcmpg\nif";
    }

    int label_true = g_L_num++;
    int label_end = g_L_num++;

    CODEGEN("%s%s L%d\n", cmd_type, cmd, label_true);
    CODEGEN("iconst_0\n");
    CODEGEN("goto L%d\n", label_end);
    CODEGEN("L%d:\n", label_true);
    CODEGEN("iconst_1\n");
    CODEGEN("L%d:\n", label_end);
}