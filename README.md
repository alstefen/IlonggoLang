## Build Instructions
From the project root directory in your terminal:
1. ```flex x_lexer.l```
2. ```bison -d x_parser.y```
3. ```gcc lex.yy.c x_parser.tab.c -o compiler -lfl```
## To run:
```./compiler program.il```

## **Program Structure**

### **1. Program Declaration**
```
programa ProgramName.
```
- Must start with `programa`
- Followed by an identifier (program name)
- Ends with a period `.`

---

### **2. Variable Declaration Section**
```
mga {
    numero x, y, z.
    lutaw pi.
    litera initial.
}
```
- Starts with `mga {`
- Contains type declarations:
  - `numero` → integer
  - `lutaw` → float  
  - `litera` → char
- Variables separated by commas
- Ends with `}` after all declarations

---

### **3. Main Execution Section**
```
sugod
    x = 10.
    y = x + 5.
    z = (x * y) / 2.
tapos
```
- Starts with `sugod`
- Contains executable statements
- Ends with `tapos`
- **Only assignment statements** are supported

---

## **STATEMENT STRUCTURE**

### **Assignment Statement**
```
variable = expression.
```
- Left side: variable identifier
- Right side: arithmetic expression
- **Must end with period** `.`

---

## **EXPRESSION STRUCTURE**

### **Arithmetic Expressions**
```
x + 10
y - 5
a * b
c / d
(x + y) * 2
```
- Supports: `+`, `-`, `*`, `/`
- Parentheses for grouping
- Can include:
  - Variables
  - Integer literals (`10`)
  - Float literals (`3.14`)
  - Character literals (`'A'`)
  - Negative numbers (`-5`)

---

## **COMPLETE EXAMPLE**

```python
programa Calculator.

mga {
    numero result, x, y.
    lutaw pi.
}

sugod
    x = 10.
    y = 20.
    result = x + y.
    pi = 3.14.
tapos
```

---

## **KEY LANGUAGE RULES**

1. **Case-sensitive** identifiers
2. **Variables must be declared** before use
3. **Statements end with periods** (`.`)
4. **No control flow** (no if/while)
5. **No functions or procedures**
6. **No I/O operations**
7. **No arrays or structures**
8. **Type declarations only** (no type checking in expressions)

---


