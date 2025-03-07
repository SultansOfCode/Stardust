# Stardust

Old school hexadecimal editor with extra functionalities commonly used in ROM hacking, such as symbols' table and relative searches

Project created to experiment with [Zig](https://ziglang.org/) and [raylib](https://www.raylib.com/), while fulfilling some nostalgia from the early 2000's

The name was pun intended with Ziggy Stardust from David Bowie

---

### Symbols' table

A file that maps bytes to visual representation characters

It should have the same name as the opened file, reside in the same folder and has the `.tbl` extension. So, if you're dealing with `./roms/pkmngold.gbc` file and want to use a symbols' table, the file should be `./roms/pkmngold.tbl`

The contents of the file are something like:

```
7F= 
80=A
81=B
82=C
83=D
84=E
85=F
86=G
87=H
88=I
89=J
8A=K
8B=L
8C=M
8D=N
8E=O
8F=P
90=Q
91=R
92=S
93=T
94=U
95=V
96=W
97=X
98=Y
99=Z
9A=(
9B=)
9C=:
9D=;
9E=[
9F=]
A0=a
A1=b
A2=c
A3=d
A4=e
A5=f
A6=g
A7=h
A8=i
A9=j
AA=k
AB=l
AC=m
AD=n
AE=o
AF=p
B0=q
B1=r
B2=s
B3=t
B4=u
B5=v
B6=w
B7=x
B8=y
B9=z
```

It means, for example, bytes `80` (hexadecimal) will be shown as letter `A` and, when you press `A` in the character mode, it will insert the byte `80` (instead of byte `41`). Also, the original byte `41` will be renderended as a period `.` to avoid confusion

Each byte and symbol can only appear once

---

### Tutorial

Comming soon

---

### Shortcuts

`Left Ctrl + Home` - Go to the start of the file
`Left Ctrl + End` - Go to the end of the file
`Home` - Go to the start of the line
`End` - Go to the end of the line
`Tab` - Cycle between hexadecimal and character modes
`Esc` - Menu
`F3` - Find next (wraps around the end of the file)
`Left Shift + F3` - Find previous (wraps around the start of the file)

---

### Known issues

There is no error handling at the moment. So, if you try to open a file that does not exists, or if the computer lacks memory to open the file, program will simply crash and exit

---

### Thanks

People from [Twitch](https://twitch.tv/SultansOfCode) for watching me and supporting me while developing it

People from #Zig channel at [Libera.Chat](https://libera.chat/) for helping me out with Zig doubts

All of my [LivePix](https://livepix.gg/sultansofcode) donators

---

### Sources and licenses

FiraCode - [Source](https://github.com/tonsky/FiraCode) - [OFL-1.1 license](https://github.com/tonsky/FiraCode?tab=OFL-1.1-1-ov-file)

raylib - [Source](https://github.com/raysan5/raylib) - [Zlib license](https://github.com/raysan5/raylib?tab=Zlib-1-ov-file)

Zig - [Source](https://github.com/ziglang/zig) - [MIT license](https://github.com/ziglang/zig?tab=MIT-1-ov-file)
