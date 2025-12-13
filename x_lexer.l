%{
#include <stdio.h>
#include <string.h>
#include "x_parser.tab.h"
extern int yylineno;
%}

%option noyywrap

DIGIT       [0-9]
LETTER      [a-zA-Z]
IDENTIFIER  {LETTER}({LETTER}|{DIGIT})*
INTEGER     {DIGIT}+
FLOAT       {DIGIT}+"."{DIGIT}+
CHAR        '.'

%%

[ \t]+              { /* ignore whitespace */ }
\n                  { yylineno++; }
"//".*              { /* single-line comment */ }

"programa"          { return PROGRAM; }
"sugod"             { return START; }
"tapos"             { return FINISH; }
"mga"               { return VAR; }

"numero"            { return INT_TYPE; }
"lutaw"             { return FLOAT_TYPE; }
"litera"            { return CHAR_TYPE; }

{INTEGER}           { yylval.ival = atoi(yytext); return INTEGER; }
{FLOAT}             { yylval.fval = atof(yytext); return FLOAT; }
{CHAR}              { yylval.cval = yytext[1]; return CHAR; }
{IDENTIFIER}        { strcpy(yylval.sval, yytext); return IDENTIFIER; }

"+"                 { return PLUS; }
"-"                 { return MINUS; }
"*"                 { return MULTIPLY; }
"/"                 { return DIVIDE; }
"="                 { return ASSIGN; }

"("                 { return LPAREN; }
")"                 { return RPAREN; }
"{"                 { return LBRACE; }
"}"                 { return RBRACE; }
","                 { return COMMA; }
"."                 { return PERIOD; }

.                   { printf("Unexpected character: %s\n", yytext); }

%%
