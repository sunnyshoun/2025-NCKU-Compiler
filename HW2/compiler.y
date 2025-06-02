/* Please feel free to modify any content */

/* Definition section */
%{
    #include "compiler_common.h"
    // #define YYDEBUG 1
    // int yydebug = 1;
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
    extern FILE *yyin;

    int yylex_destroy ();
    void yyerror (char const *s)
    {
        printf("error:%d: %s\n", yylineno+1, s);
    }

    extern int yylineno;
    extern int yylex();
    extern FILE *yyin;

    /* Symbol table function - you can add new functions if needed. */
    /* parameters and return type can be changed */
    static void print_ident(Symbol* sym);
    static void create_symbol();
    static void insert_symbol(char* name, char* type, int mut, char* func_sig);
    static Symbol* lookup_symbol(char* name);
    static void dump_symbol();

    /* Global variables */
    bool HAS_ERROR = false;
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
    : PRINTLN Expr { printf("PRINTLN %s\n", $<s_val>2); } ';'
    | PRINT Expr { printf("PRINT %s\n", $<s_val>2); } ';'
    | VariableDecl ';' 
    | Assignment ';'
    | IF Expr Block
    | IF Expr Block ELSE Block
    | WHILE Expr Block
    | NEWLINE { ++yylineno; }
    | Block
;

VariableDecl
    : LET MUT ID ':' Type { insert_symbol($<s_val>3, $<s_val>5, 1, "-"); }
    | LET ID ':' Type { insert_symbol($<s_val>2, $<s_val>4, 0, "-"); }
    | LET MUT ID ':' Type '=' Expr { insert_symbol($<s_val>3, $<s_val>5, 1, "-"); }
    | LET ID ':' Type '=' Expr { insert_symbol($<s_val>2, $<s_val>4, 0, "-"); }
    | LET MUT ID '=' Expr { insert_symbol($<s_val>3, $<s_val>5, 1, "-"); }
    | LET ID '=' Expr { insert_symbol($<s_val>2, $<s_val>4, 0, "-"); }
;

Assignment
    : ID '=' Expr { 
        Symbol* sym = lookup_symbol($<s_val>1);
        if(sym){
            printf("ASSIGN\n");
            if(sym->mut == 0) {
                char error_msg[256];
                snprintf(error_msg, sizeof(error_msg), "cannot borrow immutable borrowed content `%s` as mutable", $<s_val>1);
                yyerror(error_msg);
                HAS_ERROR = true;
            }
        }
    }
    | ID ADD_ASSIGN Expr { printf("ADD_ASSIGN\n"); }
    | ID SUB_ASSIGN Expr { printf("SUB_ASSIGN\n"); }
    | ID MUL_ASSIGN Expr { printf("MUL_ASSIGN\n"); }
    | ID DIV_ASSIGN Expr { printf("DIV_ASSIGN\n"); }
    | ID REM_ASSIGN Expr { printf("REM_ASSIGN\n"); }
;

Expr
    : Literal { $$ = $<s_val>1; }
    | ID {
        Symbol* sym = lookup_symbol($<s_val>1);
        print_ident(sym);
        $$ = sym ? sym->type : "undefined";
    }
    | ID {
        Symbol* sym = lookup_symbol($<s_val>1);
        print_ident(sym);
    } '[' Expr ']' { $$ = "array"; }
    | '-' Expr %prec NEG { printf("NEG\n"); $$ = $<s_val>2; }
    | '!' Expr { printf("NOT\n"); $$ = "bool"; }
    | Expr '+' Expr { printf("ADD\n"); $$ = $<s_val>1; }
    | Expr '-' Expr { printf("SUB\n"); $$ = $<s_val>1; }
    | Expr '*' Expr { printf("MUL\n"); $$ = $<s_val>1; }
    | Expr '/' Expr { printf("DIV\n"); $$ = $<s_val>1; }
    | Expr '%' Expr { printf("REM\n"); $$ = $<s_val>1; }
    | Expr '>' Expr { 
        if (strcmp($<s_val>1, $<s_val>3) != 0 || strcmp($<s_val>1, "undefined") == 0) {
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "invalid operation: GTR (mismatched types %s and %s)", $<s_val>1, $<s_val>3);
            yyerror(error_msg);
            HAS_ERROR = true;
        }
        printf("GTR\n"); 
        $$ = "bool"; 
    }
    | Expr '<' Expr { printf("LSS\n"); $$ = "bool"; }
    | Expr GEQ Expr { printf("GEQ\n"); $$ = "bool"; }
    | Expr LEQ Expr { printf("LEQ\n"); $$ = "bool"; }
    | Expr EQL Expr { printf("EQL\n"); $$ = "bool"; }
    | Expr NEQ Expr { printf("NEQ\n"); $$ = "bool"; }
    | Expr LOR Expr { printf("LOR\n"); $$ = "bool"; }
    | Expr LAND Expr { printf("LAND\n"); $$ = "bool"; }
    | Expr LSHIFT Expr { 
        if (strcmp($<s_val>1, "i32") != 0 || strcmp($<s_val>3, "i32") != 0) {
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "invalid operation: LSHIFT (mismatched types %s and %s)", $<s_val>1, $<s_val>3);
            yyerror(error_msg);
            HAS_ERROR = true;
        }
        printf("LSHIFT\n"); 
        $$ = "i32"; 
    }
    | Expr AS Type { printf("%c2%c\n", $<s_val>1[0], $<s_val>3[0]); $$ = $<s_val>3; }
    | '"' Expr '"' { $$ = $<s_val>2; }
    | '(' Expr ')' { $$ = $<s_val>2; }
    | '[' ArrayLiteral ']' { $$ = "array"; }
;

Literal
    : INT_LIT { printf("INT_LIT %d\n", $<i_val>1); $$ = "i32"; }
    | FLOAT_LIT { printf("FLOAT_LIT %f\n", $<f_val>1); $$ = "f32"; }
    | STRING_LIT { printf("STRING_LIT \"%s\"\n", $<s_val>1); $$ = "str"; }
    | '"' '"' { printf("STRING_LIT \"\"\n", $<i_val>1); $$ = "str"; }
    | TRUE { printf("bool TRUE\n"); $$ = "bool"; }
    | FALSE { printf("bool FALSE\n"); $$ = "bool"; }
;

ArrayLiteral
    : ArrayLiteral ',' Literal 
    | Literal
;

Type
    : INT { $$ = "i32"; }
    | FLOAT { $$ = "f32"; }
    | BOOL { $$ = "bool"; }
    | STR { $$ = "str"; }
    | '&' Type { $$ = $<s_val>2; }
    | '[' Type ';' Literal ']' { $$ = "array"; }
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

    yylineno = 0;
    yyparse();

	printf("Total lines: %d\n", yylineno);
    fclose(yyin);
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

static Symbol* lookup_symbol(char* name) {
    for (int i = scopeLevel - 1; i >= 0; i--) {
        SymbolTable* table = &symbol_tables[i];
        for (int j = 0; j < table->count; j++) {
            if (strcmp(table->symbols[j].name, name) == 0) {
                return &table->symbols[j];
            }
        }
    }

    char error_msg[256];
    snprintf(error_msg, sizeof(error_msg), "undefined: %s", name);
    yyerror(error_msg);
    HAS_ERROR = true;

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