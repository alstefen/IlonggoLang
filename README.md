## Build Instructions
From the project root directory:
1. ```flex x_lexer.l```
2. ```bison -d x_parser.y```
3. ```gcc lex.yy.c x_parser.tab.c -o compiler -lfl```
To run:
```./compiler program.il```
